#' Update FDR by Permutation
#'
#' This function updates the FDR for each cutoff. By default, the set of cutoffs are determined
#' based on the quantile of the data, so that the cutoffs are evenly spaced across the data.
#' The FDR is calculated as the ratio between the number of permuted values beyond the cutoff
#' and the number of true values beyond the the cutoff. 
#' When tails is set to 'right', the FDR is calculated only on the positive side of the data.
#' When tails is set to 'both', the FDR is calculated on both sides of the data.
#'
#' @param object A \code{propr} or \code{propd} object.
#' @param number_of_cutoffs An integer. The number of cutoffs to test. Given this number, 
#' the cutoffs will be determined based on the quantile of the data. In this way, the 
#' cutoffs will be evenly spaced across the data.
#' @param custom_cutoffs A numeric vector. When provided, this vector is used as the set of 
#' cutoffs to test, and 'number_of_cutoffs' is ignored.
#' @param tails NA or 'right' or 'both'. 'right' is for one-sided on the right. 'both' for
#' symmetric two-sided test. If NA, use default value according to the property 
#' `has_meaningful_negative_values`. This is only relevant for \code{propr} objects, as 
#' \code{propd} objects are always one-sided and only have positive values.
#' @param ncores An integer. The number of parallel cores to use.
#' @return A \code{propr} or \code{propd} object with the FDR slot updated.
#' 
#' @export
updateCutoffs <-
  function(object,
           number_of_cutoffs = 100,
           custom_cutoffs = NA,
           tails = NA,
           ncores = 1) {

    if (inherits(object, "propr")) {
      updateCutoffs.propr(object, number_of_cutoffs, custom_cutoffs, tails, ncores)

    } else if (inherits(object, "propd")) {
      updateCutoffs.propd(object, number_of_cutoffs, custom_cutoffs, ncores)

    } else {
      stop("Provided 'object' not recognized.")
    }

  }

#' @rdname updateCutoffs
#' @section Methods:
#' \code{updateCutoffs.propr:}
#'  Use the \code{propr} object to permute correlation-like metrics
#'  (ie. rho, phi, phs, cor, pcor, pcor.shrink, pcor.bshrink),
#'  across a number of cutoffs. Since the permutations get saved
#'  when the object is created, calling \code{updateCutoffs}
#'  will use the same random seed each time.
#' @export
updateCutoffs.propr <-
  function(object, 
           number_of_cutoffs = 100, 
           custom_cutoffs = NA, 
           tails = NA, 
           ncores = 1) {
    if (identical(object@permutes, list(NULL))) {
      stop("Permutation testing is disabled.")
    }
    if (object@metric == "phi") {
      warning("We recommend using the symmetric phi 'phs' for FDR permutation.")
    }

    # handle right/both tails FDR test
    if (is.na(tails)) {
      tails <- ifelse(object@has_meaningful_negative_values, 'both', 'right')  # default option
    } else if (!tails %in% c('right','both')) {
      stop("Provided 'tails' not recognized.")
    }
    object@tails <- tails

    # get cutoffs
    if (is.na(custom_cutoffs)) {
      vals <- object@results$propr
      if (tails == 'right') {
        vals <- vals[vals >= 0]
      } else if (tails == 'both') {
        vals <- abs(vals)
      }
      cutoffs <- as.numeric(quantile(vals, seq(0, 1, length.out = number_of_cutoffs)))
    } else {
      cutoffs <- custom_cutoffs
    }

    # Set up FDR cutoff table
    FDR <- as.data.frame(matrix(0, nrow = length(cutoffs), ncol = 4))
    colnames(FDR) <- c("cutoff", "randcounts", "truecounts", "FDR")
    FDR$cutoff <- cutoffs

    # count the permuted values greater or less than each cutoff
    if (ncores > 1) {
      FDR$randcounts <- getFdrRandcounts.propr.parallel(object, cutoffs, ncores)
    } else{
      FDR$randcounts <- getFdrRandcounts.propr.run(object, cutoffs)
    }

    # count actual values greater or less than each cutoff
    vals <- object@results$propr
    if (tails == 'both') vals <- abs(vals)
    FDR$truecounts <- sapply(FDR$cutoff, function(cutoff) {
      countValuesBeyondThreshold(vals, cutoff, object@direct)
    })

    # calculate FDR
    FDR$FDR <- FDR$randcounts / FDR$truecounts

    # Initialize @fdr
    object@fdr <- FDR

    return(object)
  }

#' This function counts the permuted values greater or less than each cutoff,
#' using parallel processing, for a propr object
getFdrRandcounts.propr.parallel <- 
  function(object, cutoffs, ncores) {

    # Set up the cluster
    packageCheck("parallel")
    cl <- parallel::makeCluster(ncores)
    # parallel::clusterEvalQ(cl, requireNamespace(propr, quietly = TRUE))

    # define function to parallelize
    getFdrRandcounts <- function(ct.k) {
      # calculate permuted propr
      pr.k <- suppressMessages(propr::propr(
        ct.k,
        object@metric,
        ivar = object@ivar,
        alpha = object@alpha,
        p = 0
      ))
      # Vector of propr scores for each pair of taxa.
      pkt <- pr.k@results$propr
      if (object@tails == 'both') pkt <- abs(pkt)
      # Find number of permuted theta more or less than cutoff
      sapply(cutoffs, function(cutoff) countValuesBeyondThreshold(pkt, cutoff, object@direct))
    }

    # Each element of this list will be a vector whose elements
    # are the count of theta values less than the cutoff.
    randcounts <- parallel::parLapply(cl = cl,
                                      X = object@permutes,
                                      fun = getFdrRandcounts)

    # get the average randcounts across all permutations
    randcounts <- apply(as.data.frame(randcounts), 1, sum)
    randcounts <- randcounts / length(object@permutes)

    # Explicitly stop the cluster.
    parallel::stopCluster(cl)

    return(randcounts)
  }

#' This function counts the permuted values greater or less than each cutoff,
#' using a single core, for a propr object.
getFdrRandcounts.propr.run <-
  function(object, cutoffs) {

    # create empty randcounts
    randcounts <- rep(0, length(cutoffs))

    # Calculate propr for each permutation -- NOTE: `select` and `subset` disable permutation testing
    p <- length(object@permutes)
    for (k in 1:p) {
      numTicks <- progress(k, p, numTicks)

      # Calculate propr exactly based on @metric, @ivar, and @alpha
      ct.k <- object@permutes[[k]]
      pr.k <- suppressMessages(propr(
        ct.k,
        object@metric,
        ivar = object@ivar,
        alpha = object@alpha,
        p = 0
      ))
      pkt <- pr.k@results$propr
      if (object@tails == 'both') pkt <- abs(pkt)

      # calculate the cumulative (across permutations) number of permuted values more or less than cutoff
      for (cut in 1:length(cutoffs)){
        randcounts[cut] <- randcounts[cut] + countValuesBeyondThreshold(pkt, cutoffs[cut], object@direct)
      }
    }

    randcounts <- randcounts / p  # averaged across permutations
    return(randcounts)
  }

#' @rdname updateCutoffs
#' @section Methods:
#' \code{updateCutoffs.propd:}
#'  Use the \code{propd} object to permute theta across a
#'  number of theta cutoffs. Since the permutations get saved
#'  when the object is created, calling \code{updateCutoffs}
#'  will use the same random seed each time.
#' @export
updateCutoffs.propd <-
  function(object, number_of_cutoffs = 100, custom_cutoffs = NA, ncores = 1) {
    if (identical(object@permutes, data.frame()))
      stop("Permutation testing is disabled.")

    # get cutoffs
    if (is.na(custom_cutoffs)) {
      cutoffs <- as.numeric(quantile(object@results$theta, seq(0, 1, length.out = number_of_cutoffs)))
    } else {
      cutoffs <- custom_cutoffs
    }

    # Set up FDR cutoff table
    FDR <- as.data.frame(matrix(0, nrow = length(cutoffs), ncol = 4))
    colnames(FDR) <- c("cutoff", "randcounts", "truecounts", "FDR")
    FDR$cutoff <- cutoffs

    # Count the permuted values greater or less than each cutoff
    if (ncores > 1) {
      FDR$randcounts <- getFdrRandcounts.propd.parallel(object, cutoffs, ncores)
    } else{
      FDR$randcounts <- getFdrRandcounts.propd.run(object, cutoffs)
    }

    # count actual values greater or less than each cutoff
    FDR$truecounts <- sapply(1:nrow(FDR), function(cut) {
        countValuesBeyondThreshold(object@results$theta, FDR[cut, "cutoff"], direct=FALSE)
    })

    # Calculate FDR
    FDR$FDR <- FDR$randcounts / FDR$truecounts

    # Initialize @fdr
    object@fdr <- FDR

    return(object)
  }

#' This function counts the permuted values greater or less than each cutoff,
#' using parallel processing, for a propd object.
getFdrRandcounts.propd.parallel <- 
  function(object, cutoffs, ncores) {

    # Set up the cluster
    packageCheck("parallel")
    cl <- parallel::makeCluster(ncores)
    # parallel::clusterEvalQ(cl, requireNamespace(propr, quietly = TRUE))

    # define functions to parallelize
    getFdrRandcountsMod <- function(k) {
      if (is.na(object@Fivar)) stop("Please re-run 'updateF' with 'moderation = TRUE'.")
      shuffle <- object@permutes[, k]
      propdi <- suppressMessages(
        propd(
          object@counts[shuffle,],
          group = object@group,
          alpha = object@alpha,
          p = 0,
          weighted = object@weighted
        )
      )
      propdi <- suppressMessages(updateF(propdi, moderated = TRUE, ivar = Fivar))
      pkt <- propdi@results$theta_mod
      sapply(cutoffs, function(cutoff) countValuesBeyondThreshold(pkt, cutoff, direct=FALSE))
    }
    getFdrRandcounts <- function(k) {
      shuffle <- object@permutes[, k]
      pkt <- suppressMessages(
        calculate_theta(
          object@counts[shuffle,],
          object@group,
          object@alpha,
          object@results$lrv,
          only = object@active,
          weighted = object@weighted
        )
      )
      sapply(cutoffs, function(cutoff) countValuesBeyondThreshold(pkt, cutoff, direct=FALSE))
    }

    # Each element of this list will be a vector whose elements
    # are the count of theta values less than the cutoff.
    func = ifelse(object@active == "theta_mod", getFdrRandcountsMod, getFdrRandcounts)
    randcounts <- parallel::parLapply(cl = cl,
                                      X = 1:ncol(object@permutes),
                                      fun = func)

    # get the average randcounts across all permutations
    randcounts <- apply(as.data.frame(randcounts), 1, sum)
    randcounts <- randcounts / length(object@permutes)

    # Explicitly stop the cluster.
    parallel::stopCluster(cl)

    return(randcounts)
  }

#' This function counts the permuted values greater or less than each cutoff,
#' using a single core, for a propd object.
getFdrRandcounts.propd.run <- 
  function(object, cutoffs) {

    # create empty randcounts
    randcounts <- rep(0, length(cutoffs))

    # use calculateTheta to permute active theta
    p <- ncol(object@permutes)
    for (k in 1:p) {
      numTicks <- progress(k, p, numTicks)

      # calculate permuted theta values
      if (object@active == "theta_mod") {
        pkt <- suppressMessages(getPermutedThetaMod(object, k))
      } else{
        pkt <- suppressMessages(getPermutedTheta(object, k))
      }

      # calculate the cumulative (across permutations) number of permuted values more or less than cutoff
      for (cut in 1:length(cutoffs)){
        randcounts[cut] <- randcounts[cut] + countValuesBeyondThreshold(pkt, cutoffs[cut], direct=FALSE)
      }
    }

    randcounts <- randcounts / p  # averaged across permutations
    return(randcounts)
}

#' Get the theta mod values for a given permutation
getPermutedThetaMod <- 
  function(object, k) {

    if (is.na(object@Fivar)) stop("Please re-run 'updateF' with 'moderation = TRUE'.")

    # Tally k-th thetas that fall below each cutoff
    shuffle <- object@permutes[, k]

    # Calculate theta_mod with updateF (using k-th permuted object)
    propdi <- suppressMessages(
      propd(
        object@counts[shuffle,],
        group = object@group,
        alpha = object@alpha,
        p = 0,
        weighted = object@weighted
      )
    )
    propdi <- suppressMessages(updateF(propdi, moderated = TRUE, ivar = Fivar))

    return(propdi@results$theta_mod)
}

#' Get the theta values for a given permutation
getPermutedTheta <- 
  function(object, k) {

    # Tally k-th thetas that fall below each cutoff
    shuffle <- object@permutes[, k]

    # Calculate all other thetas directly (using calculateTheta)
    pkt <- suppressMessages(
      calculate_theta(
        object@counts[shuffle,],
        object@group,
        object@alpha,
        object@results$lrv,
        only = object@active,
        weighted = object@weighted
      )
    )

    return(pkt)
  }

#' Count Values Greater or Less Than a Threshold
#'
#' This function counts the number of values greater or less than a threshold.
#' The direction depends on if a direct or inverse relationship is asked,
#' as well as the sign of the threshold.
#'
#' @param values A numeric vector.
#' @param cutoff A numeric value.
#' @param direct A logical value. If \code{TRUE}, direct relationship is considered.
#' @return The number of values greater or less than the threshold.
countValuesBeyondThreshold <- function(values, cutoff, direct){
  if (direct){
    func <- ifelse(cutoff >= 0, count_greater_than, count_less_than)
  } else {
    func <- count_less_than
  }
  return(func(values, cutoff))
}
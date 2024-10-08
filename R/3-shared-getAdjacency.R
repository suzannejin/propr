#' Get Adjacency Matrix as indicated by permutation tests.
#' 
#' This function gets the significant pairs according to the permutation tests. Then it fills 
#' the adjacency matrix with 1 if pair is significant, otherwise 0. The significance is determined
#' by the cutoff value for which the false discovery rate (FDR) is less or equal than the given 
#' value 'fdr'. The significant pairs are those that have a value greater/less or equal than the 
#' cutoff, depending on the metric.
#'
#' @param object A \code{propd} or \code{propr} object.
#' @param fdr A float value for the false discovery rate. Default is 0.05.
#' @param window_size An integer. Default is 1. When it is greater than 1, the FDR
#' values would be smoothed out by a moving average of the given window size.
#' @return An adjacency matrix.
#'
#' @export
getAdjacencyFDR <- 
  function(object, fdr = 0.05, window_size = 1) {

    # get matrix
    mat <- getMatrix(object)

    # set up some parameters
    direct <- FALSE
    if (inherits(object, "propr")) {
      if (object@tails == 'both') mat <- abs(mat)
      direct <- object@direct
    }

    # create empty matrix
    adj <- matrix(0, nrow = nrow(mat), ncol = ncol(mat))
    rownames(adj) <- rownames(mat)
    colnames(adj) <- colnames(mat)

    # get cutoff
    cutoff <- getCutoffFDR(object, fdr=fdr, window_size=window_size)

    # fill in significant pairs
    if (cutoff) {
      if (direct) {
        adj[mat >= cutoff] <- 1
      } else {
        adj[mat <= cutoff] <- 1
      }
    }

  return(adj)
}

#' Get Adjacency Matrix as indicated by F-statistics
#'
#' This function gets the significant pairs, according to the F-statistics. 
#' Then it fills the adjacency matrix with 1 if pair is significant, otherwise 0.
#' Note that it can only be applied to theta_d, as updateF only works for theta_d.
#' 
#' @param object A \code{propd} or \code{propr} object.
#' @param pval A float value for the p-value. Default is 0.05.
#' @param fdr_adjusted A boolean. If TRUE, use the the FDR- adjusted p-values. 
#' Otherwise, get significant pairs based on the theoretical F-statistic cutoff.
#' @return An adjacency matrix.
#'
#' @export
getAdjacencyFstat <- 
  function(object, pval = 0.05, fdr_adjusted = TRUE) {
  
  # get matrix
  mat <- getMatrix(object)

  # create empty adjacency matrix
  adj <- matrix(0, nrow = nrow(mat), ncol = ncol(mat))
  rownames(adj) <- rownames(mat)
  colnames(adj) <- colnames(mat)

  # fill in significant pairs
  cutoff <- getCutoffFstat(object, pval, fdr_adjusted = fdr_adjusted)
  if (cutoff) adj[mat <= cutoff] <- 1

  return(adj)  
}

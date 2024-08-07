#' Get (Log-)ratios from Object
#'
#' This function provides a unified wrapper to retrieve (log-)ratios
#'  from \code{propr} and \code{propd} objects.
#'
#' When the \code{propd} object is made using \code{alpha}, this function returns
#'  the (log-)ratios as \code{(partner^alpha - pair^alpha) / alpha}.
#'
#' @inheritParams getResults
#' @param switch A boolean. For \code{propd}, toggles whether all ratios
#'  should have same orientation with respect to log-ratio means.
#'
#' @return A \code{data.frame} of (log-)ratios.
#'
#' @export
getRatios <- function(object, switch = TRUE) {
  # run ratios()
  ct <- object@counts
  alpha <- object@alpha
  lr <- ratios(ct, alpha)

  # For propd objects, define ratio so Group 1 is at top
  if (inherits(object, "propd") & switch) {
    switchRatio <- function(x) {
      text <- unlist(strsplit(x, "/"))
      paste0(text[2], "/", text[1])
    }

    df <- object@results
    for (i in 1:ncol(lr)) {
      if (df$lrm2[i] > df$lrm1[i]) {
        lr[, i] <- -1 * lr[, i]
        colnames(lr)[i] <- switchRatio(colnames(lr)[i])
      }
    }
  }

  return(lr)
}

#' Recast Matrix as Feature (Log-)Ratios
#'
#' The \code{ratios} function recasts a matrix with N feature columns
#'  as a new matrix with N * (N - 1) / 2 feature (log-)ratio columns.
#'
#' When the \code{alpha} argument is provided, this function returns
#'  the (log-)ratios as \code{(partner^alpha - pair^alpha) / alpha}.
#'
#' @param matrix A matrix. The data to recast.
#' @param alpha A double. See vignette for details. Leave missing
#'  to skip Box-Cox transformation.
#'
#' @return A matrix of (log-)ratios.
#'
#' @export
ratios <- function(matrix, alpha = NA) {
  lab <- labRcpp(ncol(matrix))

  # Replace count zeros if appropriate
  if (any(as.matrix(matrix) == 0) & is.na(alpha)) {
    matrix <- simple_zero_replacement(matrix)
  }

  # Get (log-)ratios [based on alpha]
  if (is.na(alpha)) {
    ratios <- log(matrix[, lab$Partner] / matrix[, lab$Pair])
  } else{
    message("Alert: Using alpha transformation to approximate log-ratios.")
    ratios <-
      (matrix[, lab$Partner] ^ alpha - matrix[, lab$Pair] ^ alpha) / alpha
  }

  # Name columns
  if (!is.null(colnames(matrix))) {
    colnames(ratios) <-
      paste0(colnames(matrix)[lab$Partner],
             "/", colnames(matrix)[lab$Pair])
  }

  return(ratios)
}

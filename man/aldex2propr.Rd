% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/aldex2propr.R
\name{aldex2propr}
\alias{aldex2propr}
\title{Import \code{ALDEx2} Object}
\usage{
aldex2propr(aldex.clr, how = "perb")
}
\arguments{
\item{aldex.clr}{An \code{aldex.clr} object.}

\item{how}{A character string. The proportionality method
used to build the \code{propr} object. For example,
"perb" returns an estimation of rho while "phit" returns
an estimation of phi.}
}
\value{
Returns a \code{propr} object.
}
\description{
This method constructs a \code{propr} object from an
 \code{aldex.clr} object. See Details.
}
\details{
The \code{ALDEx2} package has two exceptional features useful
 in proportionality analysis too. First, \code{ALDEx2} offers
 a number of additional log-ratio transformations, toggled
 by the \code{denom} argument in \code{aldex.clr}. Second,
 \code{ALDEx2} estimates per-feature technical variation
 within each sample using Monte-Carlo instances drawn
 from the Dirichlet distribution.

The \code{aldex2propr} function takes advantage of both
 of these features by constructing a \code{propr} object
 directly from an \code{aldex.clr} object. When interpreting
 the resultant \code{propr} object, keep in mind that
 \code{ALDEx2} adds 0.5 to all \code{@counts} regardless
 of whether the counts contain any zeros. Otherwise,
 the \code{@logratio} slot contains the log-ratio
 transformed counts as averaged across all Monte Carlo
 instances. Likewise, the \code{@matrix} slot gets
 filled with the proportionality matrix as averaged
 across all Monte Carlo instances.
}

#Functions for calculating and manipulating the G statistic

#' Calculates the G statistic
#'
#' The function is used by \code{\link{runGprimeAnalysis}} to calculate the G
#' statisic G is defined by the equation: \deqn{G = 2*\sum_{i=1}^{4}
#' n_{i}*ln\frac{obs(n_i)}{exp(n_i)}}{G = 2 * \sum n_i * ln(obs(n_i)/exp(n_i))}
#' Where for each SNP, \eqn{n_i} from i = 1 to 4 corresponds to the reference
#' and alternate allele depths for each bulk, as described in the following
#' table: \tabular{rcc}{ Allele \tab High Bulk \tab Low Bulk \cr Reference \tab
#' \eqn{n_1} \tab \eqn{n_2} \cr Alternate \tab \eqn{n_3} \tab \eqn{n_4} \cr}
#' ...and \eqn{obs(n_i)} are the observed allele depths as described in the data
#' frame. Method 1 calculates the G statistic using expected values assuming
#' read depth is equal for all alleles in both bulks: \deqn{exp(n_1) = ((n_1 +
#' n_2)*(n_1 + n_3))/(n_1 + n_2 + n_3 + n_4)} \deqn{exp(n_2) = ((n_2 + n_1)*(n_2
#' + n_4))/(n_1 + n_2 + n_3 + n_4)} etc...
#'
#' @param LowRef A vector of the reference allele depth in the low bulk
#' @param HighRef A vector of the reference allele depth in the high bulk
#' @param LowAlt A vector of the alternate allele depth in the low bulk
#' @param HighAlt A vector of the alternate allele depth in the high bulk
#'
#' @return A vector of G statistic values with the same length as
#'
#' @seealso \href{https://doi.org/10.1371/journal.pcbi.1002255}{The Statistics
#'   of Bulk Segregant Analysis Using Next Generation Sequencing}
#'   \code{\link{tricubeStat}} for G prime calculation

getG <- function(LowRef, HighRef, LowAlt, HighAlt)
{
    exp <- c(
        (LowRef + HighRef) * (LowRef + LowAlt) / (LowRef + HighRef + LowAlt + HighAlt),
        (LowRef + HighRef) * (HighRef + HighAlt) / (LowRef + HighRef + LowAlt + HighAlt),
        (LowRef + LowAlt) * (LowAlt + HighAlt) / (LowRef + HighRef + LowAlt + HighAlt),
        (LowAlt + HighAlt) * (HighRef + HighAlt) / (LowRef + HighRef + LowAlt + HighAlt)
    )
    obs <- c(LowRef, HighRef, LowAlt, HighAlt)
    
    G <-
        2 * (rowSums(obs * log(
            matrix(obs, ncol = 4) / matrix(exp, ncol = 4)
        )))
    return(G)
}

#' Calculate tricube weighted statistics for each SNP
#'
#' Uses local regression (wrapper for \code{\link[locfit]{locfit}}) to predict a
#' tricube smoothed version of the statistic supplied for each SNP. This works as a
#' weighted average across neighboring SNPs that accounts for Linkage
#' disequilibrium (LD) while minizing noise attributed to SNP calling errors.
#' Values for neighboring SNPs within the window are weighted by physical
#' distance from the focal SNP.
#'
#' @return Returns a vector of the weighted statistic caluculted with a tricube
#'   smoothing kernel
#'
#' @param POS A vector of genomic positions for each SNP
#' @param Stat A vector of values for a given statistic for each SNP
#' @param WinSize the window size (in base pairs) bracketing each SNP for which
#'   to calculate the statitics. Magwene et. al recommend a window size of ~25
#'   cM, but also recommend optionally trying several window sizes to test if
#'   peaks are over- or undersmoothed.
#' @param ... Other arguments passed to \code{\link[locfit]{locfit}} and
#'   subsequently to \code{\link[locfit]{locfit.raw}}() (or the lfproc). Usefull
#'   in cases where you get "out of vertex space warnings"; Set the maxk higher
#'   than the default 100. See \code{\link[locfit]{locfit.raw}}().
#' @examples df_filt_4mb$Gprime <- tricubeStat(POS, Stat = GStat, WinSize = 4e6)
#' @seealso \code{\link{getG}} for G statistic calculation
#' @seealso \code{\link[locfit]{locfit}} for local regression

tricubeStat <- function(POS, Stat, windowSize = 2e6, ...)
{
    if (windowSize <= 0)
        stop("A positive smoothing window is required")
    stats::predict(locfit::locfit(Stat ~ locfit::lp(POS, h = windowSize, deg = 0), ...), POS)
}


#' Non-parametric estimation of the null distribution of G'
#'
#' The function is used by \code{\link{runGprimeAnalysis}} to estimate p-values for the
#' weighted G' statistic based on the non-parametric estimation method described
#' in Magwene et al. 2011. Breifly, using the natural log of Gprime a median
#' absolute deviation (MAD) is calculated. The Gprime set is trimmed to exclude
#' outlier regions (i.e. QTL) based on Hampel's rule. An alternate method for
#' filtering out QTL is proposed using absolute delta SNP indeces greater than
#' a set threshold to filter out potential QTL. An estimation of the mode of the trimmed set
#' is calculated using the \code{\link[modeest]{mlv}} function from the package
#' modeest. Finally, the mean and variance of the set are estimated using the
#' median and mode and p-values are estimated from a log normal distribution.
#'
#' @param Gprime a vector of G prime values (tricube weighted G statistics)
#' @param deltaSNP a vector of delta SNP values for use for QTL region filtering
#' @param outlierFilter one of either "deltaSNP" or "Hampel". Method for
#'   filtering outlier (ie QTL) regions for p-value estimation
#' @param filterThreshold The absolute delta SNP index to use to filter out putative QTL
#' @export getPvals

getPvals <-
    function(Gprime,
        deltaSNP = NULL,
        outlierFilter = c("deltaSNP", "Hampel"),
        filterThreshold)
    {
        
        if (outlierFilter == "deltaSNP") {
            
            if (abs(filterThreshold) >= 0.5) {
                stop("filterThreshold should be less than 0.5")
            }
            
            message("Using deltaSNP-index to filter outlier regions with a threshold of ", filterThreshold)
            trimGprime <- Gprime[abs(deltaSNP) < abs(filterThreshold)]
        } else {
            message("Using Hampel's rule to filter outlier regions")
            lnGprime <- log(Gprime)
            
            medianLogGprime <- median(lnGprime)
            
            # calculate left median absolute deviation for the trimmed G' prime set
            MAD <-
                median(medianLogGprime - lnGprime[lnGprime <= medianLogGprime])
            
            # Trim the G prime set to exclude outlier regions (i.e. QTL) using Hampel's rule
            trimGprime <-
                Gprime[lnGprime - median(lnGprime) <= 5.2 * MAD]
        }
        
        medianTrimGprime <- median(trimGprime)
        
        # estimate the mode of the trimmed G' prime set using the half-sample method
        message("Estimating the mode of a trimmed G prime set using the 'modeest' package...")
        modeTrimGprime <-
            modeest::mlv(x = trimGprime, bw = 0.5, method = "hsm")$M
        
        muE <- log(medianTrimGprime)
        varE <- abs(muE - log(modeTrimGprime))
        #use the log normal distribution to get pvals
        message("Calculating p-values...")
        pval <-
            1 - plnorm(q = Gprime,
                meanlog = muE,
                sdlog = sqrt(varE))
        
        return(pval)
    }


#' Find false discovery rate threshold
#'
#' Given a vector of p-values and a set false discovery rate alpha the function
#' returns the lowest p-value in the vector for which the Benjamini-Hochberg
#' adjusted p-value (ie q-value) is less than that alpha.
#'
#' @param pvalues a vector of p-values
#' @param alpha the required false discovery rate alpha
#'
#' @return The p-value threshold that corresponds to the Benjamini-Hochberg adjusted p-value at the FDR set by alpha.
#'

getFDRThreshold <- function(pvalues, alpha = 0.01)
{
    sortedPvals <- sort(pvalues, decreasing = FALSE)
    pAdj <- p.adjust(sortedPvals, method = "BH")
    if (!any(pAdj < alpha)) {
        fdrThreshold <- NA
    } else {
    fdrThreshold <- sortedPvals[max(which(pAdj < alpha))]
    }
    return(fdrThreshold)
}

#' Identify QTL using a smoothed G statistic
#'
#' A wrapper for all the functions that perform the full G prime analysis to
#' identify QTL. The following steps are performed:\cr 1) Genome-wide G
#' statistics are calculated by \code{\link{getG}}. \cr G is defined by the
#' equation: \deqn{G = 2*\sum_{i=1}^{4} n_{i}*ln\frac{obs(n_i)}{exp(n_i)}}{G = 2
#' * \sum n_i * ln(obs(n_i)/exp(n_i))} Where for each SNP, \eqn{n_i} from i = 1
#' to 4 corresponds to the reference and alternate allele depths for each bulk,
#' as described in the following table: \tabular{rcc}{ Allele \tab High Bulk
#' \tab Low Bulk \cr Reference \tab \eqn{n_1} \tab \eqn{n_2} \cr Alternate \tab
#' \eqn{n_3} \tab \eqn{n_4} \cr} ...and \eqn{obs(n_i)} are the observed allele
#' depths as described in the data frame. \code{\link{getG}} calculates the G statistic
#' using expected values assuming read depth is equal for all alleles in both
#' bulks: \deqn{exp(n_1) = ((n_1 + n_2)*(n_1 + n_3))/(n_1 + n_2 + n_3 + n_4)}
#' \deqn{exp(n_2) = ((n_2 + n_1)*(n_2 + n_4))/(n_1 + n_2 + n_3 + n_4)}
#' \deqn{exp(n_3) = ((n_3 + n_1)*(n_3 + n_4))/(n_1 + n_2 + n_3 + n_4)}
#' \deqn{exp(n_4) = ((n_4 + n_2)*(n_4 + n_3))/(n_1 + n_2 + n_3 + n_4)}\cr 2) G'
#' - A tricube-smoothed G statistic is predicted by local regression within each
#' chromosome using \code{\link{tricubeStat}}. This works as a weighted average
#' across neighboring SNPs that accounts for Linkage disequilibrium (LD) while
#' minizing noise attributed to SNP calling errors. G values for neighboring
#' SNPs within the window are weighted by physical distance from the focal SNP.
#' \cr \cr 3) P-values are estimated based using the non-parametric method
#' described by Magwene et al. 2011 with the function \code{\link{getPvals}}.
#' Breifly, using the natural log of Gprime a median absolute deviation (MAD) is
#' calculated. The Gprime set is trimmed to exclude outlier regions (i.e. QTL)
#' based on Hampel's rule. An alternate method for filtering out QTL is proposed
#' using absolute delta SNP indeces greater than 0.1 to filter out potential
#' QTL. An estimation of the mode of the trimmed set is calculated using the
#' \code{\link[modeest]{mlv}} function from the package modeest. Finally, the
#' mean and variance of the set are estimated using the median and mode and
#' p-values are estimated from a log normal distribution. \cr \cr 4) Negative
#' Log10- and Benjamini-Hochberg adjusted p-values are calculated using
#' \code{\link[stats]{p.adjust}}
#'
#' @param SNPset Data frame SNP set containing previously filtered SNPs
#' @param windowSize the window size (in base pairs) bracketing each SNP for which
#'   to calculate the statitics. Magwene et. al recommend a window size of ~25
#'   cM, but also recommend optionally trying several window sizes to test if
#'   peaks are over- or undersmoothed.
#' @param outlierFilter one of either "deltaSNP" or "Hampel". Method for
#'   filtering outlier (ie QTL) regions for p-value estimation
#' @param filterThreshold The absolute delta SNP index to use to filter out putative QTL (default = 0.1)
#' @param ... Other arguments passed to \code{\link[locfit]{locfit}} and
#'   subsequently to \code{\link[locfit]{locfit.raw}}() (or the lfproc). Usefull
#'   in cases where you get "out of vertex space warnings"; Set the maxk higher
#'   than the default 100. See \code{\link[locfit]{locfit.raw}}(). But if you
#'   are getting that warning you should seriously consider increasing your
#'   window size.
#'   
#' @return The supplied SNP set tibble after G' analysis. Includes five new
#'   columns: \itemize{\item{G - The G statistic for each SNP} \item{Gprime -
#'   The tricube smoothed G statistic based on the supplied window size}
#'   \item{pvalue - the pvalue at each SNP calculatd by non-parametric
#'   estimation} \item{negLog10Pval - the -Log10(pvalue) supplied for quick
#'   plotting} \item{qvalue - the Benajamini-Hochberg adjusted p-value}}
#'
#'
#' @importFrom dplyr %>%
#'
#' @export runGprimeAnalysis
#'
#' @examples df_filt <- runGprimeAnalysis(df_filt,windowSize = 2e6,outlierFilter = "deltaSNP")
#' @useDynLib QTLseqr
#' @importFrom Rcpp sourceCpp


runGprimeAnalysis <-
    function(SNPset,
        windowSize = 1e6,
        outlierFilter = "deltaSNP",
        filterThreshold = 0.1, 
        ...)
    {
        message("Counting SNPs in each window...")
        SNPset <- SNPset %>%
            dplyr::group_by(CHROM) %>%
            dplyr::mutate(nSNPs = countSNPs_cpp(POS = POS, windowSize = windowSize))
        
        message("Calculating tricube smoothed delta SNP index...")
        SNPset <- SNPset %>%
            dplyr::mutate(tricubeDeltaSNP = tricubeStat(POS = POS, Stat = deltaSNP, windowSize, ...))
        
        message("Calculating G and G' statistics...")
        SNPset <- SNPset %>%
            dplyr::mutate(
                G = getG(
                    LowRef = AD_REF.LOW,
                    HighRef = AD_REF.HIGH,
                    LowAlt = AD_ALT.LOW,
                    HighAlt = AD_ALT.HIGH
                ),
                Gprime = tricubeStat(
                    POS = POS,
                    Stat = G,
                    windowSize = windowSize,
                    ...
                )
            ) %>%
            dplyr::ungroup() %>%
            dplyr::mutate(
                pvalue = getPvals(
                    Gprime = Gprime,
                    deltaSNP = deltaSNP,
                    outlierFilter = outlierFilter,
                    filterThreshold = filterThreshold
                ),
                negLog10Pval = -log10(pvalue),
                qvalue = p.adjust(p = pvalue, method = "BH")
            )
        
        return(as.data.frame(SNPset))
    }

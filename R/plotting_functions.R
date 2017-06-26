#' Plots different paramaters for QTL identification
#'
#' A wrapper for ggplot to plot genome wide distribution of parameters used to
#' identify QTL.
#'
#' @param SNPset a data frame with SNPs and genotype fields as imported by
#'   \code{ImportFromGATK} and after running \code{GetPrimeStats}
#' @param subset a vector of chromosome names for use in quick plotting of
#'   chromosomes of interest. Defaults to
#'   NULL and will plot all chromosomes in the SNPset
#' @param var character. The paramater for plotting. Must be one of: "nSNPs",
#'   "deltaSNP", "Gprime", "negLogPval"
#' @param line boolean. If TRUE will plot line graph. If FALSE will plot points.
#'   Plotting points will take more time.
#' @param plotThreshold boolean. Should we plot the False Discovery Rate
#'   threshold (FDR). Only plots line if var is "Gprime" or "negLogPval"
#' @param q numeric. The q-value to use as the FDR threshold. If too low, no
#'   line will be drawn and a warning will be given.
#' @param ... arguments to pass to ggplot2::geom_line or ggplot2::geom_point for
#'   changing colors etc.
#'
#' @return Plots a ggplot graph for all chromosomes or those requested in
#'   \code{subset}. By setting \code{var} to "nSNPs" the distribution of SNPs
#'   used to calculate G' will be plotted. "deltaSNP" will plot a tri-cube
#'   weighted delta SNP-index for each SNP. "Gprime" will plot the tri-cube
#'   weighted G' value. Setting "neLogPval" will plot the -log10 of the p-value
#'   at each SNP. In Gprime and negLogPval plots, a genome wide FDR threshold of
#'   q can be drawn by setting "plotThreshold" to TRUE. The defualt is a red
#'   line. If you would like to plot a different line we suggest setting
#'   "plotThreshold" to FALSE and manually adding a line using
#'   ggplot2::geom_hline.
#'
#' @examples p <- plotQTLstats(df_filt_6Mb, var = "Gprime", plotThreshold = TRUE, q = 0.01, subset = c("Chr3","Chr4"))
#' @export plotQTLstats

plotQTLstats <-
    function(SNPset,
        subset = NULL,
        var = "nSNPs",
        line = TRUE,
        plotThreshold = FALSE,
        q = 0.05,
        ...) {
        #get fdr threshold by ordering snps by pval then getting the last pval
        #with a qval < q
        tmp <- SNPset[order(SNPset$pval, decreasing = F),]
        fdrT <- tmp[sum(tmp$qval <= q), var]

        if (length(fdrT) == 0) {
            warning("The q threshold is too low. No line will be drawn")
        }

        if (!all(subset %in% unique(SNPset$CHROM))) {
            whichnot <- paste(subset[which(!subset %in% unique(SNPset$CHROM))], collapse = ', ')
            stop(paste0("The following are not true chromosome names: ", whichnot))
        }

        if (!var %in% c("nSNPs", "deltaSNP", "Gprime", "negLogPval"))
            stop(
                "Please choose one of the following variables to plot: \"nSNPs\", \"deltaSNP\", \"Gprime\", \"negLogPval\""
            )

        #don't plot threshold lines in deltaSNPprime or number of SNPs as they are not relevant
        if ((plotThreshold == TRUE &
                var == "deltaSNP") | (plotThreshold == TRUE & var == "nSNPs")) {
            message("FDR threshold is not plotted in deltaSNP or nSNPs plots")
            plotThreshold <- FALSE
        }
        SNPset <-
            if (is.null(subset)) {
                SNPset
            } else {
                SNPset[SNPset$CHROM == subset,]
            }

        p <- ggplot2::ggplot(data = SNPset) +
            facet_grid(~ CHROM, scales = "free_x") +
            scale_x_continuous(labels = format_genomic(),
                name = "Genomic Position") +
            theme(plot.margin = margin(
                b = 10,
                l = 20,
                r = 20,
                unit = "pt"
            ))

        if (var == "Gprime") {
            p <- p + ylab("G' value")
        }

        if (var == "negLogPval") {
            p <-
                p + ylab(expression("-" * log[10] * '(p-value)'))
        }

        if (var == "nSNPs") {
            p <- p + ylab("Number of SNPs in window")
        }

        if (var == "deltaSNP") {
            var <- "deltaSNPprime"
            p <- p + ylab(expression(Delta * 'SNP-index')) +
                ylim(-0.55, 0.55) +
                geom_hline(yintercept = 0,
                    color = "black",
                    alpha = 0.4)
        }

        if (line) {
            p <-
                p + geom_line(aes_string(x = "POS", y = var), size = 2, ...)
        }

        if (!line) {
            p <- p + geom_point(aes_string(x = "POS", y = var), ...)
        }

        if (plotThreshold == TRUE)
            p <-
            p + geom_hline(
                yintercept = fdrT,
                color = "red",
                size = 2,
                alpha = 0.4
            )
        p

    }

#' Plots Gprime distribution
#'
#' Plots a ggplot histogram of the distribution of Gprime with a log normal
#' distribution overlay
#'
#' @param SNPset a data frame with SNPs and genotype fields as imported by
#'   \code{ImportFromGATK} and after running \code{GetPrimeStats}
#' @param ModeEstMethod String. The method for estimation of the mode. Passed on to
#' \code{\link[modeest]{mlv}}. The default is half sample method (hsm). See
#' \code{\link[modeest]{mlv}} for other methods.
#'
#' @return Plots a ggplot histogram of the G' value distribution. It will then
#' overlay an estimated log normal distribution with the same mean and variance
#' as your G' distribution. This will allow to verify if after filtering your G'
#' value appear to be close to log normally and thus can be used to estimate
#' p-values using the non-parametric estimation method described in Magwene et al. (2013). Breifly,
#' using the natural log of Gprime a median absolute deviation (MAD) is
#' calculated. The Gprime set is trimmed to exclude outlier regions (i.e. QTL)
#' based on Hampel's rule. An estimation of the mode of the trimmed set is
#' calculated using the \code{\link[modeest]{mlv}} function from the package modeest. Finally, the mean
#' and variance of the set are estimated using the median and mode are
#' estimated and used to plot the log normal distribution.
#'
#' @examples plotGprimedist(df_filt_6Mb, ModeEstMethod = "hsm")

#'
#' @seealso \code{\link{GetPvals}} for how p-values are calculated.
#' @export plotGprimedist

plotGprimedist <- function(SNPset, ModeEstMethod = "hsm")
{
    # Non-parametric estimation of the null distribution of G'

    lnGprime <- log(SNPset$Gprime)

    # calculate left median absolute deviation for the trimmed G' prime set
    MAD <-
        median(abs(lnGprime[lnGprime <= median(lnGprime)] - median(lnGprime)))

    # Trim the G prime set to exclude outlier regions (i.e. QTL) using Hampel's rule
    trimGprime <-
        SNPset$Gprime[lnGprime - median(lnGprime) <= 5.2 * median(MAD)]

    medianTrimGprime <- median(trimGprime)

    # estimate the mode of the trimmed G' prime set using the half-sample method
    modeTrimGprime <-
        modeest::mlv(x = trimGprime, bw = 0.5, method = ModeEstMethod)$M

    muE <- log(medianTrimGprime)
    varE <- abs(muE - log(modeTrimGprime))

    #plot Gprime distrubtion
    p <- ggplot2::ggplot(SNPset) +
        xlim(0, max(SNPset$Gprime) + 1) +
        xlab("G' value") +
        geom_histogram(aes(x = Gprime, y = ..density..), binwidth = 0.5)  +
        stat_function(
            fun = dlnorm,
            size = 1,
            color = 'blue',
            args = c(meanlog = muE, sdlog = sqrt(varE))
        )
    return(p)
}
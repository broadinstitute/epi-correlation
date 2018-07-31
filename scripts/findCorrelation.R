library(dplyr)
library(optparse)
source('/scripts/resources.R')

#' Get DF containing the pvals & counts of 2 APPs.
#'
#' Resulting DF has 6 columns: chr, start, count_1, pval_1, count_2, pval_2
#' count_1, count_2 are for the first provided wig, while count_2 and pval_2 are for the second provided wig.
#' @param wig1_location Location of the 1st fitted wig file
#' @param wig2_location Location of the 2nd fitted wig file
#' @return Dataframe containing the reads, pvalues of both given wig files,
#' @export 
getPvalsOfBoth <- function(wig1_location, wig2_location)
{
    rpDF <- GetReadsPvalDF(wig1_location)
    rpDF <- bind_cols(rpDF,GetReadsPvalDF(wig2_location) %>% select(one_of(c("count","p_value"))))
    colnames(rpDF) <- c("chr","start","count_1","pval_1","count_2","pval_2")

    return(rpDF)
}

#' Calculate the correlation between two WIG files.
#'
#' Calculates the correlation between two fitted wig files, using only bins that are significant given
#' the passed pvalue threshold.
#' @param rpDF Dataframe containing count and pvalue information for both wigs. Must have a chromosome column
#'  of format "chr[0-9|X|Y]+" for filtering purposes. count & pval columns must be suffixied _1 and _2 for respective
#'  wig files. Order does not matter.
#' @param pvalue_threshold [default: 0.01] Maximum pvalue for bins that will be kept for correlation calculation.
#'  A bin must be below this pvalue in either wig to be kept.
#' @return numeric representing the correlation.
#' @export
findCorrelation <- function(rpDF, pvalue_threshold=0.01)
{
    # Filter out X & Y chromosomes
    rpDF <- rpDF[-which(rpDF$chr %in% c("chrX","chrY")),]

    # Filter to pvalue threshold
    rpDF <- rpDF %>% filter(pval_1 <= pvalue_threshold | pval_2 <= pvalue_threshold)

    cat(as.numeric(cor(rpDF$count_1, rpDF$count_2)))
}

option_list <- list(make_option('--wig1'),
                make_option('--wig2'),
                make_option('--pthreshold', default=0.01))

opts <- parse_args(OptionParser(option_list = option_list))

df <- getPvalsOfBoth(opts$wig1, opts$wig2)
findCorrelation(df,pvalue_threshold=opts$pthreshold)

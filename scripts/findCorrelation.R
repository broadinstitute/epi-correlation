suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(optparse))
source("/scripts/resources.R")

#' Get DF containing the pvals & counts of 2 APPs.
#'
#' Resulting DF has 6 columns: chr, start, count_1, pval_1, count_2, pval_2
#' count_1, count_2 are for the first provided wig, while count_2 and pval_2 are for the second provided wig.
#' @param wig1_location Location of the 1st fitted wig file
#' @param wig2_location Location of the 2nd fitted wig file
#' @return Dataframe containing the reads, pvalues of both given wig files,
#' @export 
GetPvalsOfBoth <- function(wig1_location, wig2_location) {
    rp_df <- GetReadsPvalsDF(wig1_location)
    rp_df <- bind_cols(
        rp_df,
        GetReadsPvalsDF(wig2_location) %>% 
            select(one_of(c("count", "p_value")))
        )
    colnames(rp_df) <- c("chr", "start", "count_1", "pval_1", "count_2",
        "pval_2")

    return(rp_df)
}

#' Calculate the correlation between two WIG files.
#'
#' Calculates the correlation between two fitted wig files, using only bins that are significant given
#' the passed pvalue threshold.
#' @param rp_df Dataframe containing count and pvalue information for both wigs. Must have a chromosome column
#'  of format "chr[0-9|X|Y]+" for filtering purposes. count & pval columns must be suffixied _1 and _2 for respective
#'  wig files. Order does not matter.
#' @param pvalue_threshold [default: 0.01] Maximum pvalue for bins that will be kept for correlation calculation.
#'  A bin must be below this pvalue in either wig to be kept.
#' @return numeric representing the correlation.
#' @export
FindCorrelation <- function(rp_df, pvalue_threshold = 0.01,
    mappability_threshold = 0.9) {
    # Get a mappability dataframe only containing rows passing mappability
    #   threshold
    map_df <- GetMappability(pre_filter = T,
        mappability_threshold = mappability_threshold)
    # Use left_join to keep only rows passing that threshold, and then dump the
    #   score column afterwards (we don't need it)
    rp_df <- left_join(map_df, rp_df, by = c("chr", "start")) %>%
        select(-score)
    # Filter out X & Y chromosomes
    rp_df <- rp_df[-which(rp_df$chr %in% c("chrX", "chrY")), ]

    # Filter to pvalue threshold
    rp_df <- rp_df %>% filter(
        pval_1 <= pvalue_threshold |
        pval_2 <= pvalue_threshold
        )

    cat(as.numeric(cor(rp_df$count_1, rp_df$count_2)))
}

option_list <- list(make_option("--wig1"),
                make_option("--wig2"),
                make_option("--pthreshold", default = 0.01))

opts <- parse_args(OptionParser(option_list = option_list))

df <- GetPvalsOfBoth(opts$wig1, opts$wig2)
FindCorrelation(df, pvalue_threshold = opts$pthreshold)
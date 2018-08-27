suppressPackageStartupMessages(library(optparse))
suppressPackageStartupMessages(library(plyr))
suppressPackageStartupMessages(library(dplyr))
source("/scripts/resources.R")
source("/scripts/ChromatinGWASPipeline/FitDistributionWithCVM.R")
source("/scripts/ChromatinGWASPipeline/UsefulFileLoadingFunctionsv2.R")

# Adjusted ProcessSingleFile method to work for this context
#' Fit a gamma distribution and return the parameters and p-values of all bins
#'
#' @param input_loc location of processed coverage file to run on
#' @param map_df_filename location of mappability track (must be same bin size as the coverage file)
#' @param exclude_X_Y (default: T) exclude X & Y chromosomes while fitting parameters. heavily suggested.
#' @param mappability_threshold (default: 0.9) minimum mappability of a bin for it to be included while fitting parameters.
#' @param use_pvalue_thresh (default: F) only applicable when using the 'iteration' estimation method. if T, only use values below the given pvalue threshold to fit the distribution.
#' @param p_value_thresh (default: 0.01) if using iterative estimation and use_pvalue_thresh is T, only use rows below this threshold to fit the distribution.
#' @param step_size (default: 0.01) if using iterative estimation, the step size.
#' @return a list with two objects: [[params]] which is a 4-column dataframe of the fit distribution parameters (beta, k, lambda, cvm) and [[pvals]] which is a dataframe containing the p-value of every bin.
#' @export
# TODO : how many columns are in [[pvals]]?
MobileProcessSingleFile <- function(input_loc, map_df_filename,
    exclude_X_Y = TRUE, mappability_threshold = 0.9,
    use_pvalue_thresh = F,
    p_value_thresh = 0.01, step_size = 0.01) {

  bin_df <- GetReadsDF(input_loc, postprocess = T)
  # For some reason, GetDistributionParametersWithOptim uses a Counts column
  #   that does not exist elsewhere in the code. Adding it here.
  bin_df$Counts <- bin_df$count

  if (exclude_X_Y) {
    working_df <- bin_df[!(bin_df$chr %in% c("chrX", "chrY")), ]
  } else {
    working_df <- bin_df
  }
  if (!is.null(mappability_threshold)) {
    map_df <- GetMappability(map_df_filename)
    working_df <- left_join(
      x = working_df,
      y = map_df,
      by = c("chr", "start_idx" = "start")
      )
    working_df <- working_df[working_df$score > mappability_threshold, ]
  }
  params_df <- GetDistributionParametersWithOptim(working_df = working_df)
  bin_df$p_value <- pgamma(
    q = bin_df$norm_count,
    shape = params_df$k,
    rate = params_df$beta,
    lower.tail = FALSE
    )

  return(list(params = params_df, pvals = bin_df))
}

#' Save a file containing chr, start, count, and pvalue of every non-blacklisted bin. ("Processed Fitted Coverage")
#'
#' @param input_loc location of the original processed coverage file
#' @param processing_results the list provided by MobileProcessSingleFile; a list with the objects [[params]] (4-col dataframe of fitted gamma dist parameters) and [[pvals]] (dataframe of p-values for every bin)
#' @param output_loc location to save the file; parameters will be saved in the file 'location'.PARAMS
#' @export
SaveFullDataFrame <- function(input_loc, processing_results, output_loc) {
  original_df <- GetReadsDF(input_loc)
  save_df <- left_join(
    original_df,
    processing_results[["pvals"]] %>% 
      select(one_of("chr", "start_idx", "p_value")),
    by = c("chr", "start_idx")
    )
  params_save_loc <- paste0(output_loc, ".PARAMS")
  write.table(
    save_df, file = output_loc,
    sep = " ", row.names = F,
    col.names = F, quote = F, append = F
    )
  write.table(
    processing_results[["params"]],
    file = params_save_loc, sep = ",",
    row.names = F, col.names = T,
    quote = F, append = F
    )
}

#' Ensures needed file exists, and if not told to overwrite, that final file does not exist
#' @param input_loc input processed coverage file, to ensure it exists and is non-empty
#' @param output_loc output processed fitted file location. If overwrite_file is F, ensures it does not yet exist.
#' @param overwrite_file (default: F) if true, does not check if output_loc already exists.
#' @export
IsOkToProceed <- function(input_loc, output_loc, overwrite_file = F) {
  if (!file.exists(input_loc)) {
    print(paste0("File ", input_loc, " does not exist."))
    return(FALSE)
  }

  file_info <- file.info(input_loc)
  # TODO: Ensure file is not unprocessed.
  if (file_info$size == 0) {
    print(paste0("File ", input_loc, " is empty."))
    return(FALSE)
  }

  if (file.exists(output_loc) & !overwrite_file) {
    print(paste0("File ", output_loc, " already exists. Aborting fitting."))
    return(FALSE)
  }
  return(TRUE)
}

option_list <- list(make_option("--input_loc"),
  make_option("--map_file", default = "/reference/mappability_5k.bed"),
  make_option("--overwrite_file", default = T),
  make_option("--output_loc", default = "p_values.txt"))

opts <- parse_args(OptionParser(option_list = option_list))

if (IsOkToProceed(opts$input_loc, opts$output_loc, opts$overwrite_file)) {
  processing_results <- MobileProcessSingleFile(
    input_loc = opts$input_loc,
    map_df_filename = opts$map_file
    )
  SaveFullDataFrame(opts$input_loc, processing_results, opts$output_loc)
} else {
    quit(status = 1)
}
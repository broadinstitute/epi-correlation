library(optparse)
source('/scripts/ChromatinGWASPipeline/ChromatinGWAS_Pipeline.R')

#' Get DF containing only the reads from a processed coverage file.
#' 
#' @param location location of the processed coverage file
#' @param postprocess (default F) add normalized count and thresholded count columns to the data frame.
#' @param thresh (default 500) threshold to cap count column, if postprocessing.
#' @return a dataframe of 3 cols: chr, start_idx, count. 
#' @export
GetReadsDF <- function(location, postprocess=F, thresh=500)
{
    # TODO: Do we want to add a specific neat fail if we get an unprocessed file?
    #   should be simple enough, check if first line has a "chrom=" substring.

    # If the user is calling this function, they don't want p-values. Ensure we only have the desired 3 columns.
    bin_df <- read.csv(location, sep=" ", header=FALSE, stringsAsFactors=F)
    if(ncol(bin_df) > 3)
    {
        bin_df <- bin_df %>% select(1:3)
    }
    colnames(bin_df) <- c("chr","start_idx","count")
    
    # Assuming this is a properly structed processed coverage file (which it has to be to have gotten this far), the binwidth is equal to the difference in start location of any 2 bins on the same chromosome.
    # Picking bins 1 & 2 here as we know they have to be on the same chromosome.
    binsize <- bin_df[2, "start_idx"] - bin_df[1,"start_idx"]

    # Vivian's code needs a chunk of preprocessing. (normalized count, thresholded count)
    if(postprocess)
    {
        bin_df$end_idx <- bin_df$start_idx + binsize - 1

        bin_df$norm_count <- bin_df$count/sum(as.numeric(bin_df$count),na.rm=T)*1e6
        bin_df$thresh_count <- bin_df$norm_count
        bin_df$thresh_count[bin_df$thresh_count > thresh] <- thresh
    }
    return(bin_df)
}

#' Get Reads & Pvalues of a given processed & fitted coverage file.
#'
#' @param location location of a processed & fitted coverage file.
#' @return a dataframe with 4 columns; chr, start, count, & p_value
#' @export
GetReadsPvalDF <- function(location)
{
    # TODO: fail neatly if given an unfitted coverage (no p-value)
    bin_df <- read.csv(location, sep=" ", header=FALSE, stringsAsFactors=F, col.names=c("chr","start_idx","count","p_value"))
    return(bin_df)
}

#' Get fitted gamma distribution parameters for specified processed & fitted coverage file.
#'
#' @param location location of a processed & fitted coverage file. (parameter file is found automatically based off of this string)
#' @return dataframe with 4 columns: beta, k, lambda, cvm
#' @export
GetParameters <- function(location)
{
    params_loc <- paste0(location,".PARAMS")
    if(!file.exists(params.loc))
    {
        print(paste0("Parameters missing. Please ensure parameters are saved in ",params_loc,"."))
        return NA
    }
    params_df <- read.csv(params_loc, sep=",", header=T, stringsAsFactors=F)
    return(params_df)
}

# Adjusted ProcessSingleFile method to work for this context
#' Fit a gamma distribution and return the parameters and p-values of all bins
#'
#' @param input_loc location of processed coverage file to run on
#' @param map_df_filename location of mappability track (must be same bin size as the coverage file)
#' @param exclude_X_Y (default: T) exclude X & Y chromosomes while fitting parameters. heavily suggested.
#' @param mappability_threshold (default: 0.9) minimum mappability of a bin for it to be included while fitting parameters.
#' @param estimation_method (default: 'cvm') method of fitting distribution. options are 'iteration' and 'cvm'
#' @param use_pvalue_thresh (default: F) only applicable when using the 'iteration' estimation method. if T, only use values below the given pvalue threshold to fit the distribution.
#' @param p_value_thresh (default: 0.01) if using iterative estimation and use_pvalue_thresh is T, only use rows below this threshold to fit the distribution.
#' @param step_size (default: 0.01) if using iterative estimation, the step size.
#' @return a list with two objects: [[params]] which is a 4-column dataframe of the fit distribution parameters (beta, k, lambda, cvm) and [[pvals]] which is a dataframe containing the p-value of every bin.
#' @export
# TODO : how many columns are in [[pvals]]?
MobileProcessSingleFile <- function(input_loc, map_df_filename, exclude_X_Y=TRUE, mappability_threshold=0.9, estimation_method='cvm', use_pvalue_thresh=F, p_value_thresh = 0.01, step_size = 0.01)
{
    bin_df <- GetReadsDF(input_loc, postprocess=T)
    # For some reason, GetDistributionParametersWithOptim uses a Counts column that does not exist elsewhere in the code.
    # Adding it here.
    bin_df$Counts <- bin_df$count
    
    if(estimation_method == 'iteration'){
        params_df <- PValueIterator(working_df = bin_df, step_size = step_size)
        # only keep p values from last iteration; append these to bin_df
        bin_df$p_value <- params_df$px[dim(params_df)[1]][[1]]
        # this line useful if want to just keep rows above a certain p value threshold
        if(use_pvalue_thresh){
            bin_df$p_value_thresh <- bin_df$p_value < p_value_thresh
        }

    } else if(estimation_method == 'cvm'){
        if(exclude_X_Y){
            working_df <- bin_df[!(bin_df$chr %in% c('chrX', 'chrY')),]
        } else{
            working_df <- bin_df
        }
        if(!is.null(mappability_threshold)){
            map_df <- read.table(file = map_df_filename, sep = "\t", col.names = c('chr', 'start_idx', 'score'), header = FALSE)
            working_df <- left_join(x = working_df, y = map_df, by = c('chr', 'start_idx'))
            working_df <- working_df[working_df$score > mappability_threshold,]
        }
        params_df <- GetDistributionParametersWithOptim(working_df = working_df)
        bin_df$p_value <- pgamma(q = bin_df$norm_count, shape = params_df$k, rate = params_df$beta, lower.tail = FALSE)
    }
    
    return(list(params=params_df, pvals = save_df))

}

#' Save a file containing chr, start, count, and pvalue of every non-blacklisted bin. ("Processed Fitted Coverage")
#'
#' @param input_loc location of the original processed coverage file
#' @param processing_results the list provided by MobileProcessSingleFile; a list with the objects [[params]] (4-col dataframe of fitted gamma dist parameters) and [[pvals]] (dataframe of p-values for every bin)
#' @param output_loc location to save the file; parameters will be saved in the file 'location'.PARAMS
#' @export
saveFullDataFrame <- function(input_loc, processing_results, output_loc)
{
    original_df <- GetReadsDF(input_loc)
    save_df <- left_join(original_df, processing_results[["pvals"]] %>% select(one_of("chr","start_idx","p_value")),by=c("chr","start_idx"))
    params_save_loc <- paste0(input_loc, ".PARAMS")
    write.table(save_df, file=input_loc, sep=" ", row.names=F, col.names=F, quote=F, append=F)
    write.table(processing_results[["params"]], file=params_save_loc, sep=",", row.names=F, col.names=T, quote=F, append=F)
}

#' Ensures needed file exists, and if not told to overwrite, that final file does not exist
#' @param input_loc input processed coverage file, to ensure it exists and is non-empty
#' @param output_loc output processed fitted file location. If overwrite_file is F, ensures it does not yet exist.
#' @param overwrite_file (default: F) if true, does not check if output_loc already exists.
#' @export
isOkToProceed <- function(input_loc, output_loc, overwrite_file=F)
{
    if(!file.exists(input_loc))
    {
        print(paste0("File ", input_loc," does not exist."))
        return(FALSE)
    }

    file_info <- file.info(input_loc)
    # TODO: Ensure file is not unprocessed.
    if(file_info$size == 0)
    {
        print(paste0("File ", input_loc, " is empty."))
        return(FALSE)
    }

    if(file.exists(output_loc) & !overwrite_file)
    {
        print(paste0("File ", output_loc, " already exists. Aborting fitting."))
        return(FALSE)
    }

    return(TRUE)
}


option_list <- list(make_option('--input_loc'),
                    make_option('--map_file',default="/reference/mappability_5k.bed")
                    make_option('--overwrite_file', default=T),
                    make_option('--output_loc',default="p_values.txt"))

opts <- parse_args(OptionParser(option_list = option_list))

if(isOkToProceed(opts$input_loc, opts$output_loc, opts$overwrite_file))
{
    processingResults <- MobileProcessSingleFile(
        input_loc=opts$input_loc, 
        map_df_filename=opts$map_file)

    saveFullDataFrame(opts$input_loc, processingResults, opts$output_loc)
}
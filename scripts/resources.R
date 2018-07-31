#' Get DF containing only the reads from a processed coverage file.
#' 
#' @param location location of the processed coverage file
#' @param postprocess (default F) add normalized count and thresholded count columns to the data frame.
#' @param thresh (default 500) threshold to cap count column, if postprocessing.
#' @return a dataframe of 3 cols: chr, start_idx, count. 
#' @export
GetReadsDF <- function(location, postprocess=F, thresh=500)
{
    # TODO : Do we want to add a specific neat fail if we get an unprocessed file?
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
    # TODO : fail neatly if given an unfitted coverage (no p-value)
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
        # TODO : Is there a better way of throwing an error?
        print(paste0("Parameters missing. Please ensure parameters are saved in ",params_loc,"."))
        return(NA)
    }
    params_df <- read.csv(params_loc, sep=",", header=T, stringsAsFactors=F)
    return(params_df)
}
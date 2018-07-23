# Inputs:
#   - coverage file location
#   - mappability file location
#   - (testing) output file location

# TODO:
#   - add all of the sources

library(optparse)
source('/scripts/ChromatinGWASPipeline/ChromatinGWAS_Pipeline.R')

# Vivian's code expects a bin DF with 4 columns.
# Read in our 3-column file and add an end_idx column.
# Assumes blacklist already removed.
# -- 
# Vivian adds a normalized count column and a thresholded column.
GetBinDF <- function(location, thresh=500, binsize=5000)
{
    # TODO: check that sep is actually "\t"
    bin_df <- read.csv(location, sep=" ", header=FALSE, col.names=c("chr","start_idx","count"), stringsAsFactors=F)
    bin_df$end_idx <- bin_df$start_idx + binsize - 1

    bin_df$norm_count <- bin_df$count/sum(as.numeric(bin_df$count),na.rm=T)*1e6
    bin_df$thresh_count <- bin_df$norm_count
    bin_df$thresh_count[bin_df$thresh_count > thresh] <- thresh
    return(bin_df)
}

# Adjusted ProcessSingleFile method to work for this context
MobileProcessSingleFile <- function(input_loc, map_df_filename, save_location, save_fields, step_size = 0.01, p_value_thresh = 0.01, return_params=FALSE, save_params=FALSE, exclude_X_Y=TRUE, mappability_threshold=0.9, estimation_method='cvm', overwrite_file=F)
{
    if(!file.exists(input_loc))
    {
        print(paste0("File ", input_loc," does not exist."))
        return(FALSE)
    }

    file_info <- file.info(input_loc)
    if(file_info$size == 0)
    {
        print(paste0("File ", input_loc, " is empty."))
    }

    if(file.exists(save_location) & !overwrite_file)
    {
        print(paste0("File ", save_location, " already exists. Aborting fitting."))
        return(FALSE)
    }

    bin_df <- GetBinDF(input_loc)
    # For some reason, GetDistributionParametersWithOptim uses a Counts column that does not exist elsewhere in the code.
    # Adding it here.
    bin_df$Counts <- bin_df$count
    
    if(estimation_method == 'iteration'){
        params_df <- PValueIterator(working_df = bin_df, step_size = step_size)
    # only keep p values from last iteration; append these to bin_df
        bin_df$p_value <- params_df$px[dim(params_df)[1]][[1]]
        # this line useful if want to just keep rows above a certain p value threshold
        if('p_value_thresh' %in% save_fields){
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
        if('p_value_thresh' %in% save_fields){
        bin_df$p_value_thresh <- bin_df$p_value_cvm < p_value_thresh
        }
    }
    if(grepl('chr', bin_df$chr[1])){
        bin_df$chr_str <- bin_df$chr
        bin_df <- bin_df %>% mutate(chr = gsub(pattern = 'chr', replacement = '', x = chr_str))
    }

    # what to save?
    save_df <- bin_df[,save_fields]
    
    # Adjusted; used to use a function to determine save location
    save_filename <- save_location
    if(file.exists(save_filename)){
        print(paste('Removing', save_filename))
        file.remove(save_filename)
    }
    write.table(x = save_df, file = save_filename, sep = '\t', row.names = FALSE, col.names = FALSE, quote = FALSE, append = FALSE)
    if(save_params){
        params_filename <- paste0(save_filename, ".PARAMS")
        write.table(x = params_df, file = params_filename, sep = ',', row.names = FALSE, col.names = TRUE, quote = FALSE)
    }
    if(!return_params){
        return(TRUE)
    } else{
        return(params_df)
    }

}


option_list <- list(make_option('--input_loc'),
                    make_option('--map_file'),
                    make_option('--output_loc'))

opts <- parse_args(OptionParser(option_list = option_list))
MobileProcessSingleFile(input_loc=opts$input_loc, 
    map_df_filename=opts$map_file, 
    save_location=opts$output_loc,
    save_fields=c('chr','p_value'),
    save_params=TRUE, overwrite_file = T)
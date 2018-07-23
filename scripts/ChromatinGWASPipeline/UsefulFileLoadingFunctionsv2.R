#' load segmentation (peak info) from file, using APP_full, which is a string that looks like 'Alignment Post Processing xxxxx'
#' Also needed: joined_df, which is a dataframe that contains information about the segmentation file location/APP
#' can include a wanted chromosome, or not
#' Also adds information about bin location of each identified peak, based on the user defined bin size
#' joined_df is generated with GetAPPWithSegmentationFromLIMS.R
library(plyr)
library(dplyr)

GetFile <- function(filename, header_bool, sep_str){
  if (class(filename) != 'data.frame'){
    if(grepl(pattern = 'RDS', filename)) {
      data_df <- readRDS(file = filename)
    } else {
      data_df <- read.table(file = filename, header = header_bool, sep = sep_str)
    }
  }
  else {
    data_df <- filename
  }
  return(data_df)
}

GetSegmentationFile <- function(APP_full, joined_df, use_wanted_chr = FALSE, wanted_chr = 19, bin_size = 5000){
  seg_file <- joined_df %>% dplyr::filter(Name == APP_full) %>% dplyr::select(BED.Filename)
  seg_df <- read.csv(toString(seg_file$BED.Filename),
                     sep='\t', header = FALSE, col.names = c('chr', 'start_idx', 'end_idx', 'c4', 'c5', 'c6'))
  if (use_wanted_chr){
    filter_str <- paste('chr', toString(wanted_chr), sep = '')
    print(filter_str)
    seg_df <- seg_df %>% filter(chr == filter_str)
  }
  seg_df <- seg_df %>% mutate(start_idx_round = floor(start_idx/bin_size)*bin_size) %>%
    mutate(end_idx_round = ceiling(end_idx/bin_size)*bin_size)
  return(seg_df)
}

#' This loads a binned file using APP_full (string: 'Alignment Post Processing xxxxx')
#' Also needed: joined_df which is a dataframe that contains information about the binned file location
#' Returns information with reads/bin (in count column), and normalizes count by total counts/track (norm_count),
#' and also a column with the normalized count thresholded (i.e. all values above thresh combined into one bin)
GetBinFile <- function(APP_full, joined_df, thresh = 500, col_names = c('chr', 'start_idx', 'end_idx', 'count'), 
                       use_wanted_chr = FALSE, wanted_chr = 19, 
                       reference_file = '/seq/epiprod02/Polina/IGVCount/5k/bin_bl.bed'){
  bin_file <- joined_df %>% dplyr::filter(Name == APP_full) %>% dplyr::select(Binned.Filename)
  bin_file <- toString(bin_file$Binned.Filename)
  if(grepl('/seq/epiprod02/Polina/Pass3_CellDat/', bin_file)){
    bin_df <- read.csv(bin_file, sep='\t', header = FALSE, col.names = col_names)
    if (use_wanted_chr){
      bin_df <- bin_df %>% dplyr::filter(chr == wanted_chr)
    }
    # add column for normalized counts
    bin_df$norm_count <- bin_df$count/sum(as.numeric(bin_df$count), na.rm = T)*1e6
  } else{
    # try reading in bin_df
    bin_df_test <- read.table(bin_file, header = FALSE, nrows = 1)
    if(dim(bin_df_test)[2] != 1){
      return(NULL)
    }
    bin_df <- read.table(bin_file, header = FALSE)
    col_names <- c('chr', 'start_idx')
    reference_df <- read.csv(file = reference_file, header = FALSE, stringsAsFactors = FALSE, sep = ' ', 
                             col.names = col_names)
    if(dim(bin_df)[1] != dim(reference_df)[1]){
      return(NULL)
    }
    bin_size <- reference_df$start_idx[2] - reference_df$start_idx[1]
    reference_df <- reference_df %>% mutate(end_idx = start_idx + bin_size - 1)
    reference_df$count <- bin_df$V1
    bin_df <- reference_df
    if(use_wanted_chr){
      bin_df <- bin_df %>% dplyr::filter(chr == paste0('chr',wanted_chr))
    }
    bin_df$norm_count <- bin_df$count
  }
  bin_df$thresh_count <- bin_df$norm_count
  bin_df$thresh_count[bin_df$thresh_count > thresh] <- thresh
  return(bin_df)
}

# might need to remove blacklist bins; use reference bin file
RemoveBlacklist <- function(bin_df, reference_file = 'Chr5kBinsReference_BlacklistRemoved.csv', 
                                join_fields = c('chr', 'start_idx', 'end_idx'), sep_str = ',',
                                col_names = c('chr', 'start_idx', 'end_idx', 'chr_str'),
                                col_classes = c('character', 'integer', 'integer', 'character')){
  if (class(reference_file) != 'data.frame') {
    if(grepl(pattern = 'rds', x = reference_file)){
      reference_df <- readRDS(reference_file)
    } else{
      reference_df <- read.csv(file = reference_file, header = FALSE, sep = sep_str, colClasses = col_classes)
    }
    names(reference_df) <- col_names
  } else {
    reference_df <- reference_file
  }
  bin_df <- inner_join(x = bin_df, y = reference_df, by = join_fields)
  return(bin_df)
}

#' Match bin locations (in bin_df) with segmentation locations (in seg_df)
#' bin_df and seg_df come from GetSegmentationFile and GetBinFile
#' need to split this up based on chr number or else it takes way, way too long
GetBinLocations <- function(bin_df, seg_df){
  # fail elegantly
  if (!is.element('start_idx', names(seg_df)) | !is.element('start_idx', names(bin_df))){
    warning('Can"t match seg_df and bin_df. Returning bin_df without peak information.')
    return(bin_df)
  }
  bin_df$peak_score <- 0
  bin_df$has_peak <- rep('no', dim(bin_df)[1])
  if(!grepl('chr', bin_df$chr)){
    bin_df$chr_str <- paste0('chr', bin_df$chr)  
  } else{
    bin_df$chr_str <- bin_df$chr
  }
  # use only seg_df that matches this chromosome
  seg_df_local <- seg_df %>% dplyr::filter(chr %in% unique(bin_df$chr_str))
  # check to see what segmentation matches with values in bins
  # do this in an ugly way first, then make it nicer later
  for (idx in 1:dim(seg_df_local)[1]){
    # which is the matching index in bin_df
    match_start_idx <- which(bin_df$start_idx == seg_df_local$start_idx_round[idx] & bin_df$chr_str == seg_df_local$chr[idx])
    match_end_idx <- which(bin_df$end_idx == seg_df_local$end_idx_round[idx] & bin_df$chr_str == seg_df_local$chr[idx])
    if (any(match_start_idx) && any(match_end_idx)){
      peak_range <- seq(match_start_idx, match_end_idx)
      bin_df$has_peak[peak_range] <- 'yes'
    }
  }
  return(bin_df)
}

# use this function to get a list of segmentation bins
GetSegmentationBinLocations <- function(seg_df, bin_size = 5000){
  if (seg_df$end_idx_round - seg_df$start_idx_round > bin_size){
    start_idx_list <- seq(from = seg_df$start_idx_round, to = seg_df$end_idx_round - bin_size, by = bin_size)
  } else {
    start_idx_list <- seg_df$start_idx_round
  }
  start_idx_df <- data.frame(start_idx_round = start_idx_list, chr = rep(seg_df$chr, times = length(start_idx_list)))
  return(start_idx_df)
}

# use ddply if want to run GetBinLocations on multiple chromosomes
GetBinLocationsByChromosome <- function(bin_df, seg_df){
  getChrStartIdx <- function(sub_seg_df) {
    peak_idx_only <- ddply(.data = sub_seg_df, .variables = c('start_idx_round', 'end_idx_round'), 
                                                                          .fun = GetSegmentationBinLocations)
  }
  sub_seg_df <- unique(seg_df[,c('start_idx_round', 'end_idx_round', 'chr')])
  peak_idx_df <- ddply(.data = sub_seg_df, .variables = 'chr', .fun = getChrStartIdx)
  peak_idx_df <- peak_idx_df[,c('start_idx_round', 'chr', 'has_peak')]
  names(peak_idx_df) <- c('start_idx', 'chr_str', 'has_peak')
  bin_df <- dplyr::full_join(bin_df, peak_idx_df)
  bin_df$has_peak[is.na(bin_df$has_peak)] <- 'no'
}

#! Want to get locations/counts of bins that are next to an identified peak
#! commented out in most places
GetAdjacentBinLocations <- function(bin_df){
  # fail elegantly
  if (!is.element('has_peak', names(bin_df))){
    warning('Need to add peak information with GetBinLocations.')
    return(bin_df)
  }
  bins_with_peaks <- which(bin_df$has_peak == 'yes')
  forward_idx <- bins_with_peaks + 1
  backward_idx <- bins_with_peaks - 1
  # make sure don't have overlap
  forward_idx <- setdiff(forward_idx, bins_with_peaks)
  backward_idx <- setdiff(backward_idx, bins_with_peaks)
  bin_df$has_peak[forward_idx] <- 'adjacent'
  bin_df$has_peak[backward_idx] <- 'adjacent'
  return(bin_df)
}

GetBinDf <- function(APP_full, joined_df, reference_df, use_segmentation = TRUE, 
                     use_wanted_chr = TRUE, wanted_chr = 19, bin_size = 5000, reference_file = "/seq/epiprod02/Polina/IGVCount/5k/bin_bl.bed"){
  # load bed file as bin_df
  bin_df <- GetBinFile(APP_full = APP_full, joined_df = joined_df, use_wanted_chr = use_wanted_chr, 
                       wanted_chr = wanted_chr, reference_file = reference_file)
  # bin locations for data collected with samtools starts with zero.
  if(reference_df$start_idx[1] == 0){
    bin_df <- RemoveBlacklist(bin_df = bin_df, reference_file = reference_df)
  }
  if(use_segmentation){
    seg_df <- GetSegmentationFile(APP_full = APP_full, joined_df = joined_df, wanted_chr = wanted_chr, 
                                        bin_size = bin_size)
    if(bin_df$start_idx[1] == 1){
      seg_df <- seg_df %>% mutate(start_idx_round = start_idx_round + 1)
    }
    bin_df <- GetBinLocations(bin_df = bin_df, seg_df = seg_df)
  }
  return(bin_df)
}

GetAPPTrackPairs <- function(lookup_filename = 'LIMSReports/20171025_All_H3k27ac_Tracks_andAPPs.csv', 
                             APP_list = NULL, Track_list = NULL){
  lookup_table <- GetFile(filename = lookup_filename, header_bool = TRUE, sep_str = ',')
  if(!is.null(APP_list)){
    table_subset <- join(x = data.frame(Alignment.Post.Processing = APP_list), y = lookup_table, 
                          by = "Alignment.Post.Processing", type = 'left')
  } else if(!is.null(Track_list)){
    table_subset <- join(x = data.frame(Name = Track_list), y = lookup_table, 
                          by = "Name", type = 'left')
  } else{
    return(NULL)
  }
  return(table_subset[,c('Alignment.Post.Processing', 'Name')])
}


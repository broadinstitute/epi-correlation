# this is the pipeline for the chromatin-gwas project
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(reshape))
#suppressPackageStartupMessages(library(ggplot2)) #GGPlot2 is not provided with this docker. - Polina

source("/scripts/ChromatinGWASPipeline/UsefulNoiseDistributionFitFunctions.R")
source("/scripts/ChromatinGWASPipeline/FitDistributionWithCVM.R")
source("/scripts/ChromatinGWASPipeline/UsefulFileLoadingFunctionsv2.R")

GetSaveFilename <- function(save_fields, joined_df, save_location, APP_full){
  if (save_location == "default") {
    bed_file_location <- joined_df %>% dplyr::filter(Name == APP_full) %>%
      dplyr::select(Binned.Filename)
    save_location <- dirname(
      path = toString(bed_file_location$Binned.Filename))
  }
  save_filename <- paste0(save_fields, collapse = "_")

  return(paste0(save_location, "/", save_filename, ".txt"))
}

# default save location is in same folder as bed_file_location
ProcessSingleFile <- function(APP_full, joined_df, reference_df,
    use_segmentation = FALSE, step_size = 0.01, save_location = "default",
    save_fields, p_value_thresh = 0.01, return_params = FALSE,
    save_params = FALSE, exclude_X_Y = TRUE,
    map_df_filename = "MappabilityTrack/binned_mappability_scores_5k.txt",
    map_df_sep = "\t", mappability_threshold = 0.9,
    estimation_method = "cvm", overwrite_file = FALSE,
    reference_file="/seq/epiprod02/Polina/IGVCount/5k/bin_bl.bed"){

  print(joined_df$Name)
  # load bed file as bin_df
  print(APP_full)
  # check that file exists
  if (!file.exists(joined_df$Binned.Filename[joined_df$Name == APP_full])){
    print(paste(APP_full, "does not exist"))
    return(FALSE)
  }
  # check that the file has size greater than zero
  file_info <- file.info(joined_df$Binned.Filename[joined_df$Name == APP_full])
  if (file_info$size == 0){
    print(paste(APP_full, "is improperly binned"))
    return(FALSE)
  } else if (file_info$size > 5e6){
    print(paste(APP_full, "has inappropriate header"))
    return(FALSE)
  }
  # check if file exists already
  save_filename <- GetSaveFilename(save_fields, joined_df, save_location,
    APP_full)
  if (file.exists(save_filename) & !overwrite_file){
    print(paste(APP_full, "already processed"))
    return(FALSE)
  }

  bin_df <- GetBinDf(
    APP_full = APP_full, joined_df = joined_df,
    reference_df = reference_df, use_segmentation = use_segmentation,
    use_wanted_chr = FALSE, bin_size = 5000, reference_file = reference_file
    )
  if (is.null(bin_df)){
    print(paste(APP_full, 
      "does not have the appropriate number of rows or columns."))
    return(FALSE)
  }

  # get p values
  if (estimation_method == "iteration"){
    params_df <- PValueIterator(working_df = bin_df, step_size = step_size)
    # only keep p values from last iteration; append these to bin_df
    bin_df$p_value <- params_df$px[dim(params_df)[1]][[1]]
    # this line useful if want to just keep rows above a certain p value threshold
    if ("p_value_thresh" %in% save_fields){
      bin_df$p_value_thresh <- bin_df$p_value < p_value_thresh
    }
  } else if (estimation_method == "cvm"){
    if (exclude_X_Y){
      working_df <- bin_df[!(bin_df$chr %in% c("chrX", "chrY")), ]
    } else{
      working_df <- bin_df
    }
    if (!is.null(mappability_threshold)){
      map_df <- read.table(file = map_df_filename, sep = map_df_sep,
        col.names = c("chr", "start_idx", "score"), header = FALSE)
      working_df <- left_join(x = working_df, y = map_df,
        by = c("chr", "start_idx"))
      working_df <- working_df[working_df$score > mappability_threshold, ]
    }
    params_df <- GetDistributionParametersWithOptim(working_df = working_df)
    bin_df$p_value <- pgamma(q = bin_df$norm_count, shape = params_df$k,
      rate = params_df$beta, lower.tail = FALSE)
    if ("p_value_thresh" %in% save_fields){
      bin_df$p_value_thresh <- bin_df$p_value_cvm < p_value_thresh
    }
  }

  if (grepl("chr", bin_df$chr[1])){
    bin_df$chr_str <- bin_df$chr
    bin_df <- bin_df %>% mutate(chr = gsub(pattern = "chr", replacement = "",
      x = chr_str))
  }

  #bin_df$chr <- as.numeric(bin_df$chr)
  # what to save?
  save_df <- bin_df[, save_fields]
  save_filename <- GetSaveFilename(save_fields, joined_df, save_location,
    APP_full)
  if (file.exists(save_filename)){
    print(paste("Removing", save_filename))
    file.remove(save_filename)
  }
  write.table(x = save_df, file = save_filename, sep = "\t", row.names = FALSE,
    col.names = FALSE, quote = FALSE, append = FALSE)
  if (save_params){
    params_filename <- GetSaveFilename(save_fields = "params_df",
      joined_df = joined_df, save_location = save_location,
      APP_full = APP_full)
    write.table(x = params_df, file = params_filename, sep = ",",
      row.names = FALSE, col.names = TRUE, quote = FALSE)
  }

  if (!return_params){
    return(TRUE)
  } else{
    return(params_df)
  }
}

# previous defaults: 
# joined_df_filename = '/seq/epiprod02/Polina/Pass3_CellDat/5k/Combined_APP_Segmentation_H3k27ac.csv'
# reference_df_filename = '~/Chromatin_GWAS/Chr5kBinsReference_BlacklistRemoved.csv'
# store arguments for ProcessSingleFile in ...
ProcessManyFiles <- function(
    joined_df_filename = "/seq/epiprod02/Polina/IGVCount/SANDBOX/5k/Combined_APP_Segmentation.csv",
    joined_df_sep_str = "\t",
    reference_df_filename = "/seq/epiprod02/Polina/IGVCount/5k/bin_bl.bed",
    reference_df_sep_str = " ", overwrite_file = FALSE, save_params = FALSE,
    use_wanted_APP = FALSE, wanted_APP = NULL, estimation_method = "cvm",
    save_fields = c("chr", "p_value"), save_location = "default",
    return_params = FALSE, bin_size = 5000,
    map_df_filename = "MappabilityTrack/binned_mappability_scores_5k.txt",
    map_df_sep = "\t", mappability_threshold = 0.9, exclude_X_Y = TRUE){

  joined_df <- read.csv(file = joined_df_filename, header = TRUE,
    sep = joined_df_sep_str, stringsAsFactors = FALSE)
  reference_df <- read.table(file = reference_df_filename, header = FALSE,
    sep = reference_df_sep_str, stringsAsFactors = FALSE)
    
  # check that all wanted_APP are in joined_df
  missing_APP <- sum(!(wanted_APP %in% joined_df$Name))
  if (missing_APP > 0){
    print(paste("Missing APP: ", wanted_APP[!(wanted_APP %in% joined_df$Name)],
      sep = "\n"))
    wanted_APP <- wanted_APP[wanted_APP %in% joined_df$Name]
  }

  if (dim(reference_df)[2] == 4){
    names(reference_df) <- c("chr", "start_idx", "end_idx", "chr_str")
    reference_df <- reference_df[, c("chr", "start_idx", "end_idx", "chr_str")]
  } else {
    names(reference_df) <- c("chr", "start_idx")
    reference_df$end_idx <- reference_df$start_idx + bin_size - 1
  }

  if (use_wanted_APP){
    APP_list <- as.character(wanted_APP)
  } else {
    APP_list <- joined_df$Name
  }

  tracker <- vector(mode = "list", length = length(APP_list))
  counter <- 1
  # run backwards (do newest APPs first, or ones with 9's first)
  APP_list <- sort(x = APP_list, decreasing = TRUE)
  for (APP in APP_list){
    tracker[[counter]] <- ProcessSingleFile(APP_full = APP,
      joined_df = joined_df, reference_df = reference_df,
      save_fields = save_fields, estimation_method = estimation_method,
      return_params = return_params, overwrite_file = overwrite_file,
      save_params = save_params, map_df_filename = map_df_filename,
      map_df_sep = map_df_sep, exclude_X_Y = exclude_X_Y,
      mappability_threshold = mappability_threshold,
      save_location = "default")
    if (counter %% 10 == 0){
      print(paste("Iteration", counter))
     }
    counter <- counter + 1
  }
  return(tracker)
}

# #add option to run if "main"
# main <- function(){
#   ProcessManyFiles()
# }
# 
# if(getOption('run.main', default=TRUE)){
#   main()
# }

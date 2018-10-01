suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(optparse))

option_list <- list(make_option("--input_loc"),
  make_option("--output_loc"),
  make_option("--is_mint", default = F))

opts <- parse_args(OptionParser(option_list = option_list))

# Combines the processed wig with the reference bins_template.bed file, ensuring that we have only the bins present in bins_template.
# This is important for a lot of our later processes.

# Our bin template, produced elsewhere & provided with this docker
bins_template <- read.table(
  "/reference/bins_template.bed",
  stringsAsFactors = F
  )
colnames(bins_template) <- c("chr", "start")

# Our reformatted BED file, containing 5kb regions and their coverage
sparse_coverage <- read.table(opts$input_loc, stringsAsFactors = F)
colnames(sparse_coverage) <- c("chr", "start", "count")

# Left join to ensure we have all of & only the bins in bins_template; set count to 0 where NA
final_coverage <- left_join(
  bins_template,
  sparse_coverage, by=c("chr", "start")
  )
final_coverage[which(is.na(final_coverage$count)), "count"] = 0

# read in mint blacklist & remove those bins
if(as.logical(opts$is_mint) == TRUE)
{
  mint_df <- read.table(
    file = "/reference/mint_blacklist_5k.bed", sep="\t",
    col.names = c("chr","start","stop"),
    header = FALSE,
    stringsAsFactors = FALSE
  )
  final_coverage <- anti_join(final_coverage, mint_df, by=c("chr","start"))
}

# Save
write.table(opts$output_loc, x=final_coverage,row.names = F, col.names = F,quote=F)
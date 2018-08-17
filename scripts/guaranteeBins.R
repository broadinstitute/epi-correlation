suppressPackageStartupMessages(library(dplyr))

# Combines the processed wig with the reference bins_template.bed file, ensuring that we have only the bins present in bins_template.
# This is important for a lot of our later processes.
# Get Input (args[1]) & Output (args[2]) location
args=commandArgs(trailingOnly=TRUE)

# Our bin template, produced elsewhere & provided with this docker
bins_template <- read.table("/reference/bins_template.bed", stringsAsFactors = F)
colnames(bins_template) <- c("chr","start")

# Our reformatted BED file, containing 5kb regions and their coverage
sparse_coverage <- read.table(args[1], stringsAsFactors = F)
colnames(sparse_coverage) <- c("chr","start","count")

# Left join to ensure we have all of & only the bins in bins_template; set count to 0 where NA
final_coverage <- left_join(bins_template, sparse_coverage, by=c("chr","start"))
final_coverage[which(is.na(final_coverage$count)),"count"] = 0

# Save
write.table(args[2],x=final_coverage,row.names = F, col.names = F,quote=F)

library(dplyr)

# Combines the processed wig with the reference bins_template.bed file, ensuring that we have only the bins present in bins_template.
# This is important for a lot of our later processes.
# TODO : This could be neater.
args= commandArgs(trailingOnly=TRUE)
bin_bl <- read.table("/reference/bins_template.bed", stringsAsFactors = F)
new_cov <- read.table(args[1], stringsAsFactors = F)
final_cov <- left_join(bin_bl, new_cov, by=c("V1","V2")) # V1,V2 = chr, start
final_cov[which(is.na(final_cov$V3)),"V3"] = 0 # V3 = count
write.table(args[2],x=final_cov,row.names = F, col.names = F,quote=F)

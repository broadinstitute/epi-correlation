library(dplyr)
args= commandArgs(trailingOnly=TRUE)
bin_bl <- read.table("bin_bl.bed", stringsAsFactors = F)
new_cov <- read.table(args[1], stringsAsFactors = F)
final_cov <- left_join(bin_bl, new_cov, by=c("V1","V2"))
final_cov[which(is.na(final_cov$V3)),"V3"] = 0
write.table(args[2],x=final_cov,row.names = F, col.names = F,quote=F)

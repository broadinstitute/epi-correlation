#!/usr/bin/env Rscript

options(repos = c(CRAN = "https://cloud.r-project.org/"))

install.packages(c("plyr","tidyr","dplyr","reshape","optparse", "fBasics", "goftest"))
# GGPlot2 is not provided with this docker. A few of the included scripts, however, provide functions
#	that do GGPlot2 plotting. Either run the below command later in R in the docker to use them, or
#	uncomment it below.
#install.packages(c("ggplot2"))

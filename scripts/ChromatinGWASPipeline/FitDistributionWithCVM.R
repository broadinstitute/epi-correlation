suppressPackageStartupMessages(library(plyr))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(reshape))
#library(ggplot2) # GGPlot2 is not provided with this Docker. - Polina
suppressPackageStartupMessages(library(fBasics))
suppressPackageStartupMessages(library(goftest))

source('/scripts/ChromatinGWASPipeline/UsefulFileLoadingFunctionsv2.R')
source('/scripts/ChromatinGWASPipeline/UsefulNoiseDistributionFitFunctions.R')

GetParameterCombinations <- function(beta_range = c(0.5, 1), k_range = c(18, 25), lambda_range = c(0.6, 0.9)){
  params_all <- expand.grid(beta = beta_range, k = k_range, lambda = lambda_range)
  # refine the grid a little
  params_all$params_num <- 1:nrow(params_all)
  return(params_all)
}

cvm.test2 <- function(x, null="punif", ..., nullname) {
  xname <- deparse(substitute(x))
  nulltext <- deparse(substitute(null))
  if(is.character(null)) nulltext <- null
  if(missing(nullname) || is.null(nullname)) {
    reco <- recogniseCdf(nulltext)
    nullname <- if(!is.null(reco)) reco else 
      paste("distribution", sQuote(nulltext))
  }
  stopifnot(is.numeric(x))
  x <- as.vector(x)
  n <- length(x)
  F0 <- if(is.function(null)) null else
    if(is.character(null)) get(null, mode="function") else
      stop("Argument 'null' should be a function, or the name of a function")
  U <- F0(x, ...)
  if(any(is.nan(U)) | any(is.na(U))){
    browser()
  }
  if(any(U < 0 | U > 1))
    U[U < 0] = 0; U[U > 1] = 1
    # print('Warning: coercing U to between 0 and 1')
#     stop("null distribution function returned values outside [0,1]")
  U <- sort(U)
  k <- seq_len(n)
  #omega2 <- 1/(12 * n) + sum((1-Heaviside(k,0.5*n))*(U - (2 * k - 1)/(2 * n))^2)
  omega2 <- 1/(12 * n) + sum((1-Heaviside(k,0.5*n))*(U - (2 * k - 1)/(2 * n))^2)
  PVAL <- pCvM(omega2, n=n, lower.tail=FALSE)
  names(omega2) <- "omega2"
  METHOD <- c("Cramer-von Mises test of goodness-of-fit",
              paste("Null hypothesis:", nullname))
  extras <- list(...)
  parnames <- intersect(names(extras), names(formals(F0)))
  if(length(parnames) > 0) {
    pars <- extras[parnames]
    pard <- character(0)
    for(i in seq_along(parnames))
      pard[i] <- paste(parnames[i], "=", paste(pars[[i]], collapse=" "))
    pard <- paste("with",
                  ngettext(length(pard), "parameter", "parameters"),
                  "  ", 
                  paste(pard, collapse=", "))
    METHOD <- c(METHOD, pard)
  }
  out <- list(statistic = omega2,
              p.value = PVAL,
              method = METHOD,
              data.name = xname)
  class(out) <- "htest"
  return(out)
}

pgamma_null <- function(q, params_df, weight_value){
  pgamma_mix <- params_df$lambda*pgamma(q = q, shape = params_df$k, rate = params_df$beta) +
    (1 - params_df$lambda)*punif(q = q, min = weight_value, max = 1.01*weight_value)
  return(pgamma_mix)
}

# try calculating cost using Cramer Von Mises
getCVMDistance <- function(working_df, params_df, weight_value){
  cvm_stat <- cvm.test2(x = working_df$Counts, null = 'pgamma_null', 'params_df' = params_df, 
                        'weight_value' = weight_value)
  return(cvm_stat$statistic)
}

GetDistributionParameters <- function(working_df, lambda_range = seq(from = 0.6, to = 1, by = 0.05), 
                                      fix_weight = TRUE, weight_value = 500, use_log = FALSE, length_out = 100,
                                      max_range_multiple = 300, plot_data = FALSE){
  working_df <- working_df %>% dplyr::filter(Counts > 0)
  if(use_log){
    working_df$log_count <- log(working_df$Counts)
    working_df$Counts <- working_df$log_count
    bin_width <- 0.1; max_dens <- 10
  } else{
    bin_width <- 10; max_dens <- 500
  }
  mean_init <- mean(working_df$Counts); var_init <- var(working_df$Counts)
  beta_init <- mean_init/var_init; k_init <- mean_init*beta_init 
  params_all <- GetParameterCombinations(beta_range = seq(beta_init, max_range_multiple*beta_init, length.out = length_out), 
                                         k_range = seq(k_init, max_range_multiple*k_init, length.out = length_out), 
                                         lambda_range = lambda_range)
  # set max and min vals for weight at far limit of distribution
  if(!fix_weight){
    weight_value <- 0.99*max(working_df$Counts)
  }
  #params_all <- RefineParameterCombinations(params_all)
  cvm_stat_list <- ddply(.data = params_all, .variables = 'params_num', .fun = getCVMDistance, 'working_df' = working_df, 
                         'weight_value' = weight_value)
  # make a heat map of cvm_stat_list
  cvm_stat_list <- inner_join(x = cvm_stat_list, y = params_all, by = "params_num")
  if(plot_data){
    ggplot(cvm_stat_list, aes(x = beta, y = k)) + geom_tile(aes(fill = omega2))
  }
  # what's the parameter value at the minimum cost?
  optim_params <- params_all[which.min(cvm_stat_list$omega2),]
  optim_params$Name <- working_df$Name[1]
  # plot data
  if(plot_data){
    sim_df <- data.frame(x = 0:max_dens, y = dgamma(x = 0:max_dens, shape = optim_params$k, rate = optim_params$beta))
    plt_base <- ggplot(working_df, aes(x = thresh_count, y = ..density..))
    plt1 <- plt_base + geom_histogram(aes(fill = has_peak), position = 'identity', binwidth = bin_width, alpha = 0.5) +
      geom_line(data = sim_df, aes(x = x, y = y)) + 
      ggtitle(label = paste(working_df$Name[1], ': bin counts histogram'))
    plt2 <- plt_base + geom_histogram(position = 'identity', binwidth = bin_width, alpha = 0.5) +
      geom_line(data = sim_df, aes(x = x, y = y*optim_params$lambda)) + 
      ggtitle(label = paste(working_df$Name[1], ': bin counts histogram (no peaks)'))
    plt3 <- ggplot(data = data.frame(x = pgamma(q = working_df$Counts, shape = optim_params$k, rate = optim_params$beta, 
                                                lower.tail = FALSE), has_peak = working_df$has_peak), aes(x = x)) +
      geom_histogram(binwidth = 0.025, aes(fill = has_peak), color = 'black') + ggtitle('P value distribution')
    multiplot(plt1, plt2, plt3, cols = 2)
  }
  return(optim_params)
}

# get initial values from GetDistributionParameters with coarse-grained grid
GetDistributionParametersWithOptim <- function(working_df, lambda_range = seq(0.6, 0.9, by = 0.1), length_out = 3,
                                                fix_weight = TRUE, weight_value = 500, plot_data = FALSE,
                                                bin_width = 10, max_dens = 500){
  working_df <- working_df %>% dplyr::filter(Counts > 0)
  params_init <- GetDistributionParameters(working_df = working_df, lambda_range = lambda_range, length_out = length_out)
  # set max and min vals for weight at far limit of distribution
  beta_init <- params_init$beta; k_init <- params_init$k; lambda_init <- params_init$lambda
  if(!fix_weight){
    weight_value <- 0.99*max(working_df$Counts)
  }
  # use optim to calculate parameters
  optim_params <- optim(par = c(beta_init, k_init, lambda_init), 
                            fn = function(par){params_df <- data.frame(beta = par[1], k = par[2], lambda = par[3])
                                                  getCVMDistance(params_df = params_df, 
                                                                 weight_value = weight_value, working_df = working_df)}, 
                              method = 'L-BFGS-B', lower = c(1e-5, 1e-5, 1e-5), upper = c(Inf, Inf, 1))
  # plot data
  if(plot_data){
    GetMultiplotHistograms(max_dens = max_dens, beta = optim_params$par[1], k = optim_params$par[2], 
                           lambda = optim_params$par[3], working_df = working_df, bin_width = bin_width)  
  }
  # calculate CVM with optimal parameters
  cvm <- getCVMDistance(working_df = working_df, weight_value = weight_value,
                        params_df = 
                          data.frame(beta = optim_params$par[1], k = optim_params$par[2], lambda = optim_params$par[3]))
  if('has_peak' %in% names(working_df)){
    return(data.frame(beta = optim_params$par[1], k = optim_params$par[2], lambda = optim_params$par[3],
                      cvm = cvm, no_peak = mean(working_df$has_peak == 'no'),
                      Name = working_df$Name[1]))
  } else if ('Name' %in% names(working_df)){
    return(data.frame(beta = optim_params$par[1], k = optim_params$par[2], lambda = optim_params$par[3],
                      cvm = cvm, Name = working_df$Name[1])) 
  }
    else{
    return(data.frame(beta = optim_params$par[1], k = optim_params$par[2], lambda = optim_params$par[3], cvm = cvm)) 
  }
  
}
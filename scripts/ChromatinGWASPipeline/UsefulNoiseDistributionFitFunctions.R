# this file contains useful functions for calculating fit distributions

#-----Functions for modeling truncated distributions----------#
library(dplyr)
#library(ggplot2) #GGPlot2 is not provided with this docker. - Polina
library(reshape)

GetGammaFromMuSigma <- function(sigma, mu, var_in, fun_str, lower_tail = FALSE, show_output = FALSE){
  # the meaning of var_in varies depending on the function: pgamma = q, dgamma = x, qgamma = p, rgamma = n
  # E[X] = shape/rate; var[x] = shape/(rate^2); k = shape; rate = beta
  var <- sigma^2
  beta <- mu/var
  k <- beta*mu
  funName <- match.fun(fun_str)
  if (show_output){
    print(paste('Returning', fun_str))
  }
  if (grepl(pattern = 'p', x = fun_str) | grepl(pattern = 'q', x = fun_str)){
    values <- funName(var_in, shape = k, rate = beta, lower.tail = lower_tail)  
  } else {
    values <- funName(var_in, shape = k, rate = beta)
  }
  return(values)
}

# need to create distributions, determine what sigma, mu are when some fraction of distribution is excluded
# params_df fields sigma0, mu0 (need this to be able to use ddply--otherwise GetLookupTable will be too slow)
GetTruncDistribution <- function(params_df, n_points, threshold){
  # first calculate distribution with existing sigma, mu, n_points
  sigma0 <- params_df$sigma0 
  mu0 <- params_df$mu0
  gamma_sim <- GetGammaFromMuSigma(sigma = sigma0, mu = mu0, var_in = n_points, 
                                   fun_str = 'rgamma', show_output = FALSE)
  # then remove all p_values below a threshold
  # replace with qgamma
  x_thresh <- GetGammaFromMuSigma(sigma = sigma0, mu = mu0, var_in = threshold, 
                                  fun_str = 'qgamma', show_output = FALSE)
  below_thresh <- gamma_sim[gamma_sim < x_thresh]
  sigma_trunc <- sd(below_thresh)
  mu_trunc <- mean(below_thresh)
  return(data.frame(mu_trunc = mu_trunc, sigma_trunc = sigma_trunc))
}

# create lookup table for sigma, mu to pass into gamma distribution


GetLookupTable <- function(sigma_vals, mu_vals, test_thresh = 0.2){
  # create all possible combinations of sigma and mu vals in a dataframe
  input_df <- expand.grid(sigma0 = sigma_vals, mu0 = mu_vals)
  input_df$idx <- as.numeric(rownames(input_df))
  # need to remove poorly behaving sections--i.e. ones where sigma >= mu
  input_df <- input_df %>% dplyr::filter(mu0 >= sigma0)
  # create another column with the mean and standard deviation of the truncated distribution
  for (curr_thresh in test_thresh){
    thresh_df <- ddply(input_df, .(idx), GetTruncDistribution, 'n_points' = 10000, 'threshold' = curr_thresh)
    sigma_str <- paste('sigma', curr_thresh, sep = '_')
    mu_str <- paste('mu', curr_thresh, sep = '_')
    input_df[sigma_str] <- thresh_df$sigma_trunc
    input_df[mu_str] <- thresh_df$mu_trunc
  }
  return(input_df)
}

# use lookup table to produce a loess model; this will be used to predict future parameters 
# NOTE: this function can be changed if desired to use lm as model rather than loess
GetLoessModel <- function(input_df, sigma_trunc_str = 'sigma_0.2', mu_trunc_str = 'mu_0.2', use_subset = FALSE){
  # use formula to calculate mu, sigma for a given pair of mu_trunc and sigma_trunc
  mu_formula <- as.formula(paste('mu0', '~', mu_trunc_str, '+', sigma_trunc_str))
  sigma_formula <- as.formula(paste('sigma0', '~', mu_trunc_str, '+', sigma_trunc_str))
  if (use_subset){
    train_idx <- sample(x = dim(input_df)[1], size = floor(dim(input_df)[1]/3))
    mu_model <- loess(formula = mu_formula, data = input_df, subset = train_idx, span = span)
    sigma_model <- loess(formula = sigma_formula, data = input_df, subset = train_idx, span = span)
  } else {
    mu_model <- loess(formula = mu_formula, data = input_df)
    sigma_model <- loess(formula = sigma_formula, data = input_df)
  }
  return(list(sigma_model = sigma_model, mu_model = mu_model))
}

# sigma_explain, mu_explain are the new data pair that will be applied to the model
# pay careful attention to the order, otherwise model will return the wrong value
# newdata_df has columns mu_trunc_str and sigma_trunc_str
# for example: names(input_df) = sigma_0.2, mu_0.2
PredictValuesFromLoessModel <- function(model_object, newdata_df){
  loess_predict <- predict(object = model_object, newdata = newdata_df)
  return(loess_predict)
}

#--------------Functions for iterating over p values---------------------------#
# for initializing recalculte_idx
InitializeRecalculateIdx <- function(working_df, step_size){
  stats_df0 <- working_df %>% dplyr::filter(norm_count > 0) %>% summarise(mu0 = mean(norm_count), sigma0 = sd(norm_count))
  px0 <- GetGammaFromMuSigma(sigma = stats_df0$sigma0, mu = stats_df0$mu0, var_in = working_df$norm_count, fun_str = 'pgamma')
  recalculate_idx <- px0 > step_size
  return(recalculate_idx)
}

# optional arguments: input_df, mean0, std0
PValueIterator <- function(working_df, step_size = 0.01, max_iter = 15, tolerance = 0.5, use_model = FALSE, ...){
  list_args <- list(...)
  if ('input_df' %in% names(list_args)){
    input_df <- list_args$input_df
    use_model <- TRUE
    sigma_trunc_str <- paste0('sigma_', step_size); mu_trunc_str <- paste0('mu_', step_size)
    # model_list has sigma_model and mu_model
    model_list <- GetLoessModel(input_df = input_df, sigma_trunc_str = sigma_trunc_str, mu_trunc_str = mu_trunc_str)
  } 
  recalculate_idx <- InitializeRecalculateIdx(working_df, step_size)  
  num_iter <- 1
  params_df <- data.frame(beta = numeric(max_iter), k = numeric(max_iter), mean = numeric(max_iter), 
                          sd = numeric(max_iter), px = numeric(max_iter))
  StopCriterion <- function(mean1, mean0){abs((mean1 - mean0)/mean0)*100 < tolerance}
  # now iterate
  while (num_iter <= max_iter){
    stats_df <- working_df[recalculate_idx,] %>% dplyr::filter(norm_count > 0) %>% 
                  dplyr::summarise(mu_count = mean(norm_count), sigma_count = sd(norm_count))
    if (use_model){
      names(stats_df) <- c(mu_trunc_str, sigma_trunc_str)
      params_list <- llply(.data = model_list, .fun = PredictValuesFromLoessModel, 'newdata' = stats_df)
      mu_count <- params_list$mu_model; sigma_count <- params_list$sigma_model;
      beta <- mu_count/sigma_count^2; k <- beta*mu_count
      px <- GetGammaFromMuSigma(sigma = sigma_count, mu = mu_count, var_in = working_df$norm_count, fun_str = 'pgamma')
      #px <- ptrunc(q = working_df$norm_count, spec = 'gamma', a = 0, b = max(working_df$norm_count[recalculate_idx]), 
                   #shape = k, rate = beta, lower.tail = FALSE)
    } else{
      mu_count <- stats_df$mu_count; sigma_count <- stats_df$sigma_count
      px <- GetGammaFromMuSigma(sigma = sigma_count, mu = mu_count, var_in = working_df$norm_count, fun_str = 'pgamma')
    }
    # collect parameters
    params_df$beta[num_iter] <- mu_count/sigma_count^2; params_df$k[num_iter] <- params_df$beta[num_iter]*mu_count
    params_df$mu[num_iter] <- mu_count; params_df$sigma[num_iter] <- sigma_count; 
    params_df$px[num_iter] <- list(px)
    params_df$iter_num[num_iter] <- num_iter
#     ks_value <- ks.test(x = working_df$norm_count[working_df$norm_count > 0], 
#                         y = 'pgamma', shape = params_df$k[num_iter], rate = params_df$beta[num_iter])
#     params_df$ks_value[num_iter] <- ks_value$statistic
#     # update recalculate_idx
    recalculate_idx <- px > step_size
    num_iter <- num_iter + 1
  }
  params_df$Name <- working_df$Name[1]
  return(params_df)
}

#-----------Plotting functions--------------------#
# use this function to plot the p value histograms for a single APP
GetPValueHistogram <- function(params_df, subtitle_str = 'Iteration_no', title_str = ''){
  # convert lists of px to dataframe
  px_df <- as.data.frame(params_df$px)
  names(px_df) <- paste(subtitle_str, as.factor(1:dim(px_df)[2]), sep = '_')
  px_melted <- melt(data = px_df)
  names(px_melted) <- c(subtitle_str, 'P_value')
  if(title_str == ''){
    title_str <- paste('P value distribution vs', subtitle_str)
  } 
  p_hist <- ggplot(px_melted, aes(x = P_value, y = ..density..)) + 
    geom_histogram(binwidth = 0.05, fill = 'white', color = 'black') + 
    geom_hline(yintercept = 0.5, linetype = 'dashed', color = 'blue') +
    facet_wrap(as.formula(paste0('~', subtitle_str) ))+ ggtitle(label = title_str) +
    theme(text = element_text(size = 16))
  p_dens <- ggplot(px_melted, aes(x = P_value)) + geom_density(aes_string(color = subtitle_str)) +
    theme(text = element_text(size = 14)) + ggtitle(label = title_str)
  print(p_hist); print(p_dens)
}

# use this function to plot overlay of norm_count data with estimated parameters
# has_peak indicates whether or not to include peak information
GetIterationHistogram <- function(params_df, working_df, has_peak = TRUE, bin_width = 0.1, x_lim = 25){
  # need to first construct df with all the relevant data; involves repeating norm_count a bunch of times (sadly)
  # run this a few times with dlply
  getIterDf <- function(params_df_subset, norm_count, has_peak = NA){
    df_len <- length(norm_count)
    iter_df_subset <- data.frame(norm_count = numeric(df_len), sim_vals = numeric(df_len))
    iter_df_subset$norm_count <- norm_count
    iter_df_subset$name <- paste0('Beta = ', toString(round(params_df_subset$beta, 3)), 
                                 ', k = ', toString(round(params_df_subset$k, 3)),
                                '\n Mean = ', toString(round(params_df_subset$mu, 1)), 
                               ', Sd = ', toString(round(params_df_subset$sigma, 0)))
    iter_df_subset$sim_vals <- rgamma(n = df_len, shape = params_df_subset$k, rate = params_df_subset$beta)
    if (length(has_peak) > 1){iter_df_subset$has_peak <- has_peak}
    return(iter_df_subset)
  }
  iter_df_all <- dlply(.data = params_df, .fun = getIterDf, .variables = 'iter_num', 'norm_count' = working_df$norm_count, 
                                                                      'has_peak' = working_df$has_peak)
  # plot the data from iter_df_all
  iter_df_melted <- do.call('rbind', iter_df_all)
  iter_hist <- ggplot(iter_df_melted, aes(x = norm_count, y = ..density..)) + 
                geom_histogram(aes(fill = has_peak), binwidth = bin_width, position = 'identity', alpha = 0.5) +
                geom_density(aes(x = sim_vals), trim = TRUE) + 
                facet_wrap(~ name) + theme(text = element_text(size = 16)) +
                ggtitle(params_df$Name[1]) + coord_cartesian(xlim = c(0, x_lim))
  print(iter_hist)
}

# use this function to plot the final distributions for multiple APPs
# set converge_params_df if using old method to calculate p values (i.e. p value iteration)
GetComparisonHistogram <- function(bin_df_all, params_df_all, has_peak = TRUE, bin_width = 10, max_dens = 500, min_dens = 0,
                                   converge_params_df = FALSE, factor_levels = NULL){
  if(converge_params_df){
    params_df_melted <- do.call('rbind', params_df_all)
    params_df_converged <- params_df_melted %>% group_by(Name) %>% 
      dplyr::summarize(beta = dplyr::last(beta), k = dplyr::last(k))
  } else if(!is.data.frame(params_df_all)){
    params_df_converged <- do.call('rbind', params_df_all)
  } else {
    params_df_converged <- params_df_all
  }
  bin_df_melted <- do.call('rbind', bin_df_all)
  GetSimulatedDistribution <- function(params_df_converged, npoints = 512){
    sim_distribution <- data.frame('sim_values' = numeric(npoints))
    sim_distribution$sim_values <- dgamma(x = seq(0, max_dens, length.out = npoints), shape = params_df_converged$k, 
                                          rate = params_df_converged$beta)
    if('lambda' %in% names(params_df_converged)){
      sim_distribution$sim_values <- sim_distribution$sim_values*params_df_converged$lambda
      if(has_peak){
        sim_distribution$sim_values <- sim_distribution$sim_values/params_df_converged$no_peak
      }
    }
    sim_distribution$x_values <- seq(0, max_dens, length.out = npoints)
    sim_distribution$Name <- params_df_converged$Name[1]
    sim_distribution$Name_full <- paste(params_df_converged$Name, 'k =', round(params_df_converged$k,1))
    return(sim_distribution)
  }
  test_sim <- dlply(params_df_converged, .(Name), GetSimulatedDistribution, npoints = 10000)
  test_sim_melted <- do.call('rbind', test_sim)
  if(!is.null(factor_levels)){
    bin_df_melted$Name <- factor(x = bin_df_melted$Name, levels = factor_levels)
  } else{
    bin_df_melted$Name <- factor(x = bin_df_melted$Name, levels = unique(bin_df_melted$Name))   
  }
  test_sim_melted$Name <- factor(test_sim_melted$Name, levels = levels(bin_df_melted$Name))
  fit_plot <- ggplot(bin_df_melted %>% dplyr::filter(thresh_count > min_dens), aes(x = thresh_count))
  params_text <- paste(params_df_converged$Name, round(params_df_converged$k, 2))
  if(has_peak){
    fit_plot <- fit_plot + 
      geom_histogram(aes(y = ..density.., fill = has_peak), alpha= 0.5, binwidth = bin_width, position = 'identity')
  } else {
    fit_plot <- fit_plot + 
      geom_histogram(aes(y = ..density..), alpha= 0.5, binwidth = bin_width, position = 'identity')
  }
  fit_plot <- fit_plot + 
    geom_line(data = test_sim_melted, aes(x = x_values, y = sim_values, color = 'Sim fit'), color = 'black') + 
    #ggtitle(label = paste('P value over iteration number,', params_df$Name[1])) +
    coord_cartesian(xlim = c(min_dens, max_dens)) +
    theme(text = element_text(size = 16)) + facet_wrap(~Name)
  print(fit_plot)
  return(fit_plot)
}

# use this function to plot the p value histograms for multiple data frames
GetPValueComparisonHistogram <- function(params_df_all, bin_df_all, bin_width = 0.05, factor_levels = NULL){
  if(!is.data.frame(params_df_all)){
    params_df_melted <- do.call('rbind', params_df_all)  
    params_df_converged <- params_df_melted %>% group_by(Name) %>% 
      dplyr::summarize(beta = dplyr::last(beta), k = dplyr::last(k))
  } else {
    params_df_converged <- params_df_all
  }
  px_list <- vector(mode = 'list', length = dim(params_df_melted)[1])
  #px_df <- data.frame(matrix(nrow = nrow(bin_df_all[[1]]), ncol = nrow(params_df_converged)))
  #names(px_df) <- params_df_converged$Name
  bin_df_names <- laply(.data = bin_df_all, .fun = function(bin_df){bin_df$Name[1]})
  for(idx in 1:nrow(params_df_converged)){
    wanted_idx <- which(bin_df_names == params_df_converged$Name[idx])
    working_df <- bin_df_all[[wanted_idx]]
    print(working_df$Name[1])
    working_df <- working_df %>% dplyr::filter(norm_count > 0)
    params_df <- params_df_converged[idx,]
    px <- pgamma(q = working_df$norm_count, shape = params_df$k, rate = params_df$beta, lower.tail = FALSE)
    px_df <- data.frame('Name' = params_df_converged$Name[idx], 'px' = px)
    px_list[[idx]] <- px_df
  }
  px_melted <- do.call('rbind', px_list)
  names(px_melted) <- c('Name', 'p_value')
  if(!is.null(factor_levels)){
    px_melted$Name <- factor(px_melted$Name, levels = factor_levels)
  }
  p_hist <- ggplot(px_melted, aes(x = p_value, y = ..density..)) + 
    geom_histogram(binwidth = bin_width, fill = 'white', color = 'black') + 
    geom_hline(yintercept = 1, linetype = 'dashed', color = 'blue') +
    facet_wrap(~ Name)+ theme(text = element_text(size = 16))
  print(p_hist)
}

# use this function to plot p values overlaid on bin distribution
GetPValueLevelHistogram <- function(working_df, params_df){
  blues <- colorRampPalette(c('dark blue', 'light blue'))
  px_df <- as.data.frame(params_df$px)
  names(px_df) <- paste('Iteration_', as.factor(1:min(dim(px_df))))
  px_melted <- melt(data = px_df)
  names(px_melted) <- c('Iteration_no', 'P_value')
  # need to have fixed intervals for aes(fill) to work
  px_melted$round_P <- round(px_melted$P_value, digits = 2)
  px_melted$norm_count <- rep(x = working_df$norm_count, times = dim(params_df)[1])
  p_level_hist <- ggplot(px_melted, aes(x = norm_count, y = ..density..)) + 
                    geom_histogram(aes(fill = as.factor(round_P)), binwidth = 0.1) + 
                    theme(legend.position = 'none') +
                    facet_wrap(~Iteration_no) + coord_cartesian(x = c(0, 25))
}

RunAllCalculations <- function(bin_df_all, use_model, input_df){
  # do the above for a bunch of APPs
  for (idx in seq(1,10)){
    working_df <- bin_df_all[[idx]]
    params_df <- PValueIterator(working_df, step_size = 0.01, max_iter = 12, use_model = use_model)
    GetPValueHistogram(params_df = params_df)
    GetIterationHistogram(params_df = params_df, working_df = working_df)
  }
  
  # also calculate the ks values for a bunch of APPs
  params_df_all <- vector(mode = 'list', length = 12)
  for (idx in seq(1,10)){
    working_df <- bin_df_all[[idx]]
    params_df <- PValueIterator(working_df, step_size = 0.01, max_iter = 12, use_model = use_model)
    params_df_all[[idx]] <- params_df
  }
  
  params_df_melted <- do.call('rbind', params_df_all)
  ggplot(params_df_melted, aes(x = rep(1:12, 10), y = ks_value)) + geom_point() + facet_wrap(~Name) + 
    theme(text = element_text(size = 16)) + facet_wrap(~Name)
  return(params_df_all)
}

# plot qqplot
GetComparisonQQPlot <- function(bin_df_all, params_df_all){
  params_df_melted <- do.call('rbind', params_df_all)
  bin_df_melted <- do.call('rbind', bin_df_all)
  params_df_converged <- params_df_melted %>% group_by(Name) %>% 
    dplyr::summarize(beta = dplyr::last(beta), k = dplyr::last(k))
  GetSimulatedQuantiles <- function(params_df_converged, bin_df, p_value_thresh = 0.01){
    norm_count <- bin_df %>% dplyr::filter(Name == params_df_converged$Name[1]) %>%
                    dplyr::filter(norm_count > 0) %>% select(norm_count)
    npoints <- length(norm_count$norm_count)
    sim_distribution <- data.frame('sim_values' = numeric(npoints))
    x_values <- seq(from = 0, to = 1, length.out = npoints)
    sim_distribution$sim_values <- qgamma(p = x_values, 
                                          shape = params_df_converged$k, 
                                          rate = params_df_converged$beta, lower.tail = FALSE)
    sim_distribution$p_thresh <- qgamma(p = p_value_thresh, shape = params_df_converged$k,
                                        rate = params_df_converged$beta, lower.tail = FALSE)
    sim_distribution$x_values <- x_values
    sim_distribution$Name <- params_df_converged$Name[1]
    sim_distribution$norm_count <- sort(norm_count$norm_count, decreasing = TRUE)
    return(sim_distribution)
  }
  qq_sim <- dlply(params_df_converged, .(Name), GetSimulatedQuantiles, 'bin_df' = bin_df_melted)
  qq_sim_melted <- do.call('rbind', qq_sim)
  qq_plot <- ggplot(qq_sim_melted, aes(x = sim_values, y = norm_count)) + geom_point() + 
              geom_line(linetype = 'dotted') + facet_wrap(~Name) +
              theme(text = element_text(size = 16)) + scale_y_continuous(limits = c(0, 500)) +
              scale_x_continuous(limits = c(0,125)) + 
              geom_abline(slope = 1, intercept = 0, linetype = 'dashed', color = 'blue') + 
              geom_hline(aes(yintercept = p_thresh), color = 'darkred', linetype = 'dashed')
  print(qq_plot)
}

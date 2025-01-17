#' Optimum interventions under the single center LAGO design
#' @description This function takes as input several study design parameters of a multi-stage, single center per stage LAGO design and provides the estimated optimal intervention package through simulations. The required parameters that need to be supplied to the function are an initial starting intervention package which is optimized over the stages, the lower and upper limits for the components of the intervention package, the true or best guess beta values, number of stages K, sample size per stage n, the unit costs for the intervention package components and the desired outcome goal for the LAGO study. Since this function returns the estimated optimal interventions through simulations, this function also needs as input the expected variation among the subjects within the center at any stage.
#' @param x0 a vector of starting values for the components of the intervention package
#' @param lower a vector providing the values of lower limits for the components of the intervention package
#' @param upper a vector providing the values of upper limits for the components of the intervention package
#' @param nstages the number of stages of the LAGO design K (>=2)
#' @param beta.true a vector of true i.e. population beta values
#' @param sample.size sample size (n) in each of the K stages
#' @param icc the expected variation among subjects within the center at any stage
#' @param cost.vec a vector of per unit linear cost coefficients
#' @param prob the desired outcome goal
#' @param intercept a logical argument to include intercept in the model or not (default = TRUE)
#' @param B the number of simulations (default = 100)
#'
#' @return The returned value is a named list containing
#' \item{xopt}{a dataframe containing the stage-wise estimated optimum intervention package obtained by considering the median over the given number of simulations}
#' \item{p.opt.hat}{a vector containing the stage-wise estimated success probabilities, i.e. the success probabilities corresponding to the estimated optimal intervention package by considering the median over simulations}
#' @export
#'
#' @examples
#' x.init = c(2.5, 12.5, 7) # Initial value interventions
#' x.l = c(1, 10, 2) # Lower limits for X
#' x.u = c(4, 15, 15) # Upper limits for X
#' n = 50 # Sample size
#' K = 3 # Number of stages
#' cost_lin = c(1, 8, 2.5) # Costs
#' p_bar = 0.9 # Desired outcome goal
#' # True/best guess beta values
#' beta = c(log(0.05), log(1.2), log(1.1), log(1.3))
#'
#' sim_sc <- sc_lago(x0 = x.init, lower = x.l, upper = x.u,
#'                   nstages = K, beta.true = beta,
#'                   sample.size = n, icc = 0.1,
#'                   cost.vec = cost_lin, prob = p_bar,
#'                   B = 100, intercept = TRUE)
#'
sc_lago <- function(x0, lower, upper, nstages, beta.true, sample.size, icc, cost.vec, prob, intercept = TRUE, B = 100){
  # Compatibility checks for arguments
  if(length(upper) != length(lower)) stop("lower and upper limits of the components are not at the same length") # Length of upper should be equal to length of lower ranges of the components
  if(length(upper) != length(x0)) stop("length of x0 and upper and lower do not match") # Provided ranges of the components should have the same dimension as that of the intervention package itself

  if (any(lower < 0)) stop("The intervention must have non-negative values only") # Non negative interventions only allowed
  if (any(lower >= upper)) stop("Upper limits of the intervention package must be larger than corresponding lower limits") # Components cannot have lower ranges more than or equal to the upper values
  if(intercept == TRUE & length(beta.true) != (length(x0) + 1)){
    stop("Please provide the correspodning beta0 value if the model should include the intercept. Else please change intercept to FALSE")
  }
  if(intercept == FALSE & length(beta.true) != (length(x0))){
    stop("Please check the dimension of provided beta.true value")
  }
  if(length(cost.vec) != length(x0)) stop("length of cost vector and the length of intervention package do not match") # Cost vector should be equal to the number of components in the package
  if(prob < 0 | prob > 1) stop("desired probability of success can be between 0 and 1") # Probability should be between 0 and 1
  if((nstages %% 1) != 0 | nstages < 2) stop("number of stages should be an integer >= 2") # number of stages should be an integer
  if(icc <= 0) stop("expected variation should be positive")

  # Initializing objects for use in the simulation
  xopt <- array(NA, dim = c(nstages, length(x0), B)) # Array to store the optimal intervention
  p.opt.hat <- matrix(NA, nrow = nstages, ncol = B) # Matrix to store the obtained outcome goal
  power <- rep(NA, times = B) # To store the power
  for(b in 1:B){
    response_clubbed <- NULL # Response to be initialized as NULL at every simulation
    actual_intervention_clubbed <- NULL # Actual intervention to be initialized as NULL at every simulation
    x.start = x0 # Initial value of x at each simulation
    for(k in 1:nstages){
      actual_intervention = jitter_my(x.start, n = sample.size, variation = icc) # Create the intervention data by simulation
      actual_intervention = truncate(x = actual_intervention, lower.limit = lower, upper.limit = upper) # Truncating the observations to their lower and upper limits so that interventions are not beyond their ranges
      actual_intervention_clubbed = rbind(actual_intervention_clubbed, actual_intervention) # Clubbing the interventions in each stages
      if(intercept == TRUE){
        actual_intervention_full <- cbind(1, actual_intervention) # Adding a column of 1's if intercept is added to the model
      }else{
        actual_intervention_full <- actual_intervention # No need to add a column of 1's if intercept is not needed in the model
      }
      # Calculating the value of the linear predictor
      lin_pred = t(beta.true * t(actual_intervention_full))
      response <- rep(NA, sample.size) # Initialize the vector of responses
      for(i in 1:sample.size){
        # Drawing samples from a Binomial distribution and prob = expit(the value of the linear predictor)
        response[i] <- stats::rbinom(n = 1, size = 1, prob = expit_linpred(x = sum(lin_pred[i, ])))
      }
      # Clubbing in the response from all the stages
      response_clubbed <- c(response_clubbed, response)
      if(intercept == TRUE){
        # If there is intercept in the model, fit the model with the intercept term
        fit <- suppressWarnings(stats::glm(response_clubbed ~ actual_intervention_clubbed, family = "binomial"))
      }else{
        # If there is no intercept in the model, fit the model without the intercept term
        fit <- suppressWarnings(stats::glm(response_clubbed ~ actual_intervention_clubbed - 1, family = "binomial"))
      }
      # Getting the beta estimates
      beta_hat = unname(fit$coefficients)
      # Running the LAGO optimization
      opt_lago = logisticLAGO::opt_int(cost = cost.vec, beta = beta_hat, lower = lower, upper = upper, pstar = prob, starting.value = x.start, intercept)
      xopt[k, ,b] = opt_lago$Optimum_Intervention
      x.start = xopt[k, ,b]
      p.opt.hat[k, b] = opt_lago$Obtained_p
    }
    # Power calculation
    # If intercept == TRUE, the intercept is removed while calculating the Wald Test statistic
    if(intercept == TRUE){
      test_stat <- sum(beta_hat[ - 1] * solve(stats::vcov(fit)[ - 1, - 1], beta_hat[ - 1]))
    }else{
      # If intercept == FALSE, there is no need to remove the intercept term while calculating the Wald Test statistic, as the fitted model does not have an estimated beta0
      test_stat <- sum(beta_hat * solve(stats::vcov(fit), beta_hat))
    }
    # Calculate the p-value for the Naive Wald test for no intervention effect
    p.value <- stats::pchisq(test_stat, df = (length(beta_hat) - 1), lower.tail = FALSE) # Calculate p-value
    power[b] <- ifelse(p.value <= 0.05, 1, 0) # Calculate the emperical power
  }
  # Store the output as a dataframe reporting the mean over simulations and showing results stage-wise
  opt.x <- as.data.frame(apply(xopt, MARGIN = c(1, 2), FUN = stats::median))
  # Store the obtained probability goal reporting the mean over simulations and showing results stage-wise
  opt.p <- apply(p.opt.hat, MARGIN = 1, FUN = stats::median)
  # Mean power calculated over simulations
  power.obt <- mean(power)
  # Some aesthetics to report the outputs
  name.col = 0
  for(i in 1:length(x0)){name.col[i] <- (paste0("x",i))}
  name.row = 0
  for(i in 1:nstages){name.row[i] <- (paste0("Stage",i))}
  colnames(opt.x) <- name.col; rownames(opt.x) <- name.row; names(opt.p) <- name.row
  # Returning the outputs
  return(list(xopt = opt.x, p.opt.hat = opt.p, power = power.obt))
}

#' Perform warmup for a Stan model
#'
#' @export
warmup = function(file,
                  stan_fit,
                  window_size = 100,
                  max_num_windows = 10,
                  chains = 4,
                  target_rhat = 1.05,
                  target_ess = 50,
                  print_stdout = FALSE,
                  ...) {
  args = list(...)

  model = cmdstan_model(file, quiet = FALSE)

  num_params = get_num_upars(stan_fit)

  fit = NULL
  usamples = array(0, dim = c(window_size * max_num_windows, chains, num_params))
  stepsizes = NULL
  inv_metric = NULL
  window_end = NULL
  nleapfrogs = 0
  for(window in 1:max_num_windows) {
    window_start = (window - 1) * window_size + 1
    window_end = window * window_size

    fargs = args
    fargs$chains = chains
    fargs$save_warmup = 1
    fargs$iter_warmup = window_size
    fargs$iter_sampling = 0
    fargs$metric = "dense_e"
    fargs$save_latent_dynamics = TRUE
    fargs$term_buffer = 0
    if(window == 1) {
      fargs$init_buffer = window_size
      fargs$window = 0
    } else {
      fargs$inv_metric = inv_metric
      fargs$init = sapply(1:chains, function(chain) { getInitFile(stan_fit, usamples[window_start - 1, chain,]) })
      fargs$step_size = mean(stepsizes)
      fargs$init_buffer = 0
      fargs$window = window_size + 1
    }

    fit = NULL
    if(print_stdout) {
      fit = do.call(model$sample, fargs)
    } else {
      stdout = capture.output(fit <- do.call(model$sample, fargs))
    }

    usamples[window_start:window_end,,] =
      getUnconstrainedSamples(fit)
    stepsizes = fit$metadata()$step_size_adaptation

    nleapfrogs = nleapfrogs + sum(sapply(getExtras(fit), function(df) { sum(df %>% pull(n_leapfrog__)) }))

    results = compute_window_convergence(usamples[1:window_end,,], window_size, target_rhat, target_ess)

    combined_usamples = matrix(usamples[(results$start):window_end,,] %>% aperm(c(2, 1, 3)), ncol = dim(usamples)[3])
    inv_metric = compute_inv_metric(stan_fit, combined_usamples)

    if(results$converged == TRUE) {
      break
    }
  }

  fargs = args
  fargs$chains = chains
  fargs$iter_warmup = 50
  fargs$metric = "dense_e"
  fargs$init = sapply(1:chains, function(chain) { getInitFile(stan_fit, usamples[window_end, chain,]) })
  fargs$inv_metric = inv_metric
  fargs$step_size = mean(stepsizes)
  fargs$term_buffer = 50
  fargs$init_buffer = 0
  fargs$window = 0

  return(list(args = fargs,
              usamples = usamples[1:window_end,,],
              nleapfrogs = nleapfrogs))
}

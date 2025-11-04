#' Lazy iteration operator for Flight iterators with automatic pagination
#'
#' This operator allows for lazy evaluation of Flight iterators, processing one item at a time
#' across multiple pages without consuming all results upfront.
#'
#' @param iter_or_spec Flight iterator or pagination specification
#' @param expr An expression to evaluate for each item
#' @return The result of evaluating the expression on each item
#' @export
`%::%` <- function(iter_or_spec, expr) {
  expr_subst <- substitute(expr)
  parent_env <- parent.frame()

  # Check if this is a pagination spec or a simple iterator
  if (is.list(iter_or_spec) &&
      !inherits(iter_or_spec, "python.builtin.object") &&
      !is.null(iter_or_spec$client) &&
      !is.null(iter_or_spec$criteria)) {

    # Extract pagination parameters
    client <- iter_or_spec$client
    criteria <- iter_or_spec$criteria
    max_pages <- iter_or_spec$max_pages %||% -1 # Default to 10 pages

    # Ensure page info is in criteria
    if (is.null(criteria$page_size)) {
      criteria$page_size <- 100
    }

    # Process multiple pages
    all_results <- list()
    current_page <- 1
    total_records <- NULL
    records_processed <- 0

    # Continue while we haven't exceeded max_pages AND
    # (we don't know total_records OR we haven't processed all records yet)
    while ((max_pages == -1 || current_page <= max_pages) &&
          (is.null(total_records) || ( records_processed < total_records))) {

      # Update page in criteria
      criteria$page <- current_page

      # Get iterator for current page
      py_iter <- .client_list(client, criteria)

      # Process the iterator for this page
      page_results <- list()
      page_record_count <- 0

      # Set up the environment for evaluation
      iter_env <- new.env(parent = parent_env)

      # Catch errors during iteration to continue with results we have
      tryCatch({
        # Use reticulate's iterate function
        reticulate::iterate(py_iter, function(item) {
          # Check for total_records if we don't have it yet
          if (is.null(total_records) && !is.null(item$total_records) && item$total_records > 0 ) {
            total_records <<- as.numeric(item$total_records)
          }

          extracted_data <- .extract_data(item)
          
          # Add frame property if this looks like a dataset
          if (!is.null(extracted_data) && !is.null(extracted_data$dataset_uuid)) {
            # Create the base parameters needed for dataconnect_tbl
            base_params <- list(
              study_uuid = extracted_data$study_uuid,
              study_env_uuid = extracted_data$study_env_uuid,
              dataset_uuid = extracted_data$dataset_uuid,
              dataset_name = extracted_data$dataset_name
            )
            
            # Add the frame property as a dataconnect_tbl
            extracted_data$frame <- dataconnect_tbl(client, base_params)
          }

          # Bind item to the environment
          iter_env$item <- item
          iter_env$data <- extracted_data
          # Evaluate the expression in the environment
          result <- eval(expr_subst, envir = iter_env)

          # Add result if not NULL
          if (!is.null(result)) {
            page_results <<- c(page_results, list(result))
            page_record_count <<- page_record_count + 1
          }
        })
      }, error = function(e) {
        if (grepl("FlightServerError", e$message)) {
          warning("Server returned an error during iteration: ",
                sub(".*FlightServerError: ", "", e$message))
        } else {
          warning("Error during iteration: ", e$message)
        }
      })

      # If we got no results, we've reached the end
      if (length(page_results) == 0) {
        break
      }

      # Add this page's results
      all_results <- c(all_results, page_results)
      records_processed <- records_processed + page_record_count

      # Move to next page
      current_page <- current_page + 1
    }

    return(all_results)

  } else if (inherits(iter_or_spec, "python.builtin.object")) {
    # Process a simple Python iterator (single page)
    results <- list()

    # Set up the environment for evaluation
    iter_env <- new.env(parent = parent_env)

    # Catch errors during iteration
    tryCatch({
      # Use reticulate's iterate function
      reticulate::iterate(iter_or_spec, function(item) {
        # Bind item to the environment
        iter_env$item <- item

        # Evaluate the expression in the environment
        result <- eval(expr_subst, envir = iter_env)

        # Add result if not NULL
        if (!is.null(result)) {
          results <<- c(results, list(result))
        }
      })
    }, error = function(e) {
      if (grepl("FlightServerError", e$message)) {
        warning("Server returned an error during iteration: ",
              sub(".*FlightServerError: ", "", e$message))
      } else {
        warning("Error during iteration: ", e$message)
      }
    })

    return(results)
  } else {
    stop("The first argument must be either a Python iterator or a pagination specification")
  }
}

#' Convert a named list to a data frame for markdown display
#' 
#' This function takes a named list and converts it to a data frame
#' suitable for markdown display, with proper formatting.
#' 
#' @param data A named list to convert
#' @return A data frame with two columns: "name" and "value"
#' @export
to_frame <- function(data) {
  df_transposed <- data.frame(
    Variable = names(data),
    Value = as.character(data),
    stringsAsFactors = FALSE
  )

  # Generate markdown table with proper formatting
  knitr::kable(df_transposed,
               col.names = c("name", "value"),
               row.names = FALSE,
               format = "markdown",
               align = c('l', 'l'))
}
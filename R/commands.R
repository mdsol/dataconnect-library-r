#' Execute a command on the Arrow Flight server
#'
#' @param client A FlightClient object
#' @param command The command to execute
#' @param args Additional arguments for the command (will be JSON-encoded)
#' @param body Pre-formatted body bytes (alternative to args)
#' @return 
#' A list containing the parsed results from the server.
#' Each element is either a parsed JSON object (as a list) or a raw result if parsing fails.
#' Returns NULL if an error occurs during execution.
#' @keywords internal
#' @noRd
.do_command <- function(client, command, args = list(), body = NULL) {
  if(is.null(command) || command == "") {
    stop("Command must be provided")
  }

  # Use pre-formatted body if provided, otherwise encode args as JSON
  if (!is.null(body)) {
    action_body <- body
  } else if (length(args) > 0) {
    args_json <- jsonlite::toJSON(args, auto_unbox = TRUE)
    action_body <- reticulate::r_to_py(args_json)$encode("utf-8")
  } else {
    action_body <- reticulate::r_to_py("")$encode("utf-8")
  }

  # Create proper Flight Action with type and body separate
  pa_flight <- reticulate::import("pyarrow.flight")
  action <- pa_flight$Action(command, action_body)

  options <- .get_flight_options()
  # Execute command
  tryCatch({
    result_iterator <- client$do_action(action, options = options)

    # Process result
    response <- list()
    reticulate::iterate(result_iterator, function(result) {
      # Check if this is a Flight Result object with a body
      if (!is.null(result$body)) {
        tryCatch({
          # Extract body from Flight Result and decode it (like Python code)
          body_bytes <- result$body$to_pybytes()
          body_str <- body_bytes$decode("utf-8")

          # Parse JSON
          result_data <- jsonlite::fromJSON(body_str)
          response <<- c(response, list(result_data))
        }, error = function(e) {
          # If not JSON or can't decode, add as raw
          response <<- c(response, list(result))
        })
      } else {
        # Try to decode as JSON (legacy path)
      tryCatch({
        item_str <- reticulate::py_to_r(result)
        item_json <- jsonlite::fromJSON(item_str)
        response <<- c(response, list(item_json))
      }, error = function(e) {
        # If not JSON, just add as raw
        response <<- c(response, list(result))
      })
      }
    })

    return(response)
  }, error = function(e) {
    warning("Error executing command: ", e$message)
    return(NULL)
  })
}

#' Execute a do_put command on the Arrow Flight server
#'
#' @param client A FlightClient object
#' @param config Configuration object for the dataset
#' @param data Data to upload (data.frame, Arrow Table, or schema)
#' @return A list containing:
#'   \item{success}{Logical indicating if the operation was successful.}
#'   \item{message}{A success message if the operation succeeded.}
#'   \item{error_type}{(If failed) The type of error encountered.}
#'   \item{error_message}{(If failed) A descriptive error message.}
#'   \item{original_error}{(If failed) The full error details including traceback.}
#' @keywords internal
#' @noRd
.do_put_command <- function(client, config, data) {
  if (is.null(client)) {
    stop("Client must be provided")
  }
  if (is.null(config)) {
    stop("Configuration must be provided")
  }
  if (is.null(data)) {
    stop("Data must be provided")
  }

  tryCatch({
    # Convert config to JSON string (same as Python client)
    config_json <- jsonlite::toJSON(config, auto_unbox = TRUE)

    # Create Flight descriptor with config in path (matching Python client)
    pa_flight <- reticulate::import("pyarrow.flight")
    
    # Encode config as bytes for the descriptor path
    config_bytes <- reticulate::r_to_py(config_json)$encode("utf-8")
    descriptor <- pa_flight$FlightDescriptor$for_path(config_bytes)

    # Get flight options
    options <- .get_flight_options()

    # Handle different data types to get the schema and data
    if (is.data.frame(data)) {
      arrow_data <- arrow::arrow_table(data)
      schema <- arrow_data$schema
    } else if (inherits(data, "Schema")) {
      schema <- data
      arrow_data <- NULL  # No data for metadata-only publishing
    } else if (inherits(data, c("Table", "RecordBatch"))) {
      arrow_data <- data
      schema <- data$schema
    } else {
      stop("Data must be a data.frame, Arrow Table, RecordBatch, or Schema")
    }

    # Call do_put with descriptor and schema (matching Python client pattern)
    writer_reader <- client$do_put(descriptor, schema, options = options)

    # Extract writer and reader from the returned list (Python tuple -> R list)
    writer <- writer_reader[[1]]  # First element is the writer
    reader <- writer_reader[[2]]  # Second element is the reader

    # If we have data, write it using the writer (matching Python pattern)
    arrow_data <- reticulate::r_to_py(arrow_data)
    
    if (!is.null(arrow_data)) {
      writer$write_table(arrow_data)
      writer$close()
    }

    list(
      success = TRUE,
      message = "Dataset published successfully"
    )

  }, error = function(e) {
    error_info <- .handle_flight_error(e)

    # Enhanced error logging with full traceback
    error_msg <- paste("Error in do_put_command:", e$message)

    # Add traceback information
    if (!is.null(e$call)) {
      error_msg <- paste(error_msg, "\nCall:", deparse(e$call))
    }

    # Add full traceback
    tb <- sys.calls()
    if (length(tb) > 0) {
      error_msg <- paste(error_msg, "\nTraceback:")
      for (i in seq_along(tb)) {
        error_msg <- paste(error_msg, paste0("  ", i, ": ", deparse(tb[[i]])), sep = "\n")
      }
    }

    # Add Python traceback if available
    tryCatch({
      py_error <- reticulate::py_last_error()
      if (!is.null(py_error)) {
        error_msg <- paste(error_msg, "\nPython traceback:", py_error, sep = "\n")
      ''}
    }, error = function(py_e) {
      # Ignore errors getting Python traceback
    })

    # return
    list(
      success = FALSE,
      error_type = error_info$type,
      error_message = error_info$message,
      original_error = error_msg
    )
  })
}

# Standardized error handler function
#' @keywords internal
#' @noRd
.handle_flight_error <- function(error) {
  error_msg <- conditionMessage(error)

  # Parse error type from message prefix
  if (grepl("VALIDATION_ERROR: ", error_msg)) {
    list(
      type = "VALIDATION",
      message = error_msg
    )
  } else if (grepl("NOT_FOUND: ", error_msg)) {
    list(
      type = "NOT_FOUND",
      message = error_msg
    )
  } else if (grepl("AUTHENTICATION_ERROR: ", error_msg)) {
    list(
      type = "AUTHENTICATION",
      message = error_msg
    )
  } else if (grepl("AUTHORIZATION_ERROR: ", error_msg)) {
    list(
      type = "AUTHORIZATION",
      message = error_msg
    )
  } else {
    list(
      type = "SERVER_ERROR",
      message = error_msg
    )
  }
}
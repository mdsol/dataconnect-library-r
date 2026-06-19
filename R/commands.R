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
    NULL
  })
}

#' Retrieve supported datetime formats from the Arrow Flight server
#'
#' Returns a structured data frame with the following columns:
#' \itemize{
#'   \item \code{index}: 1-based position in the returned format list.
#'   \item \code{format}: Date or datetime format string.
#'   \item \code{type}: Either \code{"date"} or \code{"datetime"}.
#' }
#'
#' @param client A FlightClient object
#' @param project_token Project token for authorization
#' @param type Filter type: one of \code{"all"}, \code{"date"}, or \code{"datetime"}
#' @return A data.frame with columns \code{index}, \code{format}, and \code{type}
#' @keywords internal
#' @noRd
.get_datetime_formats <- function(client, project_token, type = "all") {
  if (is.null(client)) {
    stop("Client must be provided")
  }

  if (missing(project_token) || is.null(project_token) || !nzchar(trimws(as.character(project_token)))) {
    stop("project_token must be provided")
  }

  if (missing(type) || is.null(type)) {
    normalized_type <- "all"
  } else {
    normalized_type <- tolower(trimws(as.character(type)))
  }
  accepted_types <- c("all", "date", "datetime")

  if (!(normalized_type %in% accepted_types)) {
    stop("type must be one of: all, date, datetime")
  }

  result <- .do_command(
    client = client,
    command = "get_datetime_formats",
    args = list(project_token = project_token, type = normalized_type)
  )

  if (is.null(result) || length(result) == 0 || is.null(result[[1]])) {
    stop("No datetime formats were returned by the server")
  }

  formats_raw <- result[[1]]
  formats <- as.character(unname(unlist(formats_raw, use.names = FALSE)))
  formats <- formats[!is.na(formats) & nzchar(formats)]

  if (length(formats) == 0) {
    stop("No datetime formats were returned by the server")
  }

  detected_type <- ifelse(grepl("HH:mm", formats, fixed = TRUE), "datetime", "date")

  structured_formats <- data.frame(
    index = seq_along(formats),
    format = formats,
    type = detected_type,
    stringsAsFactors = FALSE
  )

  if (normalized_type == "all" && nrow(structured_formats) != 128) {
    stop(sprintf("Expected 128 datetime formats for type='all' but received %d", nrow(structured_formats)))
  }

  structured_formats
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

    # Ensure writer is always closed, even if an error occurs below
    on.exit(writer$close(), add = TRUE)

    # If we have data, write it using the writer (matching Python pattern)
    arrow_data <- reticulate::r_to_py(arrow_data)

    if (!is.null(arrow_data)) {
      writer$write_table(arrow_data)
    }

    writer$done_writing()

    raw_bytes <- reader$read()
    result_str <- if (is.raw(raw_bytes)) {
      rawToChar(raw_bytes)
    } else if (!is.null(raw_bytes)) {
      raw_bytes$to_pybytes()$decode("utf-8")
    } else {
      stop("No response received from server after do_put")
    }
    result <- jsonlite::fromJSON(result_str)

    dry_publish_or_publish_result <- NULL

    datetime_format_errors <- result$invalid_datetime_formats
    date_formats_valid <- is.null(datetime_format_errors) || length(datetime_format_errors) == 0

    if (isTRUE(config$is_dry_publish)) {

      # If it's a dry publish, we expect validation results instead of dataset identifiers
      dry_publish_or_publish_result <- list(
        success = result$status,
        is_schema_valid = result$is_schema_valid,
        is_config_valid = result$is_config_valid,
        dataset_valid = result$dataset_valid,
        is_date_formats_valid = date_formats_valid,
        errors = result$errors,
        dataset_name = result$dataset_name,
        invalid_record_count = as.integer(result$invalid_record_count),
        valid_rows = as.integer(result$valid_record_count),
        duplicate_rows = as.integer(result$duplicate_record_count),
        dataset_version = result$dataset_version,
        no_of_columns = result$no_of_columns,
        invalid_records = NULL
      )
    } else {

      # For a regular publish, we expect dataset identifiers in the response
      dry_publish_or_publish_result <- list(
        success = result$status,
        dataset_name = result$dataset_name,
        dataset_uuid = result$dataset_uuid,
        dataset_version = result$dataset_version,
        invalid_record_count = as.integer(result$invalid_record_count),
        valid_rows = as.integer(result$valid_record_count),
        duplicate_rows = as.integer(result$duplicate_record_count),
        invalid_records = NULL
      )
    }

    # Try to read invalid records table (IPC stream) from the server.
    # The server streams error batches after the JSON result only when there are invalid records.
    # Batches are read one at a time and converted to R immediately so Python can release each
    # batch before the next is fetched — avoids materialising the entire stream in memory at once.
    tryCatch({
      pa <- reticulate::import("pyarrow", convert = FALSE)
      error_buf <- reader$read()
      
      if (!is.null(error_buf) && !inherits(error_buf, "python.builtin.NoneType") && !inherits(error_buf, "pyarrow.lib.NoneType")) {
        ipc_reader <- pa$ipc$open_stream(error_buf)

        # Each batch is converted to an Arrow Table immediately so the Python batch
        # can be GC'd before the next is read — safe for huge invalid-record counts.
        # arrow::concat_tables() is O(n); a single as.data.frame() call at the end
        chunks <- list()
        repeat {
          batch <- tryCatch(
            ipc_reader$read_next_batch(),
            error = function(e) NULL  # StopIteration signals end of stream
          )
          if (is.null(batch)) break
          chunks <- c(chunks, list(arrow::as_arrow_table(batch)))
        }
        
        if (length(chunks) > 0) {
          dry_publish_or_publish_result$invalid_records <- do.call(rbind, lapply(chunks, as.data.frame))
        }
      }
      
    }, error = function(e) {
       if (grepl("STR_STREAMING_ERROR", conditionMessage(e))) {
         if (isTRUE(config$is_dry_publish)) {
           stop(conditionMessage(e))
         } else {
           stop("Flight stream terminated unexpectedly during publish: ", conditionMessage(e))
         }
       } else {
         stop(e)
       }
    })

    dry_publish_or_publish_result

  }, error = function(e) {

    error_info <- .handle_flight_error(e)

    dry_publish_or_publish_result <- NULL

    if (isTRUE(config$is_dry_publish)) {
      dry_publish_or_publish_result <- list(
        success = FALSE,
        error_type = error_info$type,
        error_message = error_info$message
      )
    }

    dry_publish_or_publish_result
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
  } else if (grepl("STR_STREAMING_ERROR", error_msg)) {
    list(
      type = "STREAMING_ERROR",
      message = error_msg
    )
  } else {
    list(
      type = "SERVER_ERROR",
      message = error_msg
    )
  }
}
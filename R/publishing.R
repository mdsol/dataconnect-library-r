#' Count distinct rows based on key columns using Native R
#'
#' @param data Data frame to analyze
#' @param key_columns List or character vector of key column names
#' @return List with distinct_row_count (integer or NULL), duplicate_key_rows and error_message
#' 
.count_distinct_rows <- function(data, key_columns) {
  key_cols <- as.character(unlist(key_columns))
  
  if (length(key_cols) == 0) {
    stop("Argument 'key_columns' is mandatory for duplicate and valid rows calculation.")
  }
  
  actual_cols <- names(data)[match(tolower(key_cols), tolower(names(data)))]
  
  res <- tryCatch({
    count <- nrow(unique(data[, actual_cols, drop = FALSE]))
    dups <- data[duplicated(data[, actual_cols, drop = FALSE]), actual_cols, drop = FALSE]
    list(count = count, dups = dups, err = NULL)
  }, error = function(e) {
    list(count = NULL, dups = NULL, err = e$message)
  })
  
  return(list(distinct_row_count = res$count, duplicate_key_rows = res$dups, error_message = res$err))
}

# Import required functions
# Note: All functions internally use .get_flight_options() to add tracking headers
# (client version, IP addresses, MAC address) to all Flight operations

#' Dry publish configuration and schema to the server
#'
#' This function validates the configuration and schema without actually
#' publishing the data. It sends the configuration and schema to the server
#' for validation and returns the results.
#'
#' @param client Arrow Flight client object
#' @param config Configuration object for the dataset
#' @param data Data to upload, a \code{data.frame}
#' @return Server validation response
#' @keywords internal
#' @noRd
.dry_publish <- function(client, config, data) {

  # Input validation
  if (is.null(client)) {
    stop("Client must be provided")
  }
  if (is.null(config)) {
    stop("Configuration must be provided")
  }
  if (is.null(data)) {
    stop("Data must be provided")
  }
 # Convert data to Arrow table
  if (is.data.frame(data)) {
    arrow_data <- arrow::arrow_table(data)
  } else {
    stop("Data must be a data.frame")
  }

  # Check for empty data
  if (arrow_data$num_rows == 0) {
    warning("Uploading empty dataset")
  }

  # Format the data as expected by the dry_publish server endpoint
  # Convert config to JSON
  config_json <- jsonlite::toJSON(config, auto_unbox = TRUE)

  # Get Arrow schema from data
  schema <- arrow_data$schema

  # Serialize schema to IPC format
  schema_buffer <- schema$serialize()

  # Create combined payload: config_json + "\n\n" + schema_ipc_bytes
  config_bytes <- reticulate::r_to_py(config_json)$encode("utf-8")
  separator_bytes <- reticulate::r_to_py("\n\n")$encode("utf-8")
  schema_bytes <- reticulate::r_to_py(schema_buffer)  # Already binary, no encoding needed

  # Concatenate the bytes using Python's + operator
  combined_body <- config_bytes + separator_bytes + schema_bytes

  # Use do_command with pre-formatted body
  result <- .do_command(client, "dry_publish", body = combined_body)
  
  # Extract and parse the response content
  response <- NULL
  if (length(result) > 0) {
    # If do_command processed it successfully, return the first item
    response <- result[[1]]
  } else {
    # If do_command didn't process it, try to extract manually
    warning("No processed result from do_command, returning raw result")
    response <- result
  }
  # Venn logic for valid_rows and duplicate count
  distinct_total <- .count_distinct_rows(data, config$key_columns)
  distinct_invalid <- list(distinct_row_count = 0)
  if (!is.null(response$invalid_records) && nrow(response$invalid_records) > 0) {
    distinct_invalid <- .count_distinct_rows(response$invalid_records, config$key_columns)
  }
  if (!is.null(distinct_total$distinct_row_count)) {
    inv_count <- if(is.null(distinct_invalid$distinct_row_count)) 0 else distinct_invalid$distinct_row_count
    response$valid_rows <- as.integer(max(0, distinct_total$distinct_row_count - inv_count))
    response$duplicate_rows_based_on_keys <- nrow(distinct_total$duplicate_key_rows)
  }
  return(response)
}

#' Publish configuration, schema and data to the server
#'
#' Publishes a dataset configuration and schema to the server using an Arrow Flight client.
#' It uploads the data along with the configuration and schema.
#'
#' @param client Arrow Flight client object. Must not be NULL.
#' @param config Configuration object for the dataset. Must not be NULL.
#' @param data Data to upload, a \code{data.frame}. Must not be NULL. If empty, empty dataset will be uploaded.
#'
#' @return Result of the Flight operation.
#' @examples
#' \dontrun{
#' # Publish only configuration and data
#' publish(client, config, data)
#' 
#' }
#' @keywords internal
#' @noRd
.publish <- function(client, config, data) {
  # Input validation
  if (is.null(client)) {
    stop("Client must be provided")
  }
  if (is.null(data)) {
    stop("Data must be provided")
  }

  # Convert data to Arrow table
  if (is.data.frame(data)) {
    arrow_data <- arrow::arrow_table(data)
  } else {
    stop("Data must be a data.frame")
  }

  # Check for empty data
  if (arrow_data$num_rows == 0) {
    warning("Uploading empty dataset")
  }

tryCatch({
    result <- .do_put_command(client, config, arrow_data)

    if (result$success) {
      distinct_total <- .count_distinct_rows(data, config$key_columns)
      distinct_invalid <- list(distinct_row_count = 0)
      
      if (!is.null(result$invalid_records) && nrow(result$invalid_records) > 0) {
        distinct_invalid <- .count_distinct_rows(result$invalid_records, config$key_columns)
      }
      
      if (!is.null(distinct_total$distinct_row_count)) {
        inv_count <- if (is.null(distinct_invalid$distinct_row_count)) 0 else distinct_invalid$distinct_row_count
        result$valid_rows <- as.integer(max(0, distinct_total$distinct_row_count - inv_count))
        result$duplicate_rows_based_on_keys <- nrow(distinct_total$duplicate_key_rows)
      }
    }

    return(result)
  }, error = function(e) {
    parsed_error <- .parse_dataconnect_error(conditionMessage(e))
    .throw_dataconnect_error(parsed_error)
  })
}
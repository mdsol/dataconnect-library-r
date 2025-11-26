#' Count distinct rows based on key columns
#'
#' @param data Data frame to analyze
#' @param key_columns List or character vector of key column names
#' @return List with distinct_row_count (integer or NULL) and error_message (character or NULL)
#' @keywords internal
#' @noRd
.count_distinct_rows <- function(data, key_columns) {
  
  # Convert key_columns from list to character vector if needed
  key_cols <- as.character(unlist(key_columns))
  
  # Convert column names to lowercase for case-insensitive comparison
  key_cols_lower <- tolower(key_cols)
  data_cols_lower <- tolower(names(data))
  
  # Validate key columns exist in data (case-insensitive)
  missing_cols <- key_cols[!key_cols_lower %in% data_cols_lower]
  if (length(missing_cols) > 0) {
    error_msg <- paste("Key column(s) not found:", paste(missing_cols, collapse = ", "), ".")
    return(list(distinct_row_count = NULL, error_message = error_msg))
  }
  
  # Map key columns to actual data frame column names
  actual_cols <- names(data)[match(key_cols_lower, data_cols_lower)]
  
  # Count distinct rows based on key columns
  distinct_row_count <- nrow(unique(data[, actual_cols, drop = FALSE]))
  
  return(list(distinct_row_count = distinct_row_count, error_message = NULL))
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
  if (!is.data.frame(data)) {
    stop("Data must be a data.frame")
  }

  # Check for empty data
  if (nrow(data) == 0) {
    warning("Uploading empty dataset")
  }

  # Format the data as expected by the dry_publish server endpoint
  # Convert config to JSON
  config_json <- jsonlite::toJSON(config, auto_unbox = TRUE)

  # Get Arrow schema from data
  schema <- arrow::arrow_table(data)$schema

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
  
  distinct_row_result <- .count_distinct_rows(data, config$key_columns)

  # Append distinct row count and duplicate row count if available
  if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
    response$valid_rows <- distinct_row_result$distinct_row_count
    response$duplicate_rows_based_on_keys <- nrow(data) - distinct_row_result$distinct_row_count
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

  result <- .do_put_command(client, config, arrow_data)
  
  distinct_row_result <- NULL
  if (result$success) {
    distinct_row_result <- .count_distinct_rows(data, config$key_columns)

    # Append distinct row count and duplicate row count if available
    if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
      result <- c(result, list(valid_rows = distinct_row_result$distinct_row_count))
      result <- c(result, list(duplicate_rows_based_on_keys = nrow(data) - distinct_row_result$distinct_row_count))
    }
  }
  
  return(result)
}
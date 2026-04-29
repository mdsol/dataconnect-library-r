
#' Calculate valid rows using Venn logic
#'
#' @param response The result list from the server operation (expected to contain invalid_records)
#' @param data Original data.frame
#' @param key_columns Key columns for distinct calculations
#' @return Integer representing the calculated number of valid rows
#' @keywords internal
#' @noRd
.get_valid_rows <- function(response, data, key_columns) {
  distinct_row_result <- .count_distinct_rows(data, key_columns)
  valid_rows <- 0
  invalid_distinct_row_count <- 0

  if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
    if (!is.null(response$invalid_records) && nrow(response$invalid_records) > 0) {
      invalid_result <- .count_distinct_rows(response$invalid_records, key_columns)
      if (!is.null(invalid_result$distinct_row_count)) {
        invalid_distinct_row_count <- invalid_result$distinct_row_count
      }
    }
  }

  # Total duplicate rows in the original data (all rows minus distinct rows by key)
  duplicate_rows_based_on_keys <- nrow(data) - distinct_row_result$distinct_row_count

  # Duplicate rows among the invalid records (all invalid rows minus distinct invalid rows)
  duplicate_invalid_rows <- nrow(response$invalid_records) - invalid_distinct_row_count

  # Net duplicates: remove the duplicates that are already counted as invalid
  # (so we don't double-count rows that are both invalid and duplicated)
  net_duplicate_rows <- duplicate_rows_based_on_keys - duplicate_invalid_rows

  # Final valid rows:
  #   = all rows
  #   - invalid rows (as flagged by the server)
  #   - net duplicates (excluding those already counted as invalid)
  valid_rows <- nrow(data) - nrow(response$invalid_records) - net_duplicate_rows
    
  return(valid_rows)
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
      valid_rows = .get_valid_rows(result, data, config$key_columns)
      result <- c(result, list(valid_rows = valid_rows))
    }
    return(result)
    }, error = function(e) {
      parsed_error <- .parse_dataconnect_error(conditionMessage(e))
      .throw_dataconnect_error(parsed_error)
  })
}
#' Count distinct rows based on key columns using Python/PyArrow
#'
#' @param data Data frame to analyze
#' @param key_columns List or character vector of key column names
#' @return List with distinct_row_count (integer or NULL) and error_message (character or NULL)
#' @keywords internal
#' @noRd
.count_distinct_rows <- function(data, key_columns, compute_metadata = TRUE) {
  
  # Convert key_columns from list to character vector if needed
  key_cols <- as.character(unlist(key_columns))

  if (length(key_cols) == 0) {
    return(list(
      distinct_row_count = nrow(data),
      error_message = NULL,
      duplicate_row_indices = integer(0),
      duplicate_key_rows = data.frame(),
      actual_key_columns = character(0)
    ))
  }

  # Convert column names to lowercase for case-insensitive comparison
  key_cols_lower <- tolower(key_cols)
  data_cols_lower <- tolower(names(data))
  
  # Validate key columns exist in data (case-insensitive)
  missing_cols <- key_cols[!key_cols_lower %in% data_cols_lower]
  if (length(missing_cols) > 0) {
    error_msg <- paste("Key column(s) not found:", paste(missing_cols, collapse = ", "), ".")
    return(list(
      distinct_row_count = NULL,
      error_message = error_msg,
      duplicate_row_indices = integer(0),
      duplicate_key_rows = data.frame(),
      actual_key_columns = character(0)
    ))
  }
  
  # Map key columns to actual data frame column names
  actual_cols <- names(data)[match(key_cols_lower, data_cols_lower)]

  duplicate_row_indices <- integer(0)
  duplicate_key_rows <- data.frame()
  if (isTRUE(compute_metadata)) {
    key_data <- data[, actual_cols, drop = FALSE]
    duplicate_mask <- duplicated(key_data, fromLast = FALSE) | duplicated(key_data, fromLast = TRUE)
    duplicate_row_indices <- which(duplicate_mask)
    duplicate_key_rows <- key_data[duplicate_mask, , drop = FALSE]
  }
  
  tryCatch({
    # Convert data frame to Arrow table
    arrow_table <- arrow::arrow_table(data)
    
    # Execute the Python implementation directly
    reticulate::py_run_string("
import pyarrow as pa
import pyarrow.compute as pac
import uuid

def count_distinct_rows_py(table, key_columns):
    key_values = []
    
    for key_column in key_columns:
        if len(key_values) > 0:
            key_values = pac.binary_join_element_wise(
                key_values,
                pac.cast(table[key_column], pa.string()),
                pa.scalar('-'))
        else:
            key_values = pac.binary_join_element_wise(
                pac.cast(table[key_column], pa.string()),
                pa.scalar('-'))
    
    result_array = pa.array([str(uuid.uuid3(uuid.NAMESPACE_DNS, str(key_value))) for key_value in key_values])
    return len(pac.unique(result_array))
", convert = FALSE)
    
    # Call the Python function
    # Convert actual_cols to Python list explicitly
    py_func <- reticulate::py_eval("count_distinct_rows_py", convert = FALSE)
    py_cols <- reticulate::r_to_py(as.list(actual_cols))
    distinct_count <- as.integer(reticulate::py_to_r(py_func(arrow_table, py_cols)))
    
    return(list(
      distinct_row_count = distinct_count,
      error_message = NULL,
      duplicate_row_indices = duplicate_row_indices,
      duplicate_key_rows = duplicate_key_rows,
      actual_key_columns = actual_cols
    ))
    
  }, error = function(e) {
    error_msg <- paste("Error counting distinct rows:", e$message)
    return(list(
      distinct_row_count = NULL,
      error_message = error_msg,
      duplicate_row_indices = duplicate_row_indices,
      duplicate_key_rows = duplicate_key_rows,
      actual_key_columns = actual_cols
    ))
  })
}

.calculate_duplicate_invalid_intersection <- function(duplicate_key_rows, invalid_records, key_columns) {
  if (is.null(invalid_records) || !is.data.frame(invalid_records) || nrow(invalid_records) == 0) {
    return(0L)
  }

  if (is.null(duplicate_key_rows) || !is.data.frame(duplicate_key_rows) || nrow(duplicate_key_rows) == 0) {
    return(0L)
  }

  key_cols <- as.character(unlist(key_columns))
  if (length(key_cols) == 0) {
    return(0L)
  }

  key_cols_lower <- tolower(key_cols)
  duplicate_cols_lower <- tolower(names(duplicate_key_rows))
  invalid_cols_lower <- tolower(names(invalid_records))

  duplicate_actual_cols <- names(duplicate_key_rows)[match(key_cols_lower, duplicate_cols_lower)]
  invalid_actual_cols <- names(invalid_records)[match(key_cols_lower, invalid_cols_lower)]

  if (any(is.na(duplicate_actual_cols)) || any(is.na(invalid_actual_cols))) {
    return(0L)
  }

  duplicate_keys <- do.call(paste, c(duplicate_key_rows[, duplicate_actual_cols, drop = FALSE], sep = "\r"))
  duplicate_keys <- unique(duplicate_keys)
  invalid_keys <- do.call(paste, c(invalid_records[, invalid_actual_cols, drop = FALSE], sep = "\r"))

  as.integer(sum(invalid_keys %in% duplicate_keys))
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
  
  compute_metadata <- getOption("dataconnect.calculate_duplicates", TRUE)
  distinct_row_result <- .count_distinct_rows(data, config$key_columns, compute_metadata = compute_metadata)

  # Append distinct row count and duplicate row count if available
  if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
    duplicate_count <- nrow(data) - distinct_row_result$distinct_row_count
    invalid_count <- 0L
    intersection_count <- 0L
    if (!is.null(response$invalid_record_count) && length(response$invalid_record_count) > 0 && !is.na(response$invalid_record_count[[1]])) {
      invalid_count <- as.integer(response$invalid_record_count[[1]])
    }

    if (isTRUE(compute_metadata)) {
      intersection_count <- .calculate_duplicate_invalid_intersection(
        distinct_row_result$duplicate_key_rows,
        response$invalid_records,
        config$key_columns
      )
    }

    response$valid_rows <- max(0L, distinct_row_result$distinct_row_count - invalid_count + intersection_count)
    response$duplicate_rows_based_on_keys <- duplicate_count
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

    distinct_row_result <- NULL
    if (result$success) {
      compute_metadata <- getOption("dataconnect.calculate_duplicates", TRUE)
      distinct_row_result <- .count_distinct_rows(data, config$key_columns, compute_metadata = compute_metadata)

      # Append distinct row count and duplicate row count if available
      if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
        duplicate_count <- nrow(data) - distinct_row_result$distinct_row_count
        invalid_count <- 0L
        if (!is.null(result$invalid_record_count) && length(result$invalid_record_count) > 0 && !is.na(result$invalid_record_count[[1]])) {
          invalid_count <- as.integer(result$invalid_record_count[[1]])
        }
        intersection_count <- 0L
        if (isTRUE(compute_metadata)) {
          intersection_count <- .calculate_duplicate_invalid_intersection(
            distinct_row_result$duplicate_key_rows,
            result$invalid_records,
            config$key_columns
          )
        }

        result <- c(result, list(valid_rows = max(0L, distinct_row_result$distinct_row_count - invalid_count + intersection_count)))
        result <- c(result, list(duplicate_rows_based_on_keys = duplicate_count))
      }
    }

    return(result)
    }, error = function(e) {
      parsed_error <- .parse_dataconnect_error(conditionMessage(e))
      .throw_dataconnect_error(parsed_error)
  })
}
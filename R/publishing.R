# Calculates valid_rows using Venn logic (R06):
# valid_rows = total_rows - invalid_rows - (duplicates - intersection)
.calculate_venn_valid_rows <- function(total_rows, duplicate_keys_df, invalid_records_df, key_columns) {
  # If no duplicates, subtract only invalids
  if (is.null(duplicate_keys_df) || nrow(duplicate_keys_df) == 0) {
    invalid_count <- if (is.null(invalid_records_df)) 0 else nrow(invalid_records_df)
    return(as.integer(max(0, total_rows - invalid_count)))
  }

  # If no invalid records, subtract only duplicates
  if (is.null(invalid_records_df) || nrow(invalid_records_df) == 0) {
    return(as.integer(max(0, total_rows - nrow(duplicate_keys_df))))
  }

  # Compute intersection between duplicates and invalids using key columns
  key_cols <- unlist(key_columns)
  intersection_count <- nrow(merge(
    duplicate_keys_df[, key_cols, drop = FALSE],
    invalid_records_df[, key_cols, drop = FALSE]
  ))

  net_duplicates <- nrow(duplicate_keys_df) - intersection_count
  invalid_count <- nrow(invalid_records_df)
  valid_rows <- total_rows - invalid_count - net_duplicates
  return(as.integer(max(0, valid_rows)))
}
#' Count distinct rows based on key columns using Python/PyArrow
#'
#' @param data Data frame to analyze
#' @param key_columns List or character vector of key column names
#' @return List with distinct_row_count (integer or NULL) and error_message (character or NULL)
#' @keywords internal
#' @noRd
.count_distinct_rows <- function(data, key_columns) {
  key_cols <- as.character(unlist(key_columns))
  key_cols_lower <- tolower(key_cols)
  data_cols_lower <- tolower(names(data))
  missing_cols <- key_cols[!key_cols_lower %in% data_cols_lower]
  if (length(missing_cols) > 0) {
    error_msg <- paste("Key column(s) not found:", paste(missing_cols, collapse = ", "), ".")
    return(list(distinct_row_count = NULL, error_message = error_msg))
  }
  actual_cols <- names(data)[match(key_cols_lower, data_cols_lower)]
  distinct_count <- NULL
  error_message <- NULL
  tryCatch({
    arrow_table <- arrow::arrow_table(data)
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
    py_func <- reticulate::py_eval("count_distinct_rows_py", convert = FALSE)
    py_cols <- reticulate::r_to_py(as.list(actual_cols))
    distinct_count <- as.integer(reticulate::py_to_r(py_func(arrow_table, py_cols)))
    error_message <- NULL
  }, error = function(e) {
    error_message <<- paste("Error counting distinct rows:", e$message)
    distinct_count <<- NULL
  })
  # Note: duplicate_key_rows is required for Venn intersection logic in R06
  duplicate_key_rows <- NULL
  if (!is.null(actual_cols) && length(actual_cols) > 0) {
    duplicate_key_rows <- data[duplicated(data[, actual_cols, drop = FALSE]), actual_cols, drop = FALSE]
  }
  return(list(
    distinct_row_count = distinct_count,
    duplicate_key_rows = duplicate_key_rows,
    error_message = error_message
  ))
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
  distinct_row_result <- .count_distinct_rows(data, config$key_columns)
  if (!is.null(distinct_row_result)) {
    response$valid_rows <- .calculate_venn_valid_rows(
      total_rows = nrow(data),
      duplicate_keys_df = distinct_row_result$duplicate_key_rows,
      invalid_records_df = response$invalid_records_table,
      key_columns = config$key_columns
    )
    response$duplicate_rows_based_on_keys <- nrow(distinct_row_result$duplicate_key_rows)
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
      distinct_row_result <- .count_distinct_rows(data, config$key_columns)

      if (!is.null(distinct_row_result)) {
        result$valid_rows <- .calculate_venn_valid_rows(
          total_rows = nrow(data),
          duplicate_keys_df = distinct_row_result$duplicate_key_rows,
          invalid_records_df = result$invalid_records_table,
          key_columns = config$key_columns
        )
        result$duplicate_rows_based_on_keys <- nrow(distinct_row_result$duplicate_key_rows)
      }
    }

    return(result)
    }, error = function(e) {
      parsed_error <- .parse_dataconnect_error(conditionMessage(e))
      .throw_dataconnect_error(parsed_error)
  })
}
#' Error Detail Class
#'
#' S3 class representing a single error detail entry from a Flight error.
#' Each detail typically contains information about a specific field that caused
#' an error, including the field name, error message, and expected value.
#'
#' @param field Character string representing the field name that has an error (optional)
#' @param message Character string with the specific error message for this field (optional)
#' @param expected Character string describing the expected value (optional)
#' @param ... Additional named fields that may be present in the error detail
#'
#' @return An object of class 'ErrorDetail'
#'
#' @noRd
#' @keywords internal
ErrorDetail <- function(field = NULL, message = NULL, expected = NULL, ...) {
  # Capture any additional fields beyond the standard ones
  extra_fields <- list(...)
  
  # Build the base structure
  detail_obj <- list(
    field = field,
    message = message,
    expected = expected
  )
  
  # Add any extra fields
  if (length(extra_fields) > 0) {
    detail_obj <- c(detail_obj, extra_fields)
  }
  
  structure(detail_obj, class = "ErrorDetail")
}

#' Print Method for ErrorDetail
#'
#' @param x An ErrorDetail object
#' @param ... Additional arguments (unused)
#'
#' @export
#' @keywords internal
print.ErrorDetail <- function(x, ...) {
  cat("\n")
  cat("  Error Detail: \n")
  if (!is.null(x$field)) {
    cat("    Field: ", x$field, "\n", sep = "")
  }
  if (!is.null(x$message)) {
    cat("    Message: ", x$message, "\n", sep = "")
  }
  if (!is.null(x$expected)) {
    cat("    Expected: ", x$expected, "\n", sep = "")
  }
  
  # Print any additional fields
  standard_fields <- c("field", "message", "expected")
  extra_fields <- setdiff(names(x), standard_fields)
  if (length(extra_fields) > 0) {
    for (field_name in extra_fields) {
      cat("    ", field_name, ": ", as.character(x[[field_name]]), "\n", sep = "")
    }
  }
  
  invisible(x)
}

#' DataConnect Error Class
#'
#' S3 class representing a parsed DataConnect error with error_code, message,
#' timestamp, and details fields. The details field contains a list of
#' ErrorDetail objects providing specific information about each error.
#'
#' @param error_code Character string representing the error code
#' @param message Character string with the error message
#' @param timestamp Optional character string with ISO 8601 timestamp
#' @param details Optional list of ErrorDetail objects with additional error details
#'
#' @return An object of class 'DataConnectError'
#'
#' @noRd
#' @keywords internal
DataConnectError <- function(error_code, message, timestamp = NULL, details = NULL) {
  structure(
    list(
      error_code = error_code,
      message = message,
      timestamp = timestamp,
      details = details  # List of ErrorDetail objects
    ),
    class = "DataConnectError"
  )
}

#' Print Method for DataConnectError
#'
#' Formats and prints a DataConnectError object, including its error code,
#' message, optional timestamp, and any ErrorDetail entries in the details list.
#'
#' @param x A DataConnectError object
#' @param ... Additional arguments (unused)
#'
#' @export
#' @keywords internal
print.DataConnectError <- function(x, ...) {
  cat("Error Code: [", x$error_code, "]\n", sep = "")
  cat("Message: ", x$message, "\n", sep = "")
  
  if (!is.null(x$timestamp)) {
    cat("Timestamp: ", x$timestamp, "\n", sep = "")
  }
  
  if (!is.null(x$details) && length(x$details) > 0) {
    cat("Details:\n")
    for (i in seq_along(x$details)) {
      if (inherits(x$details[[i]], "ErrorDetail")) {
        print(x$details[[i]])
      } else {
        # Fallback for non-ErrorDetail objects
        cat("  [", i, "] ", as.character(x$details[[i]]), "\n", sep = "")
      }
    }
  }
  
  invisible(x)
}

#' Print Method for dataconnect_error condition
#'
#' S3 dispatch resolves on the first (most specific) class of an object.
#' When a dataconnect_error condition is caught in tryCatch and printed,
#' R looks for print.dataconnect_error first and then continues down the
#' class vector (e.g. to DataConnectError) if no method is found. 
#' Defining this method ensures the most-specific condition class has an
#' explicit print method and delegates to print.DataConnectError so the
#' formatted output remains consistent regardless of class ordering.
#'
#' @param x A dataconnect_error condition object
#' @param ... Additional arguments passed to print.DataConnectError
#'
#' @export
#' @keywords internal
print.dataconnect_error <- function(x, ...) {
  print.DataConnectError(x, ...)
}

#' Throw DataConnect Error
#'
#' Internal function to throw a DataConnectError condition. This allows calling
#' code to catch and handle structured error information using tryCatch. The
#' thrown condition is a DataConnectError object with added error/condition
#' classes, so users can access error_code, timestamp, details, etc. directly
#' from the error that is caught.
#'
#' @param dataconnect_error A DataConnectError object to throw
#' @param call The call to include in the error (default: sys.call(-1))
#'
#' @noRd
#' @keywords internal
.throw_dataconnect_error <- function(dataconnect_error, call = sys.call(-1)) {

  # Create a condition that is a DataConnectError with all fields directly
  # accessible. Users can catch this and access error_code, timestamp,
  # details, etc.
  condition <- structure(
    list(
      call = call,
      error_code = dataconnect_error$error_code,
      message = dataconnect_error$message,
      timestamp = dataconnect_error$timestamp,
      details = dataconnect_error$details
    ),
    class = c("dataconnect_error", "DataConnectError", "error", "condition")
  )

  stop(condition)
}

#' Extract JSON Object from String
#'
#' Internal function to extract the first complete JSON object from a string by
#' finding the matching closing brace for the first opening brace. Handles nested
#' braces and quoted strings (including escaped characters) correctly.
#'
#' @param text Character string potentially containing a JSON object
#'
#' @return The extracted JSON object substring, or the original string if no
#'   complete JSON object (matched braces) is found
#'
#' @noRd
#' @keywords internal
.extract_json_object <- function(text) {
  text <- gsub("\\\\\\\"", "\"", text) # Replacing excessive slashes from response

  first_brace <- regexpr("\\{", text)[1]

  if (first_brace < 1) {
    return(text)
  }

  brace_count <- 0
  in_string <- FALSE
  escape_next <- FALSE
  closing_brace_pos <- -1

  chars <- strsplit(substr(text, first_brace, nchar(text)), "")[[1]]

  for (i in seq_along(chars)) {
    char <- chars[i]

    if (escape_next) {
      escape_next <- FALSE
      next
    }

    if (char == "\\") {
      escape_next <- TRUE
      next
    }

    if (char == '"') {
      in_string <- !in_string
      next
    }

    if (!in_string) {
      if (char == "{") {
        brace_count <- brace_count + 1
      } else if (char == "}") {
        brace_count <- brace_count - 1
        if (brace_count == 0) {
          closing_brace_pos <- first_brace + i - 1
          break
        }
      }
    }
  }

  if (closing_brace_pos > 0) {
    return(substr(text, first_brace, closing_brace_pos))
  }

  text
}

#' Parse Flight Error Messages
#'
#' Internal function to parse error messages returned from Apache Arrow Flight
#' operations. Expects error messages in the format "PREFIX::JSON_PAYLOAD"
#' where JSON_PAYLOAD contains error_code, message, and optionally timestamp 
#' and details fields. The details field should be an array of objects, each
#' representing an ErrorDetail with field, message, and expected properties.
#'
#' @param error_message Character string containing the error message to parse.
#'   Expected format: "PREFIX::JSON_PAYLOAD" where JSON_PAYLOAD is valid JSON
#'   containing at minimum error_code and message fields. May also include:
#'   - timestamp: ISO 8601 formatted timestamp
#'   - details: Array of error detail objects, each with field, message, expected, etc.
#'
#' @return A DataConnectError object containing:
#'   \item{error_code}{The error code extracted from the JSON payload, or "UNKNOWN" if parsing fails}
#'   \item{message}{The error message extracted from the JSON payload, or the original error_message if parsing fails}
#'   \item{timestamp}{ISO 8601 timestamp if present in the JSON payload, NULL otherwise}
#'   \item{details}{List of ErrorDetail objects parsed from the details array, or NULL if not present}
#'
#' @importFrom jsonlite fromJSON
#'
#' @noRd
#' @keywords internal
.parse_dataconnect_error <- function(error_message) {
  unknown_error <- "Unknown error"
  
  # Validate input: must be a single, non-NA, non-empty character string.
  # Checking length == 1 before nchar() keeps nchar() scalar and prevents
  # if() from receiving a vector or NA logical. NA_character_ passes
  # is.character() but makes nchar() return NA, so we guard against that too.
  if (!is.character(error_message) ||
      length(error_message) != 1 ||
      is.na(error_message) ||
      nchar(error_message) == 0) {
    return(DataConnectError(
      error_code = "UNKNOWN",
      message = unknown_error
    ))
  }

  # Check if the error message follows the expected format: PREFIX::JSON_PAYLOAD
  # The :: delimiter separates the prefix from the JSON payload
  if (grepl("::", error_message, fixed = TRUE)) {
    
    # Split the error message into parts using :: as the delimiter
    # Only split on the first occurrence to handle :: within the JSON payload
    # fixed = TRUE ensures :: is treated as a literal string, not a regex
    first_delimiter_pos <- regexpr("::", error_message, fixed = TRUE)[1]
    parts <- c(
      substr(error_message, 1, first_delimiter_pos - 1),
      substr(error_message, first_delimiter_pos + 2, nchar(error_message))
    )

    # Verify the JSON payload part is non-empty
    if (nchar(parts[2]) > 0) {
      # Extract just the JSON object, handling potential trailing text
      json_part <- .extract_json_object(parts[2])
      
      # Attempt to parse the JSON payload (second part)
      tryCatch({
        # Parse the JSON string into an R list
        # simplifyDataFrame = FALSE ensures details arrays remain as lists
        error_data <- jsonlite::fromJSON(json_part, simplifyDataFrame = FALSE)

        # Parse details array into ErrorDetail objects if present
        parsed_details <- NULL
        if (!is.null(error_data$details) && is.list(error_data$details)) {
          # Convert each detail item into an ErrorDetail object
          parsed_details <- lapply(error_data$details, function(detail_item) {
            # Extract standard fields (NULL if absent)
            field_val    <- detail_item$field
            message_val  <- detail_item$message
            expected_val <- detail_item$expected

            # Get any extra fields beyond standard ones
            standard_names <- c("field", "message", "expected")
            extra_fields <- detail_item[!names(detail_item) %in% standard_names]
            
            # Create ErrorDetail with all fields
            do.call(ErrorDetail, c(
              list(field = field_val, message = message_val, expected = expected_val),
              extra_fields
            ))
          })
        }

        # Extract the structured error information from the parsed JSON
        # Return a DataConnectError object with all available fields
        return(DataConnectError(
          error_code = if (!is.null(error_data$error_code)) error_data$error_code else "UNKNOWN",
          message = if (!is.null(error_data$message)) error_data$message else unknown_error,
          timestamp = error_data$timestamp,  # NULL if not present
          details = parsed_details          # List of ErrorDetail objects or NULL
        ))
      }, error = function(e) {
        # If JSON parsing fails, return a DataConnectError with the original message
        return(DataConnectError(
          error_code = "UNKNOWN",
          message = error_message
        ))
      })
    }
  }

  # Default fallback for any error message that doesn't match the expected format
  # or couldn't be parsed successfully
  DataConnectError(
    error_code = "UNKNOWN",
    message = error_message
  )
}
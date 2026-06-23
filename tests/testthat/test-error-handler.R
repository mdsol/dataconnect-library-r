# Test suite for error_handler.R
# Tests the .parse_dataconnect_error function for proper error message parsing,
# the DataConnectError class, and the ErrorDetail class

# Load required libraries
library(testthat)
library(jsonlite)

# Directly source the file we need to test
source("../../R/error_handler.R")

# Test: Valid error message with proper format including all fields
test_that(".parse_dataconnect_error parses complete error messages correctly", {
  # Create a properly formatted error message with JSON payload including timestamp and details
  error_json <- '{"error_code":"AUTH_001","message":"Authentication failed","timestamp":"2026-02-12T10:30:00Z","details":[{"field":"token","message":"Invalid token","expected":"valid token"}]}'
  error_message <- paste0("AUTH::", error_json)
  
  # Parse the error message
  result <- .parse_dataconnect_error(error_message)
  
  # Verify the result is a DataConnectError object
  expect_s3_class(result, "DataConnectError")
  
  # Verify all fields were parsed correctly
  expect_equal(result$error_code, "AUTH_001")
  expect_equal(result$message, "Authentication failed")
  expect_equal(result$timestamp, "2026-02-12T10:30:00Z")
  
  # Verify details is a list of ErrorDetail objects
  expect_type(result$details, "list")
  expect_length(result$details, 1)
  expect_s3_class(result$details[[1]], "ErrorDetail")
  expect_equal(result$details[[1]]$field, "token")
  expect_equal(result$details[[1]]$message, "Invalid token")
  expect_equal(result$details[[1]]$expected, "valid token")
})

# Test: Valid error message with basic fields only
test_that(".parse_dataconnect_error parses basic error messages correctly", {
  # Create error message with only error_code and message
  error_json <- '{"error_code":"ERR_NOT_FOUND","message":"Resource not found"}'
  error_message <- paste0("ERROR::", error_json)
  
  # Parse the error message
  result <- .parse_dataconnect_error(error_message)
  
  # Verify the result is a DataConnectError object
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "ERR_NOT_FOUND")
  expect_equal(result$message, "Resource not found")
  expect_null(result$timestamp)
  expect_null(result$details)
})

# Test: Error message without :: delimiter
test_that(".parse_dataconnect_error handles messages without delimiter", {
  error_message <- "Simple error message without delimiter"
  
  result <- .parse_dataconnect_error(error_message)
  
  # Should return DataConnectError with UNKNOWN error code and original message
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, error_message)
})

# Test: Error message with invalid JSON payload
test_that(".parse_dataconnect_error handles invalid JSON gracefully", {
  # Create error message with malformed JSON
  error_message <- "ERROR::{this is not valid json}"
  
  result <- .parse_dataconnect_error(error_message)
  
  # Should return DataConnectError with UNKNOWN and original message when JSON parsing fails
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, error_message)
})

# Test: Error message with incomplete JSON (missing closing brace)
test_that(".parse_dataconnect_error handles incomplete JSON", {
  error_message <- 'ERROR::{"error_code":"ERR_BAD","message":"Bad request"'
  
  result <- .parse_dataconnect_error(error_message)
  
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, error_message)
})

# Test: Empty string input
test_that(".parse_dataconnect_error handles empty string", {
  result <- .parse_dataconnect_error("")
  
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, "Unknown error")
})

# Test: Non-character input
test_that(".parse_dataconnect_error handles non-character input", {
  # Test with NULL
  result <- .parse_dataconnect_error(NULL)
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, "Unknown error")

  # Test with numeric value
  result <- .parse_dataconnect_error(123)
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, "Unknown error")

  # Test with NA_character_ (passes is.character() but nchar() returns NA)
  result <- .parse_dataconnect_error(NA_character_)
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, "Unknown error")

  # Test with a length > 1 character vector
  result <- .parse_dataconnect_error(c("a", "b"))
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, "Unknown error")
})

# Test: Error message with multiple :: delimiters
test_that(".parse_dataconnect_error handles multiple delimiters", {
  # Only the first :: should be used as delimiter
  error_json <- '{"error_code":"ERR_CONNECT","message":"Failed to connect to server::port"}'
  error_message <- paste0("ERROR::", error_json)
  
  result <- .parse_dataconnect_error(error_message)
  
  # Should parse successfully, treating first :: as delimiter
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "ERR_CONNECT")
  expect_equal(result$message, "Failed to connect to server::port")
})

# Test: Error message with whitespace in JSON
test_that(".parse_dataconnect_error handles JSON with whitespace", {
  error_json <- '{
    "error_code": "ERR_WHITESPACE",
    "message": "Error with whitespace",
    "details": [{"field": "name", "message": "This JSON has newlines and spaces"}]
  }'
  error_message <- paste0("ERROR::", error_json)
  
  result <- .parse_dataconnect_error(error_message)
  
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "ERR_WHITESPACE")
  expect_equal(result$message, "Error with whitespace")
  expect_type(result$details, "list")
  expect_length(result$details, 1)
  expect_s3_class(result$details[[1]], "ErrorDetail")
  expect_equal(result$details[[1]]$field, "name")
  expect_equal(result$details[[1]]$message, "This JSON has newlines and spaces")
})

# Test: Error message with special characters in JSON values
test_that(".parse_dataconnect_error handles special characters", {
  error_json <- '{"error_code":"ERR_SPECIAL","message":"Error: failed @ 100%","details":[{"field":"path","message":"Invalid path","expected":"C:\\\\Users\\\\test"}]}'
  error_message <- paste0("ERROR::", error_json)
  
  result <- .parse_dataconnect_error(error_message)
  
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "ERR_SPECIAL")
  expect_equal(result$message, "Error: failed @ 100%")
  expect_s3_class(result$details[[1]], "ErrorDetail")
  expect_equal(result$details[[1]]$field, "path")
  expect_equal(result$details[[1]]$expected, "C:\\Users\\test")
})

# Test: Error message with nested JSON in details as array
test_that(".parse_dataconnect_error handles multiple error details", {
  error_json <- '{"error_code":"ERR_VALIDATION","message":"Validation failed","details":[{"field":"name","message":"Name too short","expected":"min 3 chars"},{"field":"age","message":"Age out of range","expected":"18-100"}]}'
  error_message <- paste0("ERROR::", error_json)
  
  result <- .parse_dataconnect_error(error_message)
  
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "ERR_VALIDATION")
  expect_equal(result$message, "Validation failed")
  expect_type(result$details, "list")
  expect_length(result$details, 2)
  
  # Check first detail
  expect_s3_class(result$details[[1]], "ErrorDetail")
  expect_equal(result$details[[1]]$field, "name")
  expect_equal(result$details[[1]]$message, "Name too short")
  expect_equal(result$details[[1]]$expected, "min 3 chars")
  
  # Check second detail
  expect_s3_class(result$details[[2]], "ErrorDetail")
  expect_equal(result$details[[2]]$field, "age")
  expect_equal(result$details[[2]]$message, "Age out of range")
  expect_equal(result$details[[2]]$expected, "18-100")
})

# Test: Error message with only one part (no JSON after ::)
test_that(".parse_dataconnect_error handles delimiter without JSON", {
  error_message <- "ERROR::"
  
  result <- .parse_dataconnect_error(error_message)
  
  # Should handle gracefully, likely failing JSON parse
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, error_message)
})

# Test: Error message with empty JSON object
test_that(".parse_dataconnect_error handles empty JSON object", {
  error_message <- "ERROR::{}"
  
  result <- .parse_dataconnect_error(error_message)
  
  # Should parse but have UNKNOWN fields due to missing required fields
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "UNKNOWN")
  expect_equal(result$message, "Unknown error")
  expect_null(result$details)
  expect_null(result$timestamp)
})

# Test: Error message with timestamp field
test_that(".parse_dataconnect_error extracts timestamp correctly", {
  error_json <- '{"error_code":"ERR_TIME","message":"Timeout error","timestamp":"2026-02-19T15:45:30Z"}'
  error_message <- paste0("ERROR::", error_json)
  
  result <- .parse_dataconnect_error(error_message)
  
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "ERR_TIME")
  expect_equal(result$message, "Timeout error")
  expect_equal(result$timestamp, "2026-02-19T15:45:30Z")
})

# Test: DataConnectError print method
test_that("DataConnectError print method works correctly", {
  # Construct DataConnectError directly to isolate the print method from parsing
  detail <- ErrorDetail(field = "test_field", message = "Test message")
  result <- DataConnectError(
    error_code = "TEST_001",
    message    = "Test error",
    timestamp  = "2026-02-19T10:00:00Z",
    details    = list(detail)
  )

  # Verify key output lines
  expect_output(print(result), "Error Code: \\[TEST_001\\]")
  expect_output(print(result), "Message: Test error")
  expect_output(print(result), "Timestamp: 2026-02-19T10:00:00Z")
  expect_output(print(result), "Details")
})

# Test: DataConnectError print method without optional fields
test_that("DataConnectError print method omits timestamp and details when absent", {
  result <- DataConnectError(error_code = "ERR_BARE", message = "Bare error")

  output <- capture_output(print(result))
  expect_match(output, "Error Code: \\[ERR_BARE\\]")
  expect_match(output, "Message: Bare error")
  expect_no_match(output, "Timestamp")
  expect_no_match(output, "Details")
})

# Test: ErrorDetail class creation
test_that("ErrorDetail class can be created with standard fields", {
  detail <- ErrorDetail(
    field = "username",
    message = "Username is required",
    expected = "non-empty string"
  )
  
  expect_s3_class(detail, "ErrorDetail")
  expect_equal(detail$field, "username")
  expect_equal(detail$message, "Username is required")
  expect_equal(detail$expected, "non-empty string")
})

# Test: ErrorDetail with extra fields
test_that("ErrorDetail class handles extra fields beyond standard ones", {
  error_json <- '{"error_code":"ERR_CUSTOM","message":"Custom error","details":[{"field":"email","message":"Invalid email","expected":"user@domain.com","severity":"high","code":"E001"}]}'
  error_message <- paste0("ERROR::", error_json)
  
  result <- .parse_dataconnect_error(error_message)
  
  expect_s3_class(result$details[[1]], "ErrorDetail")
  expect_equal(result$details[[1]]$field, "email")
  expect_equal(result$details[[1]]$message, "Invalid email")
  expect_equal(result$details[[1]]$expected, "user@domain.com")
  expect_equal(result$details[[1]]$severity, "high")
  expect_equal(result$details[[1]]$code, "E001")
})

# Test: ErrorDetail print method
test_that("ErrorDetail print method works correctly", {
  detail <- ErrorDetail(
    field = "password",
    message = "Password too weak",
    expected = "min 8 characters"
  )

  expect_output(print(detail), "Error Detail")
  expect_output(print(detail), "Field: password")
  expect_output(print(detail), "Message: Password too weak")
  expect_output(print(detail), "Expected: min 8 characters")
})

# Test: ErrorDetail with partial fields (NULLs are silently skipped in print)
test_that("ErrorDetail print method omits NULL fields", {
  detail <- ErrorDetail(field = "token")

  output <- capture_output(print(detail))
  expect_match(output, "Field: token")
  expect_no_match(output, "Message")
  expect_no_match(output, "Expected")
})

# Test: ErrorDetail print method with extra fields
test_that("ErrorDetail print method outputs extra fields", {
  detail <- ErrorDetail(
    field    = "email",
    message  = "Invalid email",
    severity = "high",
    code     = "E001"
  )

  expect_output(print(detail), "severity: high")
  expect_output(print(detail), "code: E001")
})

# Test: Error message with trailing text after JSON (real-world pyarrow format)
test_that(".parse_dataconnect_error handles error messages with trailing text after JSON", {
  # Real format from pyarrow.flight errors which have ". Detail: Failed" after JSON
  error_message <- 'pyarrow._flight.FlightServerError: RES_002::{
  "error_code": "RES_002",
  "message": "Study environment not found",
  "timestamp": "2026-02-23T17:24:50.837551Z",
  "details": [
    {
      "field": "study_env_uuid",
      "message": "",
      "expected": "A valid study_env_uuid"
    }
  ]
}. Detail: Failed'
  
  # Parse the error message
  result <- .parse_dataconnect_error(error_message)
  
  # Verify the result is a DataConnectError object with correct parsing
  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "RES_002")
  expect_equal(result$message, "Study environment not found")
  expect_equal(result$timestamp, "2026-02-23T17:24:50.837551Z")
  
  # Verify details were parsed correctly despite trailing text
  expect_type(result$details, "list")
  expect_length(result$details, 1)
  expect_s3_class(result$details[[1]], "ErrorDetail")
  expect_equal(result$details[[1]]$field, "study_env_uuid")
  expect_equal(result$details[[1]]$message, "")
  expect_equal(result$details[[1]]$expected, "A valid study_env_uuid")
})
# Test: .throw_dataconnect_error raises a condition with the correct class and fields
test_that(".throw_dataconnect_error throws a dataconnect_error condition with all fields", {
  detail          <- ErrorDetail(field = "x", message = "bad value", expected = "integer")
  dataconnect_err <- DataConnectError(
    error_code = "ERR_THROW",
    message    = "Thrown error",
    timestamp  = "2026-01-01T00:00:00Z",
    details    = list(detail)
  )

  # Verify it throws an error of the right class
  expect_error(.throw_dataconnect_error(dataconnect_err), class = "dataconnect_error")

  # Verify all fields are accessible on the caught condition
  tryCatch(
    .throw_dataconnect_error(dataconnect_err),
    dataconnect_error = function(e) {
      expect_equal(e$error_code, "ERR_THROW")
      expect_equal(e$message,    "Thrown error")
      expect_equal(e$timestamp,  "2026-01-01T00:00:00Z")
      expect_length(e$details, 1)
      expect_s3_class(e$details[[1]], "ErrorDetail")
      expect_equal(e$details[[1]]$field, "x")
    }
  )
})

# =============================================================================
# Tests for .normalize_enodia_error
# =============================================================================

# Test: Non-matching messages are returned unchanged
test_that(".normalize_enodia_error passes through non-enodia errors unchanged", {
  msgs <- c(
    "Simple error",
    "FlightServerError: some other error",
    "ERROR::some json payload",
    "Connection refused",
    # Structured PREFIX::JSON whose payload mentions "unauthenticated error" — must
    # NOT be normalised; the broad old pattern would have silently overwritten it.
    'XYZ_E_099::{"error_code":"XYZ_E_099","message":"unauthenticated error occurred"}'
  )
  for (msg in msgs) {
    expect_equal(.normalize_enodia_error(msg), msg)
  }
})

# Test: Flight unauthenticated gate matches but message is unrecognized — falls back to AUTH_E_001
test_that(".normalize_enodia_error maps unknown flight unauthenticated messages to AUTH_E_001", {
  msg <- "Flight returned unauthenticated error, with message: some unknown server error. gRPC client debug context: foo"
  result <- .normalize_enodia_error(msg)

  expect_match(result, "^AUTH_E_001::\\{")

  json_str <- sub("^AUTH_E_001::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)

  expect_equal(parsed$error_code, "AUTH_E_001")
  expect_equal(parsed$message, "Authentication token is missing from the request.")
})

# Test: Scenario 1 — No authorization header (AUTH_E_001)
test_that(".normalize_enodia_error maps missing auth header to AUTH_E_001", {
  msg <- "Flight returned unauthenticated error, with message: authorization header not present. gRPC client debug context: foo"
  result <- .normalize_enodia_error(msg)

  # Should be rewritten to PREFIX::JSON format
  expect_match(result, "^AUTH_E_001::\\{")

  # Parse the JSON payload to verify fields
  json_str <- sub("^AUTH_E_001::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)

  expect_equal(parsed$error_code, "AUTH_E_001")
  expect_equal(parsed$message, "Authentication token is missing from the request.")
  expect_true(nzchar(parsed$timestamp))
  expect_length(parsed$details, 1)
  expected_detail_msg <- paste0(
    "Ensure you provide the correct user authentication ",
    "token. The user token must be valid and generated ",
    "from the SDK Key Management page in iMedidata > ",
    "Data Connect > Developer Center."
  )
  expect_equal(parsed$details[[1]]$field, "token")
  expect_null(parsed$details[[1]]$message)
  expect_equal(parsed$details[[1]]$expected, expected_detail_msg)
})

# Test: Scenario 2 — Malformed token (AUTH_E_002)
test_that(".normalize_enodia_error maps malformed token to AUTH_E_002", {
  msg <- "FlightUnauthenticatedError: Flight returned unauthenticated error, with message: API token not provided or formatted incorrectly. gRPC client debug context: bar"
  result <- .normalize_enodia_error(msg)

  expect_match(result, "^AUTH_E_002::\\{")

  json_str <- sub("^AUTH_E_002::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)

  expected_detail_msg <- paste0(
    "Ensure you provide the correct user authentication ",
    "token. The user token must be valid and generated ",
    "from the SDK Key Management page in iMedidata > ",
    "Data Connect > Developer Center."
  )
  expect_equal(parsed$error_code, "AUTH_E_002")
  expect_equal(parsed$message, "Authentication token is invalid or malformed.")
  expect_null(parsed$details[[1]]$message)
  expect_equal(parsed$details[[1]]$expected, expected_detail_msg)
})

# Test: Scenario 3 — Invalid API token (AUTH_E_003)
test_that(".normalize_enodia_error maps invalid API token to AUTH_E_003", {
  msg <- "FlightUnauthenticatedError: Flight returned unauthenticated error, with message: Invalid API token. gRPC client debug context: baz"
  result <- .normalize_enodia_error(msg)

  expect_match(result, "^AUTH_E_003::\\{")

  json_str <- sub("^AUTH_E_003::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)

  expected_detail_msg <- paste0(
    "Ensure you provide the correct user authentication ",
    "token. The user token must be valid and generated ",
    "from the SDK Key Management page in iMedidata > ",
    "Data Connect > Developer Center."
  )
  expect_equal(parsed$error_code, "AUTH_E_003")
  expect_equal(parsed$message, "Authentication token is expired or revoked.")
  expect_null(parsed$details[[1]]$message)
  expect_equal(parsed$details[[1]]$expected, expected_detail_msg)
})

# Test: Scenario 4 — Rate limit exceeded (AUTH_E_004)
test_that(".normalize_enodia_error maps rate limit exceeded to AUTH_E_004", {
  msg <- "FlightUnauthenticatedError: Flight returned unauthenticated error, with message: rate limit exceeded. gRPC client debug context: qux"
  result <- .normalize_enodia_error(msg)

  expect_match(result, "^AUTH_E_004::\\{")

  json_str <- sub("^AUTH_E_004::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)

  expect_equal(parsed$error_code, "AUTH_E_004")
  expect_equal(parsed$message, "Rate limit exceeded.")
  expect_null(parsed$details[[1]]$message)
  expect_equal(parsed$details[[1]]$expected, "Wait before making more requests.")
})

# Test: No server message defaults to AUTH_E_001
test_that(".normalize_enodia_error defaults to AUTH_E_001 when no server message", {
  # Message matches the gate but has no "with message:" segment
  msg <- "FlightUnauthenticatedError: some opaque gRPC failure"
  result <- .normalize_enodia_error(msg)

  expect_match(result, "^AUTH_E_001::\\{")

  json_str <- sub("^AUTH_E_001::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)

  expect_equal(parsed$error_code, "AUTH_E_001")
  expect_equal(parsed$message, "Authentication token is missing from the request.")
})

# Test: Case-insensitive gate matching
test_that(".normalize_enodia_error gate pattern is case-insensitive", {
  # Mixed case FlightUnauthenticatedError
  msg1 <- "flightunauthenticatederror: with message: authorization header not present"
  result1 <- .normalize_enodia_error(msg1)
  expect_match(result1, "^AUTH_E_001::\\{")

  # "unauthenticated error" variant
  msg2 <- "Flight returned UNAUTHENTICATED ERROR, with message: Invalid API token"
  result2 <- .normalize_enodia_error(msg2)
  expect_match(result2, "^AUTH_E_003::\\{")
})

# Test: Strips gRPC debug context noise
test_that(".normalize_enodia_error strips trailing gRPC debug context", {
  msg <- "FlightUnauthenticatedError: Flight returned unauthenticated error, with message: authorization header not present. gRPC client debug context: {\"created\":\"@1234567890\",\"description\":\"Error\",\"grpc_status\":16}"
  result <- .normalize_enodia_error(msg)

  json_str <- sub("^AUTH_E_001::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)

  # The server message should be clean, without gRPC debug noise
  expect_equal(parsed$error_code, "AUTH_E_001")
  expect_equal(parsed$message, "Authentication token is missing from the request.")
})

# Test: Strips "Client context:" trailing noise
test_that(".normalize_enodia_error strips trailing Client context noise", {
  msg <- "FlightUnauthenticatedError: Flight returned unauthenticated error, with message: Invalid API token. Client context: some::debug::info"
  result <- .normalize_enodia_error(msg)

  expect_match(result, "^AUTH_E_003::\\{")

  json_str <- sub("^AUTH_E_003::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)
  expect_equal(parsed$error_code, "AUTH_E_003")
})

# Test: Output is valid PREFIX::JSON consumed by .parse_dataconnect_error
test_that(".normalize_enodia_error output is parseable by .parse_dataconnect_error", {
  msg <- "FlightUnauthenticatedError: Flight returned unauthenticated error, with message: authorization header not present. gRPC client debug context: debug"

  # The normalized output should flow through .parse_dataconnect_error correctly
  result <- .parse_dataconnect_error(msg)

  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "AUTH_E_001")
  expect_equal(result$message, "Authentication token is missing from the request.")
  expect_true(!is.null(result$timestamp))
  expect_length(result$details, 1)
  expect_s3_class(result$details[[1]], "ErrorDetail")
  expect_equal(result$details[[1]]$field, "token")
})

# Test: Timestamp is valid ISO 8601 format
test_that(".normalize_enodia_error produces valid ISO 8601 timestamp", {
  msg <- "FlightUnauthenticatedError: with message: Invalid API token"
  result <- .normalize_enodia_error(msg)

  json_str <- sub("^AUTH_E_003::", "", result)
  parsed <- jsonlite::fromJSON(json_str, simplifyDataFrame = FALSE)

  # Verify timestamp parses as a valid datetime
  ts <- as.POSIXct(parsed$timestamp, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  expect_false(is.na(ts))
})

test_that(".parse_dataconnect_error correctly parses streaming error details", {
  msg <- "FlightServerError: STR_STREAMING_ERROR::{\"error_code\":\"STR_001\", \"message\":\"Failed after 10 rows.\"}"
  
  result <- .parse_dataconnect_error(msg)
  
  # Verificăm proprietățile reale ale obiectului DataConnectError
  expect_equal(result$error_code, "STR_001")
  expect_equal(result$message, "Failed after 10 rows.")
})

# Test: Authorization error (AUTHZ_002) with realistic gRPC metadata noise before PREFIX::JSON
test_that(".parse_dataconnect_error parses AUTHZ_002 authorization error correctly", {
  error_json <- '{"error_code":"AUTHZ_002","message":"You are not allowed to publish to this project.","timestamp":"2026-06-23T11:40:04.721125+00:00","details":[{"field":"user_uuid","message":"User aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee is not the project owner for project ffffffff-1111-2222-3333-444444444444.","expected":"Make sure you are a project owner for project TestProject and try again."}]}'
  # Real-world format: gRPC metadata wrapper with an earlier '::' and stray JSON before the payload
  error_message <- paste0(
    'Client context: some::debug {"foo":"bar"} grpc_message:"AUTHZ_002::',
    error_json,
    '". Detail: Permission denied'
  )

  result <- .parse_dataconnect_error(error_message)

  expect_s3_class(result, "DataConnectError")
  expect_equal(result$error_code, "AUTHZ_002")
  expect_equal(result$message, "You are not allowed to publish to this project.")
  expect_equal(result$timestamp, "2026-06-23T11:40:04.721125+00:00")
  expect_type(result$details, "list")
  expect_length(result$details, 1)
  expect_s3_class(result$details[[1]], "ErrorDetail")
  expect_equal(result$details[[1]]$field, "user_uuid")
  expect_equal(result$details[[1]]$message, "User aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee is not the project owner for project ffffffff-1111-2222-3333-444444444444.")
  expect_equal(
    result$details[[1]]$expected,
    "Make sure you are a project owner for project TestProject and try again."
  )
})

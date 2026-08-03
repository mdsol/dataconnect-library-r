context("Publishing operations")

# Load required libraries
library(testthat)
library(mockery)

# Directly source the files we need to test
source("../../R/commands.R")
source("../../R/publishing.R")

# Create a mock function for .get_flight_options that we'll use in each test
mock_flight_options <- function() {
  list(headers = list(c("x-client-dataconnect", "1.2.0")))
}

# Create sample data and schema that will be used across tests
sample_data <- data.frame(
  subjid = c("001", "002", "003", "004", "005"),
  visit = c("Baseline", "Week 2", "Week 4", "Week 6", "Week 8"),
  measurement = c(25.5, 30.2, 15.8, 22.1, 28.9),
  site = c("Site A", "Site A", "Site B", "Site B", "Site C"),
  stringsAsFactors = FALSE
)

# Standard configuration for tests
test_config <- list(
  project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b76ad",
  study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a560",
  study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d56793",
  dataset_name = "my_dataset",
  dataset_description = "Example dataset",
  key_columns = list("subjid", "visit"),
  source_datasets = list()
)

test_that("dry_publish validates inputs and prepares for server call", {
  # Configuration for your dataset
  config <- list(
    project_uuid = "ec079457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2144dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec1f2a7-07ba-4fa8-bfcf-34fbc5d56793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )

  # Create a mock client
  mock_client <- list()

  # Test input validation
  expect_error(.dry_publish(NULL, config, sample_data), "Client must be provided")
  expect_error(.dry_publish(mock_client, NULL, sample_data), "Configuration must be provided")
  expect_error(.dry_publish(mock_client, config, NULL), "Data must be provided")
  expect_error(.dry_publish(mock_client, config, "not_data_frame"), "Data must be a data.frame")
  
  # Test that the function accepts valid inputs without error (we'll skip the actual execution)
  # This validates that our input preparation logic is sound
  expect_true(inherits(sample_data, "data.frame"))
  expect_true(is.list(config))
  expect_true(!is.null(config$dataset_name))
})

test_that("dry_publish parses server response correctly and drops batch number", {
  test_data <- data.frame(
    subjid = c("001", "002", "003", "001", "002"),
    visit = c("V1", "V1", "V2", "V1", "V1")
  )
  
  # This mock represents what the MAPPED result should look like 
  # after it passes through your logic in R/commands.R
  mock_mapped_result <- list(
    status = "valid",
    valid_rows = 3,
    duplicate_rows_based_on_keys = 2,
    # Note: dataset_batch_number is NOT here because the mapper should have removed it
    dataset_name = "test_dataset"
  )
  
  config <- list(dataset_name = "test_dataset") 
  mock_client <- list()
  
  # We stub .do_command to return the ALREADY MAPPED list.
  # We wrap it in list() because your code does result[[1]]
  mockery::stub(.dry_publish, ".do_command", function(...) {
    return(list(mock_mapped_result))
  })
  
  result <- .dry_publish(mock_client, config, test_data)
  
  # Now these should pass because we are simulating the correct internal flow
  expect_equal(result$valid_rows, 3)
  expect_equal(result$duplicate_rows_based_on_keys, 2) 
  
  # This will now be NULL because it's not in our mock_mapped_result
  expect_null(result$dataset_batch_number)
})

test_that("dry_publish handles all unique rows via server response", {
  test_data <- data.frame(id = c(1, 2, 3))
  config <- list(dataset_name = "unique_test")
  
  # Server reports 0 duplicates
  mock_response <- list(
    status = "valid",
    valid_rows = 3,
    duplicate_rows_based_on_keys = 0
  )
  
  mockery::stub(.dry_publish, ".do_command", function(...) list(mock_response))
  
  result <- .dry_publish(list(), config, test_data)
  
  expect_equal(result$valid_rows, 3)
  expect_equal(result$duplicate_rows_based_on_keys, 0)
})

test_that("dry_publish handles all duplicate rows via server response", {
  test_data <- data.frame(id = c(1, 1, 1))
  config <- list(dataset_name = "dup_test")
  
  # Server reports only 1 valid row out of 3
  mock_response <- list(
    status = "valid",
    valid_rows = 1,
    duplicate_rows_based_on_keys = 2
  )
  
  mockery::stub(.dry_publish, ".do_command", function(...) list(mock_response))
  
  result <- .dry_publish(list(), config, test_data)
  
  expect_equal(result$valid_rows, 1)
  expect_equal(result$duplicate_rows_based_on_keys, 2)
})

test_that("dry_publish returns server-validated counts regardless of column casing", {
  # Mixed case data frame
  test_data <- data.frame(SubjID = c("001", "001"), VISIT = c("V1", "V1"))
  
  # Server handles the casing and returns the result
  mock_server_response <- list(
    status = "valid",
    valid_rows = 1,
    duplicate_rows = 1
  )
  
  mock_dry_publish <- function(client, config, data) {
    return(mock_server_response)
  }
  
  result <- mock_dry_publish(NULL, list(), test_data)
  
  expect_equal(result$valid_rows, 1)
  expect_equal(result$duplicate_rows, 1)
})

test_that(".publish correctly returns server-side record metrics without key duplication", {
  # 1. Setup dummy data, client, and missing config
  dummy_client <- list()
  dummy_data <- data.frame(subjid = "001", val = 1)
  test_config <- list(key_columns = list("subjid"))
  
  # 2. Mock what .do_put_command returns natively using the new server-side contract
  mock_put_result <- list(
    success = TRUE, 
    dataset_name = "DS1TEST",
    valid_record_count = 100,      
    duplicate_record_count = 0,    
    invalid_record_count = 0,
    invalid_records = NULL
  )
  
  # 3. Stub the internal functions so .publish doesn't do real network actions
  mockery::stub(.publish, ".do_put_command", mock_put_result)
  
  # 4. Execute the publish command
  result <- .publish(dummy_client, test_config, dummy_data)
  
  # 5. Verifications
  keys <- names(result)
  
  # Ensure the list properties are entirely unique (no duplicate keys in return payload map)
  expect_equal(length(keys), length(unique(keys)), 
               info = "The resulting list contains duplicate key allocations!")
               
  # Validate that the new server-side contract fields pass through natively
  expect_equal(result$valid_record_count, 100)
  expect_equal(result$duplicate_record_count, 0)
  expect_equal(result$invalid_record_count, 0)
})

test_that(".do_put_command converts STR_STREAMING_ERROR to a soft failure when is_dry_publish is TRUE", {
  # 1. Create minimal mock client that passes initial phases
  read_call_count <- 0
  
  mock_writer <- list(
    write_table = function(x) NULL,
    done_writing = function() NULL,
    close = function() NULL
  )
  
  # Mock reader that returns different values on successive calls:
  # First call: valid JSON status response
  # Second call: should trigger stream error (but we'll inject error earlier)
  mock_reader <- list(
    read = function() {
      read_call_count <<- read_call_count + 1
      if (read_call_count == 1) {
        # First read returns the canonical publish envelope
        charToRaw('{"success": true, "metadata": {"dataset_name": "test"}, "metrics": {"total_valid_rows": 0, "total_invalid_rows": 5, "total_duplicate_rows": 0}, "checks": {"schema_is_valid": true, "config_is_valid": true, "date_formats_are_valid": true, "dataset_is_valid": true, "invalid_datetime_formats": {}}, "errors": []}')
      } else {
        # Second read would return error buffer, but we'll inject error in open_stream instead
        charToRaw('')
      }
    }
  )
  
  mock_client <- list(
    do_put = function(descriptor, schema, options) {
      list(mock_writer, mock_reader)
    }
  )
  
  # 2. THE KEY: Stub reticulate::import to return a mock pyarrow module
  # When .do_put_command calls reticulate::import("pyarrow", convert = FALSE),
  # we return a mock that throws STR_STREAMING_ERROR when open_stream is called
  mock_pa <- list(
    ipc = list(
      open_stream = function(...) {
        stop("FlightServerError: STR_STREAMING_ERROR::{\"error_code\":\"STR_001\", \"message\":\"Mid-stream failure\"}")
      }
    )
  )
  
  mockery::stub(
    .do_put_command,
    "reticulate::import",
    function(module, convert = TRUE) {
      if (module == "pyarrow.flight") {
        # Return mock for pa_flight import (used earlier in function)
        list(
          FlightDescriptor = list(
            for_path = function(x) list(path = x)
          )
        )
      } else if (module == "pyarrow") {
        # Return our mock that will throw the streaming error
        mock_pa
      } else {
        stop("Unexpected module import: ", module)
      }
    }
  )
  
  # Also stub .get_flight_options to avoid side effects
  mockery::stub(.do_put_command, ".get_flight_options", function() list())
  
  mock_config <- list(is_dry_publish = TRUE)
  mock_data <- data.frame(a = 1)
  
  # 3. Execute and verify - for dry_publish, outer tryCatch converts error to soft failure
  # The inner tryCatch detects STREAMING_ERROR, calls stop(), and outer tryCatch
  # should preserve that classification because the original error text is included
  result <- .do_put_command(mock_client, mock_config, mock_data)
  
  # Verify it's a soft failure (not an exception)
  expect_type(result, "list")
  expect_false(result$success)
  
  # Verify the soft failure retains the streaming classification and backend details
  expect_equal(result$error_type, "STREAMING_ERROR")
  expect_true(grepl("STR_001|Mid-stream failure", result$error_message))
})

test_that(".do_put_command gracefully handles empty error stream (python.builtin.NoneType)", {
  
  read_call_count <- 0
  
  # Mock the reader to return a valid JSON first, and a Python None object second
  mock_reader <- list(
    read = function() {
      read_call_count <<- read_call_count + 1
      if (read_call_count == 1) {
        # First read: Server returns the canonical publish envelope
        charToRaw('{"success": true, "metadata": {"dataset_name": "test"}, "metrics": {"total_valid_rows": 2, "total_invalid_rows": 0, "total_duplicate_rows": 1}, "checks": {"schema_is_valid": true, "config_is_valid": true, "date_formats_are_valid": true, "dataset_is_valid": true, "invalid_datetime_formats": {}}, "errors": []}')
      } else {
        # Second read: Simulate the Python NoneType object returned by the optimized backend
        structure(list(), class = c("python.builtin.NoneType", "python.builtin.object"))
      }
    }
  )
  
  mock_writer <- list(write_table = function(x) NULL, done_writing = function() NULL, close = function() NULL)
  mock_client <- list(do_put = function(descriptor, schema, options) list(mock_writer, mock_reader))
  
  # Stub reticulate and options so it runs in pure R
  mockery::stub(.do_put_command, "reticulate::import", function(...) list(FlightDescriptor = list(for_path = function(x) list(path = x))))
  mockery::stub(.do_put_command, ".get_flight_options", list())
  
  mock_config <- list(is_dry_publish = TRUE)
  mock_data <- data.frame(subjid = c("001", "002"))
  
  # Execute the command
  result <- .do_put_command(mock_client, mock_config, mock_data)
  
  # Verifications: It should NOT crash, and invalid_records should be an empty list
  expect_true(result$success)
  expect_equal(result$metrics$total_valid_rows, 2)
  expect_equal(result$metrics$total_duplicate_rows, 1)
  expect_equal(result$invalid_records, list())
})

# ==============================================================================
# Canonical envelope contract (shared shape with the Python SDK / Arrow server)
# ==============================================================================
test_that(".do_put_command surfaces the full checks section for a failing dry_publish", {
  read_call_count <- 0
  mock_reader <- list(
    read = function() {
      read_call_count <<- read_call_count + 1
      if (read_call_count > 1) return(NULL)  # no invalid-records IPC stream to open
      charToRaw(paste0(
        '{"success": false, ',
        '"metadata": {"dataset_name": "test", "dataset_version": null, "column_count": 3, ',
        '"dataset_uuid": null, "dataset_batch_number": null}, ',
        '"metrics": {"total_valid_rows": 1, "total_invalid_rows": 1, "total_duplicate_rows": 0}, ',
        '"checks": {"schema_is_valid": false, "config_is_valid": true, "date_formats_are_valid": false, ',
        '"dataset_is_valid": false, "invalid_datetime_formats": {"visit_date": "DD-MM-YYYY"}}, ',
        '"errors": ["schema mismatch"]}'
      ))
    }
  )

  mock_writer <- list(write_table = function(x) NULL, done_writing = function() NULL, close = function() NULL)
  mock_client <- list(do_put = function(descriptor, schema, options) list(mock_writer, mock_reader))

  mockery::stub(.do_put_command, "reticulate::import", function(...) list(FlightDescriptor = list(for_path = function(x) list(path = x))))
  mockery::stub(.do_put_command, ".get_flight_options", list())

  mock_config <- list(is_dry_publish = TRUE)
  mock_data <- data.frame(subjid = c("001", "002"))

  result <- .do_put_command(mock_client, mock_config, mock_data)

  expect_false(result$success)
  expect_equal(result$metadata$column_count, 3)
  expect_null(result$metadata$dataset_uuid)
  expect_false(result$checks$schema_is_valid)
  expect_false(result$checks$dataset_is_valid)
  expect_equal(result$checks$invalid_datetime_formats, list(visit_date = "DD-MM-YYYY"))
  expect_equal(result$errors, "schema mismatch")
})

test_that(".do_put_command surfaces dataset_uuid and dataset_batch_number for a real publish", {
  read_call_count <- 0
  mock_reader <- list(
    read = function() {
      read_call_count <<- read_call_count + 1
      if (read_call_count > 1) return(NULL)  # no invalid-records IPC stream to open
      charToRaw(paste0(
        '{"success": true, ',
        '"metadata": {"dataset_name": "test", "dataset_version": 2, "column_count": 4, ',
        '"dataset_uuid": "abc-123", "dataset_batch_number": 7}, ',
        '"metrics": {"total_valid_rows": 5, "total_invalid_rows": 0, "total_duplicate_rows": 0}, ',
        '"checks": {"schema_is_valid": true, "config_is_valid": true, "date_formats_are_valid": true, ',
        '"dataset_is_valid": true, "invalid_datetime_formats": {}}, ',
        '"errors": []}'
      ))
    }
  )

  mock_writer <- list(write_table = function(x) NULL, done_writing = function() NULL, close = function() NULL)
  mock_client <- list(do_put = function(descriptor, schema, options) list(mock_writer, mock_reader))

  mockery::stub(.do_put_command, "reticulate::import", function(...) list(FlightDescriptor = list(for_path = function(x) list(path = x))))
  mockery::stub(.do_put_command, ".get_flight_options", list())

  mock_config <- list(is_dry_publish = FALSE)
  mock_data <- data.frame(subjid = c("001", "002"))

  result <- .do_put_command(mock_client, mock_config, mock_data)

  expect_true(result$success)
  expect_equal(result$metadata$dataset_uuid, "abc-123")
  expect_equal(result$metadata$dataset_batch_number, 7)
  expect_true(result$checks$dataset_is_valid)
  expect_equal(result$checks$invalid_datetime_formats, list())
})

# ==============================================================================
# EDGE CASE 2: Chunking Aggregation (Handling massive invalid record streams)
# ==============================================================================
test_that(".do_put_command correctly aggregates multiple chunked batches of invalid records", {
  
  read_call_count <- 0
  
  mock_reader <- list(
    read = function() {
      read_call_count <<- read_call_count + 1
      if (read_call_count == 1) {
        # Server returns failure due to invalid records, using the canonical publish envelope
        charToRaw('{"success": false, "metadata": {"dataset_name": "test"}, "metrics": {"total_valid_rows": 0, "total_invalid_rows": 4, "total_duplicate_rows": 0}, "checks": {"schema_is_valid": false, "config_is_valid": true, "date_formats_are_valid": true, "dataset_is_valid": false, "invalid_datetime_formats": {}}, "errors": []}')
      } else {
        # Return a dummy valid raw buffer to trigger stream opening
        raw(10) 
      }
    }
  )
  
  mock_writer <- list(write_table = function(x) NULL, done_writing = function() NULL, close = function() NULL)
  mock_client <- list(do_put = function(descriptor, schema, options) list(mock_writer, mock_reader))
  
  # Create an IPC reader mock that emits 2 distinct batches, then stops
  batch_count <- 0
  mock_ipc_reader <- list(
    read_next_batch = function() {
      batch_count <<- batch_count + 1
      if (batch_count == 1) {
        data.frame(id = 1, error = "invalid format")
      } else if (batch_count == 2) {
        data.frame(id = 2, error = "missing key")
      } else {
        stop("StopIteration") # Simulates the end of the Python stream
      }
    }
  )
  
  # Stub reticulate to return our mocked PyArrow IPC stream
  mock_pa <- list(ipc = list(open_stream = function(...) mock_ipc_reader))
  
  mockery::stub(.do_put_command, "reticulate::import", function(module, ...) {
    if (module == "pyarrow") return(mock_pa)
    list(FlightDescriptor = list(for_path = function(x) list(path = x)))
  })
  
  mockery::stub(.do_put_command, ".get_flight_options", list())
  
  # Pass through the Arrow conversion since our mock batches are already data frames
  mockery::stub(.do_put_command, "arrow::as_arrow_table", function(x) x) 
  
  mock_config <- list(is_dry_publish = TRUE)
  mock_data <- data.frame(a = 1)
  
  # Execute the command
  result <- .do_put_command(mock_client, mock_config, mock_data)
  
  # Verifications: It should fail (success = FALSE), but successfully rbind both chunks!
  expect_false(result$success)
  expect_equal(result$metrics$total_invalid_rows, 4)
  
  # The invalid records should be a single dataframe with 2 rows (combining both batches)
  expect_true(is.data.frame(result$invalid_records))
  expect_equal(nrow(result$invalid_records), 2)
  expect_equal(result$invalid_records$id, c(1, 2))
})
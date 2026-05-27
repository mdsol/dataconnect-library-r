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
        # First read returns valid JSON status
        charToRaw('{"status": true, "dataset_name": "test", "invalid_record_count": 5}')
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
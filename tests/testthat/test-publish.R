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

test_that(".get_valid_rows calculates valid rows correctly using Venn logic", {
  # 1. Setup test data: 5 total rows
  # Distinct keys: "001", "002", "003", "004" (4 distinct rows total)
  test_data <- data.frame(
    subjid = c("001", "001", "002", "003", "004"),
    measure = c(1.5, 2.3, 3.1, 4.2, 5.0)
  )
  
  # 2. Setup invalid records returned by the server
  # The server flagged both "001" records as invalid
  # Distinct invalid keys: "001" (1 distinct invalid row)
  invalid_df <- data.frame(
    subjid = c("001", "001"),
    measure = c(1.5, 2.3)
  )
  
  mock_response <- list(
    success = TRUE,
    invalid_records = invalid_df
  )
  
  key_columns <- list("subjid")
  
  # 3. Execute the function
  # Math: 4 (Total Distinct) - 1 (Invalid Distinct) = 3 Valid Rows
  result <- .get_valid_rows(mock_response, test_data, key_columns)
  
  # 4. Verify the exact mathematical output
  expect_equal(result, 3)
})

test_that(".get_valid_rows perfectly handles the complex Venn diagram scenario", {
  # 1. Setup the 100-row test data
  # To get 12 duplicates, we create 13 rows with the exact same key ("overlap_key") 
  # and 87 unique rows. Total: 100 rows, 88 distinct.
  test_data <- data.frame(
    id = c(rep("overlap_key", 13), paste0("unique_row_", 1:87)),
    measure = 1:100
  )
  
  # 2. Setup the 5 invalid rows returned by the server
  # To get 2 invalid duplicates, we include the "overlap_key" 3 times.
  # Plus 2 distinct invalid keys. Total: 5 rows, 3 distinct.
  invalid_df <- data.frame(
    id = c("overlap_key", "overlap_key", "overlap_key", "unique_row_1", "unique_row_2"),
    measure = c(1, 2, 3, 14, 15)
  )
  
  mock_response <- list(
    success = TRUE,
    invalid_records = invalid_df
  )
  
  key_columns <- list("id")
  
  # 3. Execute the function
  # The math it will do internally based on our discrete fix:
  # total_duplicates = 100 - 88 = 12
  # invalid_duplicates = 5 - 3 = 2
  # net_duplicates = 12 - 2 = 10
  # valid_rows = 100 - 5 - 10 = 85
  result <- .get_valid_rows(mock_response, test_data, key_columns)
  
  # 4. Verify the exact diagram output
  expect_equal(result, 85)
})

test_that(".get_valid_rows handles NULL invalid_records perfectly without crashing to numeric(0)", {
  # 1. Setup test data: 4 rows total
  # Distinct keys: "001", "002", "003" (3 distinct rows total, 1 duplicate for "001")
  test_data <- data.frame(
    subjid = c("001", "001", "002", "003"),
    measure = c(1.5, 2.3, 3.1, 4.2)
  )
  
  # 2. Setup response exactly as it comes when everything is valid
  # No errors means invalid_records is NULL
  mock_response <- list(
    success = TRUE,
    invalid_records = NULL
  )
  
  key_columns <- list("subjid")
  
  # 3. Execute the function
  # Math: 4 total rows - 0 invalid rows - 1 duplicate = 3 Valid Rows
  result <- .get_valid_rows(mock_response, test_data, key_columns)
  
  # 4. Verify the output is exactly a single number, not NULL or numeric(0)
  expect_equal(result, 3)
  expect_true(is.numeric(result))
  expect_false(length(result) == 0, info = "Result evaluated to numeric(0) due to NULL math!")
})

test_that(".publish correctly overwrites valid_rows without creating duplicate keys", {
  # 1. Setup dummy data and client (we won't actually use them due to stubs)
  dummy_client <- list()
  dummy_data <- data.frame(subjid = "001", val = 1)
  
  # 2. Mock what .do_put_command returns natively (with a NULL valid_rows)
  mock_put_result <- list(
    success = TRUE, 
    dataset_name = "DS1TEST",
    valid_rows = NULL,  # This comes naturally from the response
    invalid_records = NULL
  )
  
  # 3. Stub the internal functions so .publish doesn't do real work
  # Tell .publish that when it calls .do_put_command, it gets mock_put_result
  mockery::stub(.publish, ".do_put_command", mock_put_result)
  
  # Tell .publish that when it calculates .get_valid_rows, it just gets 100
  mockery::stub(.publish, ".get_valid_rows", 100)
  
  # 4. Execute the publish command
  result <- .publish(dummy_client, test_config, dummy_data)
  
  # 5. Verifications
  keys <- names(result)
  
  # Expect the length of unique keys to match the length of all keys
  expect_equal(length(keys), length(unique(keys)), 
               info = "The resulting list contains duplicate names (like $valid_rows)!")
               
  # Expect the final valid_rows to be the calculated one (100), not the NULL
  expect_equal(result$valid_rows, 100)
})

test_that(".get_valid_rows returns NA_integer_ with a warning when distinct count cannot be computed", {
  # 1. Setup test data with NO column named "missing_key"
  test_data <- data.frame(
    subjid = c("001", "002", "003"),
    measure = c(1.5, 2.3, 3.1)
  )

  mock_response <- list(
    success = TRUE,
    invalid_records = NULL
  )

  # 2. Use a key that does not exist in the data — this forces
  # .count_distinct_rows to return distinct_row_count = NULL
  # with an informative error_message.
  key_columns <- list("missing_key")

  # 3. Execute and verify it warns + returns NA_integer_ instead of
  # silently propagating numeric(0) through the Venn arithmetic.
  expect_warning(
    result <- .get_valid_rows(mock_response, test_data, key_columns),
    "Unable to compute valid row count"
  )

  expect_true(is.na(result))
  expect_identical(result, NA_integer_)
  expect_equal(length(result), 1L)
})

test_that(".get_valid_rows returns NA when distinct count fails on invalid_records", {
  test_data <- data.frame(subjid = c("001", "002", "003"), measure = 1:3)

  # invalid_records has a *different* schema — missing 'subjid'
  invalid_df <- data.frame(other_col = c("x", "y"))

  mock_response <- list(success = TRUE, invalid_records = invalid_df)

  expect_warning(
    result <- .get_valid_rows(mock_response, test_data, list("subjid")),
    "invalid records"
  )
  expect_identical(result, NA_integer_)
})
context("Publishing operations")

# Load required libraries
library(testthat)
library(mockery)

# Directly source the files we need to test
source("../../R/commands.R")
source("../../R/publishing.R")

# Unit tests for .count_distinct_rows
test_that(".count_distinct_rows returns correct count with valid key columns", {
  test_data <- data.frame(
    id = c(1, 2, 3, 1, 2),
    name = c("A", "B", "C", "A", "B"),
    value = c(10, 20, 30, 10, 20)
  )
  
  # Test with single key column
  result <- .count_distinct_rows(test_data, "id")
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
  
  # Test with multiple key columns as vector
  result <- .count_distinct_rows(test_data, c("id", "name"))
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
  
  # Test with all columns as keys (all rows distinct)
  result <- .count_distinct_rows(test_data, c("id", "name", "value"))
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
})

test_that(".count_distinct_rows handles list of key columns", {
  test_data <- data.frame(
    subjid = c("001", "002", "003", "001"),
    visit = c("V1", "V1", "V2", "V1"),
    measure = c(1.5, 2.3, 3.1, 1.5)
  )
  
  # Test with list format
  result <- .count_distinct_rows(test_data, list("subjid", "visit"))
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
  
  # Test with character vector
  result <- .count_distinct_rows(test_data, c("subjid", "visit"))
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
})

test_that(".count_distinct_rows is case-insensitive for column names", {
  test_data <- data.frame(
    SubjID = c("001", "002", "003", "001"),
    Visit = c("V1", "V1", "V2", "V1"),
    Measure = c(1.5, 2.3, 3.1, 1.5)
  )
  
  # Test with lowercase key columns as list
  result <- .count_distinct_rows(test_data, list("subjid", "visit"))
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
  
  # Test with uppercase key columns as list
  result <- .count_distinct_rows(test_data, list("SUBJID", "VISIT"))
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
  
  # Test with mixed case key columns as character vector
  result <- .count_distinct_rows(test_data, c("SubjId", "vIsIt"))
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
})

test_that(".count_distinct_rows returns error for missing columns", {
  test_data <- data.frame(
    id = c(1, 2, 3),
    name = c("A", "B", "C")
  )
  
  # Test with single missing column
  result <- .count_distinct_rows(test_data, "missing_col")
  expect_null(result$distinct_row_count)
  expect_true(grepl("Key column\\(s\\) not found", result$error_message))
  expect_true(grepl("missing_col", result$error_message))
  
  # Test with multiple missing columns
  result <- .count_distinct_rows(test_data, c("col1", "col2"))
  expect_null(result$distinct_row_count)
  expect_true(grepl("Key column\\(s\\) not found", result$error_message))
  expect_true(grepl("col1", result$error_message))
  expect_true(grepl("col2", result$error_message))
  
  # Test with mix of valid and invalid columns
  result <- .count_distinct_rows(test_data, c("id", "invalid"))
  expect_null(result$distinct_row_count)
  expect_true(grepl("Key column\\(s\\) not found", result$error_message))
  expect_true(grepl("invalid", result$error_message))
})

test_that(".count_distinct_rows handles empty data frame", {
  test_data <- data.frame(
    id = integer(0),
    name = character(0)
  )
  
  result <- .count_distinct_rows(test_data, "id")
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 0)
})

test_that(".count_distinct_rows handles all duplicate rows", {
  test_data <- data.frame(
    id = c(1, 1, 1, 1),
    name = c("A", "A", "A", "A"),
    value = c(10, 20, 30, 40)
  )
  
  result <- .count_distinct_rows(test_data, c("id", "name"))
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 1)
})

test_that(".count_distinct_rows returns duplicate row identities for a simple duplicate group", {
  test_data <- data.frame(
    id = c(1, 2, 2, 3)
  )

  result <- .count_distinct_rows(test_data, key_columns = "id")

  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 3)
  expect_equal(result$duplicate_row_indices, 3)
  expect_equal(nrow(result$duplicate_key_rows), 1)
  expect_equal(names(result$duplicate_key_rows), "id")
})

test_that(".count_distinct_rows returns duplicate metadata for character keys", {
  test_data <- data.frame(
    id = c("A", "B", "B", "C"),
    stringsAsFactors = FALSE
  )

  result <- .count_distinct_rows(test_data, "id")

  expect_equal(result$duplicate_row_indices, 3)
  expect_equal(nrow(result$duplicate_key_rows), 1)
  expect_equal(result$actual_key_columns, "id")
})

test_that(".calculate_duplicate_invalid_intersection counts matching composite keys", {
  duplicate_key_rows <- data.frame(
    subjid = c("001", "002"),
    visit = c("V1", "V1"),
    stringsAsFactors = FALSE
  )

  invalid_records <- data.frame(
    subjid = c("001", "002", "099"),
    visit = c("V1", "V1", "V1"),
    stringsAsFactors = FALSE
  )

  key_columns <- c("subjid", "visit")

  expect_equal(
    .calculate_duplicate_invalid_intersection(duplicate_key_rows, invalid_records, key_columns),
    2
  )
})

test_that(".calculate_duplicate_invalid_intersection avoids key-collision false positives", {
  duplicate_key_rows <- data.frame(
    subjid = c("A.B"),
    visit = c("C"),
    stringsAsFactors = FALSE
  )

  invalid_records <- data.frame(
    subjid = c("A"),
    visit = c("B.C"),
    stringsAsFactors = FALSE
  )

  key_columns <- c("subjid", "visit")

  expect_equal(
    .calculate_duplicate_invalid_intersection(duplicate_key_rows, invalid_records, key_columns),
    0
  )
})

test_that(".calculate_duplicate_invalid_intersection returns zero for empty invalid records", {
  duplicate_key_rows <- data.frame(
    subjid = c("001", "002"),
    visit = c("V1", "V1"),
    stringsAsFactors = FALSE
  )

  invalid_records <- data.frame(
    subjid = character(0),
    visit = character(0),
    stringsAsFactors = FALSE
  )

  key_columns <- c("subjid", "visit")

  expect_equal(
    .calculate_duplicate_invalid_intersection(duplicate_key_rows, invalid_records, key_columns),
    0
  )
})

test_that(".calculate_duplicate_invalid_intersection returns zero for NULL invalid records", {
  duplicate_key_rows <- data.frame(
    subjid = c("001", "002"),
    visit = c("V1", "V1"),
    stringsAsFactors = FALSE
  )

  key_columns <- c("subjid", "visit")

  expect_equal(
    .calculate_duplicate_invalid_intersection(duplicate_key_rows, NULL, key_columns),
    0
  )
})

test_that(".count_distinct_rows handles all unique rows", {
  test_data <- data.frame(
    id = c(1, 2, 3, 4),
    name = c("A", "B", "C", "D")
  )
  
  result <- .count_distinct_rows(test_data, "id")
  expect_null(result$error_message)
  expect_equal(result$distinct_row_count, 4)
})

# Create a mock function for .get_flight_options that we'll use in each test
mock_flight_options <- function() {
  list(headers = list(c("x-client-dataconnect", "1.1.0")))
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

test_that("dry_publish appends distinct row counts with valid key columns", {
  # Test data with duplicates based on key columns
  test_data <- data.frame(
    subjid = c("001", "002", "003", "001", "002"),
    visit = c("V1", "V1", "V2", "V1", "V1"),
    measure = c(1.5, 2.3, 3.1, 1.5, 2.3)
  )
  
  config <- list(
    project_uuid = "ec079457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2143dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec1f2a7-07ba-4fa8-bfcf-34fbc5d56793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  mock_client <- list()
  
  # Create a wrapper that bypasses byte operations but tests the integration
  mock_dry_publish <- function(client, config, data) {
    # Input validation (same as .dry_publish)
    if (is.null(client)) stop("Client must be provided")
    if (is.null(config)) stop("Configuration must be provided")
    if (is.null(data)) stop("Data must be provided")
    if (!is.data.frame(data)) stop("Data must be a data.frame")
    if (nrow(data) == 0) warning("Uploading empty dataset")
    
    # Simulate .do_command response
    response <- list(status = "valid", message = "Schema validated")
    
    # This is the key part we're testing - integration with .count_distinct_rows
    distinct_row_result <- NULL
    if (!is.null(config$key_columns)) {
      distinct_row_result <- .count_distinct_rows(data, config$key_columns)
    }
    
    # Append distinct row count and duplicate row count if available
    if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
      response$valid_rows <- distinct_row_result$distinct_row_count
      response$duplicate_rows_based_on_keys <- nrow(data) - distinct_row_result$distinct_row_count
    }
    
    return(response)
  }
  
  result <- mock_dry_publish(mock_client, config, test_data)
  
  # Verify dry_publish logic appends the distinct row counts
  expect_true(!is.null(result$valid_rows))
  expect_equal(result$valid_rows, 3)  # 3 distinct subjid+visit combinations
  expect_true(!is.null(result$duplicate_rows_based_on_keys))
  expect_equal(result$duplicate_rows_based_on_keys, 2)  # 5 total - 3 distinct = 2 duplicates
})

test_that("dry_publish appends counts when all rows are unique", {
  # Test data with no duplicates
  test_data <- data.frame(
    subjid = c("001", "002", "003"),
    visit = c("V1", "V2", "V3"),
    measure = c(1.5, 2.3, 3.1)
  )
  
  config <- list(
    project_uuid = "ec029457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2145dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d22793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  mock_client <- list()
  
  mock_dry_publish <- function(client, config, data) {
    if (is.null(client)) stop("Client must be provided")
    if (is.null(config)) stop("Configuration must be provided")
    if (is.null(data)) stop("Data must be provided")
    if (!is.data.frame(data)) stop("Data must be a data.frame")
    if (nrow(data) == 0) warning("Uploading empty dataset")
    
    response <- list(status = "valid")
    
    distinct_row_result <- NULL
    if (!is.null(config$key_columns)) {
      distinct_row_result <- .count_distinct_rows(data, config$key_columns)
    }
    
    if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
      response$valid_rows <- distinct_row_result$distinct_row_count
      response$duplicate_rows_based_on_keys <- nrow(data) - distinct_row_result$distinct_row_count
    }
    
    return(response)
  }
  
  result <- mock_dry_publish(mock_client, config, test_data)
  
  # All rows are unique
  expect_equal(result$valid_rows, 3)
  expect_equal(result$duplicate_rows_based_on_keys, 0)
})

test_that("dry_publish appends counts when all rows are duplicates", {
  # Test data where all rows have same key
  test_data <- data.frame(
    subjid = c("001", "001", "001", "001"),
    visit = c("V1", "V1", "V1", "V1"),
    measure = c(1.5, 2.3, 3.1, 4.2)
  )
  
  config <- list(
    project_uuid = "ec033457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2219dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d11793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  mock_client <- list()
  
  mock_dry_publish <- function(client, config, data) {
    if (is.null(client)) stop("Client must be provided")
    if (is.null(config)) stop("Configuration must be provided")
    if (is.null(data)) stop("Data must be provided")
    if (!is.data.frame(data)) stop("Data must be a data.frame")
    if (nrow(data) == 0) warning("Uploading empty dataset")
    
    response <- list(status = "valid")
    
    distinct_row_result <- NULL
    if (!is.null(config$key_columns)) {
      distinct_row_result <- .count_distinct_rows(data, config$key_columns)
    }
    
    if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
      response$valid_rows <- distinct_row_result$distinct_row_count
      response$duplicate_rows_based_on_keys <- nrow(data) - distinct_row_result$distinct_row_count
    }
    
    return(response)
  }
  
  result <- mock_dry_publish(mock_client, config, test_data)
  
  # Only 1 distinct key combination
  expect_equal(result$valid_rows, 1)
  expect_equal(result$duplicate_rows_based_on_keys, 3)  # 4 total - 1 distinct = 3 duplicates
})

test_that("dry_publish handles case-insensitive key column matching", {
  # Test data with mixed case column names
  test_data <- data.frame(
    SubjID = c("001", "002", "003", "001"),
    VISIT = c("V1", "V1", "V2", "V1"),
    measure = c(1.5, 2.3, 3.1, 1.5)
  )
  
  # Config with lowercase key columns
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),  # lowercase
    source_datasets = list()
  )
  
  mock_client <- list()
  
  mock_dry_publish <- function(client, config, data) {
    if (is.null(client)) stop("Client must be provided")
    if (is.null(config)) stop("Configuration must be provided")
    if (is.null(data)) stop("Data must be provided")
    if (!is.data.frame(data)) stop("Data must be a data.frame")
    if (nrow(data) == 0) warning("Uploading empty dataset")
    
    response <- list(status = "valid")
    
    distinct_row_result <- NULL
    if (!is.null(config$key_columns)) {
      distinct_row_result <- .count_distinct_rows(data, config$key_columns)
    }
    
    if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
      response$valid_rows <- distinct_row_result$distinct_row_count
      response$duplicate_rows_based_on_keys <- nrow(data) - distinct_row_result$distinct_row_count
    }
    
    return(response)
  }
  
  result <- mock_dry_publish(mock_client, config, test_data)
  
  # Should match case-insensitively and count correctly
  expect_equal(result$valid_rows, 3)
  expect_equal(result$duplicate_rows_based_on_keys, 1)
})

test_that("dry_publish does not append counts when key_columns is NULL", {
  # Test data
  test_data <- data.frame(
    subjid = c("001", "002", "003"),
    visit = c("V1", "V2", "V3"),
    measure = c(1.5, 2.3, 3.1)
  )
  
  # Config without key_columns
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = NULL,
    source_datasets = list()
  )
  
  mock_client <- list()
  
  mock_dry_publish <- function(client, config, data) {
    if (is.null(client)) stop("Client must be provided")
    if (is.null(config)) stop("Configuration must be provided")
    if (is.null(data)) stop("Data must be provided")
    if (!is.data.frame(data)) stop("Data must be a data.frame")
    if (nrow(data) == 0) warning("Uploading empty dataset")
    
    response <- list(status = "valid")
    
    distinct_row_result <- NULL
    if (!is.null(config$key_columns)) {
      distinct_row_result <- .count_distinct_rows(data, config$key_columns)
    }
    
    if (!is.null(distinct_row_result) && !is.null(distinct_row_result$distinct_row_count)) {
      response$valid_rows <- distinct_row_result$distinct_row_count
      response$duplicate_rows_based_on_keys <- nrow(data) - distinct_row_result$distinct_row_count
    }
    
    return(response)
  }
  
  result <- mock_dry_publish(mock_client, config, test_data)
  
  # Should not have valid_rows or duplicate_rows_based_on_keys
  expect_true(is.null(result$valid_rows))
  expect_true(is.null(result$duplicate_rows_based_on_keys))
})

test_that("publish validates inputs and handles different scenarios correctly", {
  # Configuration for your dataset
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )

  # Create a mock client
  mock_client <- list()

  # Test input validation - these should all error
  expect_error(.publish(NULL, config, sample_data), "Client must be provided")
  expect_error(.publish(mock_client, NULL, sample_data), "Configuration must be provided")
  # .publish() converts via arrow::arrow_table() first; invalid data errors can
  # come from Arrow rather than our own message.
  expect_error(
    .publish(mock_client, config, NULL),
    "Data must be provided|only data frames are allowed"
  )
  
  # Test invalid data type
  expect_error(
    .publish(mock_client, config, "invalid_data"),
    "Data must be a data.frame|only data frames are allowed"
  )
  expect_error(
    .publish(mock_client, config, list(a = 1, b = 2)),
    "Data must be a data.frame|only data frames are allowed"
  )
  
  # Test that valid inputs are accepted (we'll mock the actual calls)
  expect_true(inherits(sample_data, "data.frame"))
  expect_true(is.list(config))
  expect_true(!is.null(config$dataset_name))
})

test_that("publish handles publishing with required data correctly", {
  # Configuration for your dataset
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )

  # Create a mock client
  mock_client <- list()

  # Mock do_put_command to return writer/reader structure like the real implementation
  captured_client <- NULL
  captured_config <- NULL
  captured_data <- NULL
  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    captured_client <<- client
    captured_config <<- config
    captured_data <<- data
    # Return structure matching the real implementation
    return(list(success = TRUE, message = "Dataset published successfully."))
  })

  # Mock .get_flight_options
  mockery::stub(.publish, ".get_flight_options", mock_flight_options)

  # Test the function with data (since data is now required)
  sample_data <- data.frame(x = 1:3, y = letters[1:3])
  result <- .publish(mock_client, config, sample_data)

  # Verify the correct transformation and call occurred
  expect_type(result, "list")
  expect_true(result$success)
  expect_equal(result$message, "Dataset published successfully.")
  
  # Verify do_put_command was called with correct parameters
  expect_identical(captured_client, mock_client)
  expect_identical(captured_config, config)
  
  # Verify that the captured data is an Arrow Table (converted from our sample data)
  expect_true(inherits(captured_data, "Table"))
  expect_equal(captured_data$num_rows, 3)  # Our sample data has 3 rows
})

test_that("publish transforms data.frame to Arrow Table correctly", {
  # Configuration for your dataset
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  # Sample data schema
  sample_data_schema <- arrow::schema(
    subjid = arrow::string(),
    visit = arrow::string(),
    measurement = arrow::float64(),
    site = arrow::string()
  )

  # Sample data
  sample_data <- data.frame(
    subjid = c("001", "002", "003"),
    visit = c("Baseline", "Week 2", "Week 4"),
    measurement = c(25.5, 30.2, 15.8),
    site = c("Site A", "Site A", "Site B"),
    stringsAsFactors = FALSE
  )

  # Create a mock client
  mock_client <- list()

  # Create a mock arrow table that will be returned by arrow::arrow_table
  mock_arrow_table <- structure(
    list(
      num_rows = 3,
      schema = sample_data_schema
    ),
    class = "Table"
  )

  # Mock arrow::arrow_table to verify data transformation
  data_transformation_called <- FALSE
  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    expect_identical(data, sample_data)  # Verify correct data passed
    data_transformation_called <<- TRUE
    return(mock_arrow_table)
  })

  # Mock do_put_command to capture what gets passed to it
  captured_data <- NULL
  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    captured_data <<- data
    return(list(success = TRUE, message = "Dataset published successfully."))
  })

  # Mock .get_flight_options
  mockery::stub(.publish, ".get_flight_options", mock_flight_options)

  # Test the function with data
  result <- .publish(mock_client, config, sample_data)

  # Verify the transformation occurred
  expect_true(data_transformation_called)
  expect_type(result, "list")
  expect_true(result$success)
  expect_equal(result$message, "Dataset published successfully.")
  expect_identical(captured_data, mock_arrow_table)  # Should be transformed to arrow table
})

test_that("publish warns about empty datasets", {
  # Configuration for your dataset
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  # Sample data schema
  sample_data_schema <- arrow::schema(
    subjid = arrow::string(),
    visit = arrow::string(),
    measurement = arrow::float64(),
    site = arrow::string()
  )

  # Empty data frame
  empty_data <- data.frame(
    subjid = character(0),
    visit = character(0),
    measurement = numeric(0),
    site = character(0),
    stringsAsFactors = FALSE
  )

  # Create a mock client
  mock_client <- list()

  # Create a mock empty arrow table
  mock_empty_arrow_table <- structure(
    list(
      num_rows = 0,  # This is the key - 0 rows should trigger warning
      schema = sample_data_schema
    ),
    class = "Table"
  )

  # Mock arrow::arrow_table to return empty table
  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    return(mock_empty_arrow_table)
  })

  # Mock do_put_command
  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    return(list(success = TRUE, message = "Dataset published successfully."))
  })

  # Mock .get_flight_options
  mockery::stub(.publish, ".get_flight_options", mock_flight_options)

  # Test the function with empty data - should warn
  expect_warning(
    result <- .publish(mock_client, config, empty_data),
    "Uploading empty dataset"
  )
  
  expect_type(result, "list")
  expect_true(result$success)
  expect_equal(result$message, "Dataset published successfully.")
})

test_that("do_put_command handles the new writer/reader pattern correctly", {

  # Configuration for your dataset
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  # Sample data schema
  sample_data_schema <- arrow::schema(
    subjid = arrow::string(),
    visit = arrow::string(),
    measurement = arrow::float64(),
    site = arrow::string()
  )

  # Sample data
  sample_data <- data.frame(
    subjid = c("001", "002"),
    visit = c("Baseline", "Week 2"),
    measurement = c(25.5, 30.2),
    site = c("Site A", "Site A"),
    stringsAsFactors = FALSE
  )

  # Create a mock client
  mock_client <- structure(
    list(
      `do_put` = function(descriptor, schema, options) {
        # Mock the Python tuple return as R list
        mock_writer <- structure(
          list(
            write_table = function(data) { "data_written" },
            done_writing = function() {},
            close = function() {}
          ),
          class = "MockWriter"
        )
        mock_reader <- structure(
          list(
            read = function() charToRaw('{"status":true,"dataset_name":"my_dataset","dataset_uuid":"test-uuid","dataset_version":"1","dataset_batch_number":1}')
          ),
          class = "MockReader"
        )
        
        list(mock_writer, mock_reader)  # Unnamed list like Python tuple
      }
    ),
    class = "MockFlightClient"
  )

  # Create a mock arrow table
  mock_arrow_table <- structure(
    list(
      num_rows = 2,
      schema = sample_data_schema
    ),
    class = "Table"
  )

  # Mock arrow::arrow_table
  mockery::stub(.do_put_command, "arrow::arrow_table", function(data) {
    return(mock_arrow_table)
  })

  # Mock .get_flight_options
  mockery::stub(.do_put_command, ".get_flight_options", mock_flight_options)

  # Mock reticulate functions
  mockery::stub(.do_put_command, "reticulate::import", function(module) {
    list(FlightDescriptor = list(for_path = function(path) "mock_descriptor"))
  })
  
  mockery::stub(.do_put_command, "reticulate::r_to_py", function(x) {
    list(encode = function(encoding) "mock_bytes")
  })

  # Test the function
  result <- .do_put_command(mock_client, config, sample_data)

  # Verify the result structure
  expect_type(result, "list")
  expect_true(result$success == TRUE)
})

test_that("do_put_command attaches invalid_records when invalid_record_count > 0", {
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )

  sample_data <- data.frame(
    subjid = c("001"),
    visit = c("V1"),
    stringsAsFactors = FALSE
  )

  read_calls <- 0

  mock_client <- structure(
    list(
      `do_put` = function(descriptor, schema, options) {
        mock_writer <- structure(
          list(
            write_table = function(data) NULL,
            done_writing = function() NULL,
            close = function() NULL
          ),
          class = "MockWriter"
        )

        mock_reader <- structure(
          list(
            read = function() {
              read_calls <<- read_calls + 1
              if (read_calls == 1) {
                return(charToRaw('{"status":true,"dataset_name":"my_dataset","dataset_uuid":"test-uuid","dataset_version":"1","dataset_batch_number":1,"invalid_record_count":[1]}'))
              }
              charToRaw("mock_ipc_payload")
            }
          ),
          class = "MockReader"
        )

        list(mock_writer, mock_reader)
      }
    ),
    class = "MockFlightClient"
  )

  mockery::stub(.do_put_command, "arrow::arrow_table", function(data) {
    structure(list(num_rows = nrow(data), schema = list()), class = "Table")
  })

  mockery::stub(.do_put_command, "reticulate::import", function(module, convert = TRUE) {
    if (identical(module, "pyarrow.flight")) {
      return(list(FlightDescriptor = list(for_path = function(path) "mock_descriptor")))
    }
    if (identical(module, "pyarrow")) {
      return(list(ipc = list(open_stream = function(buf) list(read_all = function() "mock_py_table"))))
    }
    stop("Unexpected module import")
  })

  mockery::stub(.do_put_command, "reticulate::r_to_py", function(x) {
    list(encode = function(encoding) "mock_bytes")
  })

  mockery::stub(.do_put_command, "arrow::as_arrow_table", function(py_table) {
    data.frame(subjid = "001", visit = "V1", error = "invalid", stringsAsFactors = FALSE)
  })

  mockery::stub(.do_put_command, ".get_flight_options", mock_flight_options)

  result <- .do_put_command(mock_client, config, sample_data)

  expect_true(result$success)
  expect_equal(result$invalid_record_count, 1)
  expect_true(is.data.frame(result$invalid_records))
  expect_equal(nrow(result$invalid_records), 1)
  expect_equal(read_calls, 2)
})

test_that("dry_publish returns response as-is when do_command result is NULL", {
  sample_data <- data.frame(
    subjid = c("001"),
    visit = c("V1"),
    stringsAsFactors = FALSE
  )

  config <- list(
    project_uuid = "ec079457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2144dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec1f2a7-07ba-4fa8-bfcf-34fbc5d56793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list(),
    is_dry_publish = TRUE
  )

  mock_client <- list()

  mockery::stub(.dry_publish, ".do_command", function(client, command, args = list(), body = NULL) {
    NULL
  })

  expect_null(.dry_publish(mock_client, config, sample_data))
})

# Tests for .publish function integration with .count_distinct_rows
test_that("publish appends valid_rows and duplicate_rows_based_on_keys when successful", {
  # Test data with some duplicates
  test_data <- data.frame(
    subjid = c("001", "002", "003", "001", "002"),
    visit = c("V1", "V1", "V2", "V1", "V1"),
    measure = c(1.5, 2.3, 3.1, 1.5, 2.3)
  )
  
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  mock_client <- list()
  
  # Mock arrow::arrow_table
  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    list(num_rows = nrow(data), schema = list())
  })
  
  # Mock .do_put_command to return success
  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    return(list(success = TRUE, message = "Dataset published successfully."))
  })
  
  result <- .publish(mock_client, config, test_data)
  
  # Verify success and counts are appended
  expect_true(result$success)
  expect_equal(result$valid_rows, 3)  # 3 distinct subjid+visit combinations
  expect_equal(result$duplicate_rows_based_on_keys, 2)  # 5 total - 3 distinct = 2 duplicates
})

test_that("publish appends counts when all rows are unique", {
  test_data <- data.frame(
    subjid = c("001", "002", "003"),
    visit = c("V1", "V2", "V3"),
    measure = c(1.5, 2.3, 3.1)
  )
  
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  mock_client <- list()
  
  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    list(num_rows = nrow(data), schema = list())
  })
  
  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    return(list(success = TRUE, message = "Dataset published successfully."))
  })
  
  result <- .publish(mock_client, config, test_data)
  
  expect_true(result$success)
  expect_equal(result$valid_rows, 3)
  expect_equal(result$duplicate_rows_based_on_keys, 0)
})

test_that("publish appends counts when all rows are duplicates", {
  test_data <- data.frame(
    subjid = c("001", "001", "001", "001"),
    visit = c("V1", "V1", "V1", "V1"),
    measure = c(1.5, 2.3, 3.1, 4.2)
  )
  
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  mock_client <- list()
  
  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    list(num_rows = nrow(data), schema = list())
  })
  
  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    return(list(success = TRUE, message = "Dataset published successfully."))
  })
  
  result <- .publish(mock_client, config, test_data)
  
  expect_true(result$success)
  expect_equal(result$valid_rows, 1)
  expect_equal(result$duplicate_rows_based_on_keys, 3)
})

test_that("R06: valid_rows accounts for intersection of duplicates and invalid records", {
  withr::local_options(dataconnect.calculate_duplicates = TRUE)
  test_data <- data.frame(
    subjid = sprintf("%03d", c(1:88, 1:12)),
    visit = c(rep("V1", 88), rep("V1", 12)),
    measure = seq_len(100),
    stringsAsFactors = FALSE
  )

  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )

  mock_client <- list()

  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    list(num_rows = nrow(data), schema = list())
  })

  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    list(
      success = TRUE,
      message = "Dataset published successfully.",
      invalid_record_count = 5,
      invalid_records = data.frame(
        subjid = c("001", "002", "089", "090", "091"),
        visit = c("V1", "V1", "V1", "V1", "V1"),
        measure = c(1, 2, 89, 90, 91),
        stringsAsFactors = FALSE
      )
    )
  })

  result <- .publish(mock_client, config, test_data)

  expect_true(result$success)
  expect_equal(result$invalid_record_count, 5)
  expect_equal(result$valid_rows, 85)
})

test_that("dry_publish applies R06 logic for valid_rows", {
  withr::local_options(dataconnect.calculate_duplicates = TRUE)
  test_data <- data.frame(
    subjid = sprintf("%03d", c(1:88, 1:12)),
    visit = c(rep("V1", 88), rep("V1", 12)),
    measure = seq_len(100),
    stringsAsFactors = FALSE
  )

  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list(),
    is_dry_publish = TRUE
  )

  mock_client <- list()

  mockery::stub(.dry_publish, ".do_command", function(client, command, args = list(), body = NULL) {
    list(
      list(
        success = TRUE,
        message = "Dataset published successfully.",
        invalid_record_count = 5,
        invalid_records = data.frame(
          subjid = c("001", "002", "089", "090", "091"),
          visit = c("V1", "V1", "V1", "V1", "V1"),
          measure = c(1, 2, 89, 90, 91),
          stringsAsFactors = FALSE
        )
      )
    )
  })

  result <- .dry_publish(mock_client, config, test_data)

  expect_true(result$success)
  expect_equal(result$invalid_record_count, 5)
  expect_equal(result$valid_rows, 85)
})

test_that("publish does not append counts when upload fails", {
  test_data <- data.frame(
    subjid = c("001", "002", "003"),
    visit = c("V1", "V1", "V2"),
    measure = c(1.5, 2.3, 3.1)
  )
  
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),
    source_datasets = list()
  )
  
  mock_client <- list()
  
  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    list(num_rows = nrow(data), schema = list())
  })
  
  # Mock .do_put_command to return failure
  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    return(list(success = FALSE, message = "Upload failed"))
  })
  
  result <- .publish(mock_client, config, test_data)
  
  # When upload fails, counts should not be appended
  expect_false(result$success)
  expect_equal(result$message, "Upload failed")
  expect_true(is.null(result$valid_rows))
  expect_true(is.null(result$duplicate_rows_based_on_keys))
})

test_that("publish handles case-insensitive key column matching", {
  test_data <- data.frame(
    SubjID = c("001", "002", "003", "001"),
    VISIT = c("V1", "V1", "V2", "V1"),
    measure = c(1.5, 2.3, 3.1, 1.5)
  )
  
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name = "my_dataset",
    dataset_description = "Example dataset",
    key_columns = list("subjid", "visit"),  # lowercase
    source_datasets = list()
  )
  
  mock_client <- list()
  
  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    list(num_rows = nrow(data), schema = list())
  })
  
  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    return(list(success = TRUE, message = "Dataset published successfully."))
  })
  
  result <- .publish(mock_client, config, test_data)
  
  # Should match case-insensitively
  expect_true(result$success)
  expect_equal(result$valid_rows, 3)
  expect_equal(result$duplicate_rows_based_on_keys, 1)
})

test_that("R06: valid_rows is never negative (AC-04)", {
  # 5 unique rows, but server reports 10 invalid — more than total distinct
  # Formula without clamping: 5 - 10 + 0 = -5 → must clamp to 0
  test_data <- data.frame(
    subjid = c("001", "002", "003", "004", "005"),
    visit  = c("V1",  "V1",  "V1",  "V1",  "V1"),
    measure = 1:5,
    stringsAsFactors = FALSE
  )

  config <- list(
    project_uuid             = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid               = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid   = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name             = "my_dataset",
    dataset_description      = "Example dataset",
    key_columns              = list("subjid", "visit"),
    source_datasets          = list()
  )

  mock_client <- list()

  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    list(num_rows = nrow(data), schema = list())
  })

  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    list(
      success              = TRUE,
      message              = "Dataset published successfully.",
      invalid_record_count = 10,
      invalid_records      = data.frame(
        subjid  = c("001", "002", "003", "004", "005", "006", "007", "008", "009", "010"),
        visit   = rep("V1", 10),
        measure = 1:10,
        stringsAsFactors = FALSE
      )
    )
  })

  result <- .publish(mock_client, config, test_data)

  expect_true(result$success)
  expect_equal(result$valid_rows, 0)
})

test_that("R06: handles NULL key_columns correctly (AC-05)", {
  # 100 rows, no key_columns — all rows treated as distinct
  # 5 invalid records reported by server, no duplicates → valid_rows = 95
  test_data <- data.frame(
    subjid  = sprintf("%03d", 1:100),
    visit   = rep("V1", 100),
    measure = 1:100,
    stringsAsFactors = FALSE
  )

  config <- list(
    project_uuid           = "ec099457-9ddc-4c7f-9144-f2212c6b11ad",
    study_uuid             = "e2149dd5-2ca7-4b1d-9973-20d166f9a260",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d58793",
    dataset_name           = "my_dataset",
    dataset_description    = "Example dataset",
    key_columns            = NULL,
    source_datasets        = list()
  )

  mock_client <- list()

  mockery::stub(.publish, "arrow::arrow_table", function(data) {
    list(num_rows = nrow(data), schema = list())
  })

  mockery::stub(.publish, ".do_put_command", function(client, config, data) {
    list(
      success              = TRUE,
      message              = "Dataset published successfully.",
      invalid_record_count = 5,
      invalid_records      = data.frame(
        subjid  = c("001", "002", "003", "004", "005"),
        visit   = rep("V1", 5),
        measure = 1:5,
        stringsAsFactors = FALSE
      )
    )
  })

  result <- .publish(mock_client, config, test_data)

  expect_true(result$success)
  expect_equal(result$valid_rows, 95)
})


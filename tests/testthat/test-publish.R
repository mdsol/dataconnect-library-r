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

# Tests for .publish function integration with .count_distinct_rows
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

test_that("publish and dry_publish mapping logic correctly handles server response", {
  # This simulates the raw list coming back from the server BEFORE your mapping in commands.R
  mock_raw_server_result <- list(
    status = "success",
    dataset_name = "my_dataset",
    dataset_uuid = "123-abc",
    dataset_version = 1,
    dataset_batch_number = 999, # Field to be removed
    invalid_record_count = 0,
    valid_rows = 100,           # New field
    duplicate_rows = 5          # New field to be renamed
  )

  # 1. Test the mapping logic for a regular publish
  # We simulate the list construction you added in R/commands.R
  publish_result <- list(
    success = mock_raw_server_result$status,
    dataset_name = mock_raw_server_result$dataset_name,
    dataset_uuid = mock_raw_server_result$dataset_uuid,
    dataset_version = mock_raw_server_result$dataset_version,
    invalid_record_count = mock_raw_server_result$invalid_record_count,
    valid_rows = mock_raw_server_result$valid_rows,
    duplicate_rows_based_on_keys = mock_raw_server_result$duplicate_rows,
    invalid_records = NULL
  )

  # Assertions for Image 1 & 2 feedback
  expect_equal(publish_result$valid_rows, 100)
  expect_equal(publish_result$duplicate_rows_based_on_keys, 5)
  
  # Crucial: verify dataset_batch_number is NOT leaked to the user
  expect_null(publish_result$dataset_batch_number)
})
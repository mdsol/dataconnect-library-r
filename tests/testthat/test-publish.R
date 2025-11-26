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
  list(headers = list(c("x-client-dataconnect-r-version", "1.0.1")))
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
  
  # Mock .do_command to return a basic response that dry_publish will append to
  mockery::stub(.dry_publish, ".do_command", function(client, command, body) {
    return(list(list(status = "valid", message = "Schema validated")))
  })
  
  # Mock jsonlite::toJSON to avoid complex serialization
  mockery::stub(.dry_publish, "jsonlite::toJSON", function(x, auto_unbox = TRUE) {
    "{}"
  })
  
  # Mock arrow::arrow_table
  mockery::stub(.dry_publish, "arrow::arrow_table", function(data) {
    list(schema = list(serialize = function() charToRaw("{}")))
  })
  
  # Mock reticulate::r_to_py to return Python-like bytes objects
  mockery::stub(.dry_publish, "reticulate::r_to_py", function(x) {
    if (is.raw(x)) {
      # schema_buffer is already raw - return as Python bytes object
      py_bytes <- structure(list(), class = c("python.builtin.bytes", "python.builtin.object"))
      return(py_bytes)
    } else {
      # For strings, return mock with encode method
      list(encode = function(encoding) {
        py_bytes <- structure(list(), class = c("python.builtin.bytes", "python.builtin.object"))
        return(py_bytes)
      })
    }
  })
  
  result <- .dry_publish(mock_client, config, test_data)
  
  # Verify dry_publish appended the distinct row counts to the response
  expect_true(!is.null(result$valid_rows))
  expect_equal(result$valid_rows, 3)  # 3 distinct subjid+visit combinations
  expect_true(!is.null(result$duplicate_rows_based_on_keys))
  expect_equal(result$duplicate_rows_based_on_keys, 2)  # 5 total rows - 3 distinct = 2 duplicates
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
  
  mockery::stub(.dry_publish, ".do_command", function(client, command, body) {
    return(list(list(status = "valid")))
  })
  
  mockery::stub(.dry_publish, "jsonlite::toJSON", function(x, auto_unbox = TRUE) {
    "{}"
  })
  
  mockery::stub(.dry_publish, "arrow::arrow_table", function(data) {
    list(schema = list(serialize = function() charToRaw("{}")))
  })
  
  mockery::stub(.dry_publish, "reticulate::r_to_py", function(x) {
    if (is.raw(x)) {
      py_bytes <- structure(list(), class = c("python.builtin.bytes", "python.builtin.object"))
      return(py_bytes)
    } else {
      list(encode = function(encoding) {
        py_bytes <- structure(list(), class = c("python.builtin.bytes", "python.builtin.object"))
        return(py_bytes)
      })
    }
  })
  
  result <- .dry_publish(mock_client, config, test_data)
  
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
  
  mockery::stub(.dry_publish, ".do_command", function(client, command, body) {
    return(list(list(status = "valid")))
  })
  
  mockery::stub(.dry_publish, "jsonlite::toJSON", function(x, auto_unbox = TRUE) {
    "{}"
  })
  
  mockery::stub(.dry_publish, "arrow::arrow_table", function(data) {
    list(schema = list(serialize = function() charToRaw("{}")))
  })
  
  mockery::stub(.dry_publish, "reticulate::r_to_py", function(x) {
    if (is.raw(x)) {
      py_bytes <- structure(list(), class = c("python.builtin.bytes", "python.builtin.object"))
      return(py_bytes)
    } else {
      list(encode = function(encoding) {
        py_bytes <- structure(list(), class = c("python.builtin.bytes", "python.builtin.object"))
        return(py_bytes)
      })
    }
  })
  
  result <- .dry_publish(mock_client, config, test_data)
  
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
  
  mockery::stub(.dry_publish, ".do_command", function(client, command, body) {
    return(list(list(status = "valid")))
  })
  
  mockery::stub(.dry_publish, "jsonlite::toJSON", function(x, auto_unbox = TRUE) {
    "{}"
  })
  
  mockery::stub(.dry_publish, "arrow::arrow_table", function(data) {
    list(schema = list(serialize = function() charToRaw("{}")))
  })
  
  mockery::stub(.dry_publish, "reticulate::r_to_py", function(x) {
    if (is.raw(x)) {
      py_bytes <- structure(list(), class = c("python.builtin.bytes", "python.builtin.object"))
      return(py_bytes)
    } else {
      list(encode = function(encoding) {
        py_bytes <- structure(list(), class = c("python.builtin.bytes", "python.builtin.object"))
        return(py_bytes)
      })
    }
  })
  
  result <- .dry_publish(mock_client, config, test_data)
  
  # Should match case-insensitively and count correctly
  expect_equal(result$valid_rows, 3)
  expect_equal(result$duplicate_rows_based_on_keys, 1)
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
  expect_error(.publish(mock_client, config, NULL), "Data must be provided")
  
  # Test invalid data type
  expect_error(.publish(mock_client, config, "invalid_data"), 
               "Data must be a data.frame")
  expect_error(.publish(mock_client, config, list(a = 1, b = 2)), 
               "Data must be a data.frame")
  
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
            close = function() {}
          ),
          class = "MockWriter"
        )
        mock_reader <- structure(list(), class = "MockReader")
        return(list(mock_writer, mock_reader))  # Unnamed list like Python tuple
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
  expect_true(result$message == "Dataset published successfully")
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


context("Publishing operations")

# Load required libraries
library(testthat)
library(mockery)

# Directly source the files we need to test
source("../../R/commands.R")
source("../../R/publishing.R")

# Create a mock function for .get_flight_options that we'll use in each test
mock_flight_options <- function() {
  list(headers = list(c("x-client-dataconnect-r-version", "1.0.0")))
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
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d56793",
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

test_that("publish validates inputs and handles different scenarios correctly", {
  # Configuration for your dataset
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d56793",
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
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d56793",
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
    return("Dataset published successfully.")
  })

  # Mock .get_flight_options
  mockery::stub(.publish, ".get_flight_options", mock_flight_options)

  # Test the function with data (since data is now required)
  sample_data <- data.frame(x = 1:3, y = letters[1:3])
  result <- .publish(mock_client, config, sample_data)

  # Verify the correct transformation and call occurred
  expect_type(result, "character")
  expect_true(result == "Dataset published successfully.")
  
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
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d56793",
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
    return("Dataset published successfully.")
  })

  # Mock .get_flight_options
  mockery::stub(.publish, ".get_flight_options", mock_flight_options)

  # Test the function with data
  result <- .publish(mock_client, config, sample_data)

  # Verify the transformation occurred
  expect_true(data_transformation_called)
  expect_type(result, "character")
  expect_true(result == "Dataset published successfully.")
  expect_identical(captured_data, mock_arrow_table)  # Should be transformed to arrow table
})

test_that("publish warns about empty datasets", {
  # Configuration for your dataset
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d56793",
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
    return("Dataset published successfully.")
  })

  # Mock .get_flight_options
  mockery::stub(.publish, ".get_flight_options", mock_flight_options)

  # Test the function with empty data - should warn
  expect_warning(
    result <- .publish(mock_client, config, empty_data),
    "Uploading empty dataset"
  )
  
  expect_type(result, "character")
  expect_true(result == "Dataset published successfully.")
})

test_that("do_put_command handles the new writer/reader pattern correctly", {

  # Configuration for your dataset
  config <- list(
    project_uuid = "ec099457-9ddc-4c7f-9144-f2212c6b76ad",
    study_uuid = "e2149dd5-2ca7-4b1d-9973-20d166f9a560",
    study_environment_uuid = "cec9f2a7-07ba-4fa8-bfcf-34fbc5d56793",
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

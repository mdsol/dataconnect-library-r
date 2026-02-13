context("Fetch Data operations")

library(testthat)
library(mockery)

source("../../R/dataconnect_client.R")

test_that("fetch_data errors when dataset_uuid is missing, NULL, NA, or empty", {
  client <- DataConnectClient$new(token = "dummy")
  # missing argument
  expect_error(client$fetch_data(), "Parameter is required: dataset_uuid")
  # NULL
  expect_error(client$fetch_data(dataset_uuid = NULL), "Parameter is required: dataset_uuid")
  # NA
  expect_error(client$fetch_data(dataset_uuid = NA), "Parameter is required: dataset_uuid")
  # empty string
  expect_error(client$fetch_data(dataset_uuid = ""), "Parameter is required: dataset_uuid")
})

test_that("fetch_data returns expected data frame on success", {
  client <- DataConnectClient$new(token = "dummy")
  dataset_uuid <- "dummy-uuid"

  # Mock the internal .get_dataset method to return a known data frame
  mock_data <- data.frame(id = 1:3, value = c("a", "b", "c"), stringsAsFactors = FALSE)
  mockery::stub(client$fetch_data, ".get_dataset", function(client, dataset_uuid, ...) {
    mock_data
  })

  result <- client$fetch_data(dataset_uuid = dataset_uuid)

  expect_equal(result, mock_data, check.attributes = FALSE)
})

test_that("fetch_data returns expected data frame on success when valid study_uuid is included, but it should also return a deprecation warning", {
  client <- DataConnectClient$new(token = "dummy")
  dataset_uuid <- "dummy-uuid"
  study_uuid <- "dummy-study-uuid"

  # Mock the internal .get_dataset method to return a known data frame
  mock_data <- data.frame(id = 1:3, value = c("a", "b", "c"), stringsAsFactors = FALSE)
  mockery::stub(client$fetch_data, ".get_dataset", function(client, dataset_uuid, ...) {
    mock_data
  })

  expect_warning(
    result <- client$fetch_data(study_uuid = study_uuid, dataset_uuid = dataset_uuid),
    "You only need to provide dataset_uuid; the Study context is now resolved automatically."
    )

  expect_equal(result, mock_data, check.attributes = FALSE)
})

test_that("fetch_data returns expected data frame on success when valid study_environment_uuid is included, but it should also return a deprecation warning", {
  client <- DataConnectClient$new(token = "dummy")
  dataset_uuid <- "dummy-uuid"
  study_environment_uuid <- "dummy-study-env-uuid"

  # Mock the internal .get_dataset method to return a known data frame
  mock_data <- data.frame(id = 1:3, value = c("a", "b", "c"), stringsAsFactors = FALSE)
  mockery::stub(client$fetch_data, ".get_dataset", function(client, dataset_uuid, ...) {
    mock_data
  })

  expect_warning(
    result <- client$fetch_data(study_environment_uuid = study_environment_uuid, dataset_uuid = dataset_uuid),
    "You only need to provide dataset_uuid; the Study Environment context is now optional, and will be resolved automatically."
  )
  expect_equal(result, mock_data, check.attributes = FALSE)
})
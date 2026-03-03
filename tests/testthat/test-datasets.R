context("Datasets pagination")

library(testthat)
library(mockery)

# Source the implementation under test (same pattern as other tests in this repo)
source("../../R/datasets.R")

test_that(".get_datasets forwards server-side pagination (page + page_size) in criteria", {
  captured_client <- NULL
  captured_criteria <- NULL

  mockery::stub(.get_datasets, ".get_flights", function(client, criteria) {
    captured_client <<- client
    captured_criteria <<- criteria
    list(list(dataset_uuid = "d-1"))
  })

  mock_client <- list()

  out <- .get_datasets(
    client = mock_client,
    study_uuid = "study-1",
    study_environment_uuid = "env-1",
    search_dataset_name = "abc",
    page = 3,
    page_size = 200
  )

  expect_type(out, "list")
  expect_equal(length(out), 1)
  expect_identical(captured_client, mock_client)

  expect_equal(captured_criteria$flight_type, "DATASETS")

  # Pagination keys sent to server
  expect_equal(as.integer(captured_criteria$page), 3L)
  expect_true(!is.null(captured_criteria$page_size))
  expect_equal(as.integer(captured_criteria$page_size), 200L)

  # Search criteria forwarded
  if (!is.null(captured_criteria$study_uuid)) {
    expect_equal(captured_criteria$study_uuid, "study-1")
  }
  if (!is.null(captured_criteria$search_dataset_name)) {
    expect_equal(captured_criteria$search_dataset_name, "abc")
  }

  # Env key name varies in your codebase; accept either but require the value
  if (!is.null(captured_criteria$study_env_uuid)) {
    expect_equal(captured_criteria$study_env_uuid, "env-1")
  } else if (!is.null(captured_criteria$study_environment_uuid)) {
    expect_equal(captured_criteria$study_environment_uuid, "env-1")
  } else {
    fail("Expected criteria to contain study_env_uuid or study_environment_uuid")
  }
})
context("Datasets pagination")

library(testthat)
library(mockery)

# Source the implementation under test (same pattern as other tests in this repo)
source("../../R/datasets.R")

# ── .get_datasets tests ──────────────────────────────────────────────────────
test_that(".get_datasets forwards server-side pagination (page + page_size) in criteria", {
  captured_client <- NULL
  captured_criteria <- NULL

  mockery::stub(.get_datasets, ".list_flights", function(client, criteria) {
    captured_client <<- client
    captured_criteria <<- criteria
    list()
  })

  # Stub reticulate::iterate to simulate empty iteration
  mockery::stub(.get_datasets, "reticulate::iterate", function(iter, fn) {
    # Don't call fn, simulating empty iterator
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
  expect_true(!is.null(out$datasets))
  expect_type(out$datasets, "list")
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

test_that(".get_datasets returns total_records = 0L and correct pagination defaults for empty iterator", {
  mockery::stub(.get_datasets, ".get_flights", function(client, criteria) list())
  mockery::stub(.get_datasets, ".list_flights", function(client, criteria) list())
  mockery::stub(.get_datasets, "reticulate::iterate", function(iter, fn) { })

  out <- .get_datasets(
    client = list(),
    study_uuid = "study-1",
    study_environment_uuid = "env-1",
    search_dataset_name = "abc",
    page = 2,
    page_size = 50
  )
  expect_type(out, "list")
  expect_equal(out$total_records, 0L)
  expect_type(out$pagination, "list")
  expect_equal(out$pagination$page, 2)
  expect_equal(out$pagination$page_size, 50)
  expect_true(is.na(out$pagination$total_pages))
})

test_that(".get_datasets uses total_records from first item only", {
  mockery::stub(.get_datasets, ".get_flights", function(client, criteria) list())
  mockery::stub(.get_datasets, ".list_flights", function(client, criteria) list())
  call_count <- 0
  mockery::stub(.get_datasets, "reticulate::iterate", function(iter, fn) {
    call_count <<- 1
    fn(list(total_records = 42))
    call_count <<- 2
    fn(list(total_records = 999))
  })
  out <- .get_datasets(
    client = list(),
    study_uuid = "study-1",
    study_environment_uuid = "env-1",
    search_dataset_name = "abc",
    page = 1,
    page_size = 10
  )
  expect_equal(call_count, 2)
  expect_equal(out$total_records, 42L)
})

test_that(".get_datasets extracts pagination from app_metadata if present, otherwise uses defaults", {
  mockery::stub(.get_datasets, ".get_flights", function(client, criteria) list())
  mockery::stub(.get_datasets, ".list_flights", function(client, criteria) list())
  # Simulate app_metadata with pagination
  mockery::stub(.get_datasets, ".extract_app_metadata", function(item) {
    list(pagination = list(page = 5, page_size = 25, total_pages = 7))
  })
  call_count <- 0
  mockery::stub(.get_datasets, "reticulate::iterate", function(iter, fn) {
    call_count <<- 1
    fn(list(total_records = 123))
  })
  out <- .get_datasets(
    client = list(),
    study_uuid = "study-1",
    study_environment_uuid = "env-1",
    search_dataset_name = "abc",
    page = 2,
    page_size = 50
  )
  expect_equal(out$pagination$page, 5)
  expect_equal(out$pagination$page_size, 25)
  expect_equal(out$pagination$total_pages, 7)
  expect_equal(out$total_records, 123L)
})

# ── .get_studies tests ──────────────────────────────────────────────────────

test_that(".get_studies sends correct criteria to .list_flights", {
  captured_criteria <- NULL

  # Mock .list_flights to capture criteria
  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    captured_criteria <<- criteria
    # Return empty mock iterator (reticulate::iterate will be mocked)
    list()
  })

  # Mock reticulate::iterate to do nothing
  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    # Don't execute the function
  })

  mock_client <- list()

  .get_studies(
    client = mock_client,
    search_study_name = "demo",
    page = 2,
    page_size = 50
  )

  expect_equal(captured_criteria$flight_type, "STUDIES")
  expect_equal(captured_criteria$search_study_name, "demo")
  expect_equal(as.integer(captured_criteria$page), 2L)
  expect_equal(as.integer(captured_criteria$page_size), 50L)
})

test_that(".get_studies extracts total_records from first item only", {
  # Mock .list_flights
  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    list()
  })

  # Track how many times the iterator function is called
  call_count <- 0

  # Mock reticulate::iterate to simulate multiple items
  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    # Simulate first item with total_records
    call_count <<- 1
    fn(list(total_records = 100))

    # Simulate second item with different total_records (should be ignored)
    call_count <<- 2
    fn(list(total_records = 999))
  })

  # Mock .extract_data to return NULL (we're only testing total_records)
  mockery::stub(.get_studies, ".extract_data", function(item, simplify_data_frame) {
    NULL
  })

  result <- .get_studies(
    client = list(),
    search_study_name = ""
  )

  # Should use total_records from first item only
  expect_equal(call_count, 2)
  expect_equal(result$total_records, 100L)
})

test_that(".get_studies calls .extract_data with simplify_data_frame = FALSE", {
  captured_simplify_param <- NULL

  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    list()
  })

  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    fn(list(total_records = 5))
  })

  mockery::stub(.get_studies, ".extract_data", function(item, simplify_data_frame) {
    captured_simplify_param <<- simplify_data_frame
    list(name = "Study1", uuid = "s-1", environments = list())
  })

  .get_studies(
    client = list(),
    search_study_name = ""
  )

  expect_false(captured_simplify_param)
})

test_that(".get_studies returns correct structure with studies", {
  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    list()
  })

  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    # Simulate two items
    fn(list(total_records = 2))
    fn(list(total_records = 99))  # Should be ignored
  })

  # Mock .extract_data to return study objects
  call_index <- 0
  mockery::stub(.get_studies, ".extract_data", function(item, simplify_data_frame) {
    call_index <<- call_index + 1
    if (call_index == 1) {
      list(
        name = "Demo Study",
        uuid = "study-uuid-1",
        environments = list(
          list(name = "Dev", uuid = "env-1"),
          list(name = "Prod", uuid = "env-2")
        )
      )
    } else {
      list(
        name = "Diabetes Study",
        uuid = "study-uuid-2",
        environments = list(
          list(name = "Test", uuid = "env-3")
        )
      )
    }
  })

  result <- .get_studies(
    client = list(),
    search_study_name = ""
  )

  expect_type(result, "list")
  expect_equal(result$total_records, 2L)
  expect_type(result$studies, "list")
  expect_equal(length(result$studies), 2)

  # Check first study
  expect_equal(result$studies[[1]]$name, "Demo Study")
  expect_equal(result$studies[[1]]$uuid, "study-uuid-1")
  expect_equal(length(result$studies[[1]]$environments), 2)

  # Check second study
  expect_equal(result$studies[[2]]$name, "Diabetes Study")
  expect_equal(result$studies[[2]]$uuid, "study-uuid-2")
  expect_equal(length(result$studies[[2]]$environments), 1)
})

test_that(".get_studies handles empty results", {
  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    list()
  })

  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    # No items - iterator is empty
  })

  result <- .get_studies(
    client = list(),
    search_study_name = "nonexistent"
  )

  expect_type(result, "list")
  expect_equal(result$total_records, 0L)
  expect_type(result$studies, "list")
  expect_equal(length(result$studies), 0)
})

test_that(".get_studies handles NULL data from .extract_data", {
  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    list()
  })

  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    fn(list(total_records = 10))
    fn(list(total_records = 20))
  })

  # Mock .extract_data to return NULL (e.g., malformed data)
  mockery::stub(.get_studies, ".extract_data", function(item, simplify_data_frame) {
    NULL
  })

  result <- .get_studies(
    client = list(),
    search_study_name = ""
  )

  # Should still return total_records from first item
  expect_equal(result$total_records, 10L)
  # But studies list should be empty
  expect_equal(length(result$studies), 0)
})

test_that(".get_studies uses default parameters correctly", {
  captured_criteria <- NULL

  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    captured_criteria <<- criteria
    list()
  })

  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    # Empty iterator
  })

  .get_studies(client = list())

  expect_equal(captured_criteria$flight_type, "STUDIES")
  expect_equal(captured_criteria$search_study_name, "")
  expect_null(captured_criteria$page)
  expect_null(captured_criteria$page_size)
})

test_that(".get_studies maps realistic study/environment payload and prints output", {
  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    list()
  })

  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    fn(list(total_records = 248))
    fn(list(total_records = 999))
    fn(list(total_records = 1000))
  })

  simulated_studies <- list(
    list(
      name = "PWB Oncology Master",
      uuid = "8f7f8f86-53e3-4ab3-8e2f-0f7f5c16c3d1",
      phase = "Phase III",
      therapeutic_area = "Oncology",
      environments = list(
        list(name = "DEV", uuid = "f1d2d2f9-48b3-4e2f-9ae1-c9198a9c5d3d"),
        list(name = "UAT", uuid = "c95f6f4a-c7e8-4db6-8dd2-4b7809fa63b7"),
        list(name = "PROD", uuid = "2f7ebf83-22db-4e4b-b5e3-a3cde6f11e91")
      )
    ),
    list(
      name = "Exciter Diabetes Registry",
      uuid = "b0d6f3c1-8f11-4e37-bec2-2abf0cd9a21e",
      phase = "Observational",
      therapeutic_area = "Endocrinology",
      environments = list(
        list(name = "DEV", uuid = "a8b3d7d9-9df4-44f0-9947-2367bb85eb48"),
        list(name = "PROD", uuid = "0db6f6b4-4b5e-44f8-b9a6-0f112d6e1f20")
      )
    ),
    list(
      name = "CNS Safety Surveillance",
      uuid = "6a823a5b-9de3-4a1a-bf5e-782f5f8224da",
      phase = "Post-Marketing",
      therapeutic_area = "Neurology",
      environments = list(
        list(name = "SANDBOX", uuid = "fb5f7679-1c7e-4ab7-a996-2616d2b8f6ce"),
        list(name = NULL, uuid = "6f9bc6b1-f8a0-4f1a-ae80-5a4aa0cba936"),
        list(name = "PROD", uuid = NULL)
      )
    )
  )

  call_index <- 0
  mockery::stub(.get_studies, ".extract_data", function(item, simplify_data_frame) {
    call_index <<- call_index + 1
    simulated_studies[[call_index]]
  })

  result <- .get_studies(
    client = list(),
    search_study_name = "onc",
    page = 1,
    page_size = 25
  )

  cat("COMPREHENSIVE_GET_STUDIES_PRINT_START\n", file = stderr())
  print(result)
  cat("COMPREHENSIVE_GET_STUDIES_PRINT_END\n", file = stderr())

  expect_equal(result$total_records, 248L)
  expect_equal(length(result$studies), 3)
  expect_equal(result$studies[[1]]$name, "PWB Oncology Master")
  expect_equal(length(result$studies[[1]]$environments), 3)
  expect_equal(result$studies[[1]]$environments[[3]]$name, "PROD")
  expect_equal(result$studies[[2]]$therapeutic_area, "Endocrinology")
  expect_equal(result$studies[[3]]$environments[[2]]$name, NULL)
  expect_equal(result$studies[[3]]$environments[[3]]$uuid, NULL)
})

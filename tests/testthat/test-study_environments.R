context("Study environments")

library(testthat)
library(mockery)

test_that("StudyEnvironment stores uuid and name", {
  env <- StudyEnvironment$new(uuid = "env-1", name = "Prod")

  expect_true(methods::is(env, "StudyEnvironment"))
  expect_equal(env$uuid, "env-1")
  expect_equal(env$name, "Prod")
})

test_that(".get_studies maps environments to a flattened name string", {
  mockery::stub(.get_studies, ".list_flights", list())
  mockery::stub(.get_studies, "reticulate::iterate", function(x, f) f(list(total_records = 1)))

  mockery::stub(
    .get_studies,
    ".extract_data",
    function(item, simplify_data_frame) {
      list(
        name = "Demo Study",
        uuid = "study-uuid-1",
        environments = list(
          list(name = "Dev", uuid = "env-1"),
          list(name = "Prod", uuid = "env-2")
        )
      )
    }
  )

  result <- .get_studies(client = list(), search_study_name = "")

  # Validate the raw result metadata before deep-inspecting environment objects.
  raw_total <- if (!is.null(result$total_count)) result$total_count else result$total_records
  expect_equal(raw_total, 1L)
  expect_length(result$studies, 1)

  envs <- result$studies[[1]]$environments
  expect_type(envs, "character")
  expect_equal(envs, "Dev, Prod")
  expect_false(grepl("env-", envs))
})

test_that(".get_studies drops unnamed environments and keeps flattened names", {
  mockery::stub(.get_studies, ".list_flights", function(client, criteria) {
    list()
  })

  mockery::stub(.get_studies, "reticulate::iterate", function(iter, fn) {
    fn(list(total_records = 1))
  })

  mockery::stub(
    .get_studies,
    ".extract_data",
    function(item, simplify_data_frame) {
      list(
        name = "Demo Study",
        uuid = "study-uuid-1",
        environments = list(
          list(name = "Prod"),
          list(uuid = "env-2"),
          list()
        )
      )
    }
  )

  result <- .get_studies(client = list(), search_study_name = "")
  envs <- result$studies[[1]]$environments

  expect_type(envs, "character")
  expect_equal(envs, "Prod")
})

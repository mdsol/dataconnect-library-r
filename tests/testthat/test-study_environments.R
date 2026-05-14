context("Study environments")

library(testthat)
library(mockery)

test_that("StudyEnvironment stores uuid and name", {
  env <- StudyEnvironment$new(uuid = "env-1", name = "Prod")

  expect_true(methods::is(env, "StudyEnvironment"))
  expect_equal(env$uuid, "env-1")
  expect_equal(env$name, "Prod")
})

test_that(".get_studies preserves environments as named list entries", {
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

  result <- .get_studies(
    client = list(),
    search_study_name = ""
  )

  expect_equal(result$total_records, 1L)
  expect_length(result$studies, 1)

  envs <- result$studies[[1]]$environments
  expect_type(envs, "list")
  expect_length(envs, 2)
  expect_equal(envs[[1]]$name, "Dev")
  expect_equal(envs[[2]]$name, "Prod")
  expect_equal(envs[[1]]$uuid, "env-1")
  expect_equal(envs[[2]]$uuid, "env-2")
})

test_that(".get_studies preserves environment entries with missing fields", {
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

  result <- .get_studies(
    client = list(),
    search_study_name = ""
  )
  envs <- result$studies[[1]]$environments

  expect_type(envs, "list")
  expect_length(envs, 3)
  expect_equal(envs[[1]]$name, "Prod")
  expect_equal(envs[[1]]$uuid, "")
  expect_equal(envs[[2]]$uuid, "env-2")
  expect_equal(envs[[2]]$name, "")
  expect_equal(envs[[3]]$uuid, "")
  expect_equal(envs[[3]]$name, "")
})

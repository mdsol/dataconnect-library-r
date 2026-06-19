context("Datetime formats")

library(testthat)
library(mockery)

source("../../R/commands.R")

.build_mock_formats <- function() {
  datetime_prefix <- sprintf("yyyy-MM-dd HH:mm:%02d", 0:79)
  date_prefix <- sprintf("yyyy-MM-%02d", c(1:31, 1:17))
  c(datetime_prefix, date_prefix)
}

test_that(".get_datetime_formats returns structured all formats with 128 entries", {
  mock_client <- list()
  mock_formats <- .build_mock_formats()

  mockery::stub(.get_datetime_formats, ".do_command", function(...) {
    list(mock_formats)
  })

  result <- .get_datetime_formats(
    client = mock_client,
    project_token = "project-token",
    type = "all"
  )

  expect_s3_class(result, "data.frame")
  expect_named(result, c("index", "format", "type"))
  expect_equal(nrow(result), 128)
  expect_equal(result$index, seq_len(128))
  expect_true(all(result$type %in% c("date", "datetime")))
})

test_that(".get_datetime_formats supports date filter", {
  captured_args <- NULL

  mockery::stub(.get_datetime_formats, ".do_command", function(client, command, args = list(), body = NULL) {
    captured_args <<- args
    list(c("yyyy-MM-dd", "MM/dd/yy"))
  })

  result <- .get_datetime_formats(
    client = list(),
    project_token = "project-token",
    type = "date"
  )

  expect_equal(captured_args$type, "date")
  expect_true(all(result$type == "date"))
  expect_equal(nrow(result), 2)
})

test_that(".get_datetime_formats supports datetime filter", {
  captured_args <- NULL

  mockery::stub(.get_datetime_formats, ".do_command", function(client, command, args = list(), body = NULL) {
    captured_args <<- args
    list(c("yyyy-MM-dd HH:mm:ss", "yyyy-MM-ddTHH:mm:ss"))
  })

  result <- .get_datetime_formats(
    client = list(),
    project_token = "project-token",
    type = "datetime"
  )

  expect_equal(captured_args$type, "datetime")
  expect_true(all(result$type == "datetime"))
  expect_equal(nrow(result), 2)
})

test_that(".get_datetime_formats validates type input", {
  expect_error(
    .get_datetime_formats(client = list(), project_token = "project-token", type = "invalid"),
    "type must be one of: all, date, datetime"
  )
})

test_that(".get_datetime_formats result maps cleanly to publish datetime_formats payload", {
  mockery::stub(.get_datetime_formats, ".do_command", function(...) {
    list(c("yyyy-MM-dd", "MM/dd/yy"))
  })

  formats_df <- .get_datetime_formats(
    client = list(),
    project_token = "project-token",
    type = "date"
  )

  datetime_formats <- as.list(stats::setNames(
    formats_df$format[1],
    "start_date"
  ))

  config <- list(
    project_token = "project-token",
    dataset_name = "sample",
    key_columns = list("id"),
    source_datasets = list(),
    datetime_formats = datetime_formats,
    is_dry_publish = TRUE
  )

  encoded <- jsonlite::toJSON(config, auto_unbox = TRUE)
  decoded <- jsonlite::fromJSON(encoded)

  expect_equal(decoded$datetime_formats$start_date, "yyyy-MM-dd")
})

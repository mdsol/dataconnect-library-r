context("Datetime formats")

library(testthat)
library(mockery)

source("../../R/commands.R")
source("../../R/table.R")

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

  expect_type(result, "list")
  expect_s3_class(result, "data.frame")
  expect_named(result, c("index", "format", "type"))
  expect_equal(nrow(result), 128)
  expect_equal(result$index, seq_len(128))
  expect_true(all(result$type %in% c("date", "datetime")))
})

test_that(".get_datetime_formats warns but still returns formats when count differs from 128", {
  mockery::stub(.get_datetime_formats, ".do_command", function(...) {
    list(c("yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "MM/dd/yy"))
  })

  result <- expect_warning(
    .get_datetime_formats(client = list(), project_token = "project-token", type = "all"),
    "Expected 128 datetime formats"
  )

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 3)
})

test_that(".get_datetime_formats supports date filter", {
  captured_args <- NULL

  mockery::stub(.get_datetime_formats, ".do_command", function(client, command, args = list(), body = NULL, trace_state = NULL) {
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

  mockery::stub(.get_datetime_formats, ".do_command", function(client, command, args = list(), body = NULL, trace_state = NULL) {
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

test_that(".get_datetime_formats sends unsupported types to the server", {
  captured_args <- NULL

  mockery::stub(.get_datetime_formats, ".do_command", function(client, command, args = list(), body = NULL, trace_state = NULL) {
    captured_args <<- args
    list("yyyy-MM-dd")
  })

  result <- .get_datetime_formats(client = list(), project_token = "project-token", type = "INVALID")
  expect_equal(captured_args$type, "invalid")
  expect_equal(result$format, "yyyy-MM-dd")
})

test_that(".do_command records trace IDs from successful JSON payloads", {
  trace_state <- new.env(parent = emptyenv())
  payload <- list(
    to_pybytes = function() {
      list(decode = function(encoding) {
        '{"formats":["yyyy-MM-dd"],"trace_id":"trace-action-1"}'
      })
    }
  )
  mockery::stub(.do_command, "reticulate::import", function(...) {
    list(Action = function(command, body) list())
  })
  mockery::stub(.do_command, ".get_flight_options", function() list())
  mockery::stub(.do_command, "reticulate::iterate", function(iterator, callback) {
    callback(iterator)
  })

  result <- .do_command(
    client = list(do_action = function(action, options) list(body = payload)),
    command = "get_datetime_formats",
    trace_state = trace_state
  )

  expect_equal(trace_state$trace_id, "trace-action-1")
  expect_equal(result[[1]]$formats, "yyyy-MM-dd")
  expect_null(result[[1]]$trace_id)
})

test_that(".do_command records trace IDs from legacy JSON results", {
  trace_state <- new.env(parent = emptyenv())
  mockery::stub(.do_command, "reticulate::import", function(...) {
    list(Action = function(command, body) list())
  })
  mockery::stub(.do_command, ".get_flight_options", function() list())
  mockery::stub(.do_command, "reticulate::iterate", function(iterator, callback) {
    callback(iterator)
  })
  mockery::stub(.do_command, "reticulate::py_to_r", function(item) {
    '{"formats":["yyyy-MM-dd"],"trace_id":"trace-legacy-1"}'
  })

  result <- .do_command(
    client = list(do_action = function(action, options) list()),
    command = "get_datetime_formats",
    trace_state = trace_state
  )

  expect_equal(trace_state$trace_id, "trace-legacy-1")
  expect_equal(result[[1]]$formats, "yyyy-MM-dd")
  expect_null(result[[1]]$trace_id)
})

test_that("pre-request validation errors do not inherit a previous trace ID", {
  trace_state <- new.env(parent = emptyenv())
  trace_state$trace_id <- "trace-old-1"

  error <- tryCatch(
    .with_trace_id(
      trace_state,
      .get_datetime_formats(client = list(), project_token = "")
    ),
    error = identity
  )

  expect_null(error$trace_id)
  expect_null(trace_state$trace_id)
  expect_false(grepl("trace-old-1", conditionMessage(error), fixed = TRUE))
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

test_that(".get_datetime_formats preserves the data.frame return shape", {
  mockery::stub(.get_datetime_formats, ".do_command", function(...) {
    list(c("yyyy-MM-dd", "MM/dd/yy"))
  })

  result <- .get_datetime_formats(
    client = list(),
    project_token = "project-token",
    type = "date"
  )

  expect_named(result, c("index", "format", "type"))
})
# End of datetime format tests.

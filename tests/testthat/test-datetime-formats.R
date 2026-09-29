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
    list(response = list(list(formats = mock_formats)), trace_id = NULL)
  })

  result <- .get_datetime_formats(
    client = mock_client,
    project_token = "project-token",
    type = "all"
  )

  expect_type(result, "list")
  expect_s3_class(result$formats, "data.frame")
  expect_named(result$formats, c("index", "format", "type"))
  expect_equal(nrow(result$formats), 128)
  expect_equal(result$formats$index, seq_len(128))
  expect_true(all(result$formats$type %in% c("date", "datetime")))
})

test_that(".get_datetime_formats warns but still returns formats when count differs from 128", {
  mockery::stub(.get_datetime_formats, ".do_command", function(...) {
    list(response = list(list(formats = c("yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "MM/dd/yy"))), trace_id = NULL)
  })

  result <- expect_warning(
    .get_datetime_formats(client = list(), project_token = "project-token", type = "all"),
    "Expected 128 datetime formats"
  )

  expect_s3_class(result$formats, "data.frame")
  expect_equal(nrow(result$formats), 3)
})

test_that(".get_datetime_formats supports date filter", {
  captured_args <- NULL

  mockery::stub(.get_datetime_formats, ".do_command", function(client, command, args = list(), body = NULL) {
    captured_args <<- args
    list(response = list(list(formats = c("yyyy-MM-dd", "MM/dd/yy"))), trace_id = NULL)
  })

  result <- .get_datetime_formats(
    client = list(),
    project_token = "project-token",
    type = "date"
  )

  expect_equal(captured_args$type, "date")
  expect_true(all(result$formats$type == "date"))
  expect_equal(nrow(result$formats), 2)
})

test_that(".get_datetime_formats supports datetime filter", {
  captured_args <- NULL

  mockery::stub(.get_datetime_formats, ".do_command", function(client, command, args = list(), body = NULL) {
    captured_args <<- args
    list(response = list(list(formats = c("yyyy-MM-dd HH:mm:ss", "yyyy-MM-ddTHH:mm:ss"))), trace_id = NULL)
  })

  result <- .get_datetime_formats(
    client = list(),
    project_token = "project-token",
    type = "datetime"
  )

  expect_equal(captured_args$type, "datetime")
  expect_true(all(result$formats$type == "datetime"))
  expect_equal(nrow(result$formats), 2)
})

test_that(".get_datetime_formats sends unsupported types to the server", {
  captured_args <- NULL

  mockery::stub(.get_datetime_formats, ".do_command", function(client, command, args = list(), body = NULL) {
    captured_args <<- args
    list(response = list(list(formats = c("yyyy-MM-dd"))), trace_id = NULL)
  })

  result <- .get_datetime_formats(client = list(), project_token = "project-token", type = "INVALID")
  expect_equal(captured_args$type, "invalid")
  expect_equal(result$formats$format, "yyyy-MM-dd")
})

test_that(".get_datetime_formats result maps cleanly to publish datetime_formats payload", {
  mockery::stub(.get_datetime_formats, ".do_command", function(...) {
    list(response = list(list(formats = c("yyyy-MM-dd", "MM/dd/yy"))), trace_id = NULL)
  })

  formats_df <- .get_datetime_formats(
    client = list(),
    project_token = "project-token",
    type = "date"
  )

  datetime_formats <- as.list(stats::setNames(
    formats_df$formats$format[1],
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

test_that(".get_datetime_formats includes a trace_id field alongside formats", {
  mockery::stub(.get_datetime_formats, ".do_command", function(...) {
    list(response = list(list(formats = c("yyyy-MM-dd", "MM/dd/yy"))), trace_id = "trace-abc")
  })

  result <- .get_datetime_formats(
    client = list(),
    project_token = "project-token",
    type = "date"
  )

  expect_true("trace_id" %in% names(result))
})
# End of datetime format tests.

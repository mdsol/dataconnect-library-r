context("Connection operations")

# Load required libraries
library(testthat)
library(mockery)

# Directly source the file we need to test
source("../../R/connection.R")

# ── .set_dataconnect_token ─────────────────────────────────────────────────

test_that(".set_dataconnect_token rejects empty token", {
  expect_error(.set_dataconnect_token(""), "Token cannot be empty")
})

test_that(".set_dataconnect_token rejects NULL token", {
  expect_error(.set_dataconnect_token(NULL), "Token cannot be empty")
})

test_that(".set_dataconnect_token rejects missing token", {
  expect_error(.set_dataconnect_token(), "Token cannot be empty")
})

test_that(".set_dataconnect_token sets DATACONNECT_TOKEN env var for current session", {
  old_token <- Sys.getenv("DATACONNECT_TOKEN")
  on.exit(Sys.setenv(DATACONNECT_TOKEN = old_token), add = TRUE)

  suppressMessages(.set_dataconnect_token("session-token-123"))

  expect_equal(Sys.getenv("DATACONNECT_TOKEN"), "session-token-123")
})

test_that(".set_dataconnect_token returns invisible TRUE", {
  old_token <- Sys.getenv("DATACONNECT_TOKEN")
  on.exit(Sys.setenv(DATACONNECT_TOKEN = old_token), add = TRUE)

  result <- suppressMessages(.set_dataconnect_token("some-token"))

  expect_true(result)
  # Verify invisibility by checking the call doesn't auto-print
  expect_invisible(suppressMessages(.set_dataconnect_token("some-token")))
})

test_that(".set_dataconnect_token permanent=TRUE writes token to .Renviron", {
  tmp_home <- tempfile("home_")
  dir.create(tmp_home, recursive = TRUE)
  on.exit(unlink(tmp_home, recursive = TRUE), add = TRUE)
  renviron_path <- file.path(tmp_home, ".Renviron")

  old_home  <- Sys.getenv("HOME")
  old_token <- Sys.getenv("DATACONNECT_TOKEN")
  on.exit(Sys.setenv(HOME = old_home, DATACONNECT_TOKEN = old_token), add = TRUE)

  Sys.setenv(HOME = tmp_home)
  suppressMessages(.set_dataconnect_token("perm-token-abc", permanent = TRUE))

  expect_true(file.exists(renviron_path))
  lines <- readLines(renviron_path)
  expect_true(any(grepl("^DATACONNECT_TOKEN=perm-token-abc$", lines)))
})

test_that(".set_dataconnect_token permanent=TRUE replaces existing token in .Renviron", {
  tmp_home <- tempfile("home_")
  dir.create(tmp_home, recursive = TRUE)
  on.exit(unlink(tmp_home, recursive = TRUE), add = TRUE)
  renviron_path <- file.path(tmp_home, ".Renviron")
  writeLines(c("OTHER_VAR=keep-me", "DATACONNECT_TOKEN=old-token"), renviron_path)

  old_home  <- Sys.getenv("HOME")
  old_token <- Sys.getenv("DATACONNECT_TOKEN")
  on.exit(Sys.setenv(HOME = old_home, DATACONNECT_TOKEN = old_token), add = TRUE)

  Sys.setenv(HOME = tmp_home)
  suppressMessages(.set_dataconnect_token("new-token", permanent = TRUE))

  lines <- readLines(renviron_path)
  # New token present
  expect_true(any(grepl("^DATACONNECT_TOKEN=new-token$", lines)))
  # Old token removed
  expect_false(any(grepl("old-token", lines)))
})

test_that(".set_dataconnect_token permanent=TRUE preserves other .Renviron entries", {
  tmp_home <- tempfile("home_")
  dir.create(tmp_home, recursive = TRUE)
  on.exit(unlink(tmp_home, recursive = TRUE), add = TRUE)
  renviron_path <- file.path(tmp_home, ".Renviron")
  writeLines(c("OTHER_VAR=keep-me", "ANOTHER=also-keep"), renviron_path)

  old_home  <- Sys.getenv("HOME")
  old_token <- Sys.getenv("DATACONNECT_TOKEN")
  on.exit(Sys.setenv(HOME = old_home, DATACONNECT_TOKEN = old_token), add = TRUE)

  Sys.setenv(HOME = tmp_home)
  suppressMessages(.set_dataconnect_token("my-token", permanent = TRUE))

  lines <- readLines(renviron_path)
  expect_true(any(grepl("^OTHER_VAR=keep-me$", lines)))
  expect_true(any(grepl("^ANOTHER=also-keep$", lines)))
})

test_that(".set_dataconnect_token permanent=TRUE warns on write failure but still sets session token", {
  old_token <- Sys.getenv("DATACONNECT_TOKEN")
  on.exit(Sys.setenv(DATACONNECT_TOKEN = old_token), add = TRUE)

  # Point HOME at a non-writable path to trigger the write error
  mockery::stub(.set_dataconnect_token, "writeLines", function(...) stop("permission denied"))

  expect_warning(
    suppressMessages(.set_dataconnect_token("fallback-token", permanent = TRUE)),
    "Could not write to .Renviron file"
  )

  # Token should still be set in the session despite the file error
  expect_equal(Sys.getenv("DATACONNECT_TOKEN"), "fallback-token")
})

# ── .get_client_header ─────────────────────────────────────────────────────

test_that(".get_client_header returns a named list", {
  result <- .get_client_header()
  expect_type(result, "list")
  expect_length(result, 1)
})

test_that(".get_client_header uses the correct header name", {
  result <- .get_client_header()
  expect_equal(names(result), "x-client-dataconnect")
})

test_that(".get_client_header value starts with R_SDK;", {
  result <- .get_client_header()
  expect_true(startsWith(result[["x-client-dataconnect"]], "R_SDK;"))
})

test_that(".get_client_header value contains the package version", {
  result <- .get_client_header()
  version <- as.character(utils::packageVersion("dataconnect"))
  expect_true(grepl(version, result[["x-client-dataconnect"]], fixed = TRUE))
})

# ── .get_flight_options ────────────────────────────────────────────────────

test_that(".get_flight_options returns NULL with warning when reticulate and arrow are unavailable", {
  mockery::stub(.get_flight_options, "requireNamespace", function(pkg, ...) FALSE)

  expect_warning(
    result <- .get_flight_options(),
    "reticulate package not available"
  )
  expect_null(result)
})
test_that(".get_flight_options warns and returns NULL when py_run_string fails and arrow is unavailable", {
  # Allow requireNamespace("reticulate") to pass but fail py_run_string
  mockery::stub(.get_flight_options, "reticulate::py_run_string", function(...) stop("python error"))
  mockery::stub(.get_flight_options, "requireNamespace", function(pkg, ...) {
    if (pkg == "arrow") FALSE else TRUE
  })

  expect_warning(
    result <- .get_flight_options(),
    "Error creating flight options"
  )
  expect_null(result)
})

test_that(".get_flight_options omits the public IP header and preserves other headers on success", {
  mock_options <- list(
    headers = list(
      c("x-client-dataconnect", "R_SDK;1.0.0;"),
      c("x-client-local-ip", "192.168.1.5"),
      c("x-client-mac", "aa:bb:cc:dd:ee:ff")
    )
  )
  mockery::stub(.get_flight_options, "requireNamespace", function(pkg, ...) TRUE)
  # Assert the generated Python source drops the public-IP header while still building local IP/MAC headers.
  mockery::stub(.get_flight_options, "reticulate::py_run_string", function(code, ...) {
    expect_false(grepl("x-client-public-ip", code, fixed = TRUE))
    if (grepl("create_flight_options_with_network_info", code, fixed = TRUE)) {
      expect_true(grepl("x-client-local-ip", code, fixed = TRUE))
      expect_true(grepl("x-client-mac", code, fixed = TRUE))
    }
    invisible(NULL)
  })
  mockery::stub(
    .get_flight_options,
    "reticulate::py$create_flight_options_with_network_info",
    function() mock_options
  )

  result <- .get_flight_options()

  header_names <- vapply(result$headers, function(h) h[[1]], character(1))
  expect_true("x-client-dataconnect" %in% header_names)
  expect_true("x-client-local-ip" %in% header_names)
  expect_false("x-client-public-ip" %in% header_names)
})
# ── .connect ───────────────────────────────────────────────────────────────

test_that(".connect builds a grpc+tcp URI when use_tls is FALSE", {
  captured_uri <- NULL
  mock_client <- "mock_client"
  mock_trace_state <- new.env(parent = emptyenv())
  mockery::stub(.connect, ".get_client", function(uri, use_tls) {
    captured_uri <<- uri
    list(client = mock_client, trace_state = mock_trace_state)
  })

  result <- .connect("localhost", 8815)

  expect_equal(captured_uri, "grpc+tcp://localhost:8815")
  expect_identical(result$client, mock_client)
  expect_identical(result$trace_state, mock_trace_state)
})

test_that(".connect builds a grpc+tls URI when use_tls is TRUE", {
  captured_uri <- NULL
  captured_tls <- NULL
  mock_client <- "mock_client_tls"
  mock_trace_state <- new.env(parent = emptyenv())
  mockery::stub(.connect, ".get_client", function(uri, use_tls) {
    captured_uri <<- uri
    captured_tls <<- use_tls
    list(client = mock_client, trace_state = mock_trace_state)
  })

  result <- .connect("dummy.imedidata.com", 443, use_tls = TRUE)

  expect_equal(captured_uri, "grpc+tls://dummy.imedidata.com:443")
  expect_true(captured_tls)
  expect_identical(result$client, mock_client)
  expect_identical(result$trace_state, mock_trace_state)
})

test_that(".connect returns the client and trace state from .get_client", {
  mock_client <- structure(list(), class = "MockFlightClient")
  mock_trace_state <- new.env(parent = emptyenv())
  connection <- list(client = mock_client, trace_state = mock_trace_state)
  mockery::stub(.connect, ".get_client", function(uri, use_tls) connection)

  result <- .connect("host", 1234)

  expect_identical(result, connection)
})

# ── .get_client ────────────────────────────────────────────────────────────

test_that(".get_client stops when PyArrow is not available", {
  mockery::stub(.get_client, "reticulate::py_module_available", function(module) FALSE)

  expect_error(
    .get_client("grpc+tcp://localhost:8815", FALSE),
    "PyArrow module is not available"
  )
})

test_that("client trace middleware extracts IDs from escaped IPv6 gRPC errors", {
  skip_if_not(reticulate::py_module_available("pyarrow"))

  connection <- .get_client("grpc+tcp://127.0.0.1:5005", FALSE)
  trace_state <- connection$trace_state
  middleware_class <- reticulate::py_eval("_DataConnectTraceMiddleware", convert = FALSE)
  middleware <- middleware_class(trace_state)
  trace_id <- "trace-583f90d5250b271c72802814d94f47ad"
  payload <- as.character(jsonlite::toJSON(
    list(
      error_code = "VAL_007",
      message = 'Invalid "dataset_name"',
      trace_id = trace_id
    ),
    auto_unbox = TRUE
  ))
  escaped_payload <- as.character(jsonlite::toJSON(payload, auto_unbox = TRUE))
  escaped_payload <- substr(escaped_payload, 2, nchar(escaped_payload) - 1)
  error_message <- paste0(
    'UNKNOWN:Error received from peer ipv6:%5B::1%5D:5007 {created_time:"2026-10-05T10:19:22.4546385+00:00", ',
    'grpc_status:2, grpc_message:"VAL_007::', escaped_payload, '"}. Detail: Failed'
  )

  runtime_error_class <- reticulate::py_eval("RuntimeError", convert = FALSE)
  middleware$call_completed(runtime_error_class(error_message))

  expect_equal(reticulate::py_to_r(reticulate::py_get_attr(trace_state, "trace_id")), trace_id)
})

test_that("client trace middleware extracts string and bytes response headers", {
  skip_if_not(reticulate::py_module_available("pyarrow"))

  state_class <- reticulate::py_eval("_DataConnectTraceState", convert = FALSE)
  middleware_class <- reticulate::py_eval("_DataConnectTraceMiddleware", convert = FALSE)
  cases <- list(
    list(headers = "{'x-dataconnect-trace-id': ['trace-string-string']}", expected = "trace-string-string"),
    list(headers = "{'x-dataconnect-trace-id': [b'trace-string-bytes']}", expected = "trace-string-bytes"),
    list(headers = "{b'x-dataconnect-trace-id': ['trace-bytes-string']}", expected = "trace-bytes-string"),
    list(headers = "{b'x-dataconnect-trace-id': [b'trace-bytes-bytes']}", expected = "trace-bytes-bytes")
  )

  for (case in cases) {
    trace_state <- state_class()
    middleware <- middleware_class(trace_state)
    headers <- reticulate::py_eval(case$headers, convert = FALSE)

    middleware$received_headers(headers)

    expect_equal(reticulate::py_to_r(reticulate::py_get_attr(trace_state, "trace_id")), case$expected)
  }
})

test_that("client trace middleware keeps header IDs over payload IDs", {
  skip_if_not(reticulate::py_module_available("pyarrow"))

  state_class <- reticulate::py_eval("_DataConnectTraceState", convert = FALSE)
  middleware_class <- reticulate::py_eval("_DataConnectTraceMiddleware", convert = FALSE)
  trace_state <- state_class()
  middleware <- middleware_class(trace_state)
  middleware$received_headers(reticulate::py_eval(
    "{'x-dataconnect-trace-id': ['header-trace']} ",
    convert = FALSE
  ))
  runtime_error_class <- reticulate::py_eval("RuntimeError", convert = FALSE)

  middleware$call_completed(runtime_error_class('AUTH_001::{"trace_id":"payload-trace"}'))

  expect_equal(reticulate::py_to_r(reticulate::py_get_attr(trace_state, "trace_id")), "header-trace")
})

test_that("client trace middleware resets state for each call", {
  skip_if_not(reticulate::py_module_available("pyarrow"))

  state_class <- reticulate::py_eval("_DataConnectTraceState", convert = FALSE)
  factory_class <- reticulate::py_eval("_DataConnectTraceMiddlewareFactory", convert = FALSE)
  trace_state <- state_class()
  factory <- factory_class(trace_state)

  first_middleware <- factory$start_call(NULL)
  first_middleware$received_headers(reticulate::py_eval(
    "{'x-dataconnect-trace-id': ['first-trace']} ",
    convert = FALSE
  ))
  expect_equal(reticulate::py_to_r(reticulate::py_get_attr(trace_state, "trace_id")), "first-trace")

  second_middleware <- factory$start_call(NULL)
  second_middleware$call_completed(NULL)

  expect_null(reticulate::py_to_r(reticulate::py_get_attr(trace_state, "trace_id")))
})
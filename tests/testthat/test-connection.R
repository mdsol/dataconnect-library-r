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

# ── .connect ───────────────────────────────────────────────────────────────

test_that(".connect builds a grpc+tcp URI when use_tls is FALSE", {
  captured_uri <- NULL
  mockery::stub(.connect, ".get_client", function(uri, use_tls) {
    captured_uri <<- uri
    "mock_client"
  })

  result <- .connect("localhost", 8815)

  expect_equal(captured_uri, "grpc+tcp://localhost:8815")
  expect_equal(result, "mock_client")
})

test_that(".connect builds a grpc+tls URI when use_tls is TRUE", {
  captured_uri <- NULL
  captured_tls <- NULL
  mockery::stub(.connect, ".get_client", function(uri, use_tls) {
    captured_uri <<- uri
    captured_tls <<- use_tls
    "mock_client_tls"
  })

  result <- .connect("dummy.imedidata.com", 443, use_tls = TRUE)

  expect_equal(captured_uri, "grpc+tls://dummy.imedidata.com:443")
  expect_true(captured_tls)
  expect_equal(result, "mock_client_tls")
})

test_that(".connect returns the client from .get_client", {
  mock_client <- structure(list(), class = "MockFlightClient")
  mockery::stub(.connect, ".get_client", function(uri, use_tls) mock_client)

  result <- .connect("host", 1234)

  expect_identical(result, mock_client)
})

# ── .get_client ────────────────────────────────────────────────────────────

test_that(".get_client stops when PyArrow is not available", {
  mockery::stub(.get_client, "reticulate::py_module_available", function(module) FALSE)

  expect_error(
    .get_client("grpc+tcp://localhost:8815", FALSE),
    "PyArrow module is not available"
  )
})

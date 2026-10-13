#' Set Data Connect authentication token
#'
#' Sets the DATACONNECT_TOKEN environment variable for authentication with
#' Data Connect servers. The token will be automatically included in all
#' flight requests as an authorization header.
#'
#' @param token The authentication token to set
#' @param permanent If TRUE, attempts to add the token to .Renviron file for persistence
#' @return Invisibly returns TRUE if successful
#' @examples
#' \dontrun{
#' # Set token for current session
#' .set_dataconnect_token("your-token-here")
#' 
#' # Set token permanently (adds to .Renviron)
#' .set_dataconnect_token("your-token-here", permanent = TRUE)
#' }
#' @keywords internal
#' @noRd
.set_dataconnect_token <- function(token, permanent = FALSE) {
  if (missing(token) || is.null(token) || !nzchar(token)) {
    stop("Token cannot be empty")
  }

  # Set for current session
  Sys.setenv(DATACONNECT_TOKEN = token)

  if (permanent) {
    # Try to add to .Renviron file
    tryCatch({
      renviron_path <- file.path(Sys.getenv("HOME"), ".Renviron")

      # Read existing .Renviron if it exists
      existing_lines <- character(0)
      if (file.exists(renviron_path)) {
        existing_lines <- readLines(renviron_path, warn = FALSE)
      }

      # Remove any existing DATACONNECT_TOKEN lines
      existing_lines <- existing_lines[!grepl("^DATACONNECT_TOKEN=", existing_lines)]

      # Add the new token line
      new_lines <- c(existing_lines, paste0("DATACONNECT_TOKEN=", token))

      # Write back to .Renviron
      writeLines(new_lines, renviron_path)

      message("Token added to .Renviron file. Restart R session for permanent effect.")

    }, error = function(e) {
      warning("Could not write to .Renviron file: ", e$message)
      message("Token set for current session only.")
    })
  } else {
    message("Token set for current session.")
  }

  invisible(TRUE)
}

#' Get client information and create flight options
#'
#' Returns client information with properly formatted headers for PyArrow Flight
#' using Python's cross-platform libraries via reticulate. Automatically includes
#' authentication token from DATACONNECT_TOKEN environment variable if set.
#' 
#' @details
#' The function creates flight options with the following headers:
#' \itemize{
#'   \item Client information
#'   \item Local IP address (x-client-local-ip)
#'   \item MAC address (x-client-mac) if available
#'   \item Authorization header with Bearer token if DATACONNECT_TOKEN env var is set
#' }
#' 
#' @section Environment Variables:
#' \describe{
#'   \item{DATACONNECT_TOKEN}{Optional authentication token that will be included 
#'   as "Authorization: Bearer <token>" header}
#' }
#' 
#' @import arrow
#' @return Flight options with headers containing client information, network information and authentication token
#' @keywords internal
#' @noRd
.get_flight_options <- function() {
  # Get client header
  client_header <- .get_client_header()
  client_header_name <- names(client_header)[1]
  client_header_value <- client_header[[1]]

  # Check if reticulate is available
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    warning("reticulate package not available, using minimal flight options")
    # Return minimal flight options with just the client information
    if (requireNamespace("arrow", quietly = TRUE)) {
      arrow_pkg <- asNamespace("arrow")
      pa_flight <- arrow_pkg$flight
      headers <- list(c(client_header_name, client_header_value))

      # Add DATACONNECT_TOKEN if available (using lowercase header)
      token <- Sys.getenv("DATACONNECT_TOKEN", unset = "")
      if (nzchar(token)) {
        headers <- append(headers, list(c("authorization", paste("Bearer", token))))
      }

      return(pa_flight$FlightCallOptions(headers = headers))
    }
    return(NULL)
  }

  tryCatch({
    pa_flight <- reticulate::import("pyarrow.flight")
    builtins <- reticulate::import_builtins(convert = FALSE)
    header <- function(name, value) {
      reticulate::tuple(builtins$bytes(name, "utf-8"), builtins$bytes(value, "utf-8"))
    }

    headers <- list(
      header(client_header_name, client_header_value),
      header("x-client-local-ip", .get_local_ip())
    )

    mac <- .get_mac_address()
    if (!is.null(mac)) {
      headers <- append(headers, list(header("x-client-mac", mac)))
    }

    token <- Sys.getenv("DATACONNECT_TOKEN", unset = "")
    if (nzchar(token)) {
      headers <- append(headers, list(header("authorization", paste("Bearer", token))))
    }

    return(pa_flight$FlightCallOptions(headers = headers))
  }, error = function(e) {
    warning("Error creating flight options: ", e$message)

    # Fall back to just the client information
    if (requireNamespace("arrow", quietly = TRUE)) {
      arrow_pkg <- asNamespace("arrow")
      pa_flight <- arrow_pkg$flight
      headers <- list(c(client_header_name, client_header_value))

      # Add DATACONNECT_TOKEN if available (fallback case, using lowercase)
      token <- Sys.getenv("DATACONNECT_TOKEN", unset = "")
      if (nzchar(token)) {
        headers <- append(headers, list(c("authorization", paste("Bearer", token))))
      }

      return(pa_flight$FlightCallOptions(headers = headers))
    }
    
    return(NULL)
  })
}

#' Create an Arrow Flight Client
#'
#' @details On Mac and Linux, the system trust store is usually found
#' and used automatically by pyarrow/gRPC. Hence, tls_root_certs need
#' not be passed. However on Windows, Python/gRPC often does not use
#' the system trust store by default, so the root CA certificate is
#' passed explicitly.
#' @param uri The URI (protocol://host:port) of the Arrow Flight Server
#' @param use_tls Whether to use TLS
#' @return A FlightClient object
#' @keywords internal
#' @noRd
.get_client <- function(uri, use_tls) {
  # Check for PyArrow
  if (!reticulate::py_module_available("pyarrow")) {
    stop("PyArrow module is not available. Please restart R terminal and try again.")
  }

  is_windows <- (Sys.info()["sysname"] == "Windows")

  pa_flight <- reticulate::import("pyarrow.flight")
  trace_state <- new.env(parent = emptyenv())
  trace_state$trace_id <- NULL
  client_options <- list(middleware = list(.create_trace_middleware_factory(trace_state)))

  if (use_tls && is_windows) {

    base64_certs <- system2(
      command = "powershell.exe",
      args = "-Command Get-ChildItem -Path Cert:\\LocalMachine\\Root | ForEach-Object { [System.Convert]::ToBase64String($_.RawData) }",
      stdout = TRUE
    )
    root_certs_raw <- lapply(base64_certs, base64enc::base64decode)

    to_pem <- function(raw_data) {
      base64_string <- base64enc::base64encode(raw_data)

      # Split the string into 64-character lines as per PEM standard
      lines <- c(
        "-----BEGIN CERTIFICATE-----",
        sapply(seq(1, nchar(base64_string), by = 64), function(i) {
          substring(base64_string, i, i + 63)
        }),
        "-----END CERTIFICATE-----"
      )

      paste(lines, collapse = "\n")
    }

    pem_certs <- paste0(unlist(lapply(root_certs_raw, to_pem)), collapse="\n")

    client_options$tls_root_certs <- pem_certs
  }

  client <- do.call(pa_flight$FlightClient, c(list(uri), client_options))

  return(list(client = client, trace_state = trace_state))
}

# pyarrow invokes these R callbacks during each Flight RPC; they must never raise.
.create_trace_middleware_factory <- function(trace_state) {
  pa_flight <- reticulate::import("pyarrow.flight")

  middleware_class <- reticulate::PyClass(
    "DataConnectTraceMiddleware",
    inherit = pa_flight$ClientMiddleware,
    defs = list(
      received_headers = function(self, headers) {
        trace_id <- tryCatch(.header_trace_id(headers), error = function(e) NULL)
        if (!is.null(trace_id)) {
          trace_state$trace_id <- trace_id
        }
        NULL
      },
      call_completed = function(self, exception) {
        if (is.null(exception) || inherits(exception, "python.builtin.NoneType")) {
          return(NULL)
        }
        trace_id <- tryCatch(
          .extract_payload_trace_id(reticulate::py_str(exception)),
          error = function(e) NULL
        )
        .record_trace_id(trace_state, trace_id)
        NULL
      }
    )
  )

  factory_class <- reticulate::PyClass(
    "DataConnectTraceMiddlewareFactory",
    inherit = pa_flight$ClientMiddlewareFactory,
    defs = list(
      start_call = function(self, info) {
        trace_state$trace_id <- NULL
        middleware_class()
      }
    )
  )

  factory_class()
}

# Called for both response headers and trailers; returns NULL when the header is absent.
.header_trace_id <- function(headers) {
  value <- reticulate::py_to_r(headers)[["x-dataconnect-trace-id"]]
  if (is.list(value)) {
    value <- if (length(value) > 0) value[[1]] else NULL
  }
  if (inherits(value, "python.builtin.bytes")) {
    value <- reticulate::py_to_r(value$decode("utf-8", errors = "replace"))
  }
  if (is.character(value) && length(value) >= 1 && nzchar(value[[1]])) value[[1]] else NULL
}

.get_local_ip <- function() {
  tryCatch({
    socket <- reticulate::import("socket")
    s <- socket$socket(socket$AF_INET, socket$SOCK_DGRAM)
    on.exit(s$close(), add = TRUE)
    # UDP connect sends no packets; it only selects the outbound interface.
    s$connect(reticulate::tuple("8.8.8.8", 80L))
    s$getsockname()[[1]]
  }, error = function(e) "NA")
}

.get_mac_address <- function() {
  tryCatch({
    uuid <- reticulate::import("uuid", convert = FALSE)
    mac_hex <- reticulate::import_builtins()$format(uuid$getnode(), "012x")
    mac <- paste(substring(mac_hex, seq(1, 11, 2), seq(2, 12, 2)), collapse = ":")
    if (mac_hex == "000000000000" || startsWith(mac, "00:00:00")) NULL else mac
  }, error = function(e) NULL)
}

# pyarrow schema metadata is a bytes-keyed dict (or None).
.extract_schema_trace_id <- function(schema) {
  metadata <- reticulate::py_get_attr(schema, "metadata")
  if (inherits(metadata, "python.builtin.NoneType")) {
    return(NULL)
  }
  key <- reticulate::import_builtins(convert = FALSE)$bytes("trace_id", "utf-8")
  value <- metadata$get(key)
  if (is.null(value) || inherits(value, "python.builtin.NoneType")) {
    return(NULL)
  }
  if (inherits(value, "python.builtin.bytes")) {
    value <- value$decode("utf-8", errors = "replace")
  }
  reticulate::py_to_r(value)
}

#' Connect to an Arrow Flight server
#'
#' @param host The host address
#' @param port The port number
#' @param use_tls Whether to use TLS (defaults to FALSE)
#' @return A list containing the Flight client and its trace state.
#' @keywords internal
#' @noRd
.connect <- function(host, port, use_tls = FALSE) {

  # Construct the URI
  protocol <- if(use_tls) "grpc+tls" else "grpc+tcp"
  uri <- sprintf("%s://%s:%s", protocol, host, port)

  client <- .get_client(uri, use_tls)

  return(client)
}

#' Get the client header for Arrow Flight
#'
#' Returns a header with the client details for use in Arrow Flight requests
#' @importFrom utils packageVersion
#' @return A named list with the client header
#' @keywords internal
#' @noRd
.get_client_header <- function() {
  dataconnect_version <- as.character(packageVersion("dataconnect"))
  return(list("x-client-dataconnect" = paste0("R_SDK;", dataconnect_version, ";")))
}
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
#' set_dataconnect_token("your-token-here")
#' 
#' # Set token permanently (adds to .Renviron)
#' set_dataconnect_token("your-token-here", permanent = TRUE)
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

#' Get local and public network information and create flight options
#'
#' Returns network information with properly formatted headers for PyArrow Flight
#' using Python's cross-platform libraries via reticulate. Automatically includes
#' authentication token from DATACONNECT_TOKEN environment variable if set.
#' 
#' @details
#' The function creates flight options with the following headers:
#' \itemize{
#'   \item Client version information
#'   \item Local IP address (x-client-local-ip)
#'   \item Public IP address (x-client-public-ip) 
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
#' @return Flight options with headers containing network information and authentication
#' @keywords internal
#' @noRd
.get_flight_options <- function() {
  # Get client version header
  client_version_header <- .get_client_version_header()
  client_version_name <- names(client_version_header)[1]
  client_version_value <- client_version_header[[1]]

  # Check if reticulate is available
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    warning("reticulate package not available, using minimal flight options")
    # Return minimal flight options with just the client version
    if (requireNamespace("arrow", quietly = TRUE)) {
      arrow_pkg <- asNamespace("arrow")
      pa_flight <- arrow_pkg$flight
      headers <- list(c(client_version_name, client_version_value))
      
      # Add DATACONNECT_TOKEN if available (using lowercase header)
      token <- Sys.getenv("DATACONNECT_TOKEN", unset = "")
      if (nzchar(token)) {
        headers <- append(headers, list(c("authorization", paste("Bearer", token))))
      }
      
      return(pa_flight$FlightCallOptions(headers = headers))
    }
    return(NULL)
  }

  # Define Python function to get network info and create flight options in one step
  py_code <- sprintf('
import socket
import uuid
from urllib.request import urlopen
from urllib.error import URLError
import pyarrow.flight as flight
import os

def create_flight_options_with_network_info():
    """Get network information and create flight options with headers."""
    # Initialize network info with fallbacks
    ip = "NA"
    public_ip = "NA"
    mac = "00:00:00:00:00:00"

    # Get local IP - works on all platforms
    try:
        # This creates a socket but doesn\'t actually connect
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            # This doesn\'t send any packets, just sets up the routing
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
        except Exception:
            pass
        finally:
            s.close()
    except Exception:
        pass

    # Get MAC address - cross-platform approach
    try:
        # Try using uuid which is cross-platform
        mac_int = uuid.getnode()
        mac_hex = format(mac_int, "012x")
        mac_formatted = ":".join(mac_hex[i:i+2] for i in range(0, 12, 2))

        # Only use if it seems valid (not a virtual/fallback MAC)
        if mac_int != 0 and mac_hex != "000000000000" and not mac_formatted.startswith("00:00:00"):
            mac = mac_formatted
    except Exception:
        pass

    # Always try to get public IP
    try:
        # Try multiple services with a short timeout
        services = [
            "https://api.ipify.org",
            "https://ifconfig.me",
            "https://icanhazip.com"
        ]

        for service in services:
            try:
                # Response with a short timeout
                response = urlopen(service, timeout=3)
                public_ip = response.read().decode("utf-8").strip()
                if public_ip:
                    break
            except (URLError, socket.timeout):
                continue
    except Exception:
        pass

    # Create flight options with headers
    headers = []

    # Always include client version header (added from R)
    headers.append((b"%s", b"%s"))

    # Always include local IP (will be "NA" if not found)
    headers.append((b"x-client-local-ip", ip.encode("utf-8")))

    # Always include public IP (will be "NA" if not found)
    headers.append((b"x-client-public-ip", public_ip.encode("utf-8")))

    # Add MAC header only if it\'s not the fallback
    if mac != "00:00:00:00:00:00":
        headers.append((b"x-client-mac", mac.encode("utf-8")))

    # Add DATACONNECT_TOKEN if available (using lowercase header)
    # token was pre-set by R code below
    if token:
        headers.append((b"authorization", f"Bearer {token}".encode("utf-8")))

    # Create and return options
    return flight.FlightCallOptions(headers=headers)
', client_version_name, client_version_value)

  # Execute the Python code
  tryCatch({
    token <- Sys.getenv("DATACONNECT_TOKEN", unset = "")
    reticulate::py_run_string(sprintf("token = '%s'", token))
    reticulate::py_run_string(py_code)

    # Call the Python function to get options directly
    options <- reticulate::py$create_flight_options_with_network_info()

    return(options)
  }, error = function(e) {
    warning("Error creating flight options: ", e$message)

    # Fall back to just the client version header
    if (requireNamespace("arrow", quietly = TRUE)) {
      arrow_pkg <- asNamespace("arrow")
      pa_flight <- arrow_pkg$flight
      headers <- list(c(client_version_name, client_version_value))
      
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
#' @concept On Mac and Linux, the system trust store is usually found
#' and used automatically by pyarrow/gRPC. Hence, tls_root_certs need
#' not be passed. However on  Windows, Python/gRPC often does not use
#' the system trust store by default, so passing root CA certificate
#' explicitly
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

  # Import PyArrow
  pa <- reticulate::import("pyarrow")

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

    client <- pa$flight$FlightClient(uri, tls_root_certs = pem_certs)
  } else {
    client <- pa$flight$FlightClient(uri)
  }

  return(client)
}

#' Connect to an Arrow Flight server
#'
#' @param host The host address
#' @param port The port number
#' @param use_tls Whether to use TLS (defaults to FALSE)
#' @return A FlightClient object
#' @keywords internal
#' @noRd
.connect <- function(host, port, use_tls = FALSE) {

  # Construct the URI
  protocol <- if(use_tls) "grpc+tls" else "grpc+tcp"
  uri <- sprintf("%s://%s:%s", protocol, host, port)

  client <- .get_client(uri, use_tls)

  return(client)
}

#' Get the client version header for Arrow Flight
#' Returns a header with the client version for use in Arrow Flight requests.
#' @importFrom utils packageVersion
#' @return A named list with the client version header
#' @keywords internal
#' @noRd
.get_client_version_header <- function() {
  dataconnect_version <- as.character(packageVersion("dataconnect"))
  return(list("x-client-dataconnect-r-version" = paste0(dataconnect_version)))
}
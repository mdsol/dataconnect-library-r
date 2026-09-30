# DataConnect Reference Class for dplyr-style operations
#' @import dplyr
NULL
#' Create a DataConnect reference for dplyr-style operations
#' @importFrom methods new
#' @param client A FlightClient object
#' @param ticket_data Initial ticket data for the dataset
#' @return A DataConnectRef object that supports dplyr operations
#' @keywords internal
#' @noRd
dataconnect_tbl <- function(client, ticket_data, trace_state = NULL) {
  DataConnectRef$new(client, ticket_data, trace_state)
}

# Keep the response header authoritative and use payload metadata as a fallback.
.record_trace_id <- function(trace_state, trace_id) {
  if (is.null(trace_state) || is.null(trace_id) || length(trace_id) != 1L ||
      is.na(trace_id) || !nzchar(as.character(trace_id))) {
    return(invisible(NULL))
  }

  current_trace_id <- tryCatch({
    if (inherits(trace_state, "python.builtin.object")) {
      reticulate::py_to_r(reticulate::py_get_attr(trace_state, "trace_id"))
    } else {
      trace_state$trace_id
    }
  }, error = function(e) NULL)

  if (is.null(current_trace_id) || !length(current_trace_id) || is.na(current_trace_id)) {
    if (inherits(trace_state, "python.builtin.object")) {
      reticulate::py_set_attr(trace_state, "trace_id", as.character(trace_id))
    } else if (is.environment(trace_state)) {
      trace_state$trace_id <- as.character(trace_id)
    }
  }

  invisible(NULL)
}

# Attach the current client's trace ID to an error without changing its class.
.with_trace_id <- function(client, expr) {
  tryCatch(
    force(expr),
    error = function(e) {
      trace_id <- client$trace_id
      if (!is.null(trace_id) && length(trace_id) == 1L &&
          !is.na(trace_id) && nzchar(trace_id)) {
        e$trace_id <- trace_id
      }
      stop(e)
    }
  )
}

#' Fetch the first few rows of a DataConnectRef Object
#'
#' This method returns the first `n` rows from a DataConnectRef object.
#' 
#' @param x A DataConnectRef object
#' @param n The number of rows to return. Default is 6.
#' @param ... Additional arguments (ignored, for S3 generic consistency)
#' @return A data frame with the first n rows
#' @method head DataConnectRef
#' 
#' @examples
#' \dontrun{
#' data <- dc$fetch_data(....)
#' data$frame %>% head() # returns first 6 rows
#' 
#' # head need not be chained with collect(), head internally calls collect()
#' result <- data$frame %>% head(10) # returns first 10 rows
#' df <- result
#' }
#' 
#' @importFrom utils head
#' @export
head.DataConnectRef <- function(x, n = 6L, ...) {
  result <- x$head(n)$collect()
  return(result)
}

#' Collect data from a DataConnectRef object
#'
#' This method collects data from a DataConnectRef object into memory.
#'
#' @param x A DataConnectRef object
#' @param ... Additional arguments (ignored, for S3 generic consistency)
#' @return A data frame containing the collected data
#' @method collect DataConnectRef
#' 
#' @examples
#' \dontrun{
#' data <- dc$fetch_data(....)
#' result <- data$frame %>% collect()
#' df <- result
#' }
#' 
#' @export
collect.DataConnectRef <- function(x, ...) {
  x$collect(ignore_limit = TRUE)
}

#' A Reference Class for representing DataConnect query results with dplyr-style operations.
#'
#' This class provides a lazy evaluation interface for DataConnect queries, allowing
#' users to build and modify queries before execution. It supports method chaining
#' and follows dplyr-style conventions for data manipulation.
#'
#' @field .client FlightClient object used to communicate with the DataConnect service
#' @field .ticket_data Base ticket data containing query specifications and metadata
#' @field .limit_n Row limit for query results (NULL for no limit)
#'
#' @section Methods:
#' \describe{
#'   \item{\code{initialize(client, ticket_data)}}{
#'     Constructor method that initializes a new DataConnectRef object.
#'     \itemize{
#'       \item \code{client}: FlightClient object for DataConnect communication
#'       \item \code{ticket_data}: List containing base query specifications
#'     }
#'   }
#'   \item{\code{head(n = 6L)}}{
#'     Limits the query results to the first n rows. This operation is lazy
#'     and does not execute the query immediately.
#'     \itemize{
#'       \item \code{n}: Integer specifying the number of rows to return (default: 6)
#'     }
#'     Returns the modified DataConnectRef object for method chaining.
#'   }
#'   \item{\code{collect(ignore_limit = FALSE)}}{
#'     Executes the query and returns the results as a data frame. This method
#'     triggers the actual data retrieval from the DataConnect service.
#'     \itemize{
#'       \item \code{ignore_limit}: Logical flag to ignore any previously set row limits
#'     }
#'     Returns a data frame containing the query results, or NULL if no data.
#'   }
#' }
#'
#' @examples
#' \dontrun{
#' # Create a DataConnectRef object
#' ref <- new("DataConnectRef", client = my_client, ticket_data = my_ticket)
#' 
#' # Chain operations
#' result <- ref$head(10)$collect()
#' 
#' # Or execute without limit
#' full_result <- ref$collect(ignore_limit = TRUE)
#' }
#'
#' @keywords internal
#' @noRd
DataConnectRef <- setRefClass(
  "DataConnectRef",
  fields = list(
    .client = "ANY",
    .ticket_data = "list",
    .limit_n = "ANY",
    .trace_state = "ANY"
  ),
  methods = list(
    initialize = function(client, ticket_data, trace_state = NULL) {
      .self$.client <- client
      .self$.ticket_data <- ticket_data
      .self$.limit_n <- NULL
      .self$.trace_state <- trace_state
    },

    head = function(n = 6L) {
      "Limit results to first n rows"

      .self$.limit_n <- as.integer(n)
      return(.self)
    },

    collect = function(ignore_limit = FALSE) {
      "Execute the query and return a data frame"

      # Build enhanced ticket data with all query specifications
      enhanced_ticket <- .self$.ticket_data

      # Add limit
      if (!ignore_limit && !is.null(.self$.limit_n)) {
        enhanced_ticket$limit <- .self$.limit_n
      }

      # Get the data using enhanced ticket
      result <- .with_trace_id(
        .self$.trace_state,
        .get_dataset_raw(.self$.client, enhanced_ticket, chunked = TRUE, trace_state = .self$.trace_state)
      )

      # Convert to data frame by default for data scientists
      if (!is.null(result)) {
        result <- as.data.frame(result)
      }

      return(result)
    }
  )
)
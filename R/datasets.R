#' Send a query to list flights with pagination
#'
#' @param client A FlightClient object
#' @param criteria A list of criteria for the query
#' @return A Python iterator of FlightInfo objects
#' @keywords internal
#' @noRd
.client_list <- function(client, criteria) {
  # Ensure required pagination fields exist
  if(is.null(criteria$page_size)) {
    criteria$page_size <- 100  # Default page size
  }
  if(is.null(criteria$page)) {
    criteria$page <- 1  # Start with first page
  }

  # Convert criteria to JSON and then to bytes
  json_str <- jsonlite::toJSON(criteria, auto_unbox = TRUE)
  py_bytes <- reticulate::r_to_py(json_str)$encode("utf-8")

  options <- .get_flight_options()
  # Execute the query
  py_iter <- client$list_flights(py_bytes, options = options)

  return(py_iter)
}

#' Extract data from a FlightInfo object
#'
#' @param info A FlightInfo object
#' @return A list containing the extracted data
#' @keywords internal
#' @noRd
.extract_data <- function(info) {
  if (is.null(info) || !inherits(info, "python.builtin.object")) {
    return(NULL)
  }

  tryCatch({
    # Extract the first endpoint
    endpoint <- info$endpoints[[1]]

    # Get the ticket
    ticket <- endpoint$ticket$ticket

    # Decode the ticket
    ticket_raw <- reticulate::py_to_r(ticket$decode("utf-8"))

    # Parse the JSON
    ticket_data <- jsonlite::fromJSON(ticket_raw)

    return(ticket_data)
  }, error = function(e) {
    warning("Error extracting flight data: ", e$message)
    return(NULL)
  })
}

#' Process all flight info objects from an iterator
#'
#' @param py_iter A Python iterator of FlightInfo objects
#' @param client Optional FlightClient object to add frame property to datasets
#' @return A list of extracted data
#' @keywords internal
#' @noRd
.process_iterator <- function(py_iter, client = NULL) {
  results <- list()

  # Process each FlightInfo object
  reticulate::iterate(py_iter, function(item) {
    data <- .extract_data(item)
    if (!is.null(data)) {
      # Add frame property if client is provided and this looks like a dataset
      if (!is.null(client) && !is.null(data$dataset_uuid)) {
        # Create the base parameters needed for dataconnect_tbl
        base_params <- list(
          study_uuid = data$study_uuid,
          study_env_uuid = data$study_env_uuid,
          dataset_uuid = data$dataset_uuid,
          dataset_name = data$dataset_name
        )
        # Add the frame property as a dataconnect_tbl
        data$frame <- dataconnect_tbl(client, base_params)
      }
      
      results <<- c(results, list(data))
    }
  })

  return(results)
}

#' Get all data with automatic pagination
#'
#' @param client A FlightClient object
#' @param criteria Base criteria for the query
#' @param max_pages Maximum number of pages to retrieve (defaults to 10)
#' @return A list of all data across pages
#' @keywords internal
#' @noRd
.get_paginated_data <- function(client, criteria, max_pages = 10) {
  all_results <- list()
  current_page <- 1

  # Ensure criteria has pagination fields
  if(is.null(criteria$page_size)) {
    criteria$page_size <- 100
  }

  while(current_page <= max_pages) {
    # Update page number in criteria
    criteria$page <- current_page

    # Get iterator for current page
    py_iter <- .client_list(client, criteria)

    # Process the iterator, passing client for frame creation
    page_results <- .process_iterator(py_iter, client)

    # If no results, we've reached the end
    if(length(page_results) == 0) {
      break
    }

    # Add results to our collection
    all_results <- c(all_results, page_results)

    # Move to next page
    current_page <- current_page + 1
  }

  return(all_results)
}

#' Retrieve data for a flight
#'
#' @param client A FlightClient object
#' @param ticket The ticket from a FlightInfo object
#' @param chunked Whether to read data in chunks (default: FALSE)
#' @param chunk_callback Optional callback function to process each chunk
#' @return An Arrow Table
#' @keywords internal
#' @noRd
.get_data <- function(client, ticket, chunked = FALSE, chunk_callback = NULL) {
  tryCatch({
    # Convert ticket to proper format if needed
    if(is.character(ticket)) {
      ticket <- reticulate::r_to_py(ticket)$encode("utf-8")
    } else if(is.list(ticket)) {
      json_str <- jsonlite::toJSON(ticket, auto_unbox = TRUE)
      pa_flight <- reticulate::import("pyarrow.flight")
      ticket <- pa_flight$Ticket(charToRaw(as.character(json_str)))
    }
    options <- .get_flight_options()
    # Get the reader
    reader <- client$do_get(ticket, options=options)

    if(chunked) {
      # Process in chunks
      all_data <- list()

      # Read chunks until StopIteration
      tryCatch({
        repeat {
          chunk <- reader$read_chunk()

          # Process the chunk
          r_chunk <- arrow::as_arrow_table(chunk$data)

          # If callback is provided, call it with the chunk
          if(!is.null(chunk_callback)) {
            result <- chunk_callback(r_chunk)
            all_data <- c(all_data, list(result))
          } else {
            all_data <- c(all_data, list(r_chunk))
          }
        }
      }, error = function(e) {
        # Just catch StopIteration and continue
        if(!grepl("StopIteration", e$message)) {
          stop(e)  # Re-throw other errors
        }
      })

      return(all_data)
    } else {
      # Read all data at once
      table <- reader$read_all()

      # Convert to R Arrow table
      if(requireNamespace("arrow", quietly = TRUE)) {
        result <- arrow::as_arrow_table(table)
        return(result)
      } else {
        # Try to convert to R object
        return(reticulate::py_to_r(table))
      }
    }
  }, error = function(e) {
    warning("Error retrieving flight data: ", e$message)
    warning(reticulate::py_last_error())
    return(NULL)
  })
}

#' Get raw dataset data (internal function)
#'
#' @param client A FlightClient object
#' @param ticket_data A list containing the ticket data
#' @param chunked Whether to read data in chunks (default: FALSE)
#' @param chunk_callback Optional callback function to process each chunk
#' @return An Arrow Table with the raw dataset data
#' @keywords internal
#' @noRd
.get_dataset_raw <- function(client, ticket_data, chunked = FALSE, chunk_callback = NULL) {
  if(is.null(ticket_data) || length(ticket_data) < 1) {
    stop("Ticket must be provided")
  }

  pa_flight <- reticulate::import("pyarrow.flight")

  # Convert to JSON string
  json_str <- jsonlite::toJSON(ticket_data, auto_unbox = TRUE)

  # Create a Flight Ticket object from the encoded JSON string
  ticket <- pa_flight$Ticket(charToRaw(as.character(json_str)))

  # Get the data
  return(.get_data(client, ticket, chunked = chunked, chunk_callback = chunk_callback))
}

#' Get a specific dataset
#'
#' @param client A FlightClient object
#' @param study_uuid UUID of the study
#' @param study_environment_uuid UUID of the study environment
#' @param dataset_uuid UUID of the dataset
#' @return A dataset object with metadata and frame property
#' @keywords internal
#' @noRd
.get_dataset <- function(client, study_uuid, study_environment_uuid, dataset_uuid) {
  
  # Validate required parameters
  if (is.null(study_uuid) || is.null(study_environment_uuid) || is.null(dataset_uuid)) {
    stop("All parameters are required: study_uuid, study_environment_uuid and dataset_uuid")
  }
  
  # Create ticket_data for internal use
  ticket_data <- list(
    study_uuid = study_uuid,
    study_env_uuid = study_environment_uuid,
    dataset_uuid = dataset_uuid,
    dataset_name = ""
  )
  
  # Create dataset object with frame - this is essentially what get_datasets does
  dataset_obj <- list(
    study_uuid = study_uuid,
    study_environment_uuid = study_environment_uuid,
    dataset_uuid = dataset_uuid
  )
  
  # Add the frame property - this is the main purpose of the function
  dataset_obj$frame <- dataconnect_tbl(client, ticket_data)
  
  return(dataset_obj)
}

#' List study environments from a Flight server
#'
#' @param client A FlightClient object
#' @param page_size Number of items per page (default: 100)
#' @param max_pages Maximum number of pages to retrieve (default: 10)
#' @param lazy Whether to return a pagination spec for lazy processing (default: FALSE)
#' @return If lazy=FALSE, a list of study environments; if lazy=TRUE, a pagination specification
#'         that can be used with the %::% operator
#' @keywords internal
#' @noRd
.get_study_environments <- function(client, page_size = 100, max_pages = -1, lazy = TRUE) {
  criteria <- list(
    flight_type = "STUDY_ENVIRONMENTS",
    page_size = page_size,
    page = 1
  )

  if (lazy) {
    # Return a pagination spec for lazy processing
    return(list(
      client = client,
      criteria = criteria,
      max_pages = max_pages
    ))
  } else {
    # Use the existing eager approach
    return(.get_paginated_data(client, criteria, max_pages))
  }
}

#' List datasets from a Flight server
#'
#' @param client A FlightClient object
#' @param study_uuid UUID of the study to filter by
#' @param study_environment_uuid UUID of the study environment to filter by
#' @param search_dataset_name full or part of the dataset name to search by
#' @param lazy Whether to return a pagination spec for lazy processing (default: FALSE)
#' @return If lazy=FALSE, a list of study environments; if lazy=TRUE, a pagination specification
#'         that can be used with the %::% operator
#' @keywords internal
#' @noRd
.get_datasets <- function(client, study_uuid, study_environment_uuid, search_dataset_name, lazy = FALSE) {
  criteria <- list(
    flight_type = "DATASETS",
    study_uuid= study_uuid,
    study_environment_uuid = study_environment_uuid,
    search_dataset_name = search_dataset_name,
    page_size = -1,  # Use server default,
    page = 1
  )

  if (lazy) {
    # Return a pagination spec for lazy processing
    return(list(
      client = client,
      criteria = criteria,
      max_pages = -1
    ))
  } else {
    # Use the existing eager approach
    return(.get_paginated_data(client, criteria, -1))
  }
}

#' List versions of a dataset from a Flight server
#'
#' @param client A FlightClient object
#' @param study_uuid UUID of the study to filter by
#' @param study_environment_uuid UUID of the study environment to filter by
#' @param dataset_uuid UUID of the dataset to filter by
#' @keywords internal
#' @noRd
.get_dataset_versions <- function(client, study_uuid, study_environment_uuid, dataset_uuid) {

  criteria <- list(
    flight_type = "VERSIONS",
    study_uuid= study_uuid,
    study_environment_uuid = study_environment_uuid,
    dataset_uuid = dataset_uuid
  )

  # need not set page_size as Arrow Flight Server does not support pagination
  return(.get_paginated_data(client, criteria, 1))
}
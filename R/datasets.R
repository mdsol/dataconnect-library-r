#' Send a query to list flights with pagination
#'
#' @param client A FlightClient object
#' @param criteria A list of criteria for the query
#' @return A Python iterator of FlightInfo objects
#' @keywords internal
#' @noRd
.list_flights <- function(client, criteria) {

  # Convert criteria to JSON and then to bytes
  json_str <- jsonlite::toJSON(criteria, auto_unbox = TRUE, null = "null")
  py_bytes <- reticulate::r_to_py(json_str)$encode("utf-8")

  options <- .get_flight_options()
  
  tryCatch({
    # Execute the query
    flights <- client$list_flights(py_bytes, options = options)
    return(flights)
  }, error = function(e) {
    parsed_error <- .parse_dataconnect_error(conditionMessage(e))
    .throw_dataconnect_error(parsed_error)
  })
}

#' Internal Reference Class for study environment metadata
#'
#' @field uuid UUID of the study environment
#' @field name Name of the study environment
#' @keywords internal
#' @noRd
StudyEnvironment <- setRefClass(
  "StudyEnvironment",
  fields = list(
    uuid = "ANY",
    name = "ANY"
  ),
  methods = list(
    initialize = function(uuid, name) {
      uuid <<- if (missing(uuid) || is.null(uuid) || is.na(uuid) || trimws(as.character(uuid)) == "") {
        NULL
      } else {
        as.character(uuid)
      }

      name <<- if (missing(name) || is.null(name) || is.na(name) || trimws(as.character(name)) == "") {
        NULL
      } else {
        as.character(name)
      }
    },
    to_list = function() list(uuid = uuid, name = name)
  )
)

#' Extract data from a FlightInfo object
#'
#' @param info A FlightInfo object
#' @return A list containing the extracted data
#' @keywords internal
#' @noRd
.extract_data <- function(info, simplify_data_frame = TRUE) {
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
    ticket_data <- jsonlite::fromJSON(ticket_raw, simplifyDataFrame = simplify_data_frame)

    return(ticket_data)
  }, error = function(e) {
    warning("Error extracting flight data: ", conditionMessage(e))
    return(NULL)
  })
}

#' Extract app_metadata from a FlightInfo object
#'
#' @param item A FlightInfo object
#' @return The app_metadata list or NULL if not present
#' @keywords internal
#' @noRd
.extract_app_metadata <- function(item) {
  if (is.null(item)) return(NULL)

  meta <- item$app_metadata

  if (is.null(meta) || length(meta) == 0) return(NULL)

  meta_str <- reticulate::py_to_r(meta$decode("utf-8"))

  if (is.null(meta_str)) return(NULL)

  meta_list <- jsonlite::fromJSON(meta_str, simplifyDataFrame = FALSE)

  return(meta_list)
}

#' Attach frame property to a dataset object
#'
#' Helper function to attach a dataconnect_tbl frame to a dataset item.
#' Only attaches frame if the data contains a dataset_uuid (i.e., it's a dataset).
#'
#' @param data A dataset object with dataset_uuid, study_uuid, study_env_uuid, dataset_name
#' @param client A FlightClient object
#' @return The data object with $frame property attached if it's a dataset, otherwise returns data unchanged
#' @keywords internal
#' @noRd
.attach_dataset_frame <- function(data, client) {
  # Only attach frame if this is a dataset (has dataset_uuid)
  if (is.null(data) || is.null(data$dataset_uuid)) {
    return(data)
  }
  
  base_params <- list(
    study_uuid = data$study_uuid,
    study_env_uuid = data$study_env_uuid,
    dataset_uuid = data$dataset_uuid,
    dataset_name = data$dataset_name
  )
  
  data$frame <- dataconnect_tbl(client, base_params)
  return(data)
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

  tryCatch({
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
  }, error = function(e) {
    parsed_error <- .parse_dataconnect_error(conditionMessage(e))
    .throw_dataconnect_error(parsed_error)
  })

  return(results)
}

#' Get all flights
#'
#' @param client A FlightClient object
#' @param criteria Base criteria for the query
#' @return A list of all flights matching the criteria, with frame properties added for datasets
#' @keywords internal
#' @noRd
.get_flights <- function(client, criteria) {

  all_results <- list()

  # Get iterator for flights
  py_iter <- .list_flights(client, criteria)

  # Process the iterator, passing client for frame creation
  results <- .process_iterator(py_iter, client)

  if(length(results) > 0) {
    
    # Add results to our collection
    all_results <- c(all_results, results)
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
      py_chunks <- list()

      # Read chunks until StopIteration
      tryCatch({
        repeat {
          chunk <- reader$read_chunk()
          py_chunks[[length(py_chunks) + 1]] <- chunk$data
        }
      }, error = function(e) {
        # Just catch StopIteration and continue
        if(!grepl("StopIteration", e$message)) {
          stop(e)  # Re-throw other errors
        }
      })

      # Combine all chunks on the Python side, then convert to R
      if (length(py_chunks) > 0) {
        pa <- reticulate::import("pyarrow")
        combined_py_table <- pa$Table$from_batches(py_chunks)
        
        # Convert to R Arrow table
        result <- arrow::as_arrow_table(combined_py_table)
        
        # If callback is provided, call it with the result
        if(!is.null(chunk_callback)) {
          result <- chunk_callback(result)
        }
        
        return(result)
      }
      
      return(NULL)
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
    parsed_error <- .parse_dataconnect_error(conditionMessage(e))
    .throw_dataconnect_error(parsed_error)
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
#' @param study_uuid UUID of the study (optional)
#' @param study_environment_uuid UUID of the study environment (optional)
#' @param dataset_uuid UUID of the dataset
#' @return A dataset object with metadata and frame property
#' @keywords internal
#' @noRd
.get_dataset <- function(client, study_uuid = NULL, study_environment_uuid = NULL, dataset_uuid) {

  # Build ticket_data from provided identifiers
  ticket_data <- list(
    study_uuid = study_uuid,
    study_env_uuid = study_environment_uuid,
    dataset_uuid = dataset_uuid,
    dataset_name = ""
  )
  
  # Build dataset object with metadata
  dataset_obj <- list(
    study_uuid = study_uuid,
    study_environment_uuid = study_environment_uuid,
    dataset_uuid = dataset_uuid
  )
  
  # Attach a lazy frame for data retrieval
  dataset_obj$frame <- dataconnect_tbl(client, ticket_data)
  
  return(dataset_obj)
}

#' List studies from a Flight server
#' @param client A FlightClient object
#' @param search_study_name full or part of the study name to search by
#' @param page page number for paginated results
#' @param page_size number of results per page
#' @return A named list with `total_records`, `pagination`, and `studies`
#' @keywords internal
#' @noRd
.get_studies <- function(
  client,
  search_study_name = "",
  page = NULL,
  page_size = NULL
) {
  criteria <- list(
    flight_type = "STUDIES",
    search_study_name = search_study_name,
    page = page,
    page_size = page_size
  )

  py_iter <- .list_flights(client, criteria)
  studies <- list()
  total_records <- 0L

  tryCatch({
    reticulate::iterate(py_iter, function(item) {
      if (total_records == 0L &&
          !is.null(item$total_records) &&
          item$total_records >= 0
      ) {
        total_records <<- as.integer(item$total_records)
      }

      data <- .extract_data(item, simplify_data_frame = FALSE)

      if (!is.null(data) && !is.null(data$environments) && is.list(data$environments)) {
        make_study_environment <- function(env) {
          if (is.null(env) || !is.list(env)) {
            return(NULL)
          }

          # Pass raw values; initialize handles NULL mapping for missing/empty values.
          env_uuid <- if (!is.null(env$uuid)) env$uuid else NULL
          env_name <- if (!is.null(env$name)) env$name else NULL

          if (exists("StudyEnvironment", inherits = TRUE) &&
              !is.null(StudyEnvironment$new) &&
              is.function(StudyEnvironment$new)
          ) {
            return(StudyEnvironment$new(uuid = env_uuid, name = env_name)$to_list())
          }

          return(list(uuid = env_uuid, name = env_name))
        }

        data$environments <- Filter(
          Negate(is.null),
          lapply(data$environments, make_study_environment)
        )
      }

      if (!is.null(data)) {
        studies[[length(studies) + 1]] <<- data
      }
    })
  }, error = function(e) {
    parsed_error <- .parse_dataconnect_error(conditionMessage(e))
    .throw_dataconnect_error(parsed_error)
  })

  return(list(
    total_records = total_records,
    studies = studies
  ))
}

#' List datasets from a Flight server
#'
#' @param client A FlightClient object
#' @param study_uuid UUID of the study to filter by [Optional]
#' @param study_environment_uuid UUID of the study environment to filter by
#' @param search_dataset_name full or part of the dataset name to search by
#' @param page Page number for paginated results
#' @param page_size Number of results per page
#' @return A named list with `total_records`, `pagination`, and `datasets`
#' @keywords internal
#' @noRd
.get_datasets <- function(
  client, study_uuid = NULL,
  study_environment_uuid,
  search_dataset_name,
  page,
  page_size
) {
  criteria <- list(
    flight_type = "DATASETS",
    study_uuid = study_uuid,
    study_environment_uuid = study_environment_uuid,
    search_dataset_name = search_dataset_name,
    page = page,
    page_size = page_size
  )

  py_iter <- .list_flights(client, criteria)

  first_item <- TRUE
  total_records <- 0L
  datasets <- list()
  pagination <- list(
    page = page,
    page_size = page_size,
    total_pages = NA_integer_
  )

  tryCatch({
    reticulate::iterate(py_iter, function(item) {
      if (first_item) {
        app_metadata <- .extract_app_metadata(item)

        if (!is.null(app_metadata) && !is.null(app_metadata$pagination)) {

          if (!is.null(app_metadata$pagination$total_pages)) {
            pagination$total_pages <<- as.integer(app_metadata$pagination$total_pages)
          }

          if (!is.null(app_metadata$pagination$page)) {
            pagination$page <<- as.integer(app_metadata$pagination$page)
          }

          if (!is.null(app_metadata$pagination$page_size)) {
            pagination$page_size <<- as.integer(app_metadata$pagination$page_size)
          }
        }

        if (!is.null(item$total_records)) {
          total_records <<- as.integer(item$total_records)
        }

        first_item <<- FALSE
      }

      data <- .extract_data(item)

      if (!is.null(data)) {
        data <- .attach_dataset_frame(data, client)
        datasets[[length(datasets) + 1]] <<- data
      }

    })
  }, error = function(e) {
    parsed_error <- .parse_dataconnect_error(conditionMessage(e))
    .throw_dataconnect_error(parsed_error)
  })

  return(list(
    total_records = total_records,
    pagination = pagination,
    datasets = datasets
  ))
}

#' List versions of a dataset from a Flight server
#'
#' @param client A FlightClient object
#' @param study_uuid UUID of the study to filter by (optional)
#' @param study_environment_uuid UUID of the study environment to filter by (optional)
#' @param dataset_uuid UUID of the dataset to filter by
#' @keywords internal
#' @noRd
.get_dataset_versions <- function(client, study_uuid = NULL, study_environment_uuid = NULL, dataset_uuid) {

  criteria <- list(
    flight_type = "VERSIONS",
    study_uuid= study_uuid,
    study_environment_uuid = study_environment_uuid,
    dataset_uuid = dataset_uuid
  )

  # need not set page_size as Arrow Flight Server does not support pagination
  return(.get_flights(client, criteria))
}

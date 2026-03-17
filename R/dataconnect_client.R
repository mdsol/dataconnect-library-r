# DataConnect Client using Reference Classes (consistent with DataConnectRef pattern)

#' DataConnect Client Reference Class
#'
#' A reference class for interacting with the DataConnect service. This client provides
#' methods for connecting to DataConnect servers, retrieving study environments, 
#' datasets, their versions, fetching data, performing dry runs for publishing,
#' and publishing data.
#'
#' @section Fields:
#' \describe{
#'   \item{.client}{Internal client connection object}
#'   \item{.ns}{Package namespace reference for consistent function access}
#' }
#'
#' @section Methods:
#' \describe{
#'   \item{\code{study_environments(search_study_name)}}{
#'     Retrieve all available study environments from the DataConnect server.
#'    \itemize{
#'      \item \code{search_study_name}: Optional filter for study names (default: "")
#'     }
#'     Returns a specification object containing study environment details.
#'   }
#'   \item{\code{datasets(study_uuid, study_environment_uuid, search_dataset_name, page, page_size)}}{
#'     Get all datasets for a specific study environment.
#'     \itemize{
#'       \item \code{study_uuid}: UUID of the target study (deprecated, optional)
#'       \item \code{study_environment_uuid}: UUID of the target study environment (required)
#'       \item \code{search_dataset_name}: Optional dataset name filter (default: "")
#'       \item \code{page}: Page number for paginated results (optional, default: 1)
#'       \item \code{page_size}: Number of results per page (optional, default: 50)
#'     }
#'     Returns dataset specifications.
#'   }
#'   \item{\code{dataset_versions(study_uuid = NULL, study_environment_uuid = NULL, dataset_uuid)}}{
#'     Retrieve all versions of a specific dataset.
#'     \itemize{
#'       \item \code{study_uuid}: UUID of the target study (deprecated, optional)
#'       \item \code{study_environment_uuid}: UUID of the target study environment (deprecated, optional)
#'       \item \code{dataset_uuid}: UUID of the target dataset (required)
#'     }
#'     Returns version information for the specified dataset.
#'   }
#'   \item{\code{fetch_data(study_uuid = NULL, study_environment_uuid = NULL, dataset_uuid)}}{
#'     Retrieve data from a single dataset.
#'     \itemize{
#'       \item \code{study_uuid}: UUID of the target study (deprecated, optional)
#'       \item \code{study_environment_uuid}: UUID of the target study environment (deprecated, optional)
#'       \item \code{dataset_uuid}: UUID of the target dataset (required)
#'     }
#'     Returns the actual dataset data.
#'   }
#'   \item{\code{dry_publish(project_token, dataset_name, key_columns, source_datasets, data)}}{
#'     Validate publishing parameters without actually publishing data to DataConnect.
#'     This method performs validation checks and returns feedback without making changes.
#'     \itemize{
#'       \item \code{project_token}: Authentication token for the target project (required)
#'       \item \code{dataset_name}: Name for the dataset to be published (required)
#'       \item \code{key_columns}: List of key column names (required)
#'       \item \code{source_datasets}: List of source dataset references (required)
#'       \item \code{data}: The data to be validated for publishing (required)
#'     }
#'     Returns validation results and any potential issues.
#'   }
#'   \item{\code{publish(project_token, dataset_name, key_columns, source_datasets, data)}}{
#'     Publish a dataset to DataConnect service.
#'     \itemize{
#'       \item \code{project_token}: Authentication token for the target project (required)
#'       \item \code{dataset_name}: Name for the dataset to be published (required)
#'       \item \code{key_columns}: List of key column names (required)
#'       \item \code{source_datasets}: List of source dataset references (required)
#'       \item \code{data}: The data to be published (required, cannot be null)
#'     }
#'     Returns the result of the publishing operation.
#'   }
#' }
#'
#' @examples
#' \dontrun{
#' # Initialize and create a new connection
#' client <- init(token = "authentication_token_here")
#' 
#' # Get study environments
#' envs <- client$study_environments()
#' 
#' # Get datasets for a study environment
#' datasets <- client$datasets(study_environment_uuid = env_uuid, search_dataset_name = "my_dataset", page = 3, page_size = 10)
#'
#' # Get dataset versions for a specific dataset
#' versions <- client$dataset_versions(dataset_uuid = dataset_uuid)
#'
#' # Fetch data of a specific dataset
#' data <- client$fetch_data(dataset_uuid)
#' 
#' # Dry run publishing validation
#' validation <- client$dry_publish(
#'   project_token = "token",
#'   dataset_name = "my_dataset",
#'   key_columns = c("id"),
#'   source_datasets = list(),
#'   data = my_data
#' )
#' 
#' # Publish dataset
#' result <- client$publish(
#'   project_token = "token",
#'   dataset_name = "my_dataset",
#'   key_columns = c("id"),
#'   source_datasets = list(),
#'   data = my_data
#' )
#' }
#' 
#' @export
#' @exportClass DataConnectClient
DataConnectClient <- setRefClass(
  "DataConnectClient",
  fields = list(
    .client = "ANY",
    .ns = "ANY"
  ),
  methods = list(

    initialize = function(url = "host.docker.internal", port = 5005, use_tls = FALSE, token = "", permanent = FALSE) {
      "Initialize DataConnect client with server connection"

      # Store package namespace for consistent function access
      .self$.ns <- asNamespace("dataconnect")

      # Authentication is handled via DATACONNECT_TOKEN environment variable
      .self$.ns$.set_dataconnect_token(token, permanent)

      # Create internal client using existing connect function
      .self$.client <- .connect(url, port, use_tls)
    },

    study_environments = function(search_study_name = "") {
      "Get all study environments"
      # Use existing function but return all results 
      study_envs_spec <- .get_study_environments(.self$.client, search_study_name = search_study_name)
      return(study_envs_spec)
    },

    datasets = function(study_uuid = NULL, study_environment_uuid, search_dataset_name = "", page = 1, page_size = 50) {
      "Get all datasets for a study environment"

      return(.get_datasets(.self$.client, study_uuid, study_environment_uuid, search_dataset_name, page, page_size))
    },

    dataset_versions = function (study_uuid = NULL, study_environment_uuid = NULL, dataset_uuid) {
      "Get versions of a dataset"

      if (!missing(study_uuid) && !is.null(study_uuid) && !is.na(study_uuid) && nzchar(trimws(as.character(study_uuid)))) {
        warning("You only need to provide dataset_uuid; the Study context is now resolved automatically.")
      }

      if (!missing(study_environment_uuid) && !is.null(study_environment_uuid) && !is.na(study_environment_uuid) && nzchar(trimws(as.character(study_environment_uuid)))) {
        warning("You only need to provide dataset_uuid; the Study Environment context is now optional, and will be resolved automatically.")
      }

      if (missing(study_uuid) || is.null(study_uuid) || is.na(study_uuid) || trimws(as.character(study_uuid)) == "") {
        study_uuid <- NULL
      }

      if (missing(study_environment_uuid) || is.null(study_environment_uuid) || is.na(study_environment_uuid) || trimws(as.character(study_environment_uuid)) == "") {
        study_environment_uuid <- NULL
      }

      return(.get_dataset_versions(client = .self$.client,
                                   study_uuid = study_uuid,
                                   study_environment_uuid = study_environment_uuid,
                                   dataset_uuid = dataset_uuid))
    },

    fetch_data = function(study_uuid = NULL, study_environment_uuid = NULL, dataset_uuid) {
      "Fetch data of a dataset"

      if (!missing(study_uuid) && !is.null(study_uuid) && !is.na(study_uuid) && nzchar(trimws(as.character(study_uuid)))) {
        warning("You only need to provide dataset_uuid; the Study context is now resolved automatically.")
      }

      if (!missing(study_environment_uuid) && !is.null(study_environment_uuid) && !is.na(study_environment_uuid) && nzchar(trimws(as.character(study_environment_uuid)))) {
        warning("You only need to provide dataset_uuid; the Study Environment context is now optional, and will be resolved automatically.")
      }

      if (missing(study_uuid) || is.null(study_uuid) || is.na(study_uuid) || trimws(as.character(study_uuid)) == "") {
        study_uuid <- NULL
      }

      if (missing(study_environment_uuid) || is.null(study_environment_uuid) || is.na(study_environment_uuid) || trimws(as.character(study_environment_uuid)) == "") {
        study_environment_uuid <- NULL
      }

      # Use existing function to get single dataset
      return(.get_dataset(client = .self$.client,
                          study_uuid =  study_uuid,
                          study_environment_uuid =  study_environment_uuid,
                          dataset_uuid = dataset_uuid))
    },

    dry_publish = function(project_token, dataset_name, key_columns, source_datasets, data, datetime_formats = NULL) {

      "Validate publishing parameters without actually publishing"
      if (missing(project_token) ||
          missing(dataset_name) ||
          missing(key_columns) ||
          missing(source_datasets) ||
          missing(data)) {
        stop("All parameters are required: project_token, dataset_name, key_columns, source_datasets, and data.")
      }

      if (!is.list(key_columns) || length(key_columns) < 1) {
        stop("key_columns must be a non-empty list.")
      }

      config <- list(
        project_token = project_token,
        dataset_name = dataset_name,
        dataset_description = dataset_name, # This will be removed in future versions
        key_columns = key_columns,
        source_datasets = source_datasets,
        datetime_formats = datetime_formats,
        is_dry_publish = TRUE # Note: This flag is for internal use in the publish function to determine if it's a dry run or actual publish
      )

      # Use normalized namespace access
      return(.self$.ns$.publish(.self$.client, config, data))
    },

    publish = function(project_token, dataset_name, key_columns, source_datasets, data, datetime_formats = NULL) {

      "Publish dataset to Data Connect"
      if (missing(project_token) ||
          missing(dataset_name) ||
          missing(key_columns) ||
          missing(source_datasets) ||
          missing(data)) {
        stop("All parameters are required: project_token, dataset_name, key_columns, source_datasets, and data.")
      }

      if (!is.list(key_columns) || length(key_columns) < 1) {
        stop("key_columns must be a non-empty list.")
      }

      if (is.null(data)) {
        stop("Data cannot be null for publish operation.")
      }

      config <- list(
        project_token = project_token,
        dataset_name = dataset_name,
        dataset_description = dataset_name, # This will be removed in future versions
        key_columns = key_columns,
        source_datasets = source_datasets,
        datetime_formats = datetime_formats,
        is_dry_publish = FALSE # Note: This flag is for internal use in the publish function to determine if it's a dry run or actual publish
      )

      # Use normalized namespace access
      return(.self$.ns$.publish(.self$.client, config, data))
    }
  )
)

#' Initialize DataConnect client
#'
#' Creates and returns a new DataConnectClient object for interacting with a DataConnect server.
#'
#' @param url Character. Server URL. Default is "enodia-gateway-sandbox.platform.imedidata.net".
#' @param port Integer. Server port. Default is 443.
#' @param use_tls Logical. Whether to use TLS for the connection. Default is TRUE.
#' @param token Character. User authentication token generated from the Developer Center in Medidata Data Connect.
#'
#' @return A DataConnectClient object.
#'
#' @examples
#' \dontrun{
#' client <- init(token = "authentication_token_here")
#' }
#'
#' @export
init <- function(url = "enodia-gateway.platform.imedidata.com", port = 443, use_tls = TRUE, token) {
  DataConnectClient$new(url = url, port = port, use_tls = use_tls, token = token)
}

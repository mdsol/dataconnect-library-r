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
#'   \item{\code{study_environments()}}{
#'     Retrieve all available study environments from the DataConnect server.
#'     Returns a specification object containing study environment details.
#'   }
#'   \item{\code{datasets(study_uuid, study_environment_uuid, search_dataset_name, lazy)}}{
#'     Get all datasets for a specific study environment.
#'     \itemize{
#'       \item \code{study_uuid}: UUID of the target study (required)
#'       \item \code{study_environment_uuid}: UUID of the target study environment (required)
#'       \item \code{search_dataset_name}: Optional dataset name filter (default: "")
#'       \item \code{lazy}: Whether to use lazy evaluation (default: TRUE)
#'     }
#'     Returns dataset specifications with optional lazy loading.
#'   }
#'   \item{\code{dataset_versions(study_uuid, study_environment_uuid, dataset_uuid)}}{
#'     Retrieve all versions of a specific dataset.
#'     \itemize{
#'       \item \code{study_uuid}: UUID of the target study (required)
#'       \item \code{study_environment_uuid}: UUID of the target study environment (required)
#'       \item \code{dataset_uuid}: UUID of the target dataset (required)
#'     }
#'     Returns version information for the specified dataset.
#'   }
#'   \item{\code{fetch_data(study_uuid, study_environment_uuid, dataset_uuid)}}{
#'     Retrieve data from a single dataset.
#'     \itemize{
#'       \item \code{study_uuid}: UUID of the target study (required)
#'       \item \code{study_environment_uuid}: UUID of the target study environment (required)
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
#' datasets <- client$datasets(study_uuid, env_uuid)
#' 
#' # Fetch specific dataset data
#' data <- client$fetch_data(study_uuid, env_uuid, dataset_uuid)
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
    
    study_environments = function() {
      "Get all study environments"
      # Use existing function but return all results (no lazy evaluation)
      study_envs_spec <- .get_study_environments(.self$.client)
      return(study_envs_spec)
    },
    
    datasets = function(study_uuid, study_environment_uuid, search_dataset_name = "", lazy = TRUE) {
      "Get all datasets for a study environment"
      if (missing(study_uuid) || missing(study_environment_uuid)) {
        stop("Both study_uuid and study_environment_uuid are required")
      }
      
      # Use existing function to get datasets with frames
      return(.get_datasets(.self$.client, study_uuid, study_environment_uuid, search_dataset_name, lazy = lazy))
    },

    dataset_versions = function (study_uuid, study_environment_uuid, dataset_uuid) {
      "Get versions of a dataset"
      if (missing(study_uuid) || missing(study_environment_uuid) || missing(dataset_uuid)) {
        stop("All parameters are required: study_uuid, study_environment_uuid, dataset_uuid")
      }

      return(.get_dataset_versions(.self$.client, study_uuid, study_environment_uuid, dataset_uuid))
    },

    fetch_data = function(study_uuid, study_environment_uuid, dataset_uuid) {
      "Get a single dataset"
      if (missing(study_uuid) || missing(study_environment_uuid) || missing(dataset_uuid)) {
        stop("All parameters are required: study_uuid, study_environment_uuid and dataset_uuid")
      }
      
      # Use existing function to get single dataset
      return(.get_dataset(.self$.client, study_uuid, study_environment_uuid, dataset_uuid))
    },
  
    dry_publish = function(project_token, dataset_name, key_columns, source_datasets, data) {

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
        source_datasets = source_datasets
      )
      
      # Use normalized namespace access
      return(.self$.ns$.dry_publish(.self$.client, config, data))
    },
    
    publish = function(project_token, dataset_name, key_columns, source_datasets, data) {
      
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
        source_datasets = source_datasets
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

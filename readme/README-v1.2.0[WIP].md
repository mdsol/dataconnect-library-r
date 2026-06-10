> [!WARNING]
> **\[WIP\] — This document is under active development and has not been released.**
> Content may be incomplete or subject to change. For the latest stable documentation, see [README-v1.1.0.md](README-v1.1.0.md).

To use this library, you must have a valid iMedidata account and access to required building blocks in the Medidata Platform. For details, see the Medidata [Knowledge Hub](https://learn.medidata.com/en-US/bundle/data-connect/page/developer_center.html).

**Viewing version 1.2.0** — [View all versions](https://github.com/mdsol/dataconnect-library-r/tags)

**To switch versions:**
In the top-left corner of this page, below the "Files" list header, open drop-down list, select *Switch branches/tags* → open the *Tags* tab → choose your version.
Files marked `[WIP]` are under active development and not yet released.

- [Installation](#installation)
- [What's New in v1.2.0](#whats-new-in-v120)
- [Quick Start](#quick-start)
  - [Usage](#usage)
  - [Available vignettes in R Studio](#available-vignettes-in-r-studio)
  - [Authentication](#authentication)
- [Scheduling](#scheduling)
- [Functions](#functions)
  - [init()](#init)
  - [install_miniforge()](#install_miniforge)
  - [use_miniforge_env()](#use_miniforge_env)
  - [to_frame()](#to_frame)
  - [studies()](#studies)
  - [datasets()](#datasets)
  - [dataset_versions()](#dataset_versions)
  - [fetch_data()](#fetch_data)
  - [dry_publish()](#dry_publish)
  - [publish()](#publish)
  - [collect()](#collect)
  - [head(n)](#headn)
- [Acceptable Data Types and Formats](#acceptable-data-types-and-formats)
- [Reporting known issues ](#reporting-known-issues)
- [Backend](#backend)
- [Versions](#versions)
- [Licensing](#licensing)

# Installation

To install, follow the [Installation Guide](https://github.com/mdsol/dataconnect-library-r/blob/main/vignettes/rLibrary_setup.Rmd).

**Note:** Please make sure that you are installing the latest package (v1.2.0) to have access to the latest features and updates. The older versions have been deprecated and may not function properly. 
Follow the instructions in the aforementioned Installation Guide to install the latest version. 

# What's New in v1.2.0

* Pagination removed from `studies()`. The function now returns all studies and their environments in a single response — no page looping required.
  * The `page` and `page_size` parameters are accepted for backward compatibility but have no effect on the output. A deprecation warning is shown if they are passed. 
* Updated `valid_rows` calculation in `publish()` and `dry_publish()` to prevent double-counting records that are both invalid and duplicated:
  * `valid_rows = total_rows − invalid_rows − net_duplicate_rows`.
  * `valid_rows` is always ≥ 0. 
  * `duplicate_rows`: number of rows sharing the same `key_columns` values as at least one other row in the dataset being published. Includes rows that were also counted in `invalid_record_count`.  
* **key_columns** behavior updated in `publish()` and `dry_publish()`.
  * Rows with null or missing values in key columns are now flagged as invalid.
  * If `key_columns` are not provided, deduplication is skipped and
  `duplicate_rows` returns 0
* Validation Failure Diagnostics:
  * When `publish()` or `dry_publish()` fails validation, a structured "**_invalid_records**" table is now returned alongside the error. 
  * The table contains all original data frame columns plus `_invalid_reason`: a comma-separated string listing every validation error for that record, each prefixed with the column name (`column_name:reason`). 
  * One row is returned per invalid record regardless of how many errors it has. Errors reported: `null_key_column` (null or empty value in a key column) and `invalid_value` (value not parseable as a valid datetime). 
  * A column that is both a key column and a datetime column with an `NA` value will report both errors in `_invalid_reason`. 

# Quick Start

For the full quick start guide, see the [Usage Guide](https://github.com/mdsol/dataconnect-library-r/blob/main/vignettes/rLibrary_usage.Rmd)

### Usage

```r
#use dataconnect library
library(dataconnect)
use_miniforge_env()
```

### Available vignettes in R Studio

```r
vignette("rLibrary_setup", package = "dataconnect")
vignette("rLibrary_usage", package = "dataconnect")
```

### Authentication

* **Retrieving data:** You must have a user token to establish a connection between the user's R IDE and Medidata Data Connect. You can generate this token through Data Connect’s Developer Center. For details, see [here](https://learn.medidata.com/en-US/bundle/data-connect/page/developer_center.html). Medidata recommends that you save the token in a separate file and input it into the below initiation function.

```r
dc <-init(token = "<authentication_token>")
```

* **Publish data:** You must have a project token to publish a dataset from R IDE to Medidata Data Connect. You can generate this token through Data Connect > Transformations, by creating a Custom Code project. For details, see [here](https://learn.medidata.com/en-US/bundle/data-connect/page/generate_custom_code_projects.html). 


```r
my_project_token <- "<project_token_here>"
my_dataset_name <- "your_dataset_name_here"
my_key_columns <- list("subjid", "visit")
my_source_datasets <- list("0a4aaf73-1ebf-3f14-b955-f74d56fd7010")
datetime_formats <- c("date_column" = "MM/dd/yy", "datetime_column" = "yyyy-MM-dd HH:mm:ss")

publish(
  project_token = my_project_token,
  dataset_name = my_dataset_name,
  key_columns = my_key_columns,
  source_datasets = my_source_datasets,
  data = sample_data,
  datetime_formats = as.list(datetime_formats)
)
```

## Scheduling

RStudio natively supports scheduling for both Windows OS and Linux based OS.

* [Windows RStudio script scheduler](https://cran.r-project.org/web/packages/taskscheduleR/vignettes/taskscheduleR.html)  
* [Linux based RStudio script scheduler](https://cran.r-project.org/web/packages/cronR/readme/README.html)

**Note:** These functions are native to RStudio and not to the Medidata Data Connect R Library. If you encounter errors, please contact your RStudio or your IDE provider for support.

# Functions

### init()

### Description

Initialize DataConnect client.

### Usage

```r
init(token = "<authentication_token>")
```

### Arguments

|    Argument  | Description                                                                                                              |
|:-------------|:-------------------------------------------------------------------------------------------------------------------------|
| **url**      | Server URL. Default url="enodia-gateway.platform.imedidata.com"                                                          |
| **port**     | Server port. Default port="443"                                                                                          |
| **use_tls**  | Denotes whether to use TLS. Default use_tls = "TRUE"                                                                     |
| **token**    | Authentication token, this is the user authentication token generated from the Developer Center in Medidata Data Connect |

### Output 

DataConnectClient object. This enables you to interact with Medidata Data Connect data in R.

## install_miniforge()

### Description

This function automates the setup of all prerequisites for the Medidata Data Connect R package. It installs Miniforge (a conda environment manager); creates a new conda environment with the specified Python version; and installs the necessary Python packages. This includes pyarrow, installed using pip, to enable full Flight support. The function also checks for existing installations and environments to avoid redundant setup.

### Usage

```r
install_miniforge()
```

### Arguments

| Argument | Description |
| :---- | :---- |
| **env_name** | Character. Name of the conda environment to create or use. Default: "dataconnect-library-r". |
| **python_version** | Character. Python version to install in the environment. Default: "3.13". |
| **remove_existing_env** | Logical. If TRUE, removes the existing environment with the same name before creating a new one. The default is FALSE. |

### Details

* Automatically detects client side hosting OS and architecture to select the correct Miniforge installer.  
* Installs Miniforge in the user's home directory under miniforge3.  
* Creates a conda environment with the specified Python version and required packages.  
* Uses the conda-forge channel for package installation.  
* Skips installation or environment creation if already present.  
* For persistent configuration, you can add these environment variables to your .Rprofile. This information is printed to the console when the package is installed. 

### Output

(Invisibly) A named list with the following elements:

* **miniforge_root**: Path to the Miniforge installation directory.  
* **conda_bin**: Path to the conda executable.  
* **env_path**: Path to the created conda environment.

### Note

After creating a new environment, restart your R session before using it.

### use_miniforge_env()

### Description

This function checks if your configuration meets the required prerequisites for the Medidata Connect R library. It verifies that the configuration contains both a Miniforge installation and the specified conda environment both exist, and confirms that it has the correct versions of Python and all necessary packages (such as **pyarrow**) installed within it. If the validation is successful, the function activates this conda environment for use with **reticulate**.

### Usage

```r
use_miniforge_env() 
```

### Arguments

| Argument | Description |
| :----     | :---- |
| **env_name** | Character. Name of the conda environment to use. Default: "dataconnect-library-r". |


### Details

* Verifies Miniforge installation and the specified conda environment.  
* Checks for the Python executable within the environment.  
* Ensures the **reticulate** R package is installed.  
* Activates the conda environment for reticulate.  
* Confirms the **pyarrow** Python package is available in the environment.

### Output

(Invisibly) A named list with the following elements:

* **miniforge_root**: Path to the Miniforge installation directory.  
* **conda_bin**: Path to the conda executable.  
* **env_path**: Path to the created conda environment.

### Note

If the environment does not exist:

* Check the execution of install_miniforge().  
* Restart the R session after installing Miniforge.   
* If any required components are missing, the function stops and shows error message. 

### to_frame()

### Description

This function takes a list and converts it to a R data frame.

### Usage

```r
to_frame(data)
```

### Arguments

| Argument | Description |
| :------- | :---------- |
| **data** | A named list or vector to convert |

### Output 

A data frame with two columns: **name** and **value**

### studies()

### Description

Retrieves a list of studies where the user has permission to manage custom code projects. Use the optional study name search parameter to filter results.

### Usage

```r
studies(search_study_name = "")
```

### Arguments

| Argument               | Description                                              |
| :--------------------- | :------------------------------------------------------- |
| **search_study_name**  | Optional. The approximate name of the study.             |

### Output 

Returns a list containing `total_records` and a `studies` array. 
* `total_records` reflects the count of all studies, which the user has access to, and matching the search pattern (if provided). 
* Each study includes `name`, `uuid`, and an `environments` array. 
* Each environment includes `name` and `uuid`.

### datasets()

### Description

Get all datasets for a study environment.

### Usage

```r
datasets(study_environment_uuid = study_environment_uuid, search_dataset_name = "")
```

### Arguments

| Argument                   | Description                                                                                             |
| :------------------------- | :------------------------------------------------------------------------------------------------------ |
| **study_uuid**             | Optional. Unique iMedidata study identifier. You can find this in iMedidata’s Developer Info details. If provided, it is cross-checked against the _study_environment_uuid_ and _dataset_uuid_ provided. |
| **study_environment_uuid** | Unique iMedidata study environment identifier. You can find this in iMedidata’s Developer Info details. |
| **search_dataset_name**    | Optional. The approximate name of the dataset.                                                          |
| **page**                   | Optional. Page number for paginated results. Default: 1.                                                |
| **page_size**              | Optional. Number of results per page. Default: 50.                                                      |

### Output 

Returns a list containing `total_records` (total datasets available across all pages), `pagination` and `datasets` array.

### dataset_versions()

### Description

Get all the versions of a dataset

### Usage

```r
dataset_versions(dataset_uuid = dataset_uuid)
```

### Arguments

| Argument         | Description                                                                                 |
| :-------         | :------------------------------------------------------------------------------------------ |
| **study_uuid**             | Optional. Unique iMedidata study identifier. You can find this in iMedidata’s Developer Info details. If provided, it is cross-checked against the _dataset_uuid_ provided. |
| **study_environment_uuid** | Optional. Unique iMedidata study environment identifier. You can find this in iMedidata’s Developer Info details. If provided, it is cross-checked against the _dataset_uuid_ provided. |
| **dataset_uuid** | Unique iMedidata dataset identifier. This is available in the output of datasets() function |

### Output 

Returns all available versions of the dataset.

### fetch_data()

### Description

Get a single dataset.

### Usage

```r
fetch_data(dataset_uuid = dataset_uuid)
```

### Arguments

| Argument | Description |
| :------- | :---------- |
| **study_uuid**             | Optional. Unique iMedidata study identifier. You can find this in iMedidata’s Developer Info details. If provided, it is cross-checked against the _dataset_uuid_ provided. |
| **study_environment_uuid** | Optional. Unique iMedidata study environment identifier. You can find this in iMedidata’s Developer Info details. If provided, it is cross-checked against the _dataset_uuid_ provided. |
| **dataset_uuid** | Unique iMedidata dataset identifier. This is available in the output of datasets() and dataset_versions() functions |

### Output 

Returns data from a specific dataset.

### dry_publish()

### Description

Check if the publication results meet validation requirements.


### Usage

```r
dry_publish(project_token, dataset_name, key_columns, source_datasets, data, datetime_formats = NULL)
```

### Arguments 

| Argument             | Description |
|:---------------------| :---------- |
| **project_token**    | You can generate this from the Data Connect > Transformations > Custom Code project type. This is the new name of the resulting dataset created from R IDE |
| **dataset_name**     | Data Connect expects the dataset name to be unique within the study |
| **key_columns**      | List of columns that form the composite key that identifies each unique record in the data to be validated. Key columns must not contain null/missing values (for example, `NA`) in any row. |
| **source_datasets**  | List of source dataset unique identifiers (UUIDs) to be used to create the data being validated |
| **data**             | Data frame that needs to be validated |
| **datetime_formats** | Optional. The expected format for date or datetime fields in the data frame. This is used to validate that the date or datetime fields in the data frame are in the correct format before publishing to Data Connect. This should be NULL when none of the fields in the data frame are expected to be in date or datetime type.|

### Output 

Returns the result of publishing validations as a list containing clean, server-side data-quality metrics:
* **`valid_record_count`**: Number of records that will be successfully published to the dataset in Data Connect (always ≥ 0).
* **`duplicate_record_count`**: Number of records that are duplicate based on the key fields configured.
* **`invalid_record_count`**: Records erroring out data validations & will not be published to the dataset in Data Connect

When SDK validation fails, the returned error also includes _invalid_records:
* **`invalid_records`**: A table with all original input columns plus `_invalid_reason`.
* **`_invalid_reason`**: Comma-separated validation reasons in the format `column_name:reason`.
* One row is returned per invalid record, even when the record has multiple validation errors.
* The full `_invalid_records` table is accessible programmatically from the error object. 

#### Error codes in `_invalid_reason`

| Error Code          | Description                                                                                |
|:--------------------|:-------------------------------------------------------------------------------------------|
| **null_key_column** | A key column contains a null/missing value (`NA`) in this row.                             |
| **invalid_value**   | A column value is invalid. |

### Data Validations 

| Validations             | Description                                                                                                                                                                                                                                                                                                    |
|:---------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Invalid Input**    | Required argument is missing                                                                                                                                                                                                                                                                                   |
| **project_token**     | 1. Project Token is valid and generated from the Data Connect > Transformations > Custom Code project type. This is the new name of the resulting dataset created from R IDE <br>2. More than one dataset cannot be published into a project<br>3. Only the project owner can publish datasets into a project. |
| **dataset_name**     | Maximum length of 15 characters and must only contain alphanumeric characters and underscores                                                                                                                                                                                                           |
| **key_columns** | 1. Key columns are valid column names from the data frame being published <br>2. Key columns must not contain null/missing values (for example, `NA`) in any row<br>                |
| **source_datasets**  | 1. Source Dataset is a valid dataset UUID <br>2. Source Dataset is from the same study environment.                                                                                                                                                                                                            |
| **data**             | Invalid column name '{column.name}', it must only contain alphanumeric characters and underscores, with a maximum length of 20 characters.                                                                                                                                                                     |
| **datetime_formats** | 1. Date or Date time format is not from the acceptable list of formats <br> 2. Date/Datetime format cannot be provided for a field that is not parsed as a Date/DateTime field in data frame. <br>3. Date/datetime invalid-value validation is enforced for all configured date/datetime columns, including key and non-key columns.      |
| **validation failures** | Validation failures are returned in `_invalid_records` with one row per `invalid record` and merged `_invalid_reason` entries. Supported reasons include `null_key_column` and `invalid_value` (for non-parseable date/datetime values).
|

### Data Validation Failures
- When validation fails, the SDK returns the original data frame with an appended `error` column.
- Each invalid record appears once per error type (a row with multiple errors produces multiple result rows).
- Supported error names: `NULL_KEY` (null/empty value in key column), `INVALID_VALUE` (invalid value in key column).
- A summary is printed to the console for immediate visibility.
- The full invalid records table is accessible programmatically from the error object.

### publish()

### Description

Publish dataset to Data Connect.


### Usage

```r
publish(project_token, dataset_name, key_columns, source_datasets, data, datetime_formats = NULL)
```

### Arguments

| Argument             | Description |
|:---------------------| :---------- |
| **project_token**    | You can generate this from the Data Connect > Transformations > Custom Code project type |
| **dataset_name**     | This is the new name of the resulting dataset being created from R IDE. Data Connect expects the dataset name to be unique within the study |
| **key_columns**      | List of columns that form the composite key that identifies each unique record. Rows with null/missing values (for example, NA) are flagged as invalid. Key fields are mandatory, they cannot be omitted.|
| **source_datasets**  | List of source dataset UUIDs within the study environment where the dataset is published and used to create the data that is being published |
| **data**             | Data frame which needs to be published |
| **datetime_formats** | Optional. The expected format for datetime fields in the data frame. This is used to validate that datetime fields in the data frame are in the correct format before publishing to Data Connect. This should be NULL when none of the fields in the data frame are expected to be in date or datetime type.|


### Output 

Returns the status of publish as a list containing the final backend execution results:
* **`valid_record_count`**: Number of records that will be successfully published to the dataset in Data Connect
* **`duplicate_record_count`**: Number of records that are duplicate based on the key fields configured
* **`invalid_record_count`**: Records erroring out data validations & will not be published to the dataset in Data Connect
* **`invalid_records`**: A table with all original input columns plus `_invalid_reason`
* **`_invalid_reason`**:  Comma-separated validation reasons in the format `column_name:reason`
* One row is returned per invalid record, even when the record has multiple validation errors
* The full `_invalid_records` table is accessible programmatically from the error object

#### Error codes in `_invalid_reason`

| Error Code          | Description                                                    |
|:--------------------|:---------------------------------------------------------------|
| **null_key_column** | A key column contains a null/missing value (`NA`) in this row. |
| **invalid_value**   | A column value is invalid.                                 |

### Data Validations 

| Validations             | Description                                                                                                                                                                                                                                                                                                    |
|:---------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Invalid Input**    | Required argument is missing                                                                                                                                                                                                                                                                                   |
| **project_token**     | 1. Project Token is valid and generated from the Data Connect > Transformations > Custom Code project type. This is the new name of the resulting dataset created from R IDE <br>2. More than one dataset cannot be published into a project<br>3. Only the project owner can publish datasets into a project. |
| **dataset_name**     | Maximum length of 15 characters and must only contain alphanumeric characters and underscores                                                                                                                                                                                                                  |
| **key_columns**      | 1. Key columns are valid column names from the data frame being published <br>2. Key columns must not contain null/missing values (for example, `NA`) in any row<br> 3. Maps directly to the server-side metrics payload: `valid_record_count`, `duplicate_record_count`, and `invalid_record_count` without double-penalizing overlapping row states.                                                 |
| **source_datasets**  | 1. Source Dataset is a valid dataset UUID <br>2. Source Dataset is from the same study environment.                                                                                                                                                                                                            |
| **data**             | Invalid column name '{column.name}', it must only contain alphanumeric characters and underscores, with a maximum length of 20 characters.                                                                                                                                                                     |
| **datetime_formats** | 1. Date or Date time format is not from the acceptable list of formats <br> 2. Date/Datetime format cannot be provided for a field that is not parsed as a Date/DateTime field in data frame. <br> 3. Date/datetime invalid-value validation is enforced for all configured date/datetime columns, including key and non-key columns. |

### Data Validation Failures
- When validation fails, the SDK returns the original data frame with an appended `error` column.
- Each invalid record appears once per error type (a row with multiple errors produces multiple result rows).
- Supported error names: `NULL_KEY` (null/empty value in key column), `INVALID_VALUE` (invalid value in key column).
- A summary is printed to the console for immediate visibility.
- The full invalid records table is accessible programmatically from the error object.

### collect()

### Description

Execute the query and materialize full results as a data frame in R.

### **Usage**

```r
df %>% collect()
```

### head(n)

### Description

Limit the result of a dataframe to first n rows.

### Usage

```r
df %>% head(n=10)
```

### Arguments

| Argument | Description |
| :---- | :---- |
| **n** | The first number of rows will be retrieved. Default: n=6 |


## Errors

R Library raises exceptions for many reasons, such as invalid parameters, authentication errors, and validation failures. We have introduced error codes for each category of errors to be handled programmatically. 

| Error Code | Type | Scenario                                                                                                                                                                             |
| :---------- | :-------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| AUTHZ_001	| Authorization	| Authorization service check failed | 
| VAL_002	| Validation- Page Number	| Page number is not a positive integer 
| VAL_003	| Validation- Page Size	| Page size is out of range [1, 100] 
| VAL_004	| Validation- Study Parameter	| Invalid study uuid
| VAL_005	| Validation- Study Environment Parameter	| Missing or invalid study environment uuid 
| VAL_006	| Validation- Dataset Parameter	| Invalid dataset uuid
| VAL_007	| Validation- Configuration Error	| Required input parameters are missing or invalid in configuration  
| VAL_008	| Validation- Project Token	| Invalid project token 
| VAL_009	| Validation- Unsupported Data Type	| Unsupported data types.
| VAL_010	| Validation- Unsupported Data Type	| Unsupported datetime formats.
| VAL_011	| Validation- Pagination	| Pagination is out of range
| VAL_012	| Validation- Concurrency	| Project actively being published
| VAL_013	| Validation- Formatting Error	| Data validation failed. One or more records contain formatting errors.
| RES_002	| Resource Exceptions- Study Environment  	| No authorized Study Environments found for the authenticated user
| RES_003	| Resource Exceptions- Invalid parameter | Incorrect UUID combination. 
| RES_004	| Resource Exceptions- Invalid parameter 	| Incorrect UUID combination.
| RES_005	| Resource Exceptions- Study Group |  Study Group not found for the Dataset's Study Environment. 
| RES_006	| Resource Exceptions- Study |	Study Group not found for the Dataset's Study Environment.
| RES_007	| Resource Exceptions- Client Division | 	Client Division not found for the Dataset's Study Environment.
| RES_008	| Resource Exceptions- Custom Code Project | Transformation Project is not found. 
| INT_001	| Internal Application Exception	 | Something went wrong on our end. 



## Acceptable Data Types and Formats

The below table provides the supported R column types of Data Connect R library and their representation in Medidata Data Connect.

**Note**: If a data type and format do not appear, it is possible that Data Connect R Library will not accept the result when publishing back into Medidata Data Connect. To ensure compatibility, convert the data type in your R data frame to support the R data type below.

| R&nbsp;Data&nbsp;Type | R Example | Data Connect Data Type                                                                                                                                                                         |
| :---------- | :-------- |:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **integer** | as.integer(c(1L, 2L)) | INTEGER                                                                                                                                                                                        |
| **numeric**  | as.numeric(c(1.23, 2.2)) | FLOAT<br/> **Note**: R does not store decimal places, and as a result, the supported FLOAT numeric format will persist 5 decimal places in Medidata Data Connect regardless of the value.      |
| **character** | c("str1", "str2") | STRING                                                                                                                                                                                         |
| **Date** | as.Date(c("2020-01-01", "2020-01-02")) | DATE<br/> **Note**: To successfully publish a dataset, you must specify a format for date columns using the [Supported Date and Time Formats list](DATETIME_SUPPORTED_FORMATS.md)<br/>         |
| **POSIX.ct** | as.POSIXct(c("2020-01-01 12:00:00", "2020-01-02 13:00:00"), tz \= "UTC") | DATETIME<br/> **Note**: To successfully publish a dataset, you must specify a format for date-time columns using the [Supported Date and Time Formats list](DATETIME_SUPPORTED_FORMATS.md)     |
| **logical** | c(TRUE, FALSE) | BOOLEAN<br/> **Note**: This data type is not fully compatible with Medidata Data Surveillance numeric KRI capability. To ensure compatibility, convert to integer type.                        |
| **integer** | bit64::as.integer64(c(1, 2)) | LONG                                                                                                                                                                                           |


# Reporting known issues

If you believe you have found an issue, please contact Medidata Support by submitting a ticket to Medidata Support. All issue reports should include a minimal reproducible example to ensure our team can diagnose the issue.

Additionally, all known issues are available [here](https://learn.medidata.com/en-US/bundle/current-issues/page/current_known_issues_for_data_connect.html).

# Backend

This library uses the Arrow open source library and the Iceberg open table format to enable data interoperability across platforms.

* [Apache arrow](https://arrow.apache.org/docs/r/): This library uses Arrow’s highly efficient format [pyarrow](https://arrow.apache.org/cookbook/py/flight.html) to transfer massive datasets over the network, allowing users to access & interact with remote datasets.  
    
* [Apache Iceberg](https://iceberg.apache.org/): This is the open table format underlying Medidata Data Connect's structured data management to support high-performance and reliable data analytics and storage.

# Versions

For a list of historical versions of this library and their details, see the [Data Connect Release Notes](https://learn.medidata.com/en-US/bundle/data-connect/page/data_connect_release_notes.html).

## Installing Specific Versions

**Important:** Always specify the version using the `ref` parameter to ensure you install a stable release:

```r
# Install latest stable release (v1.2.0)
devtools::install_github(
  repo = "mdsol/dataconnect-library-r", 
  ref = "v1.2.0",
  build_vignettes = TRUE, 
  upgrade = FALSE)
```

⚠️ **Note:** Installing without the `ref` parameter will install from the `main` branch, which may contain unreleased development code. Always use a version tag for production environments.

To verify the version currently installed in your environment, use the following:

```r
packageVersion("dataconnect")
```

# Licensing

BY DOWNLOADING THIS FILE (“DOWNLOAD”) YOU AGREE TO THE FOLLOWING TERMS:  
MEDIDATA SOLUTIONS, INC. AND ITS AFFILIATES (COLLECTIVELY “MEDIDATA”) GRANT A FREE OF CHARGE, NON-EXCLUSIVE AND NON-TRANSFERABLE RIGHT TO USE THE DOWNLOAD. USE OF THIS DOWNLOAD IS PERMITTED FOR INTERNAL BUSINESS PURPOSES ONLY.   
   
THIS DOWNLOAD IS MADE AVAILABLE ON AN "AS IS" BASIS WITHOUT WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, ORAL OR WRITTEN, INCLUDING, WITHOUT LIMITATION, ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE OR NON-INFRINGEMENT.  
   
MEDIDATA SHALL HAVE NO LIABILITY FOR DIRECT, INDIRECT, INCIDENTAL, CONSEQUENTIAL OR PUNITIVE DAMAGES, INCLUDING, WITHOUT LIMITATION, CLAIMS FOR LOST PROFITS, BUSINESS INTERRUPTION AND LOSS OF DATA THAT IN ANY WAY RELATE TO THIS DOWNLOAD, WHETHER OR NOT MEDIDATA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES AND NOTWITHSTANDING THE FAILURE OF THE ESSENTIAL PURPOSE OF ANY REMEDY.  
   
YOUR USE OF THIS DOWNLOAD SHALL BE AT YOUR SOLE RISK. NO SUPPORT OF ANY KIND OF THE DOWNLOAD IS PROVIDED BY MEDIDATA.

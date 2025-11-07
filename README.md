# Medidata DataConnect R library

# Overview

This library is built by Medidata to provide technical users of the Medidata Clinical Data Studio and of Medidata Data Connect – including clinical programmers, data scientists, and statisticians –  a connection to relevant data within their own existing R IDE. You can use this library  with base R functions and other libraries developed for R.

**Note:** This R library is only compatible with R Studio. We do not guarantee or provide support for other R IDEs.

To use this library, you must have a valid iMedidata account and access to required building blocks in the Medidata Platform. For details, see the Medidata [Knowledge Hub](https://learn.medidata.com/en-US/bundle/data-connect/page/developer_center.html).

- [Installation](#installation)
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

publish(
  project_token = my_project_token,
  dataset_name = my_dataset_name,
  key_columns = my_key_columns,
  source_datasets = source_datasets,
  data = sample_data)
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

|    Argument  | Description |
|:-------------| :---------- |
| **url**      | Server URL. Default url="enodia-gateway.platform.imedidata.com" |
| **port**     | Server port. Default port="443" |
| **use_tls**  | Denotes whether to use TLS. Default use_tl=="TRUE" |
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

### datasets()

### Description

Get all datasets for a study environment

### Usage

```r
datasets(study_uuid, study_environment_uuid, search_dataset_name = "")
```

### Arguments

| Argument | Description |
| :------- | :---------- |
| **study_uuid** | Unique iMedidata study environment identifier. You can find this in iMedidata’s Developer Info details |
| **study_environment_uuid** | Unique iMedidata study environment identifier. You can find this in iMedidata’s Developer Info details |
| **search_dataset_name** | Optional. The approximate name of the dataset |

### Output 

Returns all datasets in the given study and study environment and the dataset name if provided. 

### dataset_versions()

### Description

Get all the versions of a dataset

### Usage

```r
dataset_versions(study_uuid, study_environment_uuid, dataset_uuid)
```

### Arguments

| Argument | Description |
| :------- | :---------- |
| **study_uuid** | Unique iMedidata study identifier. This is available in iMedidata developer info and in the output of datasets() function |
| **study_environment_uuid** | Unique iMedidata study environment identifier. You can find this in iMedidata’s Developer Info details and in the output of datasets() function |
| **dataset_uuid** | Unique iMedidata dataset identifier. This is available in the output of datasets() function |

### Output 

Returns all available versions of the dataset.

### fetch_data()

### Description

Get a single dataset.

### Usage

```r
fetch_data(study_uuid, study_environment_uuid, dataset_uuid)
```

### Arguments

| Argument | Description |
| :------- | :---------- |
| **study_uuid** | Unique iMedidata study identifier. You can find this in iMedidata’s Developer Info details, and in the output of datasets() and dataset_versions() functions |
| **study_environment_uuid** | Unique iMedidata study environment identifier. You can find this in iMedidata’s Developer Info details and in the output of the datasets() and dataset_versions() functions |
| **dataset_uuid** | Unique iMedidata dataset identifier. This is available in the output of datasets() and dataset_versions() functions |

### Output 

Returns data from a specific dataset.

### dry_publish()

### Description

Check if the publication results meet validation requirements.

### Usage

```r
dry_publish(project_token, dataset_name, key_columns, source_datasets, data)
```

### Arguments 

| Argument | Description |
| :------- | :---------- |
| **project_token** | You can generate this from the Data Connect > Transformations > Custom Code project type. This is the new name of the resulting dataset created from R IDE |
| **dataset_name** | Data Connect expects the dataset name to be unique within the study |
| **key_columns** | List of columns that form the composite key that identifies each unique record in the data to be validated |
| **source_datasets** | List of source dataset unique identifiers (UUIDs) to be used to create the data being validated |
| **data** | Data frame that needs to be validated |

### Output 

Returns the result of publishing validations. After successful validation testing, you can expect a successful publication into Data Connect with the publish() function.

### Error Messages & Actions

| Error Message | Action |
| :------------ | :----- |
| **invalid input_config passed** | Required argument is missing input; make any required adjustment |
| **invalid dataset_name in input_config, dataset_name must only contain alphanumeric characters and underscores, with a maximum length of 15 characters** | Adjust the dataset_name. |
| **invalid study_environment_uuid or user doesn't have access to the study_environment_uuid** | Verify that</br> - The study_environment_uuid is correct.</br> - You have access to that study environment.</br> - The project token being used is in this study environment.|
| **The source dataset does not exist** | Ensure that the source dataset is in the study environment where you intend to publish the dataset. The system does not support the ability to publish a dataset from one study environment to another study environment. |
| **Error parsing dataset_uuid** | The dataset_uuid is not a valid UUID. Review and provide the correct dataset_uuid. |
| **Error in validating source dataset** | If the following error messages are not present, please contact Medidata Support, otherwise, address the error messages:</br> **- Error parsing dataset_uuid**</br> **- The source dataset does not exist**|
| **invalid schema passed** | Contact Medidata Support. |
| **Unsupported field type and format for '{field.name}'. Please refer to the readme file for supported data types and formats.** | Convert the column data type in the dataset or dataframe that is being published to a supported field type. Currently supported R field types are logical, integer, numeric, character, Date, and  POSIXct. For details, see  [here](#acceptable-data-types-and-formats). |
| **Invalid column name ‘{column.name}’, it must only contain alphanumeric characters and underscores, with a maximum length of 20 characters.** | Adjust the column name in the dataset or dataframe that is being published. |
| **Invalid key_columns passed, all key_columns must be part of the schema.** | Update the column name in the key_column argument. The key columns should exist in the dataset or dataframe that is being published. |

### publish()

### Description

Publish dataset to Data Connect.

### Usage

```r
publish(project_token, dataset_name, key_columns, source_datasets, data)
```

### Arguments

| Argument | Description |
| :------- | :---------- |
| **project_token** | You can generate this from the Data Connect > Transformations > Custom Code project type |
| **dataset_name** | This is the new name of the resulting dataset being created from R IDE. Data Connect expects the dataset name to be unique within the study |
| **key_columns** | List of columns that form the composite key that identifies each unique record in the data that is being published |
| **source_datasets** | List of source dataset UUIDs within the study environment where the dataset is published and used to create the data that is being published |
| **data** | Data frame which needs to be published |

### Output 

Returns the status of publish. When the dataset is published successfully, you can access it in Medidata Data Connect for further use.

### Error Messages & Actions

| Error Message | Action |
| :------------ | :----- |
| **Authentication failed** | Ensure you provide the correct user token and project token. You must have access to the Developer Center, iMedidata, and the specific study environment. The project token must be from the Custom Code project you created, and the user token must be valid and generated from the user Key Management page in Data Connect > Developer Center. |
| **You are not authorized to perform this action** | Ensure that you provide the correct user token and project. You must have access to the Developer Center, iMedidata, and the specific study environment. The project token must be from the Custom Code project you created, and the user token must be valid and generated from the user Key Management page in Data Connect > Developer Center. |
| **Invalid input_config passed** | Required argument is missing. Make required adjustment. |
| **Invalid dataset_name in input_config, dataset_name must only contain alphanumeric characters and underscores, with a maximum length of 15 characters** | Adjust the dataset_name. |
| **Invalid study_environment_uuid or user doesn't have access to the study_environment_uuid** |Verify that:</br> - The study_environment_uuid is correct. </br> - You have access to that study environment.</br> - The project token being used is in this study environment.|
| **The source dataset does not exist** | Ensure the source dataset is in the study environment where the dataset is intended to publish to. The system does not support publishing a dataset from one study environment to another study environment.  |
| **Error parsing dataset uuid** | The dataset_uuid is not a valid uuid. Review and provide the correct dataset_uuid. |
| **Error in validating source dataset** | If the following error messages are not present, please contact Medidata Support, otherwise, address the error messages:</br> **- Error parsing dataset_uuid**</br> **- The source dataset does not exist** |
| **Schema is not valid** | Please contact Medidata Support. |
| **Error occurred while publishing data** | Verify that the dataset that is being published passes the validation requirement in **dry_publish()**, and that you use the same arguments input in **publish()**. If the error message persists, please contact Medidata Support. |

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

## Acceptable Data Types and Formats

The below table provides the supported R column types of Data Connect R library and their representation in Medidata Data Connect.

**Note**: If a data type and format do not appear, it is possible that Data Connect R Library will not accept the result when publishing back into Medidata Data Connect. To ensure compatibility, convert the data type in your R data frame to support the R data type below.

| R&nbsp;Data&nbsp;Type | R Example | Data Connect Data Type |
| :---------- | :-------- | :--------------------- |
| **integer** | as.integer(c(1L, 2L)) | INTEGER |
| **numeric**  | as.numeric(c(1.23, 2.2)) | FLOAT<br/> **Note**: R does not store decimal places, and as a result, the supported FLOAT numeric format will persist 5 decimal places in Medidata Data Connect regardless of the value. |
| **character** | c("str1", "str2") | STRING |
| **Date** | as.Date(c("2020-01-01", "2020-01-02")) | DATE<br/> **Note**: R does not store data format, and as a result, the supported date type column will be converted to the **yyyy-MM-dd** format when publishing back to Medidata Data Connect.|
| **POSIX.ct** | as.POSIXct(c("2020-01-01 12:00:00", "2020-01-02 13:00:00"), tz \= "UTC") | DATETIME<br/> **Note**:  R does not store data format, and as a result, the supported POSIX.ct type column will be converted to **yyyy-MM-dd HH:mm:ss:SSS** format. |
| **logical** | c(TRUE, FALSE) | BOOLEAN<br/> **Note**: This data type is not fully compatible with Medidata Data Surveillance numeric KRI capability. To ensure compatibility, convert to integer type. |
| **integer** | bit64::as.integer64(c(1, 2)) | LONG |


# Reporting known issues

If you believe you have found an issue, please contact Medidata Support by submitting a ticket to Medidata Support. All issue reports should include a minimal reproducible example to ensure our team can diagnose the issue.

Additionally, all known issues are available [here](https://learn.medidata.com/en-US/bundle/current-issues/page/current_known_issues_for_data_connect.html).

# Backend

This library uses the Arrow open source library and the Iceberg open table format to enable data interoperability across platforms.

* [Apache arrow](https://arrow.apache.org/docs/r/): This library uses Arrow’s highly efficient format [pyarrow](https://arrow.apache.org/cookbook/py/flight.html) to transfer massive datasets over the network, allowing users to access & interact with remote datasets.  
    
* [Apache Iceberg](https://iceberg.apache.org/): This is the open table format underlying Medidata Data Connect's structured data management to support high-performance and reliable data analytics and storage.

# Versions

For a list of historical versions of this library and their details, see the [Data Connect Release Notes](https://learn.medidata.com/en-US/bundle/data-connect/page/data_connect_release_notes.html).    
To verify the version currently installed in your environment, use the following

```r
packageVersion("dataconnect")
```

# Licensing

BY DOWNLOADING THIS FILE (“DOWNLOAD”) YOU AGREE TO THE FOLLOWING TERMS:  
MEDIDATA SOLUTIONS, INC. AND ITS AFFILIATES (COLLECTIVELY “MEDIDATA”) GRANT A FREE OF CHARGE, NON-EXCLUSIVE AND NON-TRANSFERABLE RIGHT TO USE THE DOWNLOAD. USE OF THIS DOWNLOAD IS PERMITTED FOR INTERNAL BUSINESS PURPOSES ONLY.   
   
THIS DOWNLOAD IS MADE AVAILABLE ON AN "AS IS" BASIS WITHOUT WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, ORAL OR WRITTEN, INCLUDING, WITHOUT LIMITATION, ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE OR NON-INFRINGEMENT.  
   
MEDIDATA SHALL HAVE NO LIABILITY FOR DIRECT, INDIRECT, INCIDENTAL, CONSEQUENTIAL OR PUNITIVE DAMAGES, INCLUDING, WITHOUT LIMITATION, CLAIMS FOR LOST PROFITS, BUSINESS INTERRUPTION AND LOSS OF DATA THAT IN ANY WAY RELATE TO THIS DOWNLOAD, WHETHER OR NOT MEDIDATA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES AND NOTWITHSTANDING THE FAILURE OF THE ESSENTIAL PURPOSE OF ANY REMEDY.  
   
YOUR USE OF THIS DOWNLOAD SHALL BE AT YOUR SOLE RISK. NO SUPPORT OF ANY KIND OF THE DOWNLOAD IS PROVIDED BY MEDIDATA.

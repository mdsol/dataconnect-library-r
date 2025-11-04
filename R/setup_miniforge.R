#' Install Miniforge and Create a Conda Environment for R Integration
#'
#' This function automates the installation of Miniforge (a minimal conda installer) for the current operating system and architecture,
#' and sets up a conda environment with the specified name and Python version. 
#' Package `pyarrow` is installed via pip for full Flight support. 
#' The function checks for existing installations and environments to avoid redundant setup.
#'
#' @param env_name Character. Name of the conda environment to create or use. Default is `"dataconnect-library-r"`.
#' @param python_version Character. Python version to install in the environment. Default is `"3.13"`.
#' @param remove_existing_env Logical. If TRUE, removes the existing environment with the same name before creating a new one. Default is FALSE.
#'
#' @details
#' - Automatically detects OS and architecture to select the correct Miniforge installer.
#' - Installs Miniforge in the user's home directory under `miniforge3`.
#' - Creates a conda environment with the specified Python version and required packages.
#' - Uses the `conda-forge` channel for package installation.
#' - Skips installation or environment creation if already present.
#'
#' @return (Invisibly) A named list with the following elements:
#'   \describe{
#'     \item{miniforge_root}{Character. Path to the Miniforge installation directory.}
#'     \item{conda_bin}{Character. Path to the conda executable.}
#'     \item{env_path}{Character. Path to the created conda environment.}
#'   }
#'
#' @note
#' After creating a new environment, you may need to restart your R session before using it.
#'
#' @examples
#' \dontrun{
#' install_miniforge()
#' }
#'
#' @export
install_miniforge <- function(env_name = "dataconnect-library-r", python_version = "3.13", remove_existing_env = FALSE) {
    
    home_dir <- if (.Platform$OS.type == "windows") {
        Sys.getenv("USERPROFILE", unset = "~")
    } else {
        Sys.getenv("HOME", unset = "~")
    }
    miniforge_root <- normalizePath(file.path(home_dir, "miniforge3"), winslash = "/", mustWork = FALSE)
    conda_channel = "conda-forge"

    sysinfo <- Sys.info()
    
    sysname <- tolower(if (!is.null(sysinfo) && !is.na(sysinfo["sysname"])) sysinfo["sysname"] else "")
    r_os <- tolower(if (!is.null(R.version$os) && !is.na(R.version$os)) R.version$os else "")
    machine <- tolower(sysinfo["machine"])

    is_windows <- .Platform$OS.type == "windows"
    is_mac <- grepl("darwin", sysname) || grepl("darwin", r_os)
    is_linux <- grepl("linux", sysname) || grepl("linux", r_os)

    asset <- NULL
    if (is_windows) {
        if (grepl("64", machine)) {
            asset <- "Miniforge3-Windows-x86_64.exe"
        } else {
            stop("Miniforge installation on 32-bit Windows is not supported.")
        }
    } else if (is_mac) {
        if (grepl("arm64", machine) || grepl("aarch64", machine)) {
            asset <- "Miniforge3-MacOSX-arm64.sh"
        } else if (grepl("x86_64", machine) || grepl("amd64", machine)) {
            asset <- "Miniforge3-MacOSX-x86_64.sh"
        } else {
            stop("Unsupported Mac architecture for Miniforge installation.")
        }
    } else if (is_linux) {
        if (grepl("x86_64", machine) || grepl("amd64", machine)) {
            asset <- "Miniforge3-Linux-x86_64.sh"
        } else if (grepl("aarch64", machine) || grepl("arm64", machine)) {
            asset <- "Miniforge3-Linux-aarch64.sh"
        } else if (grepl("ppc64le", machine)) {
            asset <- "Miniforge3-Linux-ppc64le.sh"
        } else {
            stop("Unsupported Linux architecture for Miniforge installation.")
        }
    } else {
        stop("Unsupported operating system for Miniforge installation.")
    }

    installer_url <- sprintf("https://github.com/conda-forge/miniforge/releases/latest/download/%s", asset)
    
    conda_bin <- if (is_windows) {
        file.path(miniforge_root, "Scripts", "conda.exe")
    } else {
        file.path(miniforge_root, "bin", "conda")
    }

    if (!file.exists(conda_bin)) {
        message("Downloading miniforge installer: ", installer_url, " and installing to ", miniforge_root)
        temp_file <- tempfile(fileext = if (is_windows) ".exe" else ".sh")
        utils::download.file(installer_url, temp_file, mode = "wb", quiet = FALSE)
        
        if (is_windows) {
            message("Running Windows installer...")
            res <- system2(normalizePath(temp_file, winslash = "\\"), args = c("/S", sprintf("/D=%s", normalizePath(miniforge_root, winslash = "\\"))), wait = TRUE)
            if (res != 0) {
                stop("Miniforge installation failed with exit code ", res)
            }
        } else {
            Sys.chmod(temp_file, mode = "0755")
            message("Running installer...")
            res <- system2("bash", args = c(shQuote(normalizePath(temp_file)), "-b", "-p", shQuote(miniforge_root)), wait = TRUE)
            if (res != 0) {
                stop("Miniforge installation failed with exit code ", res)
            }
        }

        message("Miniforge installed successfully at ", miniforge_root)
        
        unlink(temp_file)
    } else {
        message("Miniforge is already installed at ", miniforge_root)
    }

    if (!file.exists(conda_bin)) {
        stop("Conda executable not found at expected location: ", conda_bin)
    }
    
    envpath <- normalizePath(file.path(miniforge_root, "envs", env_name), winslash = "/", mustWork = FALSE)

    # Remove existing environment if requested
    conda_envs <- suppressWarnings(system2(conda_bin, args = c("env", "list"), stdout = TRUE, stderr = TRUE))
    env_exists <- any(grepl(sprintf("^%s\\s", env_name), conda_envs))
    if (env_exists && isTRUE(remove_existing_env)) {
        message("Removing existing conda environment '", env_name, "' at ", envpath)
        conda_args_remove <- c("env", "remove", "-y", "-n", env_name)
        if (is_windows) {
            res_rm <- system2(normalizePath(conda_bin, winslash = "\\"), args = conda_args_remove, wait = TRUE)
        } else {
            res_rm <- system2(conda_bin, args = conda_args_remove, wait = TRUE)
        }
        if (res_rm != 0) {
            stop("Failed to remove conda environment '", env_name, "' with exit code ", res_rm)
        }
        message("Conda environment '", env_name, "' removed successfully.")
    }

    # Recompute envpath in case it was removed
    conda_envs <- suppressWarnings(system2(conda_bin, args = c("env", "list"), stdout = TRUE, stderr = TRUE))
    env_exists <- any(grepl(sprintf("^%s\\s", env_name), conda_envs))

    if (env_exists) {
        message("Conda environment '", env_name, "' already exists at ", envpath)
    } else {
        message("Creating conda environment '", env_name, "' with Python '", python_version, "'. This may take a few minutes...")
        
        conda_args <- c("create", "-y", "-n", env_name, paste0("python=", python_version), "-c", conda_channel, "--override-channels")

        if (is_windows) {
            res2 <- system2(normalizePath(conda_bin, winslash = "\\"), args = conda_args, wait = TRUE)
        } else {
            res2 <- system2(conda_bin, args = conda_args, wait = TRUE)
        }

        if (res2 != 0) {
            stop("Failed to create conda environment '", env_name, "' with exit code ", res2)
        }

        message("Conda environment '", env_name, "' created successfully at ", envpath)

        message("Installing R package 'base64enc' from CRAN...")
        tryCatch({
            utils::install.packages("base64enc", repos = "https://cloud.r-project.org/", quiet = TRUE)
            message("R package 'base64enc' installed successfully.")
        }, error = function(e) {
            warning("Failed to install R package 'base64enc': ", e$message, ". You may need to install it manually with install.packages('base64enc').")
        })

        message("Installing pyarrow via pip for full Flight support...")
        python_bin <- if (is_windows) {
            file.path(envpath, "python.exe")
        } else {
            file.path(envpath, "bin", "python")
        }
        pip_args <- c("-m", "pip", "install", "--upgrade", "pyarrow")
        res_pip <- system2(python_bin, args = pip_args, wait = TRUE)
        if (res_pip != 0) {
            warning("pip install pyarrow failed with exit code ", res_pip, ". You may need to install pyarrow manually in the environment, restart your R session and call use_miniforge_env().")
        } else {
            message("pyarrow installed via pip for Flight support.")
            message("\nIMPORTANT: Please add the following to your .Rprofile or run manually every time, as soon as R Studio session is restarted.\n")

            message(sprintf("Sys.setenv(RETICULATE_MINICONDA_PATH = '%s')", normalizePath(miniforge_root, winslash = "/")))
            message(sprintf("Sys.setenv(RETICULATE_PYTHON = '%s')", python_bin))
            message("has_pyarrow <- reticulate::py_module_available('pyarrow')\n")

            message("\nIMPORTANT: Please restart your R session now, before calling use_miniforge_env().\n")
        }
    }

    invisible(list(miniforge_root = miniforge_root, conda_bin = conda_bin, env_path = envpath))
}

#' Activate a Miniforge conda environment for use.
#'
#' This function checks for the existence of a Miniforge installation and a specified conda environment,
#' verifies the presence of Python and required packages and 
#' activates a Miniforge conda environment for use with reticulate.
#'
#' @param env_name Character. Name of the conda environment to use. Defaults to "dataconnect-library-r".
#'
#' @return (Invisibly) A named list with the following elements:
#'   \describe{
#'     \item{miniforge_root}{Character. Path to the Miniforge installation directory.}
#'     \item{conda_bin}{Character. Path to the conda executable.}
#'     \item{env_path}{Character. Path to the created conda environment.}
#'   }
#'
#' @details
#' - Verifies Miniforge installation and the specified conda environment.
#' - Checks for the Python executable within the environment.
#' - Ensures the 'reticulate' R package is installed.
#' - Activates the conda environment for reticulate.
#' - Confirms the 'pyarrow' Python package is available in the environment.
#'
#' @note
#' If any required component is missing, the function will stop with an informative error message.
#' It is recommended to restart the R session after installing Miniforge or the conda environment.
#'
#' For persistent use, add the following to your `.Rprofile`:
#' \preformatted{
#' Sys.setenv(RETICULATE_MINICONDA_PATH = "<miniforge_root>")
#' Sys.setenv(RETICULATE_PYTHON = "<python_bin>")
#' has_pyarrow <- reticulate::py_module_available('pyarrow')
#' }
#'
#' @examples
#' \dontrun{
#' use_miniforge_env()
#' }
#'
#' @export
use_miniforge_env <- function(env_name = "dataconnect-library-r") {
    home_dir <- if (.Platform$OS.type == "windows") {
        Sys.getenv("USERPROFILE", unset = "~")
    } else {
        Sys.getenv("HOME", unset = "~")
    }
    miniforge_root <- normalizePath(file.path(home_dir, "miniforge3"), winslash = "/", mustWork = FALSE)
    
    conda_bin <- if (.Platform$OS.type == "windows") {
        file.path(miniforge_root, "Scripts", "conda.exe")
    } else {
        file.path(miniforge_root, "bin", "conda")
    }
    
    if (!file.exists(conda_bin)) {
        stop("Conda executable not found at expected location: ", conda_bin, ". Please run install_miniforge() first.")
    }
    
    conda_envs <- suppressWarnings(system2(conda_bin, args = c("env", "list"), stdout = TRUE, stderr = TRUE))
    env_exists <- any(grepl(sprintf("^%s\\s", env_name), conda_envs))

    if (!env_exists) {
        stop("Conda environment '", env_name, "' does not exist. Please run install_miniforge() first.")
    }
    
    envpath <- normalizePath(file.path(miniforge_root, "envs", env_name), winslash = "/", mustWork = FALSE)
    python_bin <- if (.Platform$OS.type == "windows") {
        file.path(envpath, "python.exe")
    } else {
        file.path(envpath, "bin", "python")
    }

    if (!file.exists(python_bin)) {
        stop("Python executable not found in the conda environment at expected location: ", python_bin, ". Make sure the environment is set up correctly and you restarted R after installation.")
    }

    if (!requireNamespace("reticulate", quietly = TRUE)) {
        stop("The 'reticulate' package is required. Please install it with install.packages('reticulate'), restart R, and try again.")
    }

    used_condaenv <- FALSE
    try({
        reticulate::use_condaenv(env_name, conda = normalizePath(conda_bin, winslash = "/"), required = TRUE)   
        used_condaenv <- TRUE
    }, silent = TRUE)
    
    if (used_condaenv) {
        message("Using conda environment '", env_name, "' at ", envpath)

        if (reticulate::py_module_available("pyarrow") == FALSE) {
            stop("The 'pyarrow' Python package is not available in the conda environment. Please restart your R session, and call use_miniforge_env() again.")
        }
    } 
    else {
        stop("Failed to activate conda environment '", env_name, "'. Please ensure you restarted your R session before calling use_miniforge_env() again.")
    }

    invisible(list(miniforge_root = miniforge_root, conda_bin = conda_bin, env_path = envpath))
}

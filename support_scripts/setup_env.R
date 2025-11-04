# setup_env.R
# Installs R package dependencies and provides guidance for reticulate/conda setup.

# --- Configuration ---
# Set to TRUE to also install packages listed under 'Suggests' in DESCRIPTION
INSTALL_SUGGESTS <- FALSE
# Set the name of the target conda environment you expect users to have
TARGET_CONDA_ENV_NAME <- "dataconnect-library-r"
# Python version to use when creating the conda environment
PYTHON_VERSION <- "3.13"
# List of basic Python packages to install in the conda environment if arrow::install_py() isn't available
PYTHON_PACKAGES <- c("numpy", "pandas", "pyarrow")
# ---

# Define custom printing functions for better formatting
msg <- function(text, header = FALSE) {
  if (header) {
    cat("\n\033[1m", text, "\033[0m\n", sep = "")
    cat(paste(rep("-", nchar(text)), collapse = ""), "\n")
  } else {
    cat(text, "\n")
  }
}

success <- function(text) cat("\033[32m✓ ", text, "\033[0m\n", sep = "")
warn <- function(text) cat("\033[33m! ", text, "\033[0m\n", sep = "")
error <- function(text) cat("\033[31m✗ ", text, "\033[0m\n", sep = "")
code <- function(text) cat("  \033[36m", text, "\033[0m\n", sep = "")

# Pretty print for data frames
pretty_print_df <- function(df, max_rows = 10) {
  if (!is.data.frame(df) || nrow(df) == 0) return(invisible())

  # Limit rows if too many
  if (nrow(df) > max_rows) {
    df <- df[1:max_rows,]
    ellipsis <- TRUE
  } else {
    ellipsis <- FALSE
  }

  # Get column widths
  col_widths <- sapply(names(df), nchar)
  for (col in names(df)) {
    max_content_width <- max(nchar(as.character(df[[col]])))
    col_widths[col] <- max(col_widths[col], max_content_width)
  }

  # Print header
  header_line <- "  "
  for (i in seq_along(names(df))) {
    col <- names(df)[i]
    header_line <- paste0(header_line, sprintf("%-*s", col_widths[i] + 2, col))
  }
  cat(header_line, "\n")

  # Print separator
  sep_line <- "  "
  for (i in seq_along(names(df))) {
    sep_line <- paste0(sep_line, paste(rep("-", col_widths[i]), collapse = ""), "  ")
  }
  cat(sep_line, "\n")

  # Print rows
  for (r in 1:nrow(df)) {
    row_line <- "  "
    for (i in seq_along(names(df))) {
      col <- names(df)[i]
      row_line <- paste0(row_line, sprintf("%-*s", col_widths[i] + 2, as.character(df[r, i])))
    }
    cat(row_line, "\n")
  }

  if (ellipsis) {
    cat("  ...\n")
  }
}

# Start setup
msg("DataConnect Library Setup", header = TRUE)

# --- R Package Installation ---
msg("Installing R dependencies", header = TRUE)

# Ensure the 'remotes' package is installed
if (!requireNamespace("remotes", quietly = TRUE)) {
  msg("Installing 'remotes' package...")
  tryCatch({
    install.packages("remotes", repos = "https://cloud.r-project.org/")
    if (requireNamespace("remotes", quietly = TRUE)) {
      success("'remotes' installed successfully")
    } else {
      stop("'remotes' package installation failed.", call. = FALSE)
    }
  }, error = function(e) {
    error("Failed to install 'remotes'")
    error(e$message)
    stop("Cannot proceed without 'remotes'", call. = FALSE)
  })
} else {
  success("'remotes' package already installed")
}

if (.Platform$OS.type == "windows" && !requireNamespace("base64enc", quietly = TRUE)) {
  msg("Installing 'base64enc' package...")
  tryCatch({
    install.packages("base64enc", repos = "https://cloud.r-project.org/")
    if (requireNamespace("base64enc", quietly = TRUE)) {
      success("'base64enc' installed successfully")
    } else {
      stop("'base64enc' package installation failed.", call. = FALSE)
    }
  }, error = function(e) {
    error("Failed to install 'base64enc'")
    error(e$message)
    stop("Cannot proceed without 'base64enc'", call. = FALSE)
  })
} else {
  success("'base64enc' package already installed")
}

# Install dependencies from DESCRIPTION
msg("Installing package dependencies from DESCRIPTION...")
tryCatch({
  # Install Imports, Depends, LinkingTo
  remotes::install_deps(dependencies = TRUE, upgrade = "never") 
  
  if (INSTALL_SUGGESTS) {
    msg("Installing suggested R packages...")
    # Install Suggests
    remotes::install_deps(dependencies = "Suggests", upgrade = "never")
  }
  
  success("R dependencies installed successfully")
  
}, error = function(e) {
  error("Failed to install R package dependencies")
  error(e$message)
  stop("Cannot proceed with setup", call. = FALSE)
})

# --- Reticulate/Conda Guidance ---
msg("Configuring Python Environment", header = TRUE)

if (!requireNamespace("reticulate", quietly = TRUE)) {
  warn("'reticulate' package is not installed")
  msg("If your project needs Python integration, please add 'reticulate' to your DESCRIPTION file's Imports.")
} else {
  success("'reticulate' package is installed")

  # Attempt to find conda binary
  conda_path <- NULL
  tryCatch({
    conda_path <- reticulate::conda_binary()
    success(paste("Found conda at:", conda_path))
  }, error = function(e) {
    warn("Could not find conda binary")
    msg("Make sure Miniforge is installed and the 'conda' command is in your system PATH.")
  })

  if (!is.null(conda_path)) {
    msg("Checking conda environments...")
    tryCatch({
      conda_envs <- reticulate::conda_list(conda = conda_path)
      # Ensure conda_envs is a data frame and has a 'name' column
      if (is.data.frame(conda_envs) && "name" %in% names(conda_envs)) {
        msg("Available conda environments:")
        pretty_print_df(conda_envs[, c("name", "python"), drop = FALSE])

        # Check if the target environment exists
        env_exists <- TARGET_CONDA_ENV_NAME %in% conda_envs$name
        if (env_exists) {
          success(paste0("Found target environment '", TARGET_CONDA_ENV_NAME, "'"))
        } else {
          msg(paste0("Creating new environment '", TARGET_CONDA_ENV_NAME, "' with Python ", PYTHON_VERSION, "..."))

          # Create the conda environment
          tryCatch({
            reticulate::conda_create(
              envname = TARGET_CONDA_ENV_NAME,
              python_version = PYTHON_VERSION,
              conda = conda_path
            )
            success(paste0("Created conda environment '", TARGET_CONDA_ENV_NAME, "'"))

            # Set this environment as active for installing Python packages
            reticulate::use_condaenv(TARGET_CONDA_ENV_NAME, required = TRUE)

            # Install Python dependencies using arrow::install_py() if available
            if (requireNamespace("arrow", quietly = TRUE) &&
                exists("install_py", envir = asNamespace("arrow"))) {
              msg("Installing Python dependencies via arrow...")
              tryCatch({
                arrow::install_py()
                success("Python arrow dependencies installed successfully")
              }, error = function(e) {
                warn("Failed to install via arrow::install_py()")
                warn("Falling back to manual package installation")

                # Fallback to manual installation
                if (length(PYTHON_PACKAGES) > 0) {
                  msg(paste("Installing packages:", paste(PYTHON_PACKAGES, collapse=", ")))
                  reticulate::conda_install(
                    envname = TARGET_CONDA_ENV_NAME,
                    packages = PYTHON_PACKAGES,
                    conda = conda_path
                  )
                  success("Python packages installed manually")
                }
              })
            } else {
              # Manual installation if arrow package is not available
              msg("Using manual package installation...")
              if (length(PYTHON_PACKAGES) > 0) {
                msg(paste("Installing packages:", paste(PYTHON_PACKAGES, collapse=", ")))
                reticulate::conda_install(
                  envname = TARGET_CONDA_ENV_NAME,
                  packages = PYTHON_PACKAGES,
                  conda = conda_path
                )
                success("Python packages installed successfully")
              }
            }

            env_exists <- TRUE
          }, error = function(e) {
            error(paste("Failed to create conda environment:", e$message))
            msg("You may need to create it manually using:")
            code(paste("conda create -n", TARGET_CONDA_ENV_NAME, "python=", PYTHON_VERSION))
          })
        }

        # Provide guidance on using the environment
        if (env_exists) {
          msg("\nTo use this environment in your R scripts, add this line:")
          code(paste0("reticulate::use_condaenv(\"", TARGET_CONDA_ENV_NAME, "\", required = TRUE)"))
        }
      } else {
        warn("Could not retrieve conda environment list in the expected format")
      }
    }, error = function(e) {
      error("Failed to list conda environments")
      error(e$message)
    })
  } else {
    warn("Conda not found - reticulate will use other methods to find Python")
    msg("If you intend to use conda, please install it and ensure it's accessible.")
  }
}

msg("\nSetup Complete", header = TRUE)
msg("The DataConnect library is ready to use")

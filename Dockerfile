FROM rocker/tidyverse:latest

# Set environment variables
ENV PATH=/opt/conda/bin:$PATH
ENV CONDA_ALWAYS_YES=true
ENV PYTHONDONTWRITEBYTECODE=1
ENV R_REMOTES_NO_ERRORS_FROM_WARNINGS=true
ENV ACERO_ALIGNMENT_HANDLING=reallocate
ENV DEBIAN_FRONTEND=noninteractive
ENV ARROW_R_DEV=FALSE
ENV NOT_CRAN=TRUE
ENV LIBARROW_BINARY=TRUE
ENV RETICULATE_PYTHON=/opt/conda/bin/python

# Install system dependencies and Python + Arrow libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev \
    libcurl4-openssl-dev libssl-dev libxml2-dev \
    qpdf \
    wget lsb-release gnupg \
    && wget https://apache.jfrog.io/artifactory/arrow/$(lsb_release --id --short | tr 'A-Z' 'a-z')/apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb \
    && apt-get install -y ./apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends libarrow-dev libarrow-glib-dev libarrow-dataset-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm apache-arrow-apt-source-latest-*.deb

# Install Miniforge and Pyarrow
RUN wget --quiet https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O miniforge.sh \
    && /bin/bash miniforge.sh -b -p /opt/conda \
    && rm miniforge.sh \
    && conda install -y -c conda-forge pyarrow \
    && conda clean -afy

# Create a better script for package installation with fallback
RUN Rscript -e "cat('# Install packages with multi-repository fallback mechanism\n\
install_with_fallback <- function(packages) {\n\
  posit_repo <- \"https://packagemanager.posit.co/cran/__linux__/ubuntu-jammy/latest\"\n\
  cran_repo <- \"https://cloud.r-project.org/\"\n\
  \n\
  for (pkg in packages) {\n\
    cat(\"\\nAttempting to install\", pkg, \"...\\n\")\n\
    \n\
    # Try Posit repository first\n\
    cat(\"Trying to install\", pkg, \"from Posit repository\\n\")\n\
    posit_result <- try({\n\
      install.packages(pkg, repos = posit_repo, dependencies = TRUE)\n\
    }, silent = TRUE)\n\
    \n\
    # If Posit failed, try CRAN\n\
    if (inherits(posit_result, \"try-error\") || !pkg %in% installed.packages()[,\"Package\"]) {\n\
      cat(\"Falling back to CRAN for\", pkg, \"\\n\")\n\
      cran_result <- try({\n\
        install.packages(pkg, repos = cran_repo, dependencies = TRUE)\n\
      }, silent = TRUE)\n\
      \n\
      if (inherits(cran_result, \"try-error\") || !pkg %in% installed.packages()[,\"Package\"]) {\n\
        stop(\"Failed to install \", pkg, \" from either Posit or CRAN\")\n\
      } else {\n\
        cat(pkg, \"successfully installed from CRAN\\n\")\n\
      }\n\
    } else {\n\
      cat(pkg, \"successfully installed from Posit\\n\")\n\
    }\n\
  }\n\
  cat(\"\\nAll packages installed successfully!\\n\")\n\
}\n\
\n\
# Function to install dependencies with fallback repositories\n\
remotes_install_deps <- function() {\n\
  # Set up repositories with Posit as primary and CRAN as fallback\n\
  repos <- c(\n\
    POSIT = \"https://packagemanager.posit.co/cran/__linux__/ubuntu-jammy/latest\",\n\
    CRAN = \"https://cloud.r-project.org/\"\n\
  )\n\
  \n\
  # Use remotes to install dependencies with the configured repositories\n\
  cat(\"Installing package dependencies with repository fallback...\\n\")\n\
  tryCatch({\n\
    remotes::install_deps(\".\", dependencies = TRUE, upgrade = FALSE, repos = repos)\n\
    cat(\"All dependencies installed successfully!\\n\")\n\
  }, error = function(e) {\n\
    cat(\"Error installing dependencies with combined repositories. Error was:\", e$message, \"\\n\")\n\
    cat(\"Trying with just CRAN as fallback...\\n\")\n\
    remotes::install_deps(\".\", dependencies = TRUE, upgrade = FALSE, repos = \"https://cloud.r-project.org/\")\n\
  })\n\
}', file = '/tmp/install_packages.R')"

# Install core packages with fallback mechanism
RUN Rscript -e "source('/tmp/install_packages.R'); install_with_fallback(c('remotes', 'devtools'))"

# Install required packages first (before copying project files to avoid namespace issues)
RUN Rscript -e "source('/tmp/install_packages.R'); install_with_fallback(c('reticulate', 'arrow', 'jsonlite', 'dplyr', 'methods', 'utils', 'base64enc'))"

# Set working directory
WORKDIR /usr/src/app

# Copy project files
COPY . .

# Run the remotes install_deps with fallback (to catch any remaining Suggests/other deps)
RUN Rscript -e "source('/tmp/install_packages.R'); remotes_install_deps()"

# Verify all required packages are available
RUN Rscript -e 'print("FINAL VERIFICATION:"); \
    required_pkgs <- c("reticulate", "arrow", "remotes", "devtools"); \
    installed <- required_pkgs %in% installed.packages()[,"Package"]; \
    if(all(installed)) { \
        print("ALL REQUIRED PACKAGES ARE AVAILABLE"); \
        for(pkg in required_pkgs) { print(paste(pkg, ":", find.package(pkg))); } \
    } else { \
        missing <- required_pkgs[!installed]; \
        stop(paste("MISSING PACKAGES:", paste(missing, collapse=", "))); \
    }'

# Install vignette dependencies before building
RUN Rscript -e "source('/tmp/install_packages.R'); install_with_fallback(c('knitr', 'rmarkdown'))"

# Build the package tarball (without building vignettes during build)
RUN R CMD build --no-build-vignettes .

# Install the dataconnect package with vignettes using remotes
RUN Rscript -e "remotes::install_local('dataconnect_1.0.1.tar.gz', build_vignettes = TRUE, dependencies = FALSE, upgrade = FALSE)"

# Default command to keep the container running for debugging
CMD ["R"]
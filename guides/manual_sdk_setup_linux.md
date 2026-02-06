# Manual Setup Guide For Linux

## Prerequisites Check

Before starting, check what's already installed:

```bash
# Check Python 3.13 installation
python3.13 --version

# Check pip for Python 3.13
python3.13 -m pip --version

# Check pyarrow for Python 3.13
python3.13 -c "import pyarrow; print(pyarrow.__version__)"

# Check R installation
R --version

# Check RStudio installation
rstudio --version
```

If a component is already installed, you can skip its installation section.

## Python 3.13 Installation (Optional - skip if Python 3.13.x is already installed)

**Prerequisites**: None

**Skip this entire section if**: `python3.13 --version` returns Python 3.13.x

### Update and Install Prerequisites

Launch Terminal. Within the terminal,

```bash
# Update package list to get latest package information
sudo apt update

# Install tools for managing repositories (required for add-apt-repository)
sudo apt install software-properties-common -y

# Add deadsnakes PPA for newer Python versions (like Python 3.13)
sudo add-apt-repository ppa:deadsnakes/ppa

# Update package list again to include packages from the new PPA
sudo apt update
```

### Install Python 3.13

```bash
# Install Python 3.13
sudo apt install python3.13 -y

# Install the Python 3.13 development package (needed for compiling Python packages)
sudo apt-get install python3.13-dev
```

### Verify Python 3.13 Installation

```bash
# Verify Python 3.13 is installed
python3.13 --version
```

## pip Installation

**Prerequisites**: Python 3.13 must be installed

**Skip this section if**: `python3.13 -m pip --version` works successfully

```bash
# Download get-pip.py script to install pip for Python 3.13
curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py

# Install pip system-wide for Python 3.13
sudo python3.13 get-pip.py

# Verify pip installation for Python 3.13 (should print pip version and path of pip in Python 3.13)
python3.13 -m pip --version
```

## pyarrow Installation

**Prerequisites**: 
- Python 3.13 must be installed
- pip for Python 3.13 must be installed

**Skip this section if**: `python3.13 -c "import pyarrow; print(pyarrow.__version__)"` works successfully

```bash
# Install pyarrow package system-wide for Python 3.13
sudo python3.13 -m pip install --upgrade pyarrow

# Verify pyarrow installation
python3.13 -c "import pyarrow; print(pyarrow.__version__)"
```

## R Installation (Optional - skip if R is already installed)

**Prerequisites**: None

**Skip this section if**: `R --version` works successfully

### Update and Install Prerequisites

```bash
# Update package indices
sudo apt update -qq

# Install helper packages needed for adding repositories and keys
sudo apt install --no-install-recommends software-properties-common dirmngr
```

### Install System Dependencies and R

```bash
# Install build tools required for compiling R packages
sudo apt-get install -y build-essential

# Install system dependencies required by R packages (arrow, tidyr, reticulate, base64enc)
sudo apt-get install -y libxml2-dev libcurl4-openssl-dev libssl-dev

# Install system dependencies required by R packages (tidyverse)
sudo apt-get install -y libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev

# Install R base system
sudo apt install --no-install-recommends r-base

# Verify R installation
R --version
```

## RStudio Installation (Optional - skip if RStudio is already installed)

**Prerequisites**: R must be installed

**Skip this section if**: `rstudio --version` works successfully

```bash
# Navigate to Downloads folder
cd ~/Downloads

# Note: If you are working on different version of Linux, please use correct .deb path corresponding to your version of OS.
# This is an example for Ubuntu 24.04
# Download RStudio .deb file for Ubuntu 24.04
curl -L -o rstudio-2026.01.0-392-amd64.deb https://download1.rstudio.org/electron/jammy/amd64/rstudio-2026.01.0-392-amd64.deb

# Install RStudio
sudo apt install ./rstudio-2026.01.0-392-amd64.deb

# Verify RStudio installation
rstudio --version
```

**Note:** For other versions, check https://posit.co/download/rstudio-desktop/ and replace the download URL accordingly.

## DataConnect R Package Installation

**Prerequisites**: 
- Python 3.13 must be installed
- pyarrow for Python 3.13 must be installed
- R must be installed
- System dependencies must be installed:
  - Core: `build-essential`, `libxml2-dev`, `libcurl4-openssl-dev`, `libssl-dev`
  - Graphics (for tidyverse): `libfontconfig1-dev`, `libharfbuzz-dev`, `libfribidi-dev`, `libfreetype6-dev`, `libpng-dev`, `libtiff5-dev`, `libjpeg-dev`

**Skip this section if**: Within RStudio console, `library(dataconnect)` loads successfully

### Download DataConnect Package

```bash
# Navigate to Downloads folder
cd ~/Downloads

# Download the dataconnect package
curl -L -o dataconnect_1.0.1.tar.gz https://github.com/mdsol/dataconnect-library-r/releases/download/v1.0.1/dataconnect_1.0.1.tar.gz
```

### Install R Package Dependencies

**Within the terminal**, run the following commands:

```bash
# Install R package dependencies to system library
# Note: tidyverse includes dplyr, tidyr, and rlang, so we install it first
sudo R -e "install.packages('tidyverse', repos='https://cloud.r-project.org/')"
sudo R -e "install.packages('base64enc', repos='https://cloud.r-project.org/')"
sudo R -e "install.packages('reticulate', repos='https://cloud.r-project.org/')"
sudo R -e "install.packages('arrow', repos='https://cloud.r-project.org/')"
```

**Note**: Installation of tidyverse and arrow can take long time.

### Install DataConnect Package

**Within the terminal**, run the following command:

```bash
# Navigate to Downloads folder (if current directory is something else)
cd ~/Downloads

# Install the dataconnect package to system library from Downloads folder
sudo R -e "install.packages('./dataconnect_1.0.1.tar.gz', repos=NULL, type='source')"
```

**Note:** These packages are now available to all users on the system.

## Configure Python Integration

**Prerequisites**: 
- Python 3.13 must be installed
- R must be installed

### Configure R to Use Python 3.13

1. Open the system-wide R environment file:
   ```bash
   sudo nano /etc/R/Renviron.site
   ```

2. Add this line if it's not already present and save the file:
   ```
   RETICULATE_PYTHON=/usr/bin/python3.13
   ```

**Note:** This configuration applies to all R sessions for all users on the system.

**Important:** Restart the R session in RStudio.

### Verify pyarrow Installation

Within RStudio's console, run the following command:

```r
# Should return TRUE if pyarrow is installed and accessible
reticulate::py_module_available('pyarrow')
```

### Attach the following packages to use dataconnect.

```r
library(dplyr)
library(tidyverse)
library(dataconnect)
```

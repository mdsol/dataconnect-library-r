# Manual Setup Guide For Ubuntu Linux

## Python 3.13 Installation

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

# Install the Python 3.13 development package (needed for compiling some Python packages)
sudo apt-get install python3.13-dev
```

### Configure Python Alias and PATH

```bash
nano ~/.bashrc
```

To make 'python' point to Python 3.13 and to add user-installed binaries to your PATH, add the following to your `.bashrc` file and save:

```bash
alias python='/usr/bin/python3.13'
export PATH="$HOME/.local/bin:$PATH"
```

**Important:** Close the terminal and open a new terminal before proceeding.

### Verify Python Installation

```bash
# Verify Python version (should print 'Python 3.13.11' or similar)
python --version
```

### Install pip

```bash
# Download get-pip.py script to install pip for Python 3.13
curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py

# Install pip using Python 3.13 (if alias is set, 'python' points to Python 3.13)
python get-pip.py

# Verify pip installation for Python 3.13
# Should print pip version and path for Python 3.13
python -m pip --version
```

### Install pyarrow

```bash
# Upgrade/install pyarrow package using pip for Python 3.13
python -m pip install --upgrade pyarrow
```

## R Installation (Optional, only if it's not already installed)

### Update and Install Prerequisites

```bash
# Update package indices quietly
sudo apt update -qq

# Install helper packages needed for adding repositories and keys
sudo apt install --no-install-recommends software-properties-common dirmngr
```

### Install System Dependencies and R

```bash
# Install system dependencies required by some R packages (e.g., png)
sudo apt-get install -y libpng-dev

# Install R base system
sudo apt install --no-install-recommends r-base
```

### Install RStudio (if it's not already installed.)

Download .deb file for your operating system (e.g. ubuntu 22) from https://posit.co/download/rstudio-desktop/

```bash
# Assuming that the downloaded .deb file is in Downloads folder
cd ~/Downloads

# Install RStudio (replace <filename.deb> with actual .deb file name)
sudo apt install ./<filename.deb>
```

## DataConnect R Package Installation

1. Download the dataconnect package from:
   https://github.com/mdsol/dataconnect-library-r/releases/download/v1.0.1/dataconnect_1.0.1.tar.gz

2. Install dependencies

**Within RStudio's console**, run the following command:

```r
install.packages("base64enc")
install.packages("reticulate")
install.packages("tidyr")
install.packages("arrow")
install.packages("tidyverse")
```

Installation of some of these packages can take a long time.

3. Install the package:

**Within RStudio's console**, run the following command:

```r
# Install the dataconnect package from the local file
install.packages("path/to/dataconnect_1.0.1.tar.gz", 
                 repos = NULL,
                 type = "source")
```

## Configure Python Integration

### Within the terminal,

1. Open the `.Renviron` file (creates it if it doesn't exist):
   ```bash
   nano ~/.Renviron
   ```

2. Add this line if it's not already present and save the file:
   ```
   RETICULATE_PYTHON=/usr/bin/python3.13
   ```

**Important:** Restart the R session in RStudio.

### Verify pyarrow Installation

Within RStudio's console, run the following command:

```r
# Should return TRUE if pyarrow is installed and accessible
reticulate::py_module_available('pyarrow')

# While using this package (dataconnect), please attach the following.
library(dplyr)
library(rlang)
```

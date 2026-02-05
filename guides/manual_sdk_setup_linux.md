# Manual Setup Guide For Linux

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

### Install Python 3.13 (Optional - only if python 3.13.x is not already installed)

**Note**: Skip this step if python 3.13.x is already installed.

```bash
# Install Python 3.13
sudo apt install python3.13 -y

# Install the Python 3.13 development package (needed for compiling some Python packages)
sudo apt-get install python3.13-dev
```

### Configure Python as System Default (Optional - only if you want to change the default)

**Note**: This is optional. If you want your current python to be default, do not run these commands.

```bash
# Set Python 3.13 as the system-wide default for 'python' command
# NOTE: Do NOT change python3 symlink as it may break Ubuntu system scripts
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.13 1

# This command allows you to select the default Python interpreter when multiple versions are installed on your Linux system. 
# Running it will present a list of available Python alternatives, and you can choose which one should be used by default.
# This is just to verify the configuration - do not change the current choice
sudo update-alternatives --config python
```

**Note:** This configuration is system-wide. All users on the machine will have access to Python 3.13 via the `python` command.

### Verify Python Installation

```bash
# Verify Python 3.13 is accessible via 'python' command
python --version
```

### Install pip System-Wide

```bash
# Download get-pip.py script to install pip for Python 3.13
curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py

# Install pip system-wide for Python 3.13
sudo python3.13 get-pip.py

# Verify pip installation for Python 3.13
# Should print pip version and path of pip in Python 3.13
python3.13 -m pip --version
```

### Install pyarrow System-Wide

```bash
# Install pyarrow package system-wide for Python 3.13
sudo python3.13 -m pip install --upgrade pyarrow
```

## R & RStudio Installation (Optional, only if it's not already installed)

### Update and Install Prerequisites

```bash
# Update package indices quietly
sudo apt update -qq

# Install helper packages needed for adding repositories and keys
sudo apt install --no-install-recommends software-properties-common dirmngr
```

### Install System Dependencies and R (if it's not already installed)

```bash
# Install build tools required for compiling R packages
sudo apt-get install -y build-essential

# Install R base system
sudo apt install --no-install-recommends r-base

# Verify R installation
R --version
```

### Install RStudio (if it's not already installed)

```bash
# Navigate to Downloads folder
cd ~/Downloads

# Note: If you are working on different OS / version, please use correct .deb path corresponding to your version of OS.
# This is an example for Ubuntu 24.04
# Download RStudio .deb file for Ubuntu 24.04 (noble/jammy)
curl -L -o rstudio-2026.01.0-392-amd64.deb https://download1.rstudio.org/electron/jammy/amd64/rstudio-2026.01.0-392-amd64.deb

# Install RStudio
sudo apt install ./rstudio-2026.01.0-392-amd64.deb

# Verify RStudio installation
rstudio --version
```

**Note:** For other versions, check https://posit.co/download/rstudio-desktop/ and replace the download URL accordingly.

## DataConnect R Package Installation (System-Wide)

1. Download the dataconnect package:

```bash
# Navigate to Downloads folder
cd ~/Downloads

# Download the dataconnect package
curl -L -o dataconnect_1.0.1.tar.gz https://github.com/mdsol/dataconnect-library-r/releases/download/v1.0.1/dataconnect_1.0.1.tar.gz
```

2. Install dependencies system-wide

**Within the terminal**, run the following commands:

```bash
# Install R package dependencies to system library
sudo R -e "install.packages('base64enc', repos='https://cloud.r-project.org/')"
sudo R -e "install.packages('reticulate', repos='https://cloud.r-project.org/')"
sudo R -e "install.packages('tidyr', repos='https://cloud.r-project.org/')"
sudo R -e "install.packages('arrow', repos='https://cloud.r-project.org/')"
```

Installation of some of these packages can take a long time.

3. Install the dataconnect package system-wide:

**Within the terminal**, run the following command:

```bash
# Navigate to Downloads folder (if current directory is something else)
cd ~/Downloads

# Install the dataconnect package to system library from Downloads folder
sudo R -e "install.packages('./dataconnect_1.0.1.tar.gz', repos=NULL, type='source')"
```

**Note:** These packages are now available to all users on the system.

## Configure Python Integration (System-Wide)

### Within the terminal,

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
library(rlang)
library(dataconnect)
```

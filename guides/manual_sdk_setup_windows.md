# Manual Setup Guide For Windows (without MiniForge)

If you already have a Python 3.13 environment with pyarrow (virtualenv, conda, etc.), you can use it instead: use that environment's `python.exe` in the [Configure Python Integration](#configure-python-integration) step.

Run all commands in **PowerShell**.

## Prerequisites Check

```powershell
# Check Python 3.13 installation
py -3.13 --version

# Check pip for Python 3.13
py -3.13 -m pip --version

# Check pyarrow for Python 3.13
py -3.13 -c "import pyarrow; print(pyarrow.__version__)"

# Check R installation
& "C:\Program Files\R\R-4.5.*\bin\R.exe" --version

# Check RStudio installation
Test-Path "C:\Program Files\RStudio\rstudio.exe"
```

If a component is already installed, you can skip its section.

## Python 3.13 Installation

**Prerequisites**: Python 3.13.x must be installed

### Verify Python 3.13 Installation

```powershell
# Verify Python 3.13 is installed
py -3.13 --version

# Print the exact Python executable path (used in Configure Python Integration)
py -3.13 -c "import sys; print(sys.executable)"
```

## pip Installation

**Prerequisites**: pip for Python 3.13 must be installed

```powershell
# Verify pip installation for Python 3.13 (should print pip version and path of pip in Python 3.13)
py -3.13 -m pip --version
```

## pyarrow Installation

**Prerequisites**: 
- Python 3.13 must be installed
- pip for Python 3.13 must be installed

**Skip this section if**: `py -3.13 -c "import pyarrow; print(pyarrow.__version__)"` works successfully

```powershell
# Install pyarrow package for Python 3.13
py -3.13 -m pip install --upgrade pyarrow

# Verify pyarrow installation
py -3.13 -c "import pyarrow; print(pyarrow.__version__)"
```

## R Installation

**Prerequisites**: R 4.5.x must be installed

```powershell
# Verify R installation
& "C:\Program Files\R\R-4.5.*\bin\R.exe" --version
```

## RStudio Installation

**Prerequisites**: RStudio must be installed

## Rtools Installation

**Prerequisites**: R 4.5.x must be installed

Rtools provides the compiler toolchain R uses to build packages from source. It is required for installing dataconnect with `pak::pak("mdsol/dataconnect-library-r@...")`. Use the Rtools version that matches R (R 4.5.x uses Rtools 4.5).

Check first. Within RStudio's console, run:

```r
install.packages("pkgbuild")

# Should print "Your system is ready to build packages!"
pkgbuild::check_build_tools(debug = TRUE)
```

**Only if the check does not return `TRUE`**: download and run the Rtools 4.5 installer from https://cran.r-project.org/bin/windows/Rtools/ (accept the defaults), restart RStudio and run the check again.

## Install R Package Dependencies

**Prerequisites**: 
- R 4.5.x must be installed
- Rtools must be installed

```powershell
# Locate R (repeat this if you open a new PowerShell window)
$R = (Get-ChildItem "C:\Program Files\R\R-4.5.*\bin\R.exe" | Sort-Object FullName | Select-Object -Last 1).FullName

# Verify R was found (should print the path, e.g. C:\Program Files\R\R-4.5.3\bin\R.exe)
$R

# Install R package dependencies
# Note: tidyverse includes dplyr, tidyr, and rlang, so we install it first
& $R -e "install.packages('tidyverse', repos='https://cloud.r-project.org/')"
& $R -e "install.packages('base64enc', repos='https://cloud.r-project.org/')"
& $R -e "install.packages('reticulate', repos='https://cloud.r-project.org/')"
& $R -e "install.packages('arrow', repos='https://cloud.r-project.org/')"
```

**Note**: Installation of tidyverse and arrow can take a long time. Packages are installed per R version (for example `win-library\4.5`).

## Configure Python Integration

**Prerequisites**: 
- Python 3.13 with pyarrow must be installed

Find the `python.exe` that R should use. Use forward slashes (`/`) when you put it in R:

```powershell
# Default Python 3.13 (replace \ with / when used in R)
py -3.13 -c "import sys; print(sys.executable)"
```

If you use a custom environment, use that environment's `python.exe` instead (for example `C:/path/to/env/Scripts/python.exe` for a virtualenv, or `C:/path/to/env/python.exe` for conda). Confirm it has pyarrow:

```powershell
& "<path to python.exe>" -c "import pyarrow; print(pyarrow.__version__)"
```

This path is set in R with `Sys.setenv(RETICULATE_PYTHON = "<path to python.exe>")`, as shown in the vignettes below.

## Next Steps

Install the DataConnect R package and finish the setup in **RStudio** by following the setup vignette: [rLibrary_setup_without_miniforge.Rmd](../vignettes/windows/rLibrary_setup_without_miniforge.Rmd). For usage, see [rLibrary_usage_without_miniforge.Rmd](../vignettes/windows/rLibrary_usage_without_miniforge.Rmd).

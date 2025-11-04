#' Package Attach Hook
#'
#' This function is called when the package is attached to the search path.
#' It displays a startup message showing the package name and version.
#'
#' @param libname character string giving the library directory where the
#'   package was found.
#' @param pkgname character string giving the name of the package.
#'
#' @return NULL (invisibly). Called for its side effect of displaying a
#'   startup message.
#'
#' @keywords internal
#' @noRd 
.onAttach <- function(libname, pkgname) {
  packageStartupMessage("dataconnect ", utils::packageVersion("dataconnect"), " loaded.")
}

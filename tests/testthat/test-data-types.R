context("R to pyarrow data type conversion")

library(testthat)
library(arrow)

# Test a data.frame with all R types and explicit Arrow types
test_that("data.frame with all R and Arrow types converts to expected arrow types", {

	skip_if_not_installed("arrow")

	# Use arrow::Array$create for types not natively supported by R
	library(arrow)

	df <- data.frame(
		bool_col = c(TRUE, FALSE, FALSE), #bool
		int32_col = as.integer(c(1L, 2L, 3L)), #int32
		int64_col = bit64::as.integer64(c(1, 2, 3)), #int64
		double_col = as.numeric(c(1.23, 2.2, 3.3)), #double
		char_col = c("a", "b", "c"), #string
		date32_col = as.Date(c("2020-01-01", "2020-01-02", "2020-01-03")), #date32[day]
		timestamp_col1 = as.POSIXct(c("2020-01-01", "2020-01-02", "2020-01-03"), tz = "UTC"), #timestamp[us, tz=UTC]
		timestamp_col2 = as.POSIXct(c("2020-01-01 12:00:00", "2020-01-02 13:00:00", "2020-01-03 14:00:00"), tz = "UTC"), #timestamp[us, tz=UTC]
		stringsAsFactors = FALSE
	)

	# Add columns that require explicit Arrow arrays
	tbl <- arrow::arrow_table(df)

	expect_equal(tbl$schema$GetFieldByName("bool_col")$type$ToString(), "bool")
	expect_equal(tbl$schema$GetFieldByName("int32_col")$type$ToString(), "int32")
	expect_equal(tbl$schema$GetFieldByName("int64_col")$type$ToString(), "int64")
	expect_equal(tbl$schema$GetFieldByName("double_col")$type$ToString(), "double")
	expect_equal(tbl$schema$GetFieldByName("char_col")$type$ToString(), "string")
	expect_equal(tbl$schema$GetFieldByName("date32_col")$type$ToString(), "date32[day]")
	expect_equal(tbl$schema$GetFieldByName("timestamp_col1")$type$ToString(), "timestamp[us, tz=UTC]")
	expect_equal(tbl$schema$GetFieldByName("timestamp_col2")$type$ToString(), "timestamp[us, tz=UTC]")
})

# Test Arrow Table to R data.frame type mapping
test_that("arrow table to R data.frame type mapping is as expected", {
	
    skip_if_not_installed("arrow")
	
    library(arrow)
	library(bit64)
	
    tbl <- arrow_table(
		bool_col = Array$create(c(TRUE, FALSE, TRUE), type = arrow::bool()),
		int32_col = Array$create(c(1L, 2L, 3L), type = arrow::int32()),
		int64_col = Array$create(bit64::as.integer64(c(1, 2, 3)), type = arrow::int64()),
		float64_col = Array$create(c(4.4, 5.5, 6.6), type = float64()),
		char_col = Array$create(c("a", "b", "c"), type = arrow::string()),
		date32_col = Array$create(as.Date(c("2020-01-01", "2020-01-02", "2020-01-03")), type = arrow::date32()),
		timestamp_col1 = Array$create(as.POSIXct(c("2020-01-01", "2020-01-02", "2020-01-03"), tz = "UTC"), type = arrow::timestamp("us")),
		timestamp_col2 = Array$create(as.POSIXct(c("2020-01-01 12:00:00", "2020-01-02 13:00:00", "2020-01-03 14:00:00"), tz = "UTC"), type = arrow::timestamp("us"))
	)

    df <- as.data.frame(tbl)

	expect_type(df$bool_col, "logical")
    expect_type(df$int32_col, "integer")
	expect_true(inherits(df$int64_col, "integer"))
	expect_type(df$float64_col, "double")
	expect_type(df$char_col, "character")
	expect_s3_class(df$date32_col, "Date")
	expect_type(df$timestamp_col1, "double") # Arrow date64 and timestamp returns numeric
	expect_type(df$timestamp_col2, "double") # Arrow date64 and timestamp returns numeric
})


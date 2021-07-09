# USDA Plant Data Importer

This is a simple tool that will allow importing the USDA plant data CSVs, accessible [here](https://plants.sc.egov.usda.gov/home/downloads), into a sqlite database.

## How it Works

The importer is a Rust program that relies on 2 things:

1. A [data](data) directory that contains the CSVs to import
1. The [regions.json](regions.json) which defines the valid region names and abbreviations

When the program is run it will import each CSV file in the data directory into a new database called plants.db in the current directory.

The database schema is defined in [plants.sql](plants.sql).

You need to have a valid [Rust environment setup](https://rust-lang.github.io/rustup/) to build and run this.

The resulting database is largish and can easily be recreated so it is not committed to git.

## Why?

This database is used to provide lookups when adding new Hosts via the Admin screens. It provides a list of known valid hosts as well as some (but not all) common name information. Most importantly it also provides known range (state level) data for hosts.

## Future

These CSV files will grow stale as the USDA updates their data. Hopefully they will add an API for this stuff. They used to have one but took it down without warning and have not replaced it. In the meantime, if updated data is desired, then the CSVs will have to be manually downloaded from the [USDA site](https://plants.sc.egov.usda.gov/home/downloads) and then the DB regenerated.

## Known Issues

- The MN.csv file is truncated. This is how it is on the USDA server, so range data for MN will not be accurate for any host that occurs after `Viola renifolia A. Gray` in the alphabet
- As of this commit, the ID data has a row of bad data in it that has to be manually fixed. The data is fixed in the CSV stored here, but if it is redownloaded it may again contain the error. The easiest way to deal with it, is to run the import. If it fails it will report the file and line number. The data can then be manually repaired and the import run again (simply delete the database before re-running)
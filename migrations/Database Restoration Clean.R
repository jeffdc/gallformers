library(DBI)
library(dbx)
library(tidyr)
library(sjmisc)
library(RSQLite)
library(rinat)
library(stringr)
library(ggplot2)
library(lubridate)
wd <- "C:/Users/adam/Documents/GitHub/Phenology"
setwd(wd)
gfbackup <- dbConnect(RSQLite::SQLite(), "gallformers011023.sqlite")
gfnew <- dbConnect(RSQLite::SQLite(), "gallformers102223.sqlite")

### Function to restore a single genus to the taxonomy table

restore_genus <- function(genusid, gfbackup, gfnew) {
  
  # Step 1: Fetch the record with the provided id from the taxonomy table in gfbackup
  query_fetch <- sprintf("SELECT * FROM taxonomy WHERE id = %d", genusid)
  record_to_restore <- dbGetQuery(gfbackup, query_fetch)
  
  # Check if the record was fetched properly
  if (nrow(record_to_restore) == 0) {
    stop(sprintf("The record with id = %d was not found in gfbackup!", genusid))
  }
  
  # Step 2: Insert that record into the taxonomy table in gfnew
  
  # Convert the data frame values to a character vector for SQL construction
  values <- as.character(record_to_restore[1, ])
  
  # Handle blanks and NA values
  values <- sapply(values, function(x) {
    if (is.na(x) || x == "") {
      return("NULL")
    } else {
      return(paste0("'", x, "'")) # Enclose non-NULL values in single quotes
    }
  })
  
  # Construct the INSERT query
  query_insert <- sprintf("INSERT INTO taxonomy VALUES (%s)", paste(values, collapse = ", "))
  
  # Execute the INSERT query
  dbExecute(gfnew, query_insert)
  
  # Optional: Confirm that the record was added to gfnew
  query_check <- sprintf("SELECT * FROM taxonomy WHERE id = %d", genusid)
  added_record <- dbGetQuery(gfnew, query_check)
  print(added_record)
  
  ## restore that genus to taxonomytaxonomy
  
  # Values for insertion
  taxonomy_id_value <- 89
  
  # Construct the INSERT query for taxonomytaxonomy table
  query_insert_taxonomytaxonomy <- sprintf(
    "INSERT INTO taxonomytaxonomy (taxonomy_id, child_id) VALUES (%d, %d)", 
    taxonomy_id_value, 
    genusid
  )
  
  # Execute the INSERT query
  dbExecute(gfnew, query_insert_taxonomytaxonomy)
  
  # Optional: Confirm that the record was added to gfnew
  query_check <- sprintf("SELECT * FROM taxonomytaxonomy WHERE taxonomy_id = %d AND child_id = %d", taxonomy_id_value, genusid)
  added_record_taxonomytaxonomy <- dbGetQuery(gfnew, query_check)
  print(added_record_taxonomytaxonomy)
  
  ## restore all the species records associated with that genus to species table
  
  # Fetch the species IDs associated with the genus from speciestaxonomy in gfbackup
  query_species_ids <- sprintf("SELECT species_id FROM speciestaxonomy WHERE taxonomy_id = %d", genusid)
  species_ids_df <- dbGetQuery(gfbackup, query_species_ids)
  
  # If there are any species associated with this genus
  if (nrow(species_ids_df) > 0) {
    species_ids <- species_ids_df$species_id
    
    # Fetch the species records from species table in gfbackup using these species IDs
    query_species_records <- sprintf("SELECT * FROM species WHERE id IN (%s)", paste(species_ids, collapse = ","))
    species_records_to_restore <- dbGetQuery(gfbackup, query_species_records)
    
    print(species_records_to_restore) # Optionally print to check
    
    # Proceed to step 2 if everything looks good
  } else {
    print("No species associated with this genus in the backup.")
  }
  
  # Loop through the rows of species_records_to_restore and insert them into gfnew
  for (i in 1:nrow(species_records_to_restore)) {
    
    # Convert the data frame row to a character vector for SQL construction
    values <- as.character(species_records_to_restore[i, ])
    
    # Handle blanks and NA values
    values <- sapply(values, function(x) {
      if (is.na(x) || x == "") {
        return("NULL")
      } else {
        return(paste0("'", x, "'")) # Enclose non-NULL values in single quotes
      }
    })
    
    query_insert_species <- sprintf("INSERT INTO species VALUES (%s)", paste(values, collapse = ", "))
    
    # Execute the INSERT query
    dbExecute(gfnew, query_insert_species)
  }
  
  dbExecute(gfnew, "UPDATE species SET abundance_id = NULL WHERE abundance_id = 'NA'")
  # Optional: Confirm that the records were added to gfnew
  added_species <- dbGetQuery(gfnew, sprintf("SELECT * FROM species WHERE id IN (%s)", paste(species_ids, collapse = ",")))
  print(added_species)
  
  
  ## Reestablish the connection between species and genus by restoring records to the speciestaxonomy table
  
  # Extract the associations of the species corresponding to the genus id from the backup
  query_fetch_associations <- sprintf("SELECT * FROM speciestaxonomy WHERE taxonomy_id = %d", genusid)
  associations_to_restore <- dbGetQuery(gfbackup, query_fetch_associations)
  
  # For each record, create an insert statement and execute it
  for (i in 1:nrow(associations_to_restore)) {
    
    # Convert the data frame values to a character vector for SQL construction
    values <- as.character(associations_to_restore[i, ])
    
    # Handle blanks and NA values for all columns
    values <- sapply(values, function(x) {
      if (is.na(x) || x == "") {
        return("NULL")
      } else {
        return(paste0("'", x, "'")) # Enclose non-NULL values in single quotes
      }
    })
    
    query_insert <- sprintf("INSERT INTO speciestaxonomy VALUES (%s)", paste(values, collapse = ", "))
    
    # Execute the INSERT query
    dbExecute(gfnew, query_insert)
  }
  
  # Query the speciestaxonomy table in gfnew to verify that the associations have been added
  query_check <- sprintf("SELECT * FROM speciestaxonomy WHERE taxonomy_id = %d", genusid)
  added_associations <- dbGetQuery(gfnew, query_check)
  
  # Check and compare the number of rows
  if (nrow(added_associations) == nrow(associations_to_restore)) {
    cat("The associations were successfully restored!\n")
  } else {
    cat("There seems to be a discrepancy in the number of added associations. Please review the data.\n")
  }
  
  ## Restore gall-host relationships in the Host table
  
  # Use the species_ids vector to fetch all related host records from gfbackup
  query_fetch_host <- sprintf("SELECT * FROM host WHERE gall_species_id IN (%s) OR host_species_id IN (%s)", 
                              paste(species_ids, collapse = ","), paste(species_ids, collapse = ","))
  hosts_to_restore <- dbGetQuery(gfbackup, query_fetch_host)
  
  # Iterate over each row of the hosts_to_restore data frame and insert it into gfnew
  for (i in 1:nrow(hosts_to_restore)) {
    values <- hosts_to_restore[i, ]
    
    # Convert the values to character, and replace NA values with 'NULL'
    values <- sapply(values, function(x) {
      if (is.na(x)) {
        return("NULL")
      } else {
        return(paste0("'", x, "'")) # Enclose non-NULL values in single quotes
      }
    })
    
    # Construct the SQL query
    query_insert_host <- sprintf("INSERT INTO host VALUES (%s)", paste(values, collapse = ", "))
    
    # Execute the INSERT query
    dbExecute(gfnew, query_insert_host)
  }
  
  # Query the host table in gfnew to verify that the records have been added
  query_check_host <- sprintf("SELECT * FROM host WHERE gall_species_id IN (%s) OR host_species_id IN (%s)", 
                              paste(species_ids, collapse = ","), paste(species_ids, collapse = ","))
  added_hosts <- dbGetQuery(gfnew, query_check_host)
  
  # Compare the count
  if (nrow(added_hosts) == nrow(hosts_to_restore)) {
    cat("The host records were successfully restored!\n")
  } else {
    cat("There seems to be a discrepancy in the number of added host records. Please review the data.\n")
  }
  
  ### Restore any aliases
  
  # Using the list of species_ids restored above
  species_ids_vector <- species_records_to_restore$id
  
  # Check for their presence in aliasspecies table in gfbackup
  query <- sprintf("SELECT * FROM aliasspecies WHERE species_id IN (%s)", paste(species_ids_vector, collapse = ","))
  associated_aliases <- dbGetQuery(gfbackup, query)
  
  # Extracting unique alias_ids from the results
  unique_alias_ids <- unique(associated_aliases$alias_id)
  
  # Fetching the respective records from the alias table in gfbackup
  query_fetch_aliases <- sprintf("SELECT * FROM alias WHERE id IN (%s)", paste(unique_alias_ids, collapse = ","))
  aliases_to_restore <- dbGetQuery(gfbackup, query_fetch_aliases)

  # Check for each alias in gfnew; only insert if not present
  for (i in 1:nrow(aliases_to_restore)) {
    
    # Ensure that 'id' column exists
    if (!"id" %in% names(aliases_to_restore)) {
      stop("Error: 'id' column not found in aliases_to_restore data frame.")
    }
    
    current_alias_id <- aliases_to_restore[i, 'id']
    
    # Check for NA values or empty vectors and skip the iteration if found
    if (length(current_alias_id) == 0 || is.na(current_alias_id)) {
      cat("Warning: Encountered NA or empty value in alias id. Skipping this record.\n")
      next
    }
    
    query_check_existence <- sprintf("SELECT * FROM alias WHERE id = %d", current_alias_id)
    
    # Use tryCatch to handle any database errors gracefully
    existing_alias <- tryCatch({
      dbGetQuery(gfnew, query_check_existence)
    }, error = function(e) {
      cat(sprintf("Error encountered while checking for alias id %d: %s\n", current_alias_id, e$message))
      return(NULL)
    })
    
    if (is.null(existing_alias) || nrow(existing_alias) == 0) {
      dbWriteTable(gfnew, "alias", aliases_to_restore[i, , drop = FALSE], append = TRUE, row.names = FALSE)
    }
  }
  
  # Check if the records have been added to the aliasspecies table in gfnew
  added_aliasspecies <- dbGetQuery(gfnew, sprintf("SELECT * FROM aliasspecies WHERE species_id IN (%s)", paste(species_ids_vector, collapse = ",")))
  print(added_aliasspecies)
  
  
  ### Restore speciessource table
  
  # Fetch the speciessource records associated with the species from gfbackup
  query_fetch_speciessource <- sprintf("SELECT * FROM speciessource WHERE species_id IN (%s)", paste(species_ids_vector, collapse = ","))
  missing_speciessource <- dbGetQuery(gfbackup, query_fetch_speciessource)
  
  # Inserting the speciessource records into gfnew
  dbWriteTable(gfnew, "speciessource", missing_speciessource, append = TRUE, row.names = FALSE)
  
  # Check if the records have been added to the speciessource table in gfnew
  added_speciessource <- dbGetQuery(gfnew, sprintf("SELECT * FROM speciessource WHERE species_id IN (%s)", paste(species_ids_vector, collapse = ",")))
  print(added_speciessource)
  
  ### Restore link from species to image
  
  # Fetch the image records associated with the species from gfbackup
  query_fetch_image <- sprintf("SELECT * FROM image WHERE species_id IN (%s)", paste(species_ids_vector, collapse = ","))
  missing_image <- dbGetQuery(gfbackup, query_fetch_image)
  
  # Inserting the image records into gfnew
  dbWriteTable(gfnew, "image", missing_image, append = TRUE, row.names = FALSE)
  
  # Check if the records have been added to the image table in gfnew
  added_image <- dbGetQuery(gfnew, sprintf("SELECT * FROM image WHERE species_id IN (%s)", paste(species_ids_vector, collapse = ",")))
  print(added_image)
  
  ### restore connection from species to gall
  
  # Fetch the gallspecies records associated with the species from gfbackup
  query_fetch_gallspecies <- sprintf("SELECT * FROM gallspecies WHERE species_id IN (%s)", paste(species_ids_vector, collapse = ","))
  missing_gallspecies <- dbGetQuery(gfbackup, query_fetch_gallspecies)
  
  # Inserting the gallspecies records into gfnew
  dbWriteTable(gfnew, "gallspecies", missing_gallspecies, append = TRUE, row.names = FALSE)
  
  # Check if the records have been added to the gallspecies table in gfnew
  added_gallspecies <- dbGetQuery(gfnew, sprintf("SELECT * FROM gallspecies WHERE species_id IN (%s)", paste(species_ids_vector, collapse = ",")))
  print(added_gallspecies)
  
}

# Fetch the genus IDs associated with the family Tephritidae (ID: 89) from taxonomytaxonomy
query_genus_ids <- "SELECT child_id FROM taxonomytaxonomy WHERE taxonomy_id = 89"
genus_ids_df <- dbGetQuery(gfbackup, query_genus_ids)

# Apply the function on each genus ID
if (nrow(genus_ids_df) > 0) {
  lapply(genus_ids_df$child_id, restore_genus, gfbackup = gfbackup, gfnew = gfnew)
} else {
  print("No genera associated with this family.")
}

dbDisconnect(gfnew)


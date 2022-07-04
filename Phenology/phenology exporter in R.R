# library(stringr)
# library(tidyr)
# library(purrr)
# library(iNatTools)
# library(remotes)
# library(rinat)
# library(lubridate)
# library(data.table)
# library(dplyr)
# library(jsonlite)
# library(rnpn)

# this function calls the NPN database to associate an AGDD value with each observation based on lat/long and date
lookUpAGDD <- function(x){
  for (i in 1:dim(x)[1]){
    x$agdd[i]  <- npn_get_agdd_point_data('gdd:agdd',lat=x$Latitude[i],long=x$Longitude[i],date=x$observed_on[i],store_data = FALSE)
  }
  return(x)
}

### Get annotation codes
a <- fromJSON("https://api.inaturalist.org/v1/controlled_terms")
a <- flatten(a$results)
l <- lapply(seq_along(a[, "values"]), function(i) {
  cbind(idann = a$id[i], labelann = a$label[i], a[i, "values"][[1]][, c("id", "label")])
})
ann <- do.call("rbind", l)
ann

### Request url
url <-
  paste0(
    "https://api.inaturalist.org/v1/observations?quality_grade=any&identifications=any&&page=1&per_page=200&order=desc&order_by=created_at&place_id=1&taxon_id=",
    "1195335"
  )

# Get json and flatten
x <- fromJSON(url)
x <- flatten(x$results)

# Remove observations outside the US
x <- x[x$site_id=="1",]

keep <-
  c("id", "observed_on", "taxon.name","location","uri","ofvs") # values to keep

### Extract annotations if any
vals <- lapply(seq_along(x$annotations), function(i) {
  j <- x$annotations[[i]]
  n <- c("controlled_attribute_id", "controlled_value_id")
  if (all(n %in% names(j))) { # tests if there are any annotations for the obs
    ans <- j[, n]
  } else{
    ans <- data.frame(x = NA, y = NA) # if no annotations create NA data.frame
    names(ans) <- n
  }
  cbind(x[i, keep][rep(1, nrow(ans)), ], ans) # repeat obs for each annotation value and bind with ann
})
vals <- do.call("rbind", vals) # bind everything

keep <-
  c("id", "observed_on", "taxon.name","location","uri","ofvs","controlled_attribute_id", "controlled_value_id") # values to keep

### Extract observation fields if any

of <- lapply(seq_along(vals$ofvs), function(i) {
  f <- vals$ofvs[[i]]
  m <- c("name", "value")
  if (all(m %in% names(f))) { # tests if there are any annotations for the obs
    ans <- f[, m]
  } else{
    ans <- data.frame(x = NA, y = NA) # if no annotations create NA data.frame
    names(ans) <- m
  }
  cbind(vals[i, keep][rep(1, nrow(ans)), ], ans) # repeat obs for each annotation value and bind with ann
})
of <- do.call("rbind", of) # bind everything

# obs <- merge(obs, of)

## Merge obs with annotations
obs <-
  merge(
    of,
    ann,
    by.x = c("controlled_attribute_id", "controlled_value_id"),
    by.y = c("idann", "id"),
    all.x = TRUE
  )
obs <- obs[order(obs$id), ]

### Cast from long to wide and concatenate annotation values
# Results in a single line per obs
setDT(obs) # turn df to data.table to use dcast
obs <- dcast(
  obs,
  id + uri + observed_on + location + taxon.name + name + value ~ labelann,
  value.var = "label",
  fun = function(i) {
    paste(i, collapse = "; ")
  }
)
names(obs) <- gsub(" ", "_", names(obs)) # remove spaces from column names
setDT(obs) # turn df to data.table to use dcast
obs <- dcast(
  obs,
  id + uri + observed_on + location + taxon.name + Alive_or_Dead + Evidence_of_Presence + Life_Stage + NA ~ name,
  value.var = "value",
  fun = function(i) {
    paste(i, collapse = "; ")
  }
)
names(obs) <- gsub(" ", "_", names(obs)) # remove spaces from column names

obs <- obs[,c("id", "observed_on", "taxon.name","location","uri","Evidence_of_Presence","Life_Stage","Gall_generation","Gall_phenophase")]

obs <- obs[!obs$Gall_generation=="",] # remove missing gall gen
obs <- obs %>% separate(location, c("Latitude","Longitude"), ",")
obs # this can be converted back to a df with as.data.frame

# obs <- read.csv("C:/Users/adam/Downloads/bkinnew.csv")

### first time look up of AGDD--!!!time consuming for large datasets!!! 
obs <- obs[!obs$Latitude=="NA",]
obs <- obs[!obs$Longitude=="NA",]
obs <- obs[!obs$observed_on=="NA",]
obs <- obs[!obs$Gall_phenophase=="senescent",]
agdd <- lookUpAGDD(obs)

agdd$phenogen <- paste(agdd$Gall_generation, agdd$Gall_phenophase, agdd$Life_Stage, sep="_")

# output the agdd data
write.csv(agdd, "C:/Users/adam/Downloads/bfosagdd.csv", row.names = FALSE)

# remove rows with invalid agdd
agdd <- agdd[!agdd$agdd=="-9999",]

# remove rows by id
# agdd <- agdd[!agdd$id %in% c(''),]

agdd$phenogen <- gsub("bisexual_developing_","Sexgen Developing",agdd$phenogen)
agdd$phenogen <- gsub("bisexual_maturing_Adult","Sexgen Emerging",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_developing_","Agamic Developing",agdd$phenogen)
agdd$phenogen <- gsub("bisexual_perimature_","Sexgen Perimature",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_maturing_Adult","Agamic Emerging",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_maturing_","Agamic Emerging",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_perimature_","Agamic Perimature",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_oviscar_","Agamic Oviscar",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_senescent_","Agamic Senescent",agdd$phenogen)

agdd$phenogen <- factor(agdd$phenogen, levels=c("Sexgen Developing", "Sexgen Developing (Pupa)", "Sexgen Emerging", "Sexgen Perimature", "Sexgen Adult","Agamic Oviscar","Agamic Developing","Agamic Emerging","Agamic Perimature", "Agamic Senescent"))

# plot by phenophase and generation if gall has marked alternating generations
boxplot(agdd$agdd~agdd$phenogen, horizontal=T)

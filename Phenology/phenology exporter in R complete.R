library(jsonlite)
library(data.table)
# library(foreach)
# library(stringr)
library(tidyr)
# library(purrr)
# library(iNatTools)
# library(remotes)
# library(rinat)
library(lubridate)
library(dplyr)
library(rnpn)
wd <- "C:/Users/adam/Documents/GitHub/gallformers/Phenology"
setwd(wd)

# this function calls the NPN database to associate an AGDD value with each observation based on lat/long and date
lookUpAGDD <- function(x){
  for (i in 1:dim(x)[1]){
    if (is.na(x$agdd)[i]||x$agdd[i]=="") {
      x$agdd[i]  <- npn_get_agdd_point_data('gdd:agdd',lat=paste0(x$Latitude[i]),long=paste0(x$Longitude[i]),date=paste0(x$observed_on[i]),store_data = FALSE)
    } else {
      x <- x
    }
  }
  return(x)
}

lookUpAGDD50 <- function(x){
 for (i in 1:dim(x)[1]){
  if (is.na(x$agdd)[i]||x$agdd[i]=="") {
    x$agdd50[i]  <- npn_get_agdd_point_data('gdd:agdd_50f',lat=paste0(x$Latitude[i]),long=paste0(x$Longitude[i]),date=paste0(x$observed_on[i]),store_data = FALSE)
  } else {
    x <- x
  }
}
return(x)
}

lookUpSinceLeaf <- function(x){
  for (i in 1:dim(x)[1]){
    if (is.na(x$agdd)[i]||x$agdd[i]=="") {
      x$leafdate[i]  <- npn_get_agdd_point_data('si-x:average_leaf_best',lat=paste0(x$Latitude[i]),long=paste0(x$Longitude[i]),date=paste0(x$observed_on[i]),store_data = FALSE)
    } else {
      x <- x
    }
  }
  return(x)
}

lookUpSinceBloom <- function(x){
  for (i in 1:dim(x)[1]){
  if (is.na(x$agdd)[i]||x$agdd[i]=="") {
    x$bloomdate[i]  <- npn_get_agdd_point_data('si-x:average_bloom_best',lat=paste0(x$Latitude[i]),long=paste0(x$Longitude[i]),date=paste0(x$observed_on[i]),store_data = FALSE)
  } else {
    x <- x
  }
}
return(x)
}
  
# layers <- npn_get_layer_details()

# npn_get_point_data('si-x:average_leaf_best',lat=paste0("35.9383583333"),long=paste0("-78.6970583333"),date=paste0("2016-04-01"))


### Get annotation codes
a <- fromJSON("https://api.inaturalist.org/v1/controlled_terms")
a <- flatten(a$results)
l <- lapply(seq_along(a[, "values"]), function(i) {
  cbind(idann = a$id[i], labelann = a$label[i], a[i, "values"][[1]][, c("id", "label")])
})
ann <- do.call("rbind", l)
ann

keep <-
  c("id", "observed_on", "taxon.name", "location", "uri", "ofvs","annotations") # values to keep

### Request url by Taxon ID
url <-
  paste0(
    "https://api.inaturalist.org/v1/observations?quality_grade=any&identifications=any&page=1&per_page=200&place_id=1&order=desc&order_by=created_at&taxon_id=",
    "146964"
)
### alt url template for observation by GF Code 
# url <-
#   paste0(
#     "https://api.inaturalist.org/v1/observations?quality_grade=any&identifications=any&page=1&per_page=200&place_id=1order=desc&order_by=created_at&", 
#     "any&field%3Agallformers%2Bcode=q-imbricaria-nipple-gall"
#   )

nobs <- fromJSON(url)
npages <- ceiling(nobs$total_results / 200)
xout <- flatten(nobs$results)
xout <- xout[,keep]

for(i in 2:npages) {
  # Get json and flatten
  page <- paste0("&page=", i)
  x <- fromJSON(gsub("&page=1", page, url))
  Sys.sleep(.5)
  x <- flatten(x$results)
  x1 <- x[,keep]
  xout <- rbind(xout,x1)
  }

x <- xout

    ### Extract annotations if any
  vals <- lapply(seq_along(x$annotations), function(i) {
    j <- x$annotations[[i]]
    n <- c("controlled_attribute_id", "controlled_value_id")
    if (all(n %in% names(j))) {
      # tests if there are any annotations for the obs
      ans <- j[, n]
    } else{
      ans <-
        data.frame(x = NA, y = NA) # if no annotations create NA data.frame
      names(ans) <- n
    }
    cbind(x[i, keep][rep(1, nrow(ans)),], ans) # repeat obs for each annotation value and bind with ann
  })
  vals <- do.call("rbind", vals) # bind everything
  
  keep <-
    c(
      "id",
      "observed_on",
      "taxon.name",
      "location",
      "uri",
      "ofvs",
      "controlled_attribute_id",
      "controlled_value_id"
    ) # values to keep
  
  ### Extract observation fields if any
  
  of <- lapply(seq_along(vals$ofvs), function(i) {
    f <- vals$ofvs[[i]]
    m <- c("name", "value")
    if (all(m %in% names(f))) {
      # tests if there are any annotations for the obs
      ans <- f[, m]
    } else{
      ans <-
        data.frame(x = NA, y = NA) # if no annotations create NA data.frame
      names(ans) <- m
    }
    cbind(vals[i, keep][rep(1, nrow(ans)),], ans) # repeat obs for each annotation value and bind with ann
  })
  
  of <- do.call("rbind", of) # bind everything
  
  
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
    id + uri + observed_on + location + taxon.name + Evidence_of_Presence + Life_Stage + NA ~ name,
    value.var = "value",
    fun = function(i) {
      paste(i, collapse = "; ")
    }
  )
  names(obs) <- gsub(" ", "_", names(obs)) # remove spaces from column names
  
  ## for galls with generation tagged
  obs <- obs[,c("id", "observed_on", "taxon.name","location","uri","Evidence_of_Presence","Life_Stage","Gall_generation","Gall_phenophase","Host_Plant_ID")]
  obs <- obs[!obs$Gall_generation=="",] # remove missing gall gen
  obs <- obs[!obs$Gall_phenophase=="senescent",]

  ## for galls with no generation tags
  # obs <- obs[,c("id", "observed_on", "taxon.name","location","uri","Evidence_of_Presence","Life_Stage","Gall_phenophase","Host_Plant_ID")]
  
  ## for all
  obs <- obs %>% separate(location, c("Latitude","Longitude"), ",")
  obs <- obs[!is.na(obs$Longitude),]
  obs$observed_on <- gsub("/", "-", obs$observed_on)
  obs <- obs[!obs$Evidence_of_Presence=="",]
  
  prev <- read.csv(paste0(wd, "/aqpetagdd.csv"))
  agdd <- as.data.frame(join(obs,prev, type = "full", match="first"))
  
  ### first time look up of AGDD--!!!time consuming for large datasets!!! 
  obs <- obs[!obs$Latitude=="NA",]
  obs <- obs[!obs$Longitude=="NA",]
  obs <- obs[!obs$observed_on=="NA",]
  obs <- obs[!obs$Gall_phenophase=="senescent",]
  agdd <- as.data.frame(lookUpAGDD(obs))
  agdd50 <- as.data.frame(lookUpAGDD50(obs))
  leafdate <- as.data.frame(lookUpSinceLeaf(obs))
  leafdate <- cbind(obs, leafdate) 
  agdd <- agddsav
  # agdd <- agdd[!agdd$Gall_phenophase=="dormant",]
  agdd <- agdd[!agdd$agdd=="-9999",]
  # boxplot(leafdate$sinceleaf~leafdate$phenogen, horizontal=T)
  agdd$phenogen <- paste(agdd$Gall_phenophase, agdd$Life_Stage, sep="_")
  
  boxplot(agdd$agdd~agdd$phenogen, horizontal=T)
  # boxplot(agdd50$agdd~agdd50$phenogen, horizontal=T)
  # plot(leafdate$Latitude, leafdate$sinceleaf)
  plot(agdd$Latitude, agdd$agdd)
  abline(a=5400,b=-115)
  # plot(agdd50$Latitude, agdd50$agdd)
  agdd$doy <- yday(agdd$observed_on)
  # leafdate$phenogen <- paste(leafdate$Gall_phenophase, leafdate$Life_Stage, sep="_")
  plot(yday(agdd$observed_on), agdd$agdd)
  # agdd50 <- agdd50[!agdd50$agdd=="-9999",]
  agdd32$phenogen <- paste(agdd32$Gall_phenophase, agdd32$Life_Stage, sep="_")
  agdd50$phenogen <- paste(agdd50$Gall_phenophase, agdd50$Life_Stage, sep="_")
  
  agdd$adj <- agdd$agdd - 5400 + 115 * as.numeric(agdd$Latitude)
  agdd$adj <- agdd$agdd - -0.6*(as.numeric(agdd$Latitude)-41.5)**3
  plot(yday(agdd$observed_on), agdd$adj)
  plot(agdd$Latitude, agdd$agdd)
  
  # agdd[agdd$Life_Stage == "Pupa",] <- NA
  # agdd[agdd$Life_Stage == "Egg",] <- NA
  agdd[agdd$Life_Stage == "Egg",] <- NA
  
  # for galls with two gens
  agdd$phenogen <- paste(agdd$Gall_generation, agdd$Gall_phenophase, agdd$Life_Stage, sep="_")
  
  #for galls with one gen
  agdd$phenogen <- paste(agdd$Gall_phenophase, agdd$Life_Stage, sep="_")
  boxplot(agdd$agdd~agdd$phenogen, horizontal=T)
  
  
  
  # output the agdd data
  write.csv(agdd, paste0("C:/Users/adam/Downloads/", "aqpet", "agdd.csv"), row.names = FALSE)
  agdd <- read.csv("C:/Users/adam/Downloads/acoo.csv")
  
  # remove rows with invalid agdd
  
  agdd <- agdd[!agdd$agdd=="-9999",]
  # agdd <- agdd[!agdd$phenogen=="unisexual__",]
  # agdd <- agdd[!agdd$Gall_phenophase=="oviscar",]
  # agdd <- agdd[!agdd$Host_Plant_ID=="",] # removes rows missing host ID
  # agdd <- agdd[!agdd$Host_Plant_ID=="47851",] # removes rows with host ID marked "oaks"
  # agdd <- agdd[!agdd$Host_Plant_ID=="861033",] # removes rows with host ID marked "white oaks"
  
  # remove rows by id
  # agdd <- agdd[!agdd$id %in% c(''),]
  agdd <- agdd[!is.na(agdd$Longitude),]
  agdd <- agdd[!agdd$phenogen=="unisexual__",]
  agdd <- agdd[!agdd$Gall_phenophase=="oviscar",]
  threshold <- 1700
  agdd <- agdd[agdd[,11]>threshold,]
  
  # for galls with two gens
  agdd$phenogen <- gsub("bisexual_developing_Pupa","Sexgen Developing (Pupa)",agdd$phenogen)
  agdd$phenogen <- gsub("bisexual_developing_Larva","Sexgen Developing (Larva)",agdd$phenogen)
  agdd$phenogen <- gsub("bisexual_developing_","Sexgen Developing",agdd$phenogen)
  agdd$phenogen <- gsub("bisexual__Adult","Sexgen Adult",agdd$phenogen)
  agdd$phenogen <- gsub("bisexual_maturing_Adult","Sexgen Emerging",agdd$phenogen)
  agdd$phenogen <- gsub("unisexual_developing_Larva","Agamic Developing (Larva)",agdd$phenogen)
  agdd$phenogen <- gsub("bisexual_developing_","Sexgen Developing",agdd$phenogen)
  agdd$phenogen <- gsub("unisexual_developing_","Agamic Developing",agdd$phenogen)
  agdd$phenogen <- gsub("bisexual_perimature_","Sexgen Perimature",agdd$phenogen)
  agdd$phenogen <- gsub("bisexual_senescent_","Sexgen Senescent",agdd$phenogen)
  
  
  agdd$phenogen <- gsub("unisexual__Adult", "Agamic Adult", agdd$phenogen)
  agdd$phenogen <- gsub("unisexual_maturing_Adult","Agamic Emerging",agdd$phenogen)
  agdd$phenogen <- gsub("unisexual_maturing_","Agamic Emerging",agdd$phenogen)
  agdd$phenogen <- gsub("unisexual_perimature_","Agamic Perimature",agdd$phenogen)
  agdd$phenogen <- gsub("unisexual_oviscar_","Agamic Oviscar",agdd$phenogen)
  agdd$phenogen <- gsub("unisexual_senescent_","Agamic Senescent",agdd$phenogen)
  
  agdd2 <- agdd
  
  # agdd$phenogen <- factor(agdd$phenogen, levels=c("Sexgen Developing", "Sexgen Developing (Larva)", "Sexgen Developing (Pupa)", "Sexgen Emerging", "Sexgen Perimature", "Sexgen Adult","Agamic Oviscar","Agamic Developing","Agamic Developing (Larva)","Agamic Emerging","Agamic Perimature","Agamic Adult", "Agamic Senescent"))
  # agdd$phenogen <- factor(agdd$phenogen, levels=c("Sexgen Developing","Agamic Developing","Agamic Developing (Larva)","Agamic Perimature","Agamic Adult"))
  
  
  agdd$phenogen <- factor(agdd$phenogen, levels=c("Sexgen Developing", "Sexgen Developing (Larva)", "Sexgen Developing (Pupa)", "Sexgen Perimature"))
  agdd$phenogen <- factor(agdd$phenogen, levels=c("Sexgen Developing","Agamic Developing","Agamic Developing (Larva)","Agamic Perimature","Agamic Adult"))
  # 
  
  #for galls with one gen
  agdd$phenogen <- gsub("developing_Larva","Developing (Larva)",agdd$phenogen)
  agdd$phenogen <- gsub("oviscar_","Oviscar",agdd$phenogen)
  agdd$phenogen <- gsub("developing_Adult","Developing (Adult)",agdd$phenogen)
  agdd$phenogen <- gsub("dormant_Larva","Dormant (Larva)",agdd$phenogen)
  agdd$phenogen <- gsub("developing_","Developing",agdd$phenogen)
  agdd$phenogen <- gsub("dormant_", "Dormant", agdd$phenogen)
  agdd$phenogen <- gsub("perimature_","Perimature",agdd$phenogen)
  agdd$phenogen <- gsub("senescent_","Senescent",agdd$phenogen)

  
  # agdd$phenogen <- factor(agdd$phenogen, levels=c("Oviscar","Developing", "Developing (Larva)", "Developing (Pupa)", "Developing (Adult)", "Dormant", "Dormant (Larva)", "Emerging", "Perimature", "Adult","Senescent"))
  # agdd$phenogen <- factor(agdd$phenogen, levels=c("Oviscar", "Developing", "Developing (Adult)", "Dormant", "Dormant (Larva)", "Perimature"))
  
  agdd$phenogen <- factor(agdd$phenogen, levels=c("Oviscar","Developing", "Developing (Larva)", "Developing (Pupa)", "Developing (Adult)", "Dormant", "Dormant (Larva)", "Emerging", "Perimature", "Adult","Senescent"))
  agdd$phenogen <- factor(agdd$phenogen, levels=c("Oviscar", "Developing", "Developing (Adult)", "Dormant", "Dormant (Larva)", "Perimature"))
    agdd <- agdd[!agdd$Gall_phenophase=="senescent",]
  # agdd <- agdd[!agdd$Gall_phenophase=="oviscar",]
  # plot by phenophase and generation if gall has marked alternating generations
  boxplot(agdd$adj~agdd$phenogen, horizontal=T)
  
  agdd$Host_Plant_ID <- gsub("swamp white oak", "Quercus bicolor",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("white oak", "Quercus alba",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("bur oak", "Quercus macrocarpa",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("119269", "Quercus stellata",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("54780", "Quercus bicolor",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("54779", "Quercus alba",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("54781", "Quercus macrocarpa",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("58726", "Quercus prinoides",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("128686", "Quercus montana",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("82754", "Quercus lyrata",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("54783", "Quercus muehlenbergii",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("371998", "Quercus margarettae",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("167642", "Quercus chapmanii",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("167661", "Quercus oglethorpensis",agdd$Host_Plant_ID)
  agdd$Host_Plant_ID <- gsub("242521", "Quercus sinuata breviloba",agdd$Host_Plant_ID)
  
  
  codes <- c("swamp white oak", "white oak","bur oak","119269","54780","54779","54781","58726","128686","82754","54783","371998","167642","167661","242521")
  binom <- c("Quercus bicolor","Quercus alba","Quercus macrocarpa","Quercus stellata","Quercus bicolor","Quercus alba","Quercus macrocarpa","Quercus prinoides","Quercus montana","Quercus lyrata","Quercus muehlenbergii","Quercus margarettae","Quercus chapmanii","Quercus oglethorpensis","Quercus sinuata breviloba")
  Hostcodes <- as.data.frame(cbind(codes, binom))
  agdd <- merge(agdd, Hostcodes, by.x = Host_Plant_ID, by.y=codes)
  
   
   
  
  
  qmac <- agdd[agdd$Host_Plant_ID=="54781",]
  boxplot(qmac$adj~qmac$phenogen, horizontal=T)
  
  qalb <- agdd[agdd$Host_Plant_ID=="54779",]
  boxplot(qalb$adj~qalb$phenogen, horizontal=T)
  
  qstel <- agdd[agdd$Host_Plant_ID=="119269",]
  boxplot(qstel$adj~qstel$phenogen, horizontal=T)
  
  qbic <- agdd[agdd$Host_Plant_ID=="54780",]
  boxplot(qbic$adj~qbic$phenogen, horizontal=T)
  
  qmar <- agdd[agdd$Host_Plant_ID=="371998",]
  boxplot(qmar$adj~qmar$phenogen, horizontal=T)

  qmue <- agdd[agdd$Host_Plant_ID=="54783",]
  boxplot(qmue$adj~qmue$phenogen, horizontal=T)
  
  qlyr <- agdd[agdd$Host_Plant_ID=="82754",]
  boxplot(qlyr$adj~qlyr$phenogen, horizontal=T)

  qmon <-  agdd[agdd$Host_Plant_ID=="128686",]
  boxplot(qmon$adj~qmon$phenogen, horizontal=T)
  
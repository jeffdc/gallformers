# install.packages("rnpn")
# install.packages('lubridate')
# install.packages('dplyr')
# install.packages("data.table")
# install.packages("rinat")
# install.packages("remotes")
# install_github("pjhanly/iNatTools")
# install.packages("tidyr")
# install.packages("stringr")

library(stringr)
library(tidyr)
library(purrr)
library(iNatTools)
library(remotes)
library(rinat)
library(lubridate)
library(data.table)
library(dplyr)
library(jsonlite)
library(rnpn)


# this function calls the NPN database to associate an AGDD value with each observation based on lat/long and date
lookUpAGDD <- function(x){
  for (i in 1:dim(x)[1]){
    x$agdd[i]  <- npn_get_agdd_point_data('gdd:agdd',lat=x$Latitude[i],long=x$Longitude[i],date=x$observed_on[i],store_data = FALSE)
  }
  return(x)
}

# import a csv from the downloads folder; change the name to correspond to the species in question
processed <- read.csv("C:/Users/adam/Downloads/bkinnew.csv")
# processed <- read.csv("C:/Users/adam/Downloads/bkin.csv")

# processed <- merge(processed, ann, by.x ="id", by.y = "Obs.ID" )

# these processing steps remove observations that are missing things like host plant, phenophase, or generation, or are marked senescent, or outside the US. 
# Comment them out as needed 
# processed <- processed[!processed$field.host.plant.id=="",]
# processed <- processed[!processed$Gall.Phenophase=="",]
processed <- processed[!processed$Gall.Phenophase=="senescent",]
# processed <- processed[!processed$Life.Stage=="7",]
processed <- processed[!processed$Gall.Generation=="",]
# processed <- processed[processed$place_country_name=="United States",]

processed$observed_on <- substr(processed$Obs.Date,1,10)

adults <- processed[processed$Evidence.of.Presence=="24",]
needobs <- adults[adults$Life.Stage=="",]
both <- processed[processed$Evidence.of.Presence=="24; 29",]
galls <- processed[processed$Evidence.of.Presence=="29",]
# needobs <- galls[galls$field.gall.generation=="",]
# galls <- galls[!galls$field.gall.generation=="",]


needobs <- processed[processed$phenogen=="unisexual__NA",]

# creates a new field that distinguishes the phenophases for both generations. Necessary for alternating gen cynipids, harmless if not present
processed$phenogen <- paste(processed$Gall.Generation, processed$Gall.Phenophase, processed$Life.Stage, sep="_")

# if you're reimporting or processing data for which the agdd has already been looked up, reimpot the old analysis and merge here
# no current code to separate out the ones that don't have agdd looked up and look only those up but this should be added in future
agdd <- read.csv("C:/Users/adam/Downloads/bfosagdd.csv")
# agdd <- merge(processed, agdd)

### first time look up of AGDD--!!!time consuming for large datasets!!! 
processed <- processed[!is.na(processed$Latitude),]
processed <- processed[!is.na(processed$Longitude),]
processed <- processed[!is.na(processed$observed_on),]

#need to replace any possible case of 2022/05/22 with 2022-05-22 in observed_on before inputting or the whole thing breaks without producing a single result!!
processed$observed_on <- gsub("/","-",processed$observed_on)

agdd <- lookUpAGDD(processed)

# output the agdd data
write.csv(agdd, "C:/Users/adam/Downloads/bkinagdd.csv", row.names = FALSE)

# remove rows with invalid agdd
agdd <- agdd[!agdd$agdd=="-9999",]

# remove rows by id
agdd <- agdd[!agdd$id %in% c('115457525'),]

agdd$phenogen <- paste(agdd$Gall.Generation, agdd$Gall.Phenophase, agdd$Life.Stage, sep="_")

# code to divide by host plant if included in the data, modify as appropriate
# qmac <- agdd[agdd$field.host.plant.id=="Quercus macrocarpa",]
# qalb <- agdd[agdd$field.host.plant.id=="Quercus alba",]
# qstel <- agdd[agdd$field.host.plant.id=="Quercus stellata",]

# to graph by host plant
# boxplot(qstel$agdd~qstel$phenogen, horizontal=T)
# boxplot(qalb$agdd~qalb$phenogen, horizontal=T)
# boxplot(qmac$agdd~qmac$phenogen, horizontal=T)

# plot by phenophase if gall is only one generation
boxplot(agdd$agdd~agdd$field.gall.phenophase, horizontal=T)

# plot by life stage
boxplot(agdd$agdd~agdd$field.gall.phenophase, horizontal=T)

agdd <- agdd[!agdd$phenogen=="bisexual__NA",]
agdd <- agdd[!agdd$phenogen=="unisexual__NA",]
agdd <- agdd[!agdd$phenogen=="unisexual_developing_7",]
agdd$phenogen <- gsub("bisexual__2","Sexgen Adult",agdd$phenogen)
agdd$phenogen <- gsub("bisexual__4","Sexgen Developing (Pupa)",agdd$phenogen)
agdd$phenogen <- gsub("bisexual_developing_NA","Sexgen Developing",agdd$phenogen)
agdd$phenogen <- gsub("bisexual_developing_4","Sexgen Developing (Pupa)",agdd$phenogen)
agdd$phenogen <- gsub("bisexual_developing_6","Sexgen Developing (Larva)",agdd$phenogen)
agdd$phenogen <- gsub("bisexual_maturing_2","Sexgen Emerging",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_developing_NA","Agamic Developing",agdd$phenogen)
agdd$phenogen <- gsub("bisexual_perimature_NA","Sexgen Perimature",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_maturing_2","Agamic Emerging",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_maturing_NA","Agamic Emerging",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_perimature_NA","Agamic Perimature",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_oviscar_NA","Agamic Oviscar",agdd$phenogen)
agdd$phenogen <- gsub("unisexual_senescent_NA","Agamic Senescent",agdd$phenogen)

agdd$phenogen <- factor(agdd$phenogen, levels=c("Sexgen Developing", "Sexgen Developing (Larva)", "Sexgen Developing (Pupa)", "Sexgen Emerging", "Sexgen Perimature", "Sexgen Adult","Agamic Oviscar","Agamic Developing","Agamic Emerging","Agamic Perimature", "Agamic Senescent"))


# plot by phenophase and generation if gall has marked alternating generations
boxplot(agdd$agdd~agdd$phenogen, horizontal=T)

# output the processed agdd data
write.csv(agdd, "C:/Users/adam/Downloads/bkin processed.csv", row.names = FALSE)


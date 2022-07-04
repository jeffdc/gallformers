library(rnpn)
library(dplyr)
library(plyr)
library(lubridate)
library(daymetr)
setwd("C:/Users/adam/Documents/GitHub/gallformers/Phenology")

species <- npn_species()
oaks <- species[grepl('Quercus',species$genus),]
# 
alba <- npn_phenophases_by_species(100, 2020-03-31)
# 
# albphen <- npn_download_individual_phenometrics(
#   request_source='gallformers',
#   years=c('2020'),
#   species_id=c('100'), 
#   phenophase_ids = c('371'), 
#   agdd_layer='32')
# budb <- albphen[albphen$phenophase_id=='501']
# 
# df <- npn_download_individual_phenometrics(
#   request_source = 'Gallformers', 
#   years = c(2020), 
#   species_ids = c(100),
#   phenophase_ids = c(371),
#   agdd_layer = 32
#   )

df <- npn_download_individual_phenometrics(
  request_source = 'Gallformers', 
  years = c(2008:2019), 
  species_ids = c(100),
  phenophase_ids = c(371),
)

df <- df[df$numdays_since_prior_no<10,]
df <- df[!df$numdays_since_prior_no==-9999,]
df <- df[df$first_yes_doy<172]
mean(df$first_yes_doy) - 3*sd(df$first_yes_doy)
df <- df[df$first_yes_doy>54,]
df <- df[df$first_yes_doy<170,]
tma <- df[df$site_id==26202,]
fivenum(df$latitude)

length(unique(df$site_id))
length(unique(df$individual_id))







plot(
  df$first_yes_doy~df$first_yes_year,
  ylab=c("Day of Year"), xlab=c("Year"), ylim=c(1,350),
  cex=2,  cex.axis=1.5, cex.lab=1.5, pch=21
)

df_6Y <- df %>%
  group_by(df$individual_id) %>% 
  filter(n_distinct(first_yes_year) > 4)

quantiles <- as.data.frame(df_6Y %>%
                             group_by(individual_id) %>%
                             summarize(Q1 = quantile(first_yes_doy, .25), 
                                       Q3 = quantile(first_yes_doy, .75),
                                       IQR <- IQR(first_yes_doy)))

# Create a reference data frame which gives the quantiles and IQR by individual ID

df_6Y_Q = df_6Y %>% 
  right_join(quantiles, by = "individual_id")

df_6Y_Q  <- df_6Y_Q  %>%
  rename('IQR' = 'IQR <- IQR(first_yes_doy)')

# Remove first yes records that fall outside of 1.5 times the interquartile range for the individual plant.

df_6Y_clean <- subset(
  df_6Y_Q, (df_6Y_Q$first_yes_doy > (Q1 - 1.5*df_6Y_Q$IQR) & 
              df_6Y_Q$first_yes_doy < (Q3 + 1.5*df_6Y_Q$IQR))
)

# Visualize the data with the outliers removed.

plot(
  df_6Y_clean$first_yes_doy~df_6Y_clean$first_yes_year,
  ylab=c("Day of Year"), xlab=c("Year"), ylim=c(1,350),
  cex=2,  cex.axis=1.5, cex.lab=1.5, pch=21
)

plot(
  df_6Y_clean$last_yes_doy~df_6Y_clean$last_yes_year,
  ylab=c("Day of Year"), xlab=c("Year"), ylim=c(1,350),
  cex=2,  cex.axis=1.5, cex.lab=1.5, pch=21
)


df_6Y_clean <- df_6Y_clean %>%
rename(
  Latitude = latitude,
  Longitude = longitude
)

df_6Y_clean$observed_on <- as.Date(df_6Y_clean$first_yes_doy - 1, origin=paste0(df_6Y_clean$first_yes_year, "-01-01"))
  
df_6Y_agdd <- lookUpAGDD(df_6Y_clean)

write.csv(df_6Y_agdd, "C:/Users/adam/Documents/GitHub/gallformers/Phenology/qvirgleafoutagdd.csv")
qalb <- read.csv("C:/Users/adam/Documents/GitHub/gallformers/Phenology/qalbaleafoutagdd.csv")
qalb <- qalb[!qalb$numdays_since_prior_no=="-9999",]
boxplot(qalb$agdd~qalb$state, horizontal=T)

plot(qalb$agdd~qalb$Latitude)

df_6Y_agdd <- df_6Y_agdd[!df_6Y_agdd$numdays_since_prior_no > 15,]

plot(
df_6Y_agdd$agdd~df_6Y_agdd$first_yes_doy,
ylab=c("AGDD"), xlab=c("DOY"), ylim=c(350,3000),
cex=2,  cex.axis=1.5, cex.lab=1.5, pch=21
)

text(df_6Y_agdd$first_yes_doy, df_6Y_agdd$agdd, labels=df_6Y_agdd$state)

plot(
  df_6Y_agdd$agdd~df_6Y_agdd$elevation_in_meters,
  ylab=c("AGDD"), xlab=c("Elevation"), ylim=c(350,3000),
  cex=2,  cex.axis=1.5, cex.lab=1.5, pch=21
)

text(df_6Y_agdd$elevation_in_meters, df_6Y_agdd$agdd, labels=df_6Y_agdd$state)



# download raster by doy and save in WD. 1-3 already down, no need to call again
#  for(elevation in 4:365){
#   npn_download_geospatial('gdd:30yr_avg_agdd', paste0(elevation), output_path=paste0(sprintf("%03d", elevation), '_DOY_30yr_avg_agdd', '.tif'))
# }

              
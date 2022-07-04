library(raster)
library(sp)
library(lubridate)
library(rnpn)
library(leaflet)
rm(list=ls())

Rasters <- "Your path goes here"
Output <- "your path goes here"


#Download all the DOY (uses the elevation param for day of year) rasters (this code gets the firs 100 days for the long-term averages, 50 base temp)
setwd(Rasters)
for(elevation in 1:100){
  npn_download_geospatial('gdd:30yr_avg_agdd_50f', paste0(elevation), output_path=paste0(sprintf("%03d", elevation), 'DOY', '.tif'))
}

#create a stack of rasters where each layer is a day of year
files <- list.files(getwd(),pattern="*.tif")
AGDD_stack <- stack(files)
NAvalue(AGDD_stack) <- -9999
AGDD_stack

#check a few images and names
plot(AGDD_stack[[195:200]])
names(AGDD_stack)

#trim to the northeast
us <- getData("GADM", country="USA", level=1)
NE<-subset(us,NAME_1=="Maine" | NAME_1=="Vermont" | NAME_1=="New Hampshire" | 
             NAME_1=="Massachusetts" | NAME_1=="Connecticut" | NAME_1=="Pennsylvania" | 
             NAME_1=="New Jersey" | NAME_1=="Delaware" | NAME_1=="Maryland"| NAME_1=="Virginia"| 
             NAME_1=="West Virginia"| NAME_1=="Kentucky" | NAME_1=="Rhode Island" | NAME_1=="New York")

NE_AGDD<-mask(AGDD_stack, NE)
plot(NE_AGDD[[150]])

#Drop (set to NULL/NA) all pixels that have not reached a given number (450 gdds)
f <- function(r1)  ifelse(r1 > 450, r1,  NA)
NE_AGDD_over450 <-calc(NE_AGDD, fun=f)

plot(NE_AGDD_over450[[160]])


#Take the layer of the minimum value as the raster value
DOY <- which.min(NE_AGDD_over450)
plot(DOY, xlim=c(-74,-69.5), ylim=c(42 ,46))

setwd(Output)
writeRaster(DOY, "NECASC_DOY_450.tiff",
            format="GTiff",
            overwrite=TRUE,
            NANHag=-9999)

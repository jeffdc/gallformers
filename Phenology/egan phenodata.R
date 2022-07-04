library(tidyverse)
library(rnpn)
library(lubridate)
library(data.table)
library(spatstat)
# this function calls the NPN database to associate an AGDD value with each observation based on lat/long and date
lookUpAGDD32 <- function(x){
  for (i in 1:dim(x)[1]){
    x$agdd32[i]  <- npn_get_agdd_point_data('gdd:agdd',lat=paste0(x$Latitude[i]),long=paste0(x$Longitude[i]),date=paste0(x$observed_on[i]),store_data = FALSE)
  }
  return(x)
}
lookUpAGDD50 <- function(x){
  for (i in 1:dim(x)[1]){
    x$agdd50[i]  <- npn_get_agdd_point_data('gdd:agdd_50f',lat=paste0(x$Latitude[i]),long=paste0(x$Longitude[i]),date=paste0(x$observed_on[i]),store_data = FALSE)
  }
  return(x)
}
wd <- "C:/Users/adam/Documents/GitHub/gallformers/Phenology"
setwd(wd)
sites <- data.frame(Site = c("Archbold","Lake Lizzie","Dickinson","Kissimmee","Okeechobee","Alva","Gatorama"),
                     Latitude = c(27.1831, 28.2451, 27.0029, 27.9828, 27.1968, 26.7297, 26.9326),
                     Longitude = c(-81.3552,-81.1681,-80.1015,-81.3826,-80.8291,-81.6107,-81.29)
                                  )
btre <- read.csv(paste0(wd,"/Emergence in Nature.csv"))
supp1 <- read.csv("C:/Users/adam/Downloads/rsbl20190572supp1.csv")
supp3 <- read.csv(paste0(wd, "/rsbl20190572supp3.csv"))
supp3$observed_on <-  as.Date(supp3$Emergence.date, format = "%m/%d/%y")
flda <- supp3[supp3$State=="FL",]
cgbrk <- read.csv(paste0(wd, "/Initial Budbreak Common Garden.csv"))
bdbr <- read.csv(paste0(wd,"/Budbreak in Nature.csv"))
bdbr$observed_on <- as.Date(bdbr$Date.Monitored, format = "%m/%d/%Y")
fl$doy <- yday(fl$observed_on)
bkin <- read.csv(paste0(wd, "/bkinagdd.csv"))
nqv <- read.csv(paste0(wd, "/nqvagdd.csv"))

btre$observed_on <- as.Date(btre$observed_on, format = "%m/%d/%Y")
btre <- merge(sites,btre)
btre$doy <- yday(btre$observed_on)
fl <- read.csv(paste0(wd,"/Herbarium Records.csv"))
fl$observed_on <- as.Date(fl$observed_on, format = "%m/%d/%Y")
fl <- fl[!fl$Flowers=="N",]
fl <- fl[!yday(fl$observed_on)>180,]
boxplot(yday(fl$observed_on)~fl$Plant.species, horizontal = T)
flqv <-  fl[fl$Plant.species=="Quercus virginiana",]
fivenum(yday(flqv$observed_on))
flqg <-  fl[fl$Plant.species=="Quercus geminata",]
fivenum(yday(flqg$observed_on))

btqv <- btre[btre$Host.Plant=="Quercus virginiana",]

weighted.quantile(yday(btqv$observed_on), btqv$Caught, probs=seq(0.75,1), na.rm=TRUE)
fivenum(yday(btre$observed_on))



# processing common garden data--doesn't need to be done again if imported from Phenology
# cgbrk$observed_on <- as.Date(cgbrk$Date.first.break, format = "%m/%d/%Y")
# cgbrk$Latitude <- c("29.88616")
# cgbrk$Longitude <- c("-97.94669")
# write.csv(cgbrk, paste0(wd, "/Initial Budbreak Common Garden.csv"), row.names = FALSE)
cgqv <-  cgbrk[cgbrk$Host.plant=="Quercus virginiana",]
fivenum(cgqv$agdd32)
fivenum(cgqv$agdd50)
fivenum(yday(cgqv$observed_on))
cgqg <-  cgbrk[cgbrk$Host.plant=="Quercus geminata",]
fivenum(cgqg$agdd32)
fivenum(cgqg$agdd50)
fivenum(yday(cgqg$observed_on))
boxplot(cgbrk$agdd32~cgbrk$Host.plant, horizontal=T)
boxplot(cgbrk$agdd50~cgbrk$Host.plant, horizontal=T)
boxplot(yday(cgbrk$observed_on)~cgbrk$Host.plant, horizontal=T)
ggplot(cgbrk) +
  geom_point(aes(x=observed_on, y = agdd32, color = Host.plant))

DT <- data.table(bdbr)
DTsums <- DT[, sum(Number.leaves.flushed)/sum(Total.leaves.monitored),by=list(Plant.number,observed_on,Site,Plant.species)]
names(DTsums)[names(DTsums)=="V1"] <- "FlushPercent"
DTsums <- merge(DTsums, sites)
DTsums <- lookUpAGDD32(DTsums)
DTsums <- lookUpAGDD50(DTsums)
DTsums <- DTsums[!DTsums$agdd32=="-9999",]
ggplot(DTsums) +
  geom_point(aes(x=agdd32, y = FlushPercent, color = Plant.species))
write.csv(DTsums, paste0(wd, "/Budbreak in Nature.csv"), row.names = FALSE)

dt <- dt[!dt$FlushPercent=="0",]
firsts <- dt[, min(FlushPercent),by=list(Plant.number,Site,Plant.species)]
names(firsts)[names(firsts)=="V1"] <- "FlushPercent"
first <- merge(firsts,dt,by=c("Plant.number","Site","Plant.species","FlushPercent"))
boxplot(yday(first$observed_on)~first$Plant.species, horizontal=T)
boxplot(first$agdd32~first$Plant.species, horizontal=T)

dtqv <- first[first$Plant.species=="Quercus virginiana",]
dtqg <- first[first$Plant.species=="Quercus geminata",]
fivenum(dtqv$agdd32)
fivenum(dtqv$agdd50)
fivenum(yday(dtqv$observed_on))
fivenum(dtqg$agdd32)
fivenum(dtqg$agdd50)
fivenum(yday(dtqg$observed_on))


dt <- dt[!dt$FlushPercent=="0",]
firsts <- dt[, max(FlushPercent),by=list(Plant.number,Site,Plant.species)]
names(firsts)[names(firsts)=="V1"] <- "FlushPercent"
first <- merge(firsts,dt,by=c("Plant.number","Site","Plant.species","FlushPercent"))



#remove dates earlier than we can get AGDD for
supp3 <- supp3[!supp3$Year=="2015",]
supp3 <- supp3[supp3$Emergent.animal.type=="cynipid",]
supp3$ <- 

#subset for Andricus quercuslanigera
alan <- flda[flda$Species=="A. lanigera",]

#remove inquiline records
alan <- alan[alan$Emergent.animal.type=="cynipid",]

alan <- supp3[supp3$Species=="A. lanigera",]
alan <- lookUpAGDD32(alan)

#plot
boxplot(yday(cgbrk$observed_on)~cgbrk$Host.plant, horizontal = T)
ggplot(cgbrk) +
  geom_point(aes(x=observed_on, y = agdd32, shape = Host.plant))

boxplot(alanagdd$emergeagdd~alanagdd$Host.plant, horizontal = T)
boxplot(yday(alanagdd$observed_on)~alanagdd$Host.plant, horizontal = T)
alanqg <- alan[alan$Host.plant=="Qg",]
alanqv <- alan[alan$Host.plant=="Qv",]
fivenum(alanqv$E.julian)
fivenum(alanqg$E.julian)
fivenum(alanqv$agdd32)
fivenum(alanqg$agdd32)



plot(alanagdd$E.julian~alanagdd$H.julian)
boxplot(alan2$agdd~alan2$State, horizontal = T)
alan2$Host.plant <- factor(alan2$Host.plant)
alan2$State <- factor(alan2$State)
ggplot(alan2) +
       geom_point(aes(x=agdd, y = emergeagdd, color = Host.plant))



#subset for Andricus foliatus
fol <- flda[flda$Species=="A. foliatus",]

#remove inquiline records
fol <- fol[fol$Emergent.animal.type=="cynipid",]

folagdd <- lookUpAGDD32(fol)
folagdd$emergeagdd <- folagdd$agdd32
folagdd$agdd32 <- NULL
folagdd$observed_on <-  as.Date(folagdd$Emergence.date, format = "%m/%d/%y")
folagdd <- folagdd[!folagdd$emergeagdd=="-9999",]

#remove winter observations
folagdd <- folagdd[!folagdd$E.julian<366,]

#plot
boxplot(folagdd$emergeagdd~folagdd$Host.plant, horizontal = T)
boxplot(yday(folagdd$observed_on)~folagdd$Host.plant, horizontal = T)
folqv <- folagdd[folagdd$Host.plant=="Qg",]
folqg <- folagdd[folagdd$Host.plant=="Qv",]
fivenum(yday(folqv$observed_on))
fivenum(yday(folqg$observed_on))
fivenum(folqv$emergeagdd)
fivenum(folqg$emergeagdd)

#B treatae emergence
btre <- lookUpAGDD32(btre)
btre$doy <- yday(btre$observed_on)
btre <- btre[!btre$agdd32=="-9999",]
btreqv <- btre[btre$Host.Plant=="Quercus virginiana",]
btreqg <- btre[btre$Host.Plant=="Quercus geminata",]
plot(btreqv$agdd32, btreqv$Caught)
plot(btreqg$doy, btreqv$Caught)  
plot(btreqg$agdd32, btreqg$Caught)
plot(btreqg$doy, btreqg$Caught)  
geom_histogram(yday(btreqv$observed_on)) 

boxplot(yday(bkin$observed_on)~bkin$Gall.Phenophase, horizontal = T)
bkin <- bkin[bkin$Gall.Generation=="bisexual",]

bkin$Gall.Phenophase[bkin$Gall.Phenophase==""]<-"Adult"
bkin <- bkin[bkin$Gall.Phenophase=="Adult",]

fivenum(yday(bkin$observed_on))
fivenum(bkin$agdd)

dqv <- supp3[supp3$Species=="D. q. virens",]
# dqv <- lookUpAGDD32(dqv)
fall <- dqvfull[yday(dqvfull$observed_on)>155,]
fall$doy <- yday(fall$observed_on)
dqv <- dqv[yday(dqv$observed_on)<155,]
dqv$doy <- yday(dqv$observed_on)  + 365
dqv$agdd32 <- replace(dqv$agdd32,dqv$agdd32=="-9999",0)
dqv <- rbind(fall, dqv)

dqvvirg <- dqv[dqv$Host.plant=="Qv",]
dqvgem <- dqv[dqv$Host.plant=="Qg",]
plot(dqv$agdd32, yday(dqv$observed_on))
fivenum(dqvvirg$doy)
fivenum(dqvgem$doy)
fivenum(dqvvirg$agdd32)
fivenum(dqvgem$agdd32)

cbat <- supp3[supp3$Species=="C. batatoides",]
# cbat <- lookUpAGDD32(cbat)
boxplot(cbat$agdd32~cbat$Host.plant, horizontal = T)
cbatvirg <- cbat[cbat$Host.plant=="Qv",]
cbatgem <- cbat[cbat$Host.plant=="Qg",]

fivenum(yday(cbatvirg$observed_on))
fivenum(yday(cbatgem$observed_on))
fivenum(cbatvirg$agdd32)
fivenum(cbatgem$agdd32)



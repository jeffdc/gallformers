my_taxon_id <- 1090187
iNaturl_obs <- paste0("http://api.inaturalist.org/v1/observations?place_id=any","&taxon_id=", my_taxon_id,"&verifiable=any")

data.frame(c("Life.Stage","Evidence.Of.Presence"))

obs <- fromJSON(iNaturl_obs)

for (i in 1:dim(as.data.frame(obs))[1]){
  a <- c(1:dim(as.data.frame(obs[[4]]$annotations[[2]]$concatenated_attr_val))[1])
  a  <- obs[[4]]$annotations[[i]]$concatenated_attr_val)
}

a <- c(1:dim(as.data.frame(obs[[4]]$annotations[[2]]$concatenated_attr_val))[1])
a  <- rbind(a, )

ann1 <- as.data.frame(obs[[4]]$annotations[[4]]$concatenated_attr_val)
ann1 %>% 
  separate(ann1, ann1[1], c("Annotation","Value"), sep = '\\|')
ann1 <- as.data.frame(as.character(ann1[1]))

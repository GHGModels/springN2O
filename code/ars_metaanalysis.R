# setup ----
library(tidyverse)
library(lubridate)
library(modelr)
library(stringr)
library(aqp)
library(soilDB)


# read and select ars flux data ----
ars_fluxes<-read_csv("../data/ars/ars_fluxes.csv", skip = 2)

fluxes<-ars_fluxes%>%
  select(`Experimental Unit ID`, Date, N2O, Air_Temp, Soil_Temp, Soil_Moisture)%>%
  mutate(Date = mdy_hms(Date))%>%
  separate(`Experimental Unit ID`, c("state","exp"), sep = 3)

head(fluxes)

  
# read and select ars weather data ----
ars_weather<-read_csv("../data/ars/ars_weather.csv", skip = 2)

weather<-ars_weather%>%
  select(`Site ID`, Date, `Temperate, air, daily, maximum, degrees Celsius`, `Temperate, air, daily, minimum, degrees Celsius`, Precip, `Total_Net_Radn`)%>%
  mutate(Date = mdy_hms(Date))%>%
  separate(`Site ID`, c("state","exp"), sep = 3)%>%
  filter(state != "ORP")%>%
  select(-exp)%>%
  mutate(Total_Net_Radn = as.numeric(Total_Net_Radn))

head(weather)


# read and select ars weather station data for longitude and latitude ----
ars_latlong<-read_csv("../data/ars/ars_latlong.csv")

latlong<-ars_latlong%>%
  select(`Experimental Unit`, `Latitude of weather station, decimal degrees`, `Longitude of weather station, decimal degrees`)%>%
  rename(lat = `Latitude of weather station, decimal degrees`, long = `Longitude of weather station, decimal degrees`)%>%
  separate(`Experimental Unit`, c("state","exp"), sep = 3)%>%
  filter(state != "ORP")

head(latlong)

# read and select daymet ars data ----		
daymet_mandan<-read_csv("../data/ars/daymet_mandan.csv", skip = 7)		
daymet_mandan$town<-"Mandan"		
daymet_morris<-read_csv("../data/ars/daymet_morris.csv", skip = 7)		
daymet_morris$town<-"Morris"		
daymet_roseville<-read_csv("../data/ars/daymet_roseville.csv", skip = 7)		
daymet_roseville$town<-"Roseville"		
daymet_university_park<-read_csv("../data/ars/daymet_university_park.csv", skip = 7)		
daymet_university_park$town<-"University_Park"		
daymet_west_lafayette<-read_csv("../data/ars/daymet_west_lafayette.csv", skip = 7)		
daymet_west_lafayette$town<-"West_Lafayette"		
		
daymet<-rbind(daymet_mandan, daymet_morris, daymet_roseville, daymet_university_park, daymet_west_lafayette)		
		
daymet$date<-as.Date(strptime(paste(daymet$year, daymet$yday), format="%Y%j"))		
colnames(daymet)<-c("year", "yday", "daymet_prcp", "daymet_radn", "daymet_tmax", "daymet_tmin", "town", "date")		
		
head(daymet)

coldness<-daymet%>%
  mutate(spring_year = ifelse((date >"2003-06-02" & date < "2004-06-02"), 2004,
                              ifelse((date >"2004-06-02" & date < "2005-06-02"), 2005,
                                     ifelse((date >"2005-06-02" & date < "2006-06-02"), 2006,
                                            ifelse((date >"2006-06-02" & date < "2007-06-02"), 2007,
                                                   ifelse((date >"2007-06-02" & date < "2008-06-02"), 2008,
                                                          ifelse((date >"2008-06-02" & date < "2009-06-02"), 2009,
                                                                 ifelse((date >"2009-06-02" & date < "2010-06-02"), 2010,
                                                                        ifelse((date >"2010-06-02" & date < "2011-06-02"), 2011, 0)))))))))%>%
  filter(daymet_tmin < 0)%>%
  group_by(town, spring_year)%>%
  summarise(cold_sum = sum(daymet_tmin))%>%
  filter(spring_year != 0)%>%
  rename(year = spring_year)
  

# read and select soils series for experiments ----
ars_soilseries<-read_csv("../data/ars/ars_soilseries.csv")

soils<-ars_soilseries%>%
  select(`Experimental Unit`, `Soil series`)%>%
  rename(series = `Soil series`)%>%
  separate(`Experimental Unit`, c("state","exp"), sep = 3)%>%
  filter(state != "ORP")%>%
  #select(-exp)%>%
  distinct()%>%
  mutate(series = word(series, 1))%>%
  na.omit()

head(soils)

# get and add soil data ----  

our_soils<-soils%>%
  distinct(series)%>%
  mutate(dom_soil = word(series, 1))%>%
  distinct(dom_soil)%>%
  na.omit()

get_soil_data <- function(series){
  horizons(fetchKSSL(series))%>%
    select(pedon_key, hzn_desgn, sand, silt, clay, oc, ph_h2o)%>%
    filter(grepl('A', hzn_desgn))%>%
    select(-c(hzn_desgn, pedon_key))%>%
    summarise_each(funs(mean(., na.rm = TRUE)))%>%
    mutate(series = series)  
}  

brute_errors<-lapply(our_soils$dom_soil, function(series) try(get_soil_data(series)))

ars_soils<-bind_rows(Filter(function(series) !inherits(series, "try-error"), brute_errors))
 

# join and filter fluxes, weather, and location data ----
ars<-left_join(weather, fluxes, by=c("state", "Date"))
ars<-left_join(ars, soils, by = c("state", "exp"))
ars<-left_join(ars, ars_soils, by = "series" )
ars<-left_join(ars, latlong, by = "state")


colnames(ars)<-c("site", "date", "max_temp", "min_temp", 
                 "precip", "radn", "exp", "N2O", "air_temp",
                 "soil_temp", "soil_moisture", "series", 
                 "sand", "silt", "clay", "oc", "ph_h2o", "exp.y", "lat", "long")

ars<-ars%>%
  select(-exp.y)%>%
  mutate(year = year(date), month = month(date), day = yday(date))


head(ars)

    
# looking only at sites that freeze ----
ars_cold<-ars %>% filter(site %in% c("INA", "INT", "INW", "MNM", "MNR", "NDM", "NEM", "NVN", "PAH"))%>%
  mutate(town = ifelse((site %in% c("INA", "INT", "INW")), "West_Lafayette",
                       ifelse((site == "MNM"), "Morris",
                              ifelse((site == "MNR"), "Roseville",
                                     ifelse((site %in% c("NDM", "NEM", "NVN")), "Mandan",
                                            ifelse((site == "PAH"), "University_Park", "NA" ))))), date = as.Date(date))


ars_cold%>%
  select(-exp, -series)%>%
  #group_by(site, town, date, year, month, day)%>%
  #summarise_each(funs(mean(., na.rm = TRUE)))%>%
  filter(year %in% 2004:2011)%>%
  ggplot((aes(x = town, y = N2O)))+
  geom_jitter(alpha = .3) 

ars_cold%>%
  select(-exp, -series)%>%
  group_by(site, town, date, year, month, day)%>%
  summarise_each(funs(mean(., na.rm = TRUE)))%>%
  filter(year %in% 2004:2011)%>%
ggplot(aes(N2O, fill=town, color=town))+
  geom_density(alpha =.1)+
  xlim(-15, 35)+
  facet_wrap(~year)

  

# make average spring N2O for a response variable ----
  #may want to try converting average N2O into cumulative N2O like Wagner-Riddle
ars_spring<-ars_cold%>% 
  filter(day<150)%>%
  select(-exp, -series)%>%
  group_by(site,town, year)%>%
  summarise(avg_N2O = (mean(N2O, na.rm = TRUE)))

ggplot(ars_spring, aes(x=year,y=avg_N2O))+
  geom_point()+
  facet_wrap(~site)

daymet_cold<-left_join(coldness, ars_spring)

ggplot(daymet_cold, aes(x=cold_sum, y=avg_N2O))+
  geom_point()+
  facet_wrap(~town)+
  geom_smooth(method='lm')

ggplot(daymet_cold, aes(x=year, y=cold_sum, color= town))+
  geom_point()

# make annual, temperature-based variables for factors ----

  #what about a summer-temp and a winter-temp if I put the other sites back in?
   
  #need to re-partition year June-June (keep winter period together)
ars_cold<-ars_cold%>%
  mutate(spring_year = ifelse((date >"2003-06-02" & date < "2004-06-02"), 2004,
                        ifelse((date >"2004-06-02" & date < "2005-06-02"), 2005,
                               ifelse((date >"2005-06-02" & date < "2006-06-02"), 2006,
                                      ifelse((date >"2006-06-02" & date < "2007-06-02"), 2007,
                        ifelse((date >"2007-06-02" & date < "2008-06-02"), 2008,
                          ifelse((date >"2008-06-02" & date < "2009-06-02"), 2009,
                             ifelse((date >"2009-06-02" & date < "2010-06-02"), 2010,
                                ifelse((date >"2010-06-02" & date < "2011-06-02"), 2011, 0)))))))))

day<-c(155:365, 1:154)
new_days<-1:365

new_year<-data.frame(day, new_days)

ars_cold<-left_join(ars_cold, new_year, by = "day")
  
#sum up the days each winter that air temp reached 0 or lower (freeze day)
ars_freeze_day<-ars_cold%>%
  mutate(freeze_day = ifelse((daymet_tmin <0), 1, 0))%>%
  group_by(spring_year, site)%>%
  distinct(date, .keep_all=TRUE)%>%
  mutate(cum_freeze_day = cumsum(freeze_day))%>%
  summarise(annual_freeze_day = max(cum_freeze_day))%>%
  rename(year = spring_year)%>%
  right_join(ars_spring, by = c("year", "site"))

  #sum up the actual minimum temperatures to define coldest years and sites (freezing degree day(fdd))
  #fewer fdd = colder winter
ars_cold_sum<-ars_cold%>%
  #filter(daymet_tmin < 0)%>%
  distinct(date, .keep_all=TRUE)%>%
  group_by(spring_year, site)%>%
  summarise(cold_sum = sum(daymet_tmin))%>%
  filter(spring_year != 0)%>%
  rename(year = spring_year)

ggplot(ars_cold_sum, aes(x=date, y = daymet_tmin))+
  geom_point()+
  facet_wrap(~site)

ars_fdd<-ars_cold%>%
  filter(new_days>120 & new_days < 285)%>%
  group_by(spring_year, site)%>%
  distinct(date, .keep_all=TRUE)%>%
  mutate(cum_fdd = cumsum(min_temp))%>%
  mutate(cum_wdd = cumsum(max_temp))%>%
  mutate(cum_gdd = cumsum(((max_temp + min_temp)/2)))%>%
  summarise(annual_fdd = min(cum_fdd), annual_wdd = max(cum_fdd), annual_gdd = max(cum_gdd))%>%
  rename(year = spring_year)%>%
  right_join(ars_spring, by = c("year", "site"))%>%
  left_join(ars_cold_sum, by = c("year", "site"))

ggplot(ars_fdd, aes(x=date, y=cum_fdd))+
  geom_point()+
  facet_wrap(~site)

ggplot(ars_fdd, aes(x=year, y=annual_fdd))+
  geom_point(color="blue")+
  geom_point(aes(x=year, y=annual_wdd), color="red")+
  facet_wrap(~site)

  #Put freeze days and fdd together to model as function of winter coldness
ars_for_cold_mod<-ars_freeze_day%>%
  left_join(ars_fdd, by = c("year", "site", "avg_N2O"))
  
#Add site characteristic data back in for use in modeling ----
ars_for_annual_mod<-ars_cold%>%
  select(site, sand, silt, clay, oc, ph_h2o, lat)%>%
  group_by(sand)%>%
  distinct(.keep_all=TRUE)%>%
  group_by(site)%>%
  summarize_each(funs(mean(., na.rm = TRUE)))%>%
  full_join(ars_for_cold_mod, by = "site")%>%
  filter(avg_N2O < 80, site != "ALA")


#########Now ready to try some modeling for average annual spring emissions########## ----
  #ars_for_annual_mod is the dataframe resulting from all the above chunks

 #freeze days is more linear than freezing degree days (fdd)
ggplot(ars_for_annual_mod, aes(x=(annual_freeze_day), y = (avg_N2O),  color=site))+
  geom_point(size=4)+
  facet_wrap(~site)

ggplot(ars_for_annual_mod, aes(x=(cold_sum), y = (avg_N2O),  color=site))+
  geom_point(size=4)

ggplot(ars_for_annual_mod, aes(x=ph_h2o, y = avg_N2O,  color=site))+
  geom_point(size=4)

library(lme4)
fit <- lmer(log(avg_N2O) ~ clay + (1|site), data = ars_for_annual_mod)
plot(resid(fit) ~ fitted(fit))
abline(h = 0)
qqnorm(resid(fit))
qqline(resid(fit))

summary(fit)

pairs(ars_for_annual_mod[, c(4:6, 8:11)])

mod_cold<-lm(avg_N2O ~ annual_freeze_day, data=ars_for_annual_mod)

summary(mod_cold)

grid<-ars_for_annual_mod%>%
  data_grid(annual_freeze_day = seq_range(annual_freeze_day, 20))%>%
  add_predictions(mod_cold, "avg_N2O")

ggplot(ars_for_annual_mod, aes(annual_freeze_day, avg_N2O))+
  geom_point()+
  geom_line(data=grid, color="red", size=1) #same as we would get with geom_smooth(method = "lm")

ars_for_annual_mod<-ars_for_annual_mod%>%
  add_residuals(mod_cold, "resid")

ggplot(ars_for_annual_mod, aes(annual_freeze_day, resid))+
  geom_point()

  #let's add more factors

mod_cold_more<-lm(avg_N2O ~ annual_freeze_day + oc + clay + ph_h2o, data=ars_for_annual_mod)

grid<- ars_for_annual_mod%>%
  data_grid(clay, oc, .model = mod_cold_more)%>%
  add_predictions(mod_cold_more)

ggplot(grid, aes(annual_freeze_day, pred))+  
  geom_point()

ggplot(grid, aes(oc, pred))+  
  geom_point()

ggplot(grid, aes(ph_h2o, pred))+  
  geom_point()

ggplot(grid, aes(clay, pred))+  
  geom_point()

ars_for_annual_mod<-ars_for_annual_mod%>%
  add_residuals(mod_cold_more, "resid")

ggplot(ars_for_annual_mod, aes(clay, resid))+
  geom_point()

  #Try stepwise regression
library(MASS)

fit<-lm(avg_N2O ~ annual_freeze_day + oc + clay + ph_h2o, data=ars_for_annual_mod)
step<- stepAIC(fit, direction="backward")

step$anova

  #Try all-subsets regression  
library(leaps)

attach(ars_for_annual_mod)

leaps<-regsubsets(avg_N2O ~ annual_freeze_day + oc + clay + ph_h2o, data=ars_for_annual_mod, nbest=10)

plot(leaps)

ggplot(ars_for_annual_mod, aes(x=site, y=ph_h2o))+
 geom_point()


#mod_cold_more2<-lm(avg_N2O ~ annual_freeze_day + oc, data=ars_for_annual_mod)


#Let's try a bunch of models ----

ars_for_learning<-ars_for_annual_mod%>%
  na.omit()%>%
  dplyr::select(clay, oc, ph_h2o, annual_freeze_day, avg_N2O)

ars_for_learning<-as.data.frame(ars_for_learning)

library(caret)
train_control<-trainControl(method="LOOCV")
model<-train(avg_N2O ~., data=ars_for_learning, trControl=train_control, method="nb")

attach(ars_for_annual_mod)

fit1<- lm(avg_N2O ~ oc + ph_h2o + clay + annual_freeze_day)
fit2<- lm(avg_N2O ~ oc + ph_h2o + clay + annual_freeze_day + oc*ph_h2o + oc*clay + oc*ph_h2o*clay + oc*ph_h2o*clay*annual_freeze_day)
fit3<- lm(avg_N2O ~ log(oc) + ph_h2o + log(clay) + annual_freeze_day + log(oc)*ph_h2o + log(oc)*log(clay) + log(oc)*ph_h2o*log(clay) + log(oc)*ph_h2o*log(clay)*annual_freeze_day)
fit4<- lm(avg_N2O ~ annual_freeze_day + ph_h2o)

#Since I added the warmer sites, the problem is that with more warmth, we also expect more N2O



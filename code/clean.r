# See the file "clean EU15PaperDemand.r" for cleaning specific to
#    the Chas Amil and Buongiorno demand function estimates
#
# Input: .RDATA files containing
#            Paper products production and trade volume and value from FAOSTAT
#            GDP, deflator, exchange rate and population from world bank
#
# Output: .RDATA files containing data frames of Paper products (and maybe other products)
#             price time series in constant USD of baseyear, based on trade values
#             Consumption volume for EU 27 countries
#
# Author: Paul Rougieux - European Forest Institute
 
library(plyr)
library(FAOSTAT) # May remove it if I don't use it

baseyear = 2010 # Define the baseyear for constant GDP calculations and price deflator

# See tests in the /tests directory

####################################
# Load FAOSTAT and World Bank data #
####################################
setwd("Y:/Macro/Demand Econometric Models/rawdata/")
print(load(file = "Paper and paperboard.rdata"))
print(load(file = "GDP_Deflator_Exchange_Rate_Population.rdata"))

# Load EU27 countries
EU = read.csv("EUCountries.csv", as.is=TRUE)


# Select products for EU27 Countries
pp = subset(paperAndPaperboardProducts$entity, FAOST_CODE %in% EU$FAOST_CODE)


###########################
###########################
## Clean World Bank data ##
###########################
###########################
# Prepare GDP data, calculate deflator and GDP un corrent USD
#
# Select EU27 countries and rename World Bank data frame to shorter name wb
wb = subset(GDPDeflExchRPop, ISO2_WB_CODE %in% EU$ISO2_WB_CODE) 

# Rename Slovakia
wb$Country[wb$Country=="Slovak Republic"] = "Slovakia"

# Add local currency exchange rate to Euro 
wb = merge(wb, subset(EU, select=c(ISO2_WB_CODE, ExchRLCUtoEuro) ))


#####################################################################
# Convert Exchrate in Euro area countries to the Euro exchange rate #
#####################################################################
# Euro exchange rate to dollard from World Bank
exchr.euro = subset(GDPDeflExchRPop, Country=="Euro area"&Year>=1999, select=c(Year, ExchR)) 
names(exchr.euro) = c("Year", "ExchReur")

# # Check euro start year: compare last year of wb exchange rate with the EU table start year
# # If all start years correspond then we can replace NA values in Exchrate
# mutate(merge(ddply(subset(wb, Year>1993 & is.na(ExchR), select=c(Country, Year)),
#                    .(Country), summarize, NA_ExchR_Year = min(Year)),
#              subset(EU, select=c("Country", "Euro_Start_Year"))),
#        diff = NA_ExchR_Year-Euro_Start_Year)

# Split non EURO countries 
wb.neuro = subset(wb, Country%in%EU$Country[EU$Euro_Start_Year==0] )
# SPlit eurozone countries before and after their entry into the zone
# This based on the fact that there are NA values for the Exchange rate from local currency to dollar
wb.euro.after = subset(wb, Country%in%EU$Country[EU$Euro_Start_Year>0] &
                           Year>1993 & is.na(ExchR))
wb.euro.before = subset(wb, Country%in%EU$Country[EU$Euro_Start_Year>0] &
                            !(Year>1993 & is.na(ExchR)))

# Add exchange rate
wb.neuro$ExchReur = wb.neuro$ExchR
wb.euro.after = merge(wb.euro.after, exchr.euro, all.x=TRUE)
wb.euro.before = mutate(wb.euro.before, ExchReur = ExchR/ExchRLCUtoEuro)

# Combine euro and neuro together
stopifnot(nrow(wb)==nrow(wb.euro.after) + nrow(wb.euro.before) + nrow(wb.neuro))
wb = rbind(wb.euro.before, wb.euro.after, wb.neuro)
rm(wb.euro.before, wb.euro.after, wb.neuro )


###########################
# Calculate deflator base #
###########################
deflator = function(dtf){
    # Deflator after base year
    d = dtf$Deflator[dtf$Year>baseyear]
    dtf$DeflBase[dtf$Year>=baseyear] =
        Reduce(function(u,v) u*(1+v/100), d,init=1,accum=TRUE)
    
    # Deflator before base year (calculated from right to left)
    d = dtf$Deflator[dtf$Year<=baseyear]
    dtf$DeflBase[dtf$Year<=baseyear] = 
        Reduce(function(u,v) v/(1+u/100), d[-1], init=1, accum=TRUE, right=TRUE)
    return(dtf)
}
wb = ddply(wb, .(Country), deflator)


# Calculate the US deflator for baseyear, rename column to DeflUS
US = subset(GDPDeflExchRPop, Country =="United States", select=c(Country,Year,Deflator))
US = deflator(US)
names(US) = c("Country", "Year", "Deflator", "DeflUS")


##############################################
# Calculate GDP in constant USD of base year #
##############################################
wb = ddply(wb, .(Country), mutate,
            GDPconstantUSD = GDPcurrentLCU / (DeflBase * ExchReur[Year==baseyear]))


##################################
# Calculate apparent consumption #
##################################
# Change NA values to 0 - Not recommended 
# But makes sence at least that import into Finland and Sweden are 0
pp[is.na(pp)] = 0

# Calculate apparent consumption
pp = mutate(pp, Consumption = Production + Import_Quantity - Export_Quantity)

# Add GDPconstantUSD
pp = merge(pp, wb[c("Year","Country","GDPconstantUSD")])

# Rename "Total paper and paperboard" and "Printing and Writing Paper"
pp$Item[pp$Item=="Paper and Paperboard"] = "Total Paper and Paperboard"
pp$Item[pp$Item=="Other Paper+Paperboard"] = "Other Paper and Paperboard"
pp$Item[pp$Item=="Printing+Writing Paper"] = "Printing and Writing Paper"

# Change item to an ordered factor, same as in Table 3 of ChasAmil2000
pp$Item = factor(pp$Item, ordered=TRUE,
                 levels=c("Total Paper and Paperboard", "Newsprint",
                          "Printing and Writing Paper", 
                          "Other Paper and Paperboard"))


#################################################
# Calculate prices in constant USD of base year #
#################################################
# Add GDP deflator for the USA
pp = merge(pp, subset(US, select=c(Year,DeflUS)))

# Prices
# Ponderation of import and export prices as used in Chas-Amil and Buongiorno 2000
pp = mutate(pp, Price = (Import_Value + Export_Value)/
                (Import_Quantity + Export_Quantity) / DeflUS *1000)

# Import and export prices
pp = mutate(pp, Import_Price = Import_Value / Import_Quantity / DeflUS*1000)
pp = mutate(pp, Export_Price = Export_Value / Export_Quantity / DeflUS*1000)


#######################################################
# Create a table in long format containing trade data # 
#######################################################
# Might want to use the reshape2 package
pptrade = subset(pp, select=-c(Production, DeflUS, Price))
pptrade = reshape(pptrade, 
                  idvar=c("Country", "Year", "Item"), 
                  varying=list(c("Import_Quantity", "Export_Quantity"),
                               c("Import_Value", "Export_Value"),
                               c("Import_Price", "Export_Price")), 
                  v.names=c("Quantity", "Value", "Price_Trade"),
                  timevar="Trade", times=c("Import", "Export"), 
                  direction="long" )

# Check if information is kept
stopifnot(2*nrow(pp) == nrow(pptrade))
summary(pptrade$Quantity[pptrade$Trade=="Import"] - pp$Import_Quantity)
summary(pptrade$Price_Trade[pptrade$Trade=="Import"] - pp$Import_Price)

##################################################################
# Create an aggregated table of consumption and price for Europe #
##################################################################
paperProducts.aggregate = subset(pp, select=c("Item", "Year", "Consumption", "Production", 
                                              "Import_Quantity", "Export_Quantity", 
                                              "Price", "Import_Price", "Export_Price" ))

# Remove NA values not good, but do it here to calculate the aggregate
paperProducts.aggregate[is.na(paperProducts.aggregate)] = 0 

#  Sum volumes and average prices over the European Union
paperProducts.aggregate = ddply(paperProducts.aggregate, .(Item, Year),summarise, 
                                Consumption = sum(Consumption), Production = sum(Production),
                                Import_Quantity = sum(Import_Quantity), Export_Quantity = sum(Export_Quantity),
                                Price = mean(Price), Import_Price=mean(Import_Price), 
                                Export_Price = mean(Export_Price))

paperProducts.aggregate = reshape(paperProducts.aggregate, 
                                  idvar=c("Year", "Item"), 
                                  varying=list(c("Consumption", "Production", "Import_Quantity", "Export_Quantity"),
                                               c("Price","Price", "Import_Price", "Export_Price")), 
                                  v.names=c("Quantity", "Price"),
                                  timevar="Element", times=c("Consumption", "Production", "Import", "Export"), 
                                  direction="long" )

####################
# Save to end data #
####################
setwd("Y:/Macro/Demand Econometric Models/enddata/")

# Keep Consumption, price and revenue, remove Production and trade data 
paperProducts = subset(pp,select=c(Year, Country, Item, 
                                   Price, Consumption, GDPconstantUSD,
                                   Import_Price, Export_Price))

# Sort 
paperProducts = arrange(paperProducts, Item, Country, Year)

# Save to RDATA file
save(paperProducts, pptrade, wb, file="../enddata/EU27 paper products demand.rdata")


# See tests in the /tests directory


################
# Explore Raw data # 
################
# visualise missing values and explore specific data issues such as entry in the Euro area


# Countries that don't have an exchange rate in 2005 # Should contain EURO area countries
unique(wb$Country[is.na(wb$ExchR) & wb$Year==2005])

# Euro Area has the Exchange rate from 1999 or from the country's entry into the euro zone
subset(GDPDeflExchRPop, Country=="Euro area") # or
subset(GDPDeflExchRPop, ISO2_WB_CODE=="XC")

# European Union population
plot(subset(GDPDeflExchRPop, Country=="European Union", select=c(Year,Population)))

# Show FAO country and region metatables for France
subset(FAOcountryProfile, ISO2_WB_CODE=="FR")
subset(FAOregionProfile, FAOST_CODE==68)

# Euro area countries
subset(EU,Euro_Start_Year>0, select=c("Country", "Euro_Start_Year","ExchRLCUtoEuro"))
# as of 2014 add LVL 0.702804 (Latvian lats)

# order wb by Country and Year
wb = arrange(wb, Country, Year)

######################
# Explore final data #
######################
# -----------------------------------------------------------
# Script Name: Forecasting Project ECON 516
# Author: Princess Johnson
# Date: Dec 2025
#
# -----------------------------------------------------------

library(here)  # Works only inside of a project. Set the pathway to find your files in the project.
library(rlang)
library(fabletools) #  Provides tools, helpers and data structures for developing models and time series functions for 'fable' and extension packages.
library(fable) # provides common forecasting methods for tsibble, such as ARIMA and ETS. 
library(tsibble) # provides a data infrastructure for tidy temporal data with wrangling tools.
library(feasts) # provides support for visualizing data and extracting time series features.
library(slider) 
library(dplyr)
library(tidyr)
library(lubridate)
library(ggplot2)
library(gridExtra) # for arranging multi-panel plots
library(readr)  # for saving csv
library(scales) # for changing time x-axis format
library(stringr)# for replacing strings in text 



install.packages("here", dependencies = TRUE)          # 1.0.1
install.packages("rlang", dependencies = TRUE)         # 1.1.0  
install.packages("fabletools",dependencies=TRUE)       # 0.3.3
install.packages("fable")         # 0.3.3
install.packages("tsibble")       # 1.1.3
install.packages("feasts")        # 0.3.1
install.packages("slider")        # 0.3.0
install.packages("dplyr")         # 1.1.1
install.packages("tidyr")         # 1.3.0
install.packages("lubridate")     # 1.9.2
install.packages("ggplot2")       # 3.4.2
install.packages("gridExtra")     # 2.3
install.packages("readr")         # 2.1.4
install.packages("scales")        # 1.21.1
install.packages("stringr")      # 1.5.0


getwd()
############ Load Data and set as tsibble object ##############

data_raw <- read.csv("usd_ghs_2019_2024.csv")
colnames(data_raw)
ts.data <- mutate(data_raw, Month = yearmonth(as.character(data_raw$end.period)))  #Set date as month index 
ts.data.ts <- as_tsibble(ts.data, index = Month)  # Set as a tsibble object

#plot variables
exchange_rate_plot <- ts.data.ts %>% 
  autoplot(exchange.rate) +
  labs(title = "USD/GHS Exchange Rate (2019–2024)",
       y = "GHS per USD")
print(exchange_rate_plot)

#transform exchange rate to log form
ts.log.data <- ts.data.ts %>% 
  mutate(log_rate = log(exchange.rate))

# Plot log series
ts.log.data %>%
  autoplot(log_rate) +
  labs(
    title = "Log USD/GHS Exchange Rate (2019–2024)",
    y = "log(GHS per USD)",
    x = "Month"
  )

#training and validation sample split
train_data <- ts.log.data %>% filter(Month < yearmonth("2024 Jan"))
test_data  <- ts.log.data %>% filter(Month >= yearmonth("2024 Jan") & Month <= yearmonth("2024 Dec"))

#quick check
range(train_data$Month)
range(test_data$Month)

#plot training vs. validation 
ts.log.data %>%
  mutate(
    sample = if_else(
      Month < yearmonth("2024 Jan"),
      "Training (2019–2023)",
      "Validation (2024)"
    )
  ) %>%
  ggplot(aes(x = Month, y = log_rate, color = sample)) +
  geom_line(linewidth = 1) +
  labs(
    title = "Training and Validation Periods for log(USD/GHS)",
    x = "Month",
    y = "log(GHS per USD)",
    color = "Sample"
  ) +
  scale_color_manual(
    values = c(
      "Training (2019–2023)" = "blue",
      "Validation (2024)"   = "red"
    )
  ) +
  theme_minimal()

# fit multiple forcast methods
fits_train <- train_data %>%
  model(
    naive      = NAIVE(log_rate),
    snaive     = SNAIVE(log_rate),
    rw_drift   = RW(log_rate ~ drift()),
    ets        = ETS(log_rate),
    holt       = ETS(log_rate ~ error("A") + trend("A") + season("N")),
    reg_trend  = TSLM(log_rate ~ trend()),              
    arima_011  = ARIMA(log_rate ~ pdq(0,1,1)),
    arima_110  = ARIMA(log_rate ~ pdq(1,1,0))
  )
report(fits_train)

#validation forecasts and accuracy
fc_test <- fits_train %>% forecast(new_data = test_data)

ac_table <- accuracy(fc_test, test_data) %>%
  select(.model, RMSE, MAE, MAPE) %>%
  arrange(RMSE)

ac_table

#combination forecast
fits_train_combo <- train_data %>%
  model(
    ets   = ETS(log_rate),
    arima = ARIMA(log_rate),
    combo = (ETS(log_rate) + ARIMA(log_rate)) / 2
  )

fc_combo <- fits_train_combo %>%
  forecast(new_data = test_data)

accuracy(fc_combo, test_data) %>%
  select(.model, RMSE, MAE, MAPE) %>%
  arrange(RMSE)

#fitting additonal arima models onto training data
fits_train_arima_ext <- train_data %>%
  model(
    rw_drift   = RW(log_rate ~ drift()),
    arima_011  = ARIMA(log_rate ~ pdq(0,1,1)),
    arima_110  = ARIMA(log_rate ~ pdq(1,1,0)),
    arima_210  = ARIMA(log_rate ~ pdq(2,1,0)),
    arima_012  = ARIMA(log_rate ~ pdq(0,1,2)),
    arima_111  = ARIMA(log_rate ~ pdq(1,1,1))
  )

report(fits_train_arima_ext)

#running validation forecasts for expanded arima models
fc_test_arima_ext <- fits_train_arima_ext %>%
  forecast(new_data = test_data)

ac_table_ext <- accuracy(fc_test_arima_ext, test_data) %>%
  select(.model, RMSE, MAE, MAPE) %>%
  arrange(RMSE)

ac_table_ext

#validation accuracy summary table 
ac_table_ext %>%
  mutate(across(c(RMSE, MAE, MAPE), ~ round(.x, 4)))

#final model chosen based on lowest validation RMSE/MAE/MAPE: RW with drift

#final model estimation
fits_final <- ts.log.data %>%
  model(
    final_model = RW(log_rate ~ drift())
  )

report(fits_final)

#forecast for the next 24 months 
fc_24 <- fits_final %>%
  forecast(h = "24 months")

#extract fitted values from the final model
fit_vals <- augment(fits_final)

#plot of actual series, fitted values (dashed), and forecasts with intervals
autoplot(ts.log.data, log_rate) +
  geom_line(data = fit_vals, aes(x = Month, y = .fitted), linetype = "dashed") +
  autolayer(fc_24, level = c(80, 95)) +
  labs(
    title = "Actual, Fitted, and Forecasted log(USD/GHS): Jan 2025 – Dec 2026",
    y = "log(GHS per USD)",
    x = "Month"
  )

# Log-scale forecast
autoplot(fc_24, ts.log.data, level = c(80, 95)) +
  labs(
    title = "USD/GHS Forecast (log scale): Jan 2025 – Dec 2026",
    y = "log(GHS per USD)",
    x = "Month"
  )


#forecast output in csv format 
fc_24 %>%
  as_tibble() %>%
  write_csv("usd_ghs_forecast_2025_2026.csv")











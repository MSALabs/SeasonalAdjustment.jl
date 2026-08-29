```@meta
CurrentModule = SeasonalAdjustment
```

# API Reference

## The idiomatic entry point

```@docs
x13
X13Result
static
```

## Spec generation

```@docs
X13Spec
render
validate!
write_spec
generate_specs
```

## Subprocess invocation

```@docs
X13RunResult
run_x13
run_x13_batch
```

## Output-table parsing

```@docs
parse_table
parse_output
parse_udg
```

## Diagnostics (W.5)

Typed accessors over `.udg`, matching R's `seasonal` package. Each
accepts either a raw `Dict` (fixture/testable with no binary) or an
`X13Result` directly.

```@docs
udg
transformfunction
arima_model
mstats
qs
outliers
outlier_counts
fivebestmdl
seasonality_tests
residual_diagnostics
spectral_peaks
filters
```

## StatsAPI contract

`X13Result` implements `StatsAPI.aic`/`bic`/`aicc`/`loglikelihood`/
`nobs`/`residuals`/`coef`/`coefnames`/`stderror`/`dof` -- use these
fully-qualified (`StatsAPI.aic(r)`), not re-exported under their bare
names. `StatsAPI.vcov` always throws (`.udg` has no covariance matrix).

## Seasonal-parity functions

```@docs
series
select_order
open_output
import_spc
```

## Binary artifact management

```@docs
x13_binary_path
x13_binary_available
```

## Calendars

```@docs
Calendar
TableCalendar
INDIA_NSE
isbusinessday
isholiday
isweekend
adjust
advance
businessdaysbetween
holidaylist
easter_date
```

## Regressor generation

```@docs
trading_day_regressors
easter_regressor
custom_holiday_regressor
```

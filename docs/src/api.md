```@meta
CurrentModule = SeasonalAdjustment
```

# API Reference

Every function, its full signature, keywords and defaults. For a
worked example of *when* to reach for one, see the
[Manual](manual/01-specifications.md); for what the underlying concept
means, see the [Introduction](introduction/01-why-adjust.md). This page
deliberately does not repeat either.

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

## Diagnostics

Typed accessors over `.udg`. Each accepts either a raw `Dict` or an
`X13Result` directly. See the Manual's
[Accessing Diagnostics](manual/10-diagnostics-access.md) page for which
to reach for and what each one means.

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
nobs_effective
spectrum_peaks
```

## StatsAPI contract

`X13Result` implements `StatsAPI.aic`/`bic`/`aicc`/`loglikelihood`/
`nobs`/`residuals`/`coef`/`coefnames`/`stderror`/`dof`/`vcov` -- use
these fully-qualified (`StatsAPI.aic(r)`), not re-exported under their
bare names; `StatsBase.coeftable` is likewise fully-qualified, since
`StatsBase` already exports its own generic. See the Manual's
[Accessing Diagnostics](manual/10-diagnostics-access.md) page for what
each one returns and where the covariance data comes from.

```@docs
StatsAPI.dof
StatsAPI.vcov
StatsBase.coeftable
```

## Seasonal-parity functions

```@docs
series
select_order
open_output
import_spc
```

## Forecasts, missing values, components, model summary

`SeasonalAdjustment.summary` is deliberately **not exported** -- `Base`
already exports its own `summary` (a different, one-line-descriptive-
string contract), so `using SeasonalAdjustment` would collide with it;
call it fully-qualified. See [Output and Tables](manual/02-output-tables.md)
for the automatic re-run convention `forecast`/`backcast`/`components`
share with [`series`](@ref).

```@docs
forecast
backcast
interpolated
components
update
SeasonalAdjustment.summary
X13Summary
slidingspans
revision_history
```

## Plotting

`RecipesBase.jl` recipes; see the Manual's [Plots](manual/06-plots.md)
page for basic usage and which backend to pick. One architectural note
worth keeping here rather than in the Manual: `residplot`/`monthplot`/
`spectrumplot` are each a `RecipesBase.@userplot` wrapper, deliberately
NOT a plain series-type recipe -- `X13Result` already has its own bare
type recipe for `plot(r)`, which would otherwise silently shadow a
same-type series-type recipe (confirmed directly: an earlier version
built this way rendered `plot(r)`'s own series under a different
recipe's name with no error). See `residplot`'s own docstring for the
full story.

```@docs
residplot
monthplot
spectrumplot
```

`@userplot`'s own macro expansion also generates `residplot!`/
`monthplot!`/`spectrumplot!` (the "add to an existing plot" mutating
forms, matching `plot!`) -- each carries the same docstring as its
non-`!` counterpart above, not a separate one:

```@docs
residplot!
monthplot!
spectrumplot!
```

### More recipes

See the Manual's [Plots](manual/06-plots.md) page for what each one
shows.

```@docs
seasonalplot
forecastplot
residdiagplot
componentplot
spanplot
```

```@docs
seasonalplot!
forecastplot!
residdiagplot!
componentplot!
spanplot!
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

## Bundled datasets

Four real example datasets ship with the package. See the Manual's
[Datasets](manual/07-datasets.md) page for what each one is and how to
use your own data instead, and `dataset_info(name)` for full provenance
on any one of them at the REPL.

```@docs
dataset
datasets
dataset_info
DatasetInfo
```

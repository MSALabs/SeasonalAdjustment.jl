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

## Diagnostics

Typed accessors over `.udg`, the binary's own diagnostics dump. Each
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
nobs_effective
spectrum_peaks
```

## StatsAPI contract

`X13Result` implements `StatsAPI.aic`/`bic`/`aicc`/`loglikelihood`/
`nobs`/`residuals`/`coef`/`coefnames`/`stderror`/`dof`/`vcov` -- use
these fully-qualified (`StatsAPI.aic(r)`), not re-exported under their
bare names. `StatsAPI.vcov` reads the real regression/ARIMA
coefficient covariance matrix from `.rcm`/`.acm`; `StatsBase.coeftable`
(also fully-qualified, `StatsBase` already exports its own generic)
gives Estimate/Std.Error/t-value for every coefficient with no `vcov`
needed for that much.

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

`forecast`/`backcast` re-run automatically (same convention as
[`series`](@ref)) whenever the requested table or `level` isn't already
present; `components` fetches a regression effect's estimated time path
(`coef`/`coefnames` give the coefficient itself, this gives its
month-by-month factor); `update` re-runs `r.spec` with overridden
kwargs. `SeasonalAdjustment.summary` is deliberately **not exported**
-- `Base` already exports its own `summary` (a different, one-line-
descriptive-string contract), so `using SeasonalAdjustment` would
collide with it; call it fully-qualified.

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

`RecipesBase.jl` recipes -- load a plotting backend (`using Plots`, a
Makie backend, ...) to actually draw. `plot(r::X13Result)` needs no
separate import; `residplot`/`monthplot`/`spectrumplot` are each a
`RecipesBase.@userplot` wrapper (NOT a plain series-type recipe --
`X13Result` already has its own bare type recipe for `plot(r)`, which
would otherwise silently shadow a same-type series-type recipe; see
`residplot`'s own docstring for the full, real-binary/real-backend-
confirmed story).

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

`seasonalplot` is `monthplot`'s transpose (one line per calendar year);
`forecastplot`/`componentplot` build on the accessors of the same
name above; `residdiagplot` uses the real `.acf`/`.pcf`/`.ac2` tables rather
than recomputing from `r.residuals`; `spanplot` is deliberately scoped
to the headline `.udg` summaries `slidingspans`/`revision_history`
expose, not full per-span time series (see `spanplot`'s own docstring).

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

Four real example datasets ship with the package (`data/*.csv`, ~30 KB
total, plain committed CSV rather than Artifacts.toml -- see
`dataset_info(name)` for full provenance on each): `airline` (Box & Jenkins'
Series G, this package's own verification baseline), `appliance` (the
X-13 Reference Manual's own worked example, a genuinely different
seasonal shape from `airline`), `appliance_q` (`appliance` aggregated to
quarters -- `:derived`, not independently published), and `iip_india`
(India's Index of Industrial Production, MOSPI -- a real COVID level
shift, licensing terms not independently re-verified this session, see
`dataset_info("iip_india")`). `dataset(name)` returns a plain
`(date=, value=)` `NamedTuple` -- already a Tables.jl column table with
no `Tables.jl` dependency of its own -- that [`x13`](@ref) accepts
directly (`x13(dataset("airline"))`, `start` inferred automatically).

```@docs
dataset
datasets
dataset_info
DatasetInfo
```

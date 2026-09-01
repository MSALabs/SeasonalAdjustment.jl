# SeasonalAdjustment.jl

[![docs latest](https://img.shields.io/badge/docs-dev-blue.svg)](https://msalabs.github.io/SeasonalAdjustment.jl/dev/)
[![CI](https://github.com/MSALabs/SeasonalAdjustment.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/MSALabs/SeasonalAdjustment.jl/actions/workflows/CI.yml)

Official-statistics-grade seasonal adjustment for Julia — X-11,
RegARIMA, and SEATS — built on the same trusted, freely-redistributable
Census Bureau binary ([`x13prebuilt`](https://github.com/x13org/x13prebuilt))
national statistical offices run in production, with **India- and
other-market-aware calendar effects** (Diwali, Holi, and beyond) fed
into RegARIMA via `x13prebuilt`'s own user-defined-regressor mechanism
— something not available out of the box elsewhere.

Part of the [TSAnalytics.jl](https://github.com/MSALabs/TSAnalytics.jl)
project.

## Status

The `x13prebuilt` wrapper (X-11, RegARIMA, SEATS, diagnostics, plotting,
bundled datasets) is complete. A from-scratch native Julia engine hasn't
started yet.

## Design

This package deliberately departs from TSAnalytics.jl's own
"reference, never port" principle for its core functionality — it wraps
the actual Census Bureau X-13ARIMA-SEATS binary directly, rather than
reimplementing X-11/RegARIMA/SEATS from scratch, since this exact binary
is already trusted for the hardest parts of this problem (SEATS's
spectral factorization especially). A from-scratch native Julia engine
remains a planned future track, not abandoned, just deliberately
sequenced behind a working wrapper.

## Installation

**Alpha release.** Neither this package nor `TSAnalytics.jl` is in
Julia's General registry yet, so both must be installed together in a
single call — two separate `Pkg.add` calls fail in either order:

```julia
using Pkg
Pkg.add([
    PackageSpec(url = "https://github.com/MSALabs/TSAnalytics.jl",
                rev = "v0.1.0-alpha.1"),
    PackageSpec(url = "https://github.com/MSALabs/SeasonalAdjustment.jl",
                rev = "v0.1.0-alpha.1"),
])
```

After registration this becomes `] add SeasonalAdjustment`.

## Quick example

Four real example datasets ship with the package (~30 KB, plain
committed CSV — no download needed):

```julia
using SeasonalAdjustment

datasets()   # ["airline", "appliance", "appliance_q", "iip_india"]

result = x13(dataset("airline"); seasonal_order=(0,1,1,12))
result.seasonally_adjusted
result.trend
result.seasonal_factors
```

Monthly (`period=12`, the default) and quarterly (`period=4`) series are
both supported — confirmed directly against the real binary that these
are the only two periods X-13ARIMA-SEATS accepts for seasonal
adjustment:

```julia
result = x13(dataset("appliance_q"); period=4, seasonal_order=(0,1,1,4))
```

`X13Result` also carries the full `.udg` diagnostics dump the real
binary produces, through a typed accessor layer: `qs`, `outliers`,
`fivebestmdl`, `mstats`, `seasonality_tests`, and the `StatsAPI`
contract -- `aic`, `bic`, `coef`, `coefnames`, ...):

```julia
using StatsAPI

StatsAPI.aic(result)                 # 946.66...
qs(result).sa                        # (statistic=, pvalue=) QS test on the SA series
outliers(result; full=true)          # every auto-detected outlier, with estimate/se/t
series(result, :d8)                  # re-runs automatically if :d8 wasn't in `save`
```

Any spec block without a dedicated keyword (`forecast`, `slidingspans`,
`history`, ...) is reachable via `spec_args`:

```julia
x13(y; spec_args = Dict("forecast.maxlead" => "0"))
```

Plot recipes (`RecipesBase.jl` -- zero dependencies of its own; load a
real backend to draw):

```julia
using Plots
plot(result)                 # original + seasonally adjusted
residplot(result)            # regARIMA residuals
monthplot(result)            # seasonal factors by calendar period, with SI-ratio stems
spectrumplot(result)         # spectral peaks
seasonalplot(result)         # one line per year, monthplot's transpose
forecastplot(result)         # observed + forecast + prediction-interval ribbon
residdiagplot(result)        # residual series + ACF/PACF/histogram panel
componentplot(result)        # trading-day/holiday/user/outlier factor time paths
spanplot(result)             # sliding-spans / revision-history diagnostics
```

Forecasts, missing-value handling, component-factor accessors, and
`force`/`seasonalma`:

```julia
f = forecast(result; level = 0.95)     # (dates=, point=, lower=, upper=)
b = backcast(result)
x13(y; missing_action = :x13)          # X-13 interpolates via a -99999 sentinel + regARIMA
components(result; which = :holiday)   # the estimated holiday-effect time path
StatsAPI.vcov(result)                  # regression/ARIMA coefficient covariance matrix
x13(y; force = :denton)                # force SA annual totals to match the original series
```

## Known gaps in the alpha

So nobody reports these as bugs:

| Area | Status |
|---|---|
| Native Julia engine (no `x13prebuilt` binary) | not started -- deliberately sequenced behind the wrapper |
| Some SEATS-specific options (`noadmiss`, `rmod`, `maxit`, finite-vs-semi-infinite filters) | not surfaced as typed keywords -- reachable via `spec_args` |
| Near-zero / zero-crossing worked example | no such dataset is bundled yet |
| PDF build of the documentation | not yet built |
| Both packages' UUIDs | still placeholders, not yet regenerated |

Everything else that shipped earlier in this package's development --
forecasts, missing-value handling, `vcov`/`coeftable`/`summary`/`update`,
`force`/`seasonalma`, sliding spans and revision history, all nine plot
recipes, the full 281-entry saveable-table catalogue, the four bundled
datasets, and the twenty-chapter *Introduction to Seasonal Adjustment* --
is implemented and documented, not pending.

**What is worth reporting**, in priority order:

1. Anything where the package's output disagrees with R's `seasonal` on
   the same specification. That is the highest-value signal and the
   hardest to find internally.
2. Platform failures -- `x13_binary_available()` returning `false`, or
   macOS dynamic-library errors. The artifact covers Linux, macOS and
   Windows but real-world coverage beyond development machines is
   untested.
3. Specifications the package cannot express. `spec_args` is the escape
   hatch; if something needs it that you expected as a keyword, that is
   a design signal worth reporting on its own.
4. Error messages that do not say what to do next.
5. If you have real Indian monthly or quarterly data you can share --
   it may resolve the near-zero-series gap above, or simply be a useful
   second real-world test of the calendar layer.

## License

MIT for this package's own code. The bundled `x13prebuilt` binary is
distributed under the U.S. Census Bureau's own public-domain /
royalty-free license (see `x13prebuilt`'s own repository for the exact
terms) — not this package's MIT license.

```@meta
CurrentModule = SeasonalAdjustment
```

# 5. Where to Go Next

## What you can do now

Adjust a monthly or quarterly series, look at the result, run the five
checks that matter, and change the settings that come up most. That
covers a large share of routine work.

## The other document

**API Reference** is the authority on signatures, keywords, defaults
and known gaps. Every function named in this guide has an entry there
with more detail than this guide gives, deliberately. When you want to
know what a keyword accepts, go there and not here.

## Things this guide did not cover

**The other datasets.** `appliance` is the Census Bureau's own worked
example from the X-13 manual, a US retail series with a strong December
peak and a real trading-day effect. Its seasonal shape is completely
unlike the airline series, which makes it a good second thing to try.

```julia
res = x13(dataset("appliance"); aictest = [:td, :easter], transform = :auto)
```

**Quarterly data.** Everything here works with `period = 4`. Dates,
tick labels and diagnostics all follow.

```julia
res = x13(dataset("appliance_q"); period = 4, seasonal_order = (0, 1, 1, 4))
```

**SEATS.** X-13 contains a second, quite different adjustment engine,
based on decomposing a fitted ARIMA model rather than filtering.
`x13(d; seats = true)` switches to it. The M statistics don't apply;
the other diagnostics do.

**Calendar effects outside the US.** X-13's built-in moving holidays
are Easter, Labor Day and Thanksgiving. This package adds a calendar
layer and [`custom_holiday_regressor`](@ref) for anything else. The
India NSE calendar ships as [`INDIA_NSE`](@ref), Diwali is the worked
example (it moves between October and November, so no fixed seasonal
factor can absorb it), and `dataset("iip_india")` — India's real
monthly Index of Industrial Production, with a genuine COVID level
shift — is a real series to try it against:

```jldoctest
julia> using SeasonalAdjustment, Dates

julia> isholiday(INDIA_NSE, Date(2025, 10, 21))  # Diwali-Laxmi Pujan 2025
true

julia> custom_holiday_regressor(Date(2025, 9, 1), Date(2025, 12, 31), INDIA_NSE,
                                 year -> year == 2025 ? Date(2025, 10, 21) : nothing)
4-element Vector{Float64}:
 0.0
 1.0
 0.0
 0.0
```

**Forecasts and missing values.** The regARIMA model produces forecasts
and prediction intervals, not just the extension X-11 uses internally,
and `x13` can interpolate a missing value rather than requiring a clean
series:

```julia
f = forecast(res; level = 0.95)   # (dates=, point=, lower=, upper=)
x13(y; missing_action = :x13)     # interpolates via a regARIMA estimate
```

**Component-factor time paths and model diagnostics beyond the five
checks.** [`components`](@ref) gives a regression effect's own
month-by-month factor (the Diwali coefficient's actual shape, not just
its estimate); `StatsAPI.vcov`/`StatsBase.coeftable` give the
regression/ARIMA coefficient covariance matrix and a full coefficient
table; [`slidingspans`](@ref)/[`revision_history`](@ref) ask whether an
adjustment will still look the same next month. Five more plot recipes
— [`seasonalplot`](@ref), [`forecastplot`](@ref),
[`residdiagplot`](@ref), [`componentplot`](@ref), [`spanplot`](@ref) —
cover these visually; see the [API reference](../api.md).

**`force`/`seasonalma`.** Forcing seasonally adjusted annual totals to
match the original series, and pinning a specific seasonal moving-average
filter instead of X-11's own choice:

```julia
x13(y; force = :denton)
x13(y; seasonalma = :s3x9)
```

**Many series at once.** [`generate_specs`](@ref) and
[`run_x13_batch`](@ref) run a panel in parallel. Datasets broadcast, so
a quick comparison is one line:

```julia
results = x13.(dataset.(["airline", "appliance"]))
```

**Other output tables.** The four component series are four of 281
tables X-13 can write. [`series`](@ref) fetches any of them, re-running
automatically if the table wasn't saved the first time.

**The full HTML report.** [`open_output`](@ref) opens the binary's own
output in your browser, which is where the exhaustive detail lives.

**Migration.** [`import_spc`](@ref) reads an existing `.spc` file, so
specs from other X-13 tooling come across without hand-translation.

## Reading beyond the documentation

The **X-13ARIMA-SEATS Reference Manual** from the Census Bureau is the
authoritative source on every specification and every option.
Chapter 7 is the per-spec reference and Appendix B lists the output
tables.

**Ladiray and Quenneville, *Seasonal Adjustment with the X-11
Method*** (2001) is the book on X-11 itself, table by table. It
predates X-12, so it covers neither regARIMA nor SEATS, but nothing
else explains the filtering at that resolution.

**Dagum and Bianconcini, *Seasonal Adjustment Methods and Real Time
Trend-Cycle Estimation*** (2016) is the modern treatment and the
standard reference for SEATS.

**Findley, Monsell, Bell, Otto and Chen (1998)**, in the *Journal of
Business and Economic Statistics*, is the design paper for everything
X-12 added over X-11, including the sliding spans and revision history
diagnostics.

**Eurostat's ESS Guidelines on Seasonal Adjustment** is free and is
about practice rather than algorithm: when to force annual totals, how
often to re-identify models, what revision policy to adopt.

## A closing note

Two habits are worth carrying forward.

Run the checks. An adjustment that fails a diagnostic still produces a
smooth, plausible line, and nothing about looking at it will tell you.

Freeze the specification before publishing. [`static`](@ref) exists so
that your figures move when the economy moves, and not when the model
selection does.

## Design notes worth knowing before you dig further

- **The one deliberate exception in the TSAnalytics.jl family.** This
  package wraps the real `x13prebuilt` binary rather than reimplementing
  X-11/RegARIMA/SEATS from scratch — see [Design principles](../index.md)
  on the Home page for why.
- **`X13Spec`/`run_x13`/`parse_output` are the lower-level API** behind
  [`x13`](@ref) — reach for them directly if you need a custom, partial
  table selection (`x13()` itself always fetches the full D10-D13/
  S10-S13 quartet) or want to inspect the rendered `.spc` text before
  running it.
- **Platform support**: Linux, Windows, and macOS are all resolved via
  [`x13_binary_path`](@ref)/[`x13_binary_available`](@ref), each
  platform's own archive layout (a bare file, a zip subfolder, and a
  `bin/`+`lib/` directory pair, respectively) handled automatically.

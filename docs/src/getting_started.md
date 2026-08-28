```@meta
CurrentModule = SeasonalAdjustment
```

# Getting Started

## Installation

```julia
] add https://github.com/MSALabs/SeasonalAdjustment.jl
```

The first call that actually needs the `x13prebuilt` binary
([`x13`](@ref), [`run_x13`](@ref), or [`x13_binary_path`](@ref) itself)
downloads and installs the right platform-specific artifact
automatically (Julia's `LazyArtifacts` system) — nothing to configure
by hand.

!!! note "About the examples on this page"
    Every example below was actually run, not just written and assumed
    correct — the pure-Julia ones (calendars, spec construction) are
    live `jldoctest` blocks Documenter re-verifies on every docs build;
    the ones that call the real binary were confirmed directly against
    it during development (see `development-sequence.md`'s W.0-W.4
    rows for the exact values and how each was produced) but are shown
    as plain code blocks rather than live doctests, since running the
    actual `x13prebuilt` binary isn't something every environment that
    might build these docs can do.

## A first seasonal adjustment

[`x13`](@ref) accepts anything `tsvalues` does — a plain
`Vector`, or any other container from the wider TSAnalytics.jl-style
ecosystem.

```julia
using SeasonalAdjustment

# The Box-Jenkins airline passengers series (1949-1960), the standard
# benchmark in this entire field -- this exact call reproduces the
# real x13prebuilt binary's own D10/D11/D12/D13 output exactly,
# confirmed directly during this project's development.
result = x13(airline_passengers; start=(1949, 1))

result.seasonally_adjusted   # the D11 table
result.trend                 # D12
result.seasonal_factors      # D10
result.irregular              # D13
result.dates                  # Date.(1949-01-01, 1949-02-01, ...)
```

Prefer SEATS's ARIMA-model-based decomposition instead of X-11's
non-parametric filters? Pass `seats=true` — everything else about the
call, and the shape of the returned [`X13Result`](@ref), stays the
same:

```julia
result = x13(airline_passengers; start=(1949, 1), seats=true, transform=:auto,
             aictest=[:td, :easter], automdl=true)
```

## A genuine superset of R's and Python's own APIs

R's `seas()` passes any spec argument through dynamically; Python's
`x13_arima_analysis()` exposes only a curated subset. [`x13`](@ref)
combines both in one call — Python-style curated options for
discoverability, R-style raw passthrough for anything they don't cover:

```julia
result = x13(
    airline_passengers;
    start = (1949, 1),
    seasonal_order = (0, 1, 1, 12),        # Python-style curated ergonomics
    maxorder = (2, 1), maxdiff = (2, 1),   # matches statsmodels' own parameter names directly
    trading = true,                         # shorthand for a trading-day regressor
    regression_variables = ["easter[1]"],  # R-style raw passthrough, for anything not curated
)
```

A spec that would fail against the real binary is caught immediately,
before any subprocess is ever spawned:

```jldoctest
julia> using SeasonalAdjustment

julia> x13(collect(1.0:24.0))   # x13prebuilt itself requires >= 36 months (3 complete years)
ERROR: ArgumentError: series has 24 observations, but x13prebuilt requires at least 36 months (3 complete years) of data -- confirmed directly against the real binary's own error: "Series to be modelled and/or seasonally adjusted must have at least 3 complete years of data."
[...]
```

## India-aware calendar effects

Neither R's nor Python's default setup feeds non-Western holiday
effects into RegARIMA out of the box. This package's [`INDIA_NSE`](@ref)
calendar and regressor-generation functions do — entirely in pure
Julia, no binary invocation needed to build the regressor data itself:

```jldoctest
julia> using SeasonalAdjustment, Dates

julia> isholiday(INDIA_NSE, Date(2025, 10, 21))  # Diwali-Laxmi Pujan 2025
true

julia> isholiday(INDIA_NSE, Date(2025, 1, 26))  # Republic Day
true

julia> isbusinessday(INDIA_NSE, Date(2025, 10, 21))  # a holiday is never also a business day
false

julia> easter_date(2025)
2025-04-20

julia> diwali_2025_date(year) = year == 2025 ? Date(2025, 10, 21) : nothing;

julia> custom_holiday_regressor(Date(2025, 9, 1), Date(2025, 12, 31), INDIA_NSE, diwali_2025_date)
4-element Vector{Float64}:
 0.0
 1.0
 0.0
 0.0
```

Feed that regressor into a spec via [`X13Spec`](@ref)'s
`regression_user` (or [`x13`](@ref)'s own passthrough of the same
keyword) — see the real, end-to-end Diwali-effect proof in
`development-sequence.md` and `handoff/verification/diwali_regressor_proof/`
for the documented value this exact mechanism reproduces against the
real binary (October 1949's seasonal factor shifting from
`0.898593816033472` to `0.753973303751993`).

## Design notes worth knowing before you dig further

- **The one deliberate exception in the TSAnalytics.jl family.** This
  package wraps the real `x13prebuilt` binary rather than reimplementing
  X-11/RegARIMA/SEATS from scratch — see [Design principles](index.md)
  on the Home page for why, and `development-sequence.md` for the full
  policy.
- **`X13Spec`/`run_x13`/`parse_output` are the lower-level API** behind
  [`x13`](@ref) — reach for them directly if you need a custom, partial
  table selection (`x13()` itself always fetches the full D10-D13/
  S10-S13 quartet) or want to inspect the rendered `.spc` text before
  running it.
- **Platform support**: Linux, Windows, and macOS are all resolved via
  [`x13_binary_path`](@ref)/[`x13_binary_available`](@ref); see
  `development-sequence.md`'s W.1 row for exactly how each platform's
  archive layout (a bare file, a zip subfolder, and a `bin/`+`lib/`
  directory pair, respectively) was confirmed and handled.

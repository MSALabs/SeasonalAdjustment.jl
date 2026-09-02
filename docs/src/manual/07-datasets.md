```@meta
CurrentModule = SeasonalAdjustment
```

# Datasets

One paragraph: four real, verified example datasets ship with the
package. This page is kept short — the part of most interest to most
readers is using one's own data instead.

## What ships with the package?

```jldoctest
julia> using SeasonalAdjustment

julia> datasets()
4-element Vector{String}:
 "airline"
 "appliance"
 "appliance_q"
 "iip_india"
```

`airline` (Box & Jenkins' Series G, this package's own verification
baseline), `appliance` (the X-13 Reference Manual's own worked
example), `appliance_q` (`appliance` aggregated to quarters —
`:derived`, and not independently published), and `iip_india`
(India's Index of Industrial Production, MOSPI — carrying a real
COVID level shift).

## How do I load one as a DataFrame or TSFrame?

```julia
using DataFrames
dataset("airline", DataFrame)

using TSFrames
dataset("airline", TSFrame)

using TimeSeries
dataset("airline", x -> TimeArray(x; timestamp = :date))
```

[`dataset`](@ref)'s second argument is a sink — any Tables.jl-consuming
constructor. `DataFrame` and `TSFrame` accept a bare `dataset(name,
Sink)` directly; `TimeArray` needs the lambda form shown above, its
own constructor expecting the timestamp column to be named explicitly
(confirmed directly, not merely assumed). Without a sink, `dataset(name)`
returns a plain `(date=, value=)` `NamedTuple` — itself a valid
Tables.jl column table, with no `Tables.jl` dependency of its own
required.

## How do I cite one?

```julia
dataset_info("airline")
```

Every bundled dataset carries its source, licence and citation.
`iip_india` is the one exception worth knowing about up front — its
own `dataset_info` states plainly that its exact redistribution terms
were not independently re-verified at the time it was bundled.

## How do I use my own data instead?

This is the section that matters rather more than the first three, and
the one most easily forgotten on a page ostensibly about bundled data.

```julia
y = [112.0, 118.0, 132.0, 129.0]   # a plain Vector works directly
res = x13(y; start = (1949, 1))
```

Any `AbstractVector{<:Real}` works. For a custom container that
already carries its own dates — a `DataFrame` column, a `TSFrame`, or
indeed anything else — the two-function `TSAnalytics.jl` protocol may
be implemented once, whereupon `x13()` infers `start` automatically
from then on:

```julia
TSAnalytics.tsvalues(x::MyContainer) = ...   # -> Vector{<:Real}
TSAnalytics.tsindex(x::MyContainer)  = ...   # -> Vector{Date}, or nothing

res = x13(my_data)   # start inferred from tsindex(my_data)
```

This is precisely the mechanism the bundled datasets themselves make
use of — `dataset("airline")` is a plain `NamedTuple`, and the package
defines `tsvalues`/`tsindex` for that one `NamedTuple` shape, so that
`x13(dataset("airline"))` needs no explicit `start` of its own.

---

**See also:** [Getting Started chapter 2](../getting-started/02-first-adjustment.md)
for the bundled datasets used as the walkthrough's own example data.
[`dataset`](@ref)/[`datasets`](@ref)/[`dataset_info`](@ref)/
[`DatasetInfo`](@ref) in the [API Reference](../api.md).

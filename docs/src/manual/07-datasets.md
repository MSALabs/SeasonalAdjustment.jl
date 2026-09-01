```@meta
CurrentModule = SeasonalAdjustment
```

# Datasets

One paragraph: four real, verified example datasets ship with the
package. This page is short — the interesting part for most readers is
using your own data instead.

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
`:derived`, not independently published), and `iip_india` (India's
Index of Industrial Production, MOSPI — a real COVID level shift).

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
Sink)` directly; `TimeArray` needs the lambda form shown above since
its own constructor expects the timestamp column named explicitly,
confirmed directly rather than assumed. Without a sink, `dataset(name)`
returns a plain `(date=, value=)` `NamedTuple` — itself a valid
Tables.jl column table, with no `Tables.jl` dependency of its own.

## How do I cite one?

```julia
dataset_info("airline")
```

Every bundled dataset carries its source, licence and citation.
`iip_india` is the one exception worth knowing up front — its own
`dataset_info` says plainly that its exact redistribution terms were
not independently re-verified when it was bundled.

## How do I use my own data instead?

This is the section that matters more than the first three, and the
easiest to forget on a page about bundled data.

```julia
y = [112.0, 118.0, 132.0, 129.0]   # a plain Vector works directly
res = x13(y; start = (1949, 1))
```

Any `AbstractVector{<:Real}` works. For a custom container that already
carries its own dates — a `DataFrame` column, a `TSFrame`, anything —
implement the two-function `TSAnalytics.jl` protocol once and `x13()`
infers `start` automatically from then on:

```julia
TSAnalytics.tsvalues(x::MyContainer) = ...   # -> Vector{<:Real}
TSAnalytics.tsindex(x::MyContainer)  = ...   # -> Vector{Date}, or nothing

res = x13(my_data)   # start inferred from tsindex(my_data)
```

This is exactly the mechanism the bundled datasets themselves use —
`dataset("airline")` is a plain `NamedTuple`, and the package defines
`tsvalues`/`tsindex` for that one `NamedTuple` shape so
`x13(dataset("airline"))` needs no explicit `start`.

---

**See also:** [Getting Started chapter 2](../getting-started/02-first-adjustment.md)
for the bundled datasets used as the walkthrough's own example data.
[`dataset`](@ref)/[`datasets`](@ref)/[`dataset_info`](@ref)/
[`DatasetInfo`](@ref) in the [API Reference](../api.md).

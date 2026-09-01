```@meta
CurrentModule = SeasonalAdjustment
```

# Plots

One paragraph: nine `RecipesBase.jl` recipes cover the standard X-13
charts. This page is short by design — docstrings carry the keywords;
see the [Introduction](../introduction/01-why-adjust.md) for what each
chart means and why to look at it.

## How do I plot a result?

```julia
using Plots
plot(res)
```

`plot(r::X13Result)` needs no separate import beyond a backend. It
overlays the original and adjusted series by default.

## How do I show components instead of an overlay?

```julia
plot(res; panels = :components)
```

Four panels: observed, seasonally adjusted, trend, irregular.

## How do I plot growth rates?

```julia
plot(res; transform = :pc)    # period-over-period percent change
plot(res; transform = :pcy)   # year-over-year percent change
```

## How do I mark outliers?

```julia
plot(res; outliers = true)
```

## Which backend should I use?

`RecipesBase.jl` imposes no backend of its own — every recipe on this
page is backend-agnostic, and nothing else in this documentation
answers which one to pick. `Plots.jl` with the `GR` backend is what
every figure in this documentation was actually rendered with, and is
the reasonable default: fast, dependency-light, and works headlessly in
CI. A Makie backend (`CairoMakie`, `GLMakie`) is worth reaching for if
you want interactivity or are already in a Makie-based workflow — the
recipes themselves don't change.

## How do I save a figure?

```julia
p = plot(res)
savefig(p, "adjustment.png")
```

Standard `Plots.jl`/`RecipesBase.jl` usage — nothing package-specific.

## The other eight recipes

| Recipe | What it shows |
|---|---|
| [`residplot`](@ref) | regARIMA residuals against time |
| [`monthplot`](@ref) | seasonal factors by calendar period, with SI-ratio stems |
| [`spectrumplot`](@ref) | spectral peaks |
| [`seasonalplot`](@ref) | one line per calendar year, `monthplot`'s transpose |
| [`forecastplot`](@ref) | observed + forecast + prediction-interval ribbon |
| [`residdiagplot`](@ref) | residual series + ACF/PACF/histogram panel |
| [`componentplot`](@ref) | trading-day/holiday/user/outlier factor time paths |
| [`spanplot`](@ref) | sliding-spans / revision-history diagnostics |

Each is a `RecipesBase.@userplot` wrapper, called the same way as
`plot`: `residplot(res)`, `monthplot(res; choice = :seasonal)`, and so
on. Every one also has a mutating `!` form (`residplot!`) for adding to
an existing plot.

---

**See also:** [Getting Started chapter 3](../getting-started/03-was-it-any-good.md)
for these charts used as part of the five-check verification routine.
[Introduction chapters 6 and 8](../introduction/06-seasonal-filters.md)
for what `monthplot` and the seasonal-filter layout mean conceptually.

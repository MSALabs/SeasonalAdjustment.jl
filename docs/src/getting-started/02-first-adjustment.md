```@meta
CurrentModule = SeasonalAdjustment
```

# 2. Your First Adjustment

## The series

The package ships a few datasets, so nothing in this guide depends on
data you have to find first.

```jldoctest
julia> using SeasonalAdjustment

julia> datasets()
4-element Vector{String}:
 "airline"
 "appliance"
 "appliance_q"
 "iip_india"
```

We want the first one.

```jldoctest
julia> using SeasonalAdjustment

julia> d = dataset("airline");

julia> length(d.value), first(d.date), last(d.date)
(144, Dates.Date("1949-01-01"), Dates.Date("1960-12-01"))
```

Monthly totals of international airline passengers, January 1949 to
December 1960, in thousands. Box and Jenkins used it in *Time Series
Analysis: Forecasting and Control* and it's been the standard example
ever since. It appears throughout the seasonal adjustment literature
and in this package's own verification corpus. If you've read anything
at all about seasonal adjustment, you've seen this series.

Where it came from, and whether you may republish a chart of it:

```julia
dataset_info("airline")
```

```
International airline passengers ("airline")
  Source:     Box & Jenkins (1976), Series G
  Licence:    Public domain
  Kind:       published
  Frequency:  12 (monthly)
  N:          144
  Span:       1949-01-01 .. 1960-12-01
  Units:      thousands of passengers
  Citation:   Box, G.E.P. and Jenkins, G.M. (1976). Time Series
              Analysis: Forecasting and Control. Holden-Day. Series G.
```

Every dataset carries its source, licence and citation. That's
deliberate: a figure in a paper needs an attribution line, and guessing
at one is worse than looking it up. `iip_india` is the one exception
worth knowing about up front — its own `dataset_info` says plainly that
its exact redistribution terms weren't independently re-verified when
it was bundled, so check `dataset_info("iip_india")` before republishing
anything built from it.

[`dataset`](@ref) returns a `NamedTuple` of `date` and `value`, which
happens to be a valid Tables.jl table. So if you'd rather have something
else:

```julia
using DataFrames
dataset("airline", DataFrame)
```

Any Tables.jl sink works: `DataFrame`, `TSFrame`, `Tables.rowtable`,
`Tables.matrix`, or anything else that accepts a table.

The airline series is a good first example because everything it does,
it does clearly.

![Airline passengers, 1949-1960](../assets/gs01-airline-raw.png)

**Figure 2.1.** Two things are visible immediately. The series trends
upward, roughly doubling and then doubling again. And within each year
there's a repeating shape, peaking in summer, with a smaller bump in
December. The yearly shape is not constant in size: the summer peak in
1960 is far larger in absolute terms than the one in 1949.

That last point turns out to matter, and section 4 returns to it.

## Adjusting it

```julia
res = x13(dataset("airline"))
```

One call, and no `start` argument. The dataset carries its dates, and
[`x13`](@ref) reads them to work out that the series begins in January
1949.

For your own data you'd say so explicitly:

```julia
res = x13(y; start = (1949, 1))                # y a plain Vector, monthly
res = x13(y; start = (1990, 1), period = 4)    # quarterly
```

The result is an [`X13Result`](@ref). Four series come back, each a
field:

| Field | X-11 table | What it is |
|---|---|---|
| `seasonally_adjusted` | D11 | the series with the seasonal pattern removed |
| `trend` | D12 | the smooth underlying trend-cycle |
| `seasonal_factors` | D10 | the estimated seasonal pattern itself |
| `irregular` | D13 | what's left over |

Plus `residuals` from the regARIMA model, and `udg`, the binary's own
diagnostics dump, which section 3 uses heavily.

The X-11 table names in that middle column will keep appearing. They
are how the X-13 documentation and every statistical office refer to
these series, so the package keeps them visible rather than hiding them
behind Julia names alone.

## Looking at it

```julia
plot(res)
```

![Original and seasonally adjusted](../assets/gs02-original-vs-adjusted.png)

**Figure 2.2.** The original series and the adjusted one, overlaid. The
summer peaks and winter troughs are gone. What remains still rises, and
still wobbles, but the wobbles are no longer the calendar.

This is the chart to look at first, every time. If the adjusted line
doesn't look like a sensible version of the original with the yearly
rhythm taken out, nothing further is worth checking.

For the components separately:

```julia
plot(res; panels = :components)
```

![Four-panel decomposition](../assets/gs03-components.png)

**Figure 2.3.** Observed, seasonally adjusted, trend, and irregular. The
trend panel is the adjusted series smoothed further. The irregular
panel is what neither the trend nor the seasonal pattern explains, and
on a well-behaved series it should look like noise around 1.0.

## What actually happened — and what this bare call did *not* do

It's tempting to assume the single call above did everything X-13 can
do automatically: tested the transform, searched for an ARIMA model,
checked for outliers. **It didn't** — and checking that honestly is a
better first lesson than assuming it.

```julia
transformfunction(res), arima_model(res)
```

```
(:none, "(0 0 0)")
```

No transform was tested (`transformfunction` returns `:none`, not
because X-13 tried logs and rejected them, but because nothing was
asked for), and no real ARIMA model was fit — `(0 0 0)` is X-13's own
trivial fallback when neither an explicit model nor `automdl` is
requested. The adjustment in Figures 2.2–2.3 still ran (X-11's own
filtering doesn't need a fitted regARIMA model to decompose a series),
but this bare call is the "nothing turned on" baseline, not the
"X-13 doing its usual automatic work" case.

```julia
filters(res)
```

```
(seasonal_ma = ["MSR", "MSR", "MSR", "MSR", "MSR", "MSR", "MSR", "MSR", "MSR", "MSR", "MSR", "MSR"],
 trend_ma = 9, mode = nothing, sa_mode = "multiplicative seasonal adjustment", unit_root = nothing)
```

[`filters`](@ref) reports the seasonal moving average X-11 chose for
each calendar month (its own default, `MSR`, here), the trend filter
length, and the decomposition mode — X-11 still defaults to a
multiplicative decomposition even though no transform was tested at the
regARIMA stage; the two are separate choices. X-11 selects these from
properties of the data rather than applying fixed defaults, and
section 4 shows how to override them.

And the whole specification at once:

```julia
static(res)
```

[`static`](@ref) resolves every automatic decision into an explicit
specification — here, since nothing was automatic to begin with, it
mostly just echoes the bare defaults back (`arima_model="(0 0 0)"`,
`transform` left at `:none`, no outliers to list). It becomes genuinely
useful once automatic selection is actually turned on, which is where
section 3 picks up.

## Before moving on

You have an adjusted series and you have not yet checked a single thing
about whether it's any good — and, as the section above shows, you
haven't yet asked X-13 to do its usual automatic work either. That's the
subject of the next chapter, and it's not optional. Seasonal adjustment
fails quietly. A bad adjustment produces a smooth, plausible-looking
line that happens to be wrong, and nothing about Figure 2.2 would tell
you.

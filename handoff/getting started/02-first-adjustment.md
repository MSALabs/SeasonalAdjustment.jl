# 2. Your first adjustment

*≈4 pages. Figures GS-1, GS-2, GS-3.*

## The series

The package ships a few datasets, so nothing in this guide depends on data you
have to find first.

```julia
using SeasonalAdjustment, Plots

datasets()
```

```
4-element Vector{String}:
 "airline"
 "appliance"
 "appliance_q"
 "iip_india"
```

We want the first one.

```julia
d = dataset("airline")
length(d.value), first(d.date), last(d.date)
```

```
(144, Date("1949-01-01"), Date("1960-12-01"))
```

Monthly totals of international airline passengers, January 1949 to December
1960, in thousands. Box and Jenkins used it in *Time Series Analysis:
Forecasting and Control* and it has been the standard example ever since. It
appears in the X-13 documentation, in R's `seasonal`, in `statsmodels`, and in
this package's own verification corpus. If you have read anything at all about
seasonal adjustment, you have seen this series.

Where it came from, and whether you may republish a chart of it:

```julia
dataset_info("airline")
```

```
⟨output pending: run examples/ch02.jl⟩
```

Every dataset carries its source, licence and citation. That is deliberate: a
figure in a paper needs an attribution line, and guessing at one is worse than
looking it up.

`dataset` returns a `NamedTuple` of `date` and `value`, which happens to be a
valid Tables.jl table. So if you would rather have something else:

```julia
using DataFrames
dataset("airline", DataFrame)
```

Any Tables.jl sink works: `DataFrame`, `TSFrame`, `Tables.rowtable`,
`Tables.matrix`, or anything else that accepts a table.

The airline series is a good first example because everything it does, it does
clearly.

![Airline passengers, 1949-1960](../figures/out/fig-gs-01-airline-raw.svg)

**Figure GS-1.** Two things are visible immediately. The series trends upward,
roughly doubling and then doubling again. And within each year there is a
repeating shape, peaking in summer, with a smaller bump in December. The yearly
shape is not constant in size: the summer peak in 1960 is far larger in absolute
terms than the one in 1949.

That last point turns out to matter, and Chapter 4 returns to it.

## Adjusting it

```julia
res = x13(dataset("airline"))
```

One call, and no `start` argument. The dataset carries its dates, and `x13`
reads them to work out that the series begins in January 1949.

For your own data you would say so explicitly:

```julia
res = x13(y; start = (1949, 1))                # y a plain Vector, monthly
res = x13(y; start = (1990, 1), period = 4)    # quarterly
```

The result is an [`X13Result`](@ref):

```julia
res
```

```
⟨output pending: run examples/ch02.jl⟩
```

Four series come back, each a field:

| Field | X-11 table | What it is |
|---|---|---|
| `seasonally_adjusted` | D11 | the series with the seasonal pattern removed |
| `trend` | D12 | the smooth underlying trend-cycle |
| `seasonal_factors` | D10 | the estimated seasonal pattern itself |
| `irregular` | D13 | what is left over |

Plus `residuals` from the regARIMA model, and `udg`, the binary's own diagnostics
dump, which Chapter 3 uses heavily.

The X-11 table names in that middle column will keep appearing. They are how the
X-13 documentation, R's `seasonal`, and every statistical office refer to these
series, so the package keeps them visible rather than hiding them behind Julia
names alone.

## Looking at it

```julia
plot(res)
```

![Original and seasonally adjusted](../figures/out/fig-gs-02-original-vs-adjusted.svg)

**Figure GS-2.** The original series and the adjusted one, overlaid. The summer
peaks and winter troughs are gone. What remains still rises, and still wobbles,
but the wobbles are no longer the calendar.

This is the chart to look at first, every time. If the adjusted line does not
look like a sensible version of the original with the yearly rhythm taken out,
nothing further is worth checking.

For the components separately:

```julia
plot(res; panels = :components)
```

![Four-panel decomposition](../figures/out/fig-gs-03-components.svg)

**Figure GS-3.** Observed, seasonally adjusted, trend, and irregular. The trend
panel is the adjusted series smoothed further. The irregular panel is what
neither the trend nor the seasonal pattern explains, and on a well-behaved series
it should look like noise around 1.0.

Note the scale on the irregular panel. These are *ratios*, not differences,
because X-13 chose a multiplicative decomposition for this series. Chapter 4
explains that choice.

## What actually happened

The single call did rather a lot.

X-13 first tested whether to model the series in logs, and decided it should. It
then fitted a regARIMA model, which is an ARIMA model with optional regression
terms, and used that model to extend the series with forecasts. It ran the X-11
filtering procedure over the extended series, iterating between trend and
seasonal estimation three times. Along the way it chose a seasonal filter and a
trend filter based on properties of the data, and it computed several dozen
diagnostics.

Some of those choices, read back:

```julia
transformfunction(res), arima_model(res)
```

```
⟨output pending: run examples/ch02.jl⟩
```

The first tells you whether the series was modelled in logs. The second is the
ARIMA model X-13 settled on, in the `(p d q)(P D Q)` notation the documentation
uses everywhere.

The filters it picked:

```julia
filters(res)
```

```
⟨output pending: run examples/ch02.jl⟩
```

[`filters`](@ref) reports the seasonal moving average chosen for each calendar
month, the trend filter length, and the decomposition mode. X-11 selects these
from properties of the data rather than applying fixed defaults, and Chapter 4
shows how to override them.

And the whole specification at once:

```julia
static(res)
```

```
⟨output pending: run examples/ch02.jl⟩
```

[`static`](@ref) resolves every automatic decision into an explicit
specification. It is how you find out what the defaults did, and it is also how
you freeze a result for publication, which Chapter 4 returns to.

## Before moving on

You have an adjusted series and you have not yet checked a single thing about
whether it is any good. That is the subject of the next chapter, and it is not
optional. Seasonal adjustment fails quietly. A bad adjustment produces a smooth,
plausible-looking line that happens to be wrong, and nothing about Figure GS-2
would tell you.

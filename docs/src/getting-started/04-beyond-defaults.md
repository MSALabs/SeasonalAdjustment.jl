```@meta
CurrentModule = SeasonalAdjustment
```

# 4. When the Defaults Aren't Enough

Three settings account for most of what one will ever need to change.
This chapter takes them one at a time, and thereafter puts them
together.

## Multiplicative or additive

Look again at Figure 2.1. The summer peak in 1960 is much larger in
absolute terms than the one in 1949. But as a *proportion* of that
year's level, the two are similar — July sits roughly 20% above the
year's average in both.

That distinction is the whole question. When the seasonal swing grows
with the level of the series, the pattern is multiplicative and the
model belongs in logs. When the swing stays a constant number of units
regardless of level, it is additive.

X-13 tests this when asked to (`transform = :auto`, as in chapter 3's
`res`):

```julia
transformfunction(res)
```

```
:log
```

Log, meaning multiplicative. To see why this matters, the other
choice may be forced:

```julia
d = dataset("airline")
res_log  = x13(d; transform = :log)
res_none = x13(d; transform = :none)
```

![Multiplicative versus additive adjustment](../assets/gs07-transform-comparison.png)

**Figure 4.1.** The two adjusted series, and their difference. Early in
the sample the two are close. Late in the sample, where the seasonal
swing is largest, they separate. The additive version removes a
constant-sized summer effect from years where the actual effect was
much larger, and leaves visible seasonality behind as a result.

`transform` is best left at its default absent a good reason otherwise.
The reasons that do come up: a series containing zero or negative
values cannot be logged, and X-13 will pick `:none` on one's behalf;
and where a comparison is being made across a series break, or
someone else's published figures are being reproduced, the choice may
need to be pinned rather than re-tested each period.

## Outliers

A strike, a policy change, a pandemic. A single unusual observation
distorts the estimated seasonal pattern for that calendar month in
*every* year, the seasonal factor for July being estimated from all
the Julys taken together.

Detection is off by default:

```julia
res = x13(dataset("airline"); outlier = true)
outliers(res)
```

On the airline series, with the fuller specification above, one such
instance is found:

| label | type | year | period |
|---|---|---|---|
| `AO1951.May` | `:ao` | 1951 | 5 |

An additive outlier in May 1951 — one month, no lasting effect.

Worth noticing: the values around it are 163, 172, 178. **Nothing
about that looks unusual to the eye.** Detection works on regARIMA
residuals after differencing, not on levels, and so it finds things
the eye alone does not.

```julia
plot(res; outliers = true)
outlier_counts(res)
```

![Detected outlier marked](../assets/gs08-outliers.png)

**Figure 4.2.** The adjustment with the detected outlier marked.

Three types are detected automatically. An **additive outlier** (AO)
is a single odd observation. A **level shift** (LS) is a permanent
step to a new level. A **temporary change** (TC) is a jump that decays
back. [`outlier_counts`](@ref) gives the count found of each.

One caution applies everywhere and is easily forgotten. Automatic
detection near the end of a series is unreliable, there being
insufficient data yet after the event to distinguish a temporary blip
from a permanent shift. A level shift detected in the most recent few
months ought to be treated as provisional.

## Calendar effects

Months contain different numbers of Mondays. A series driven by
business activity will read higher in a month with five Mondays than
one with four, and this has nothing whatsoever to do with the season.

```julia
res = x13(dataset("airline"); trading = true, transform = :log)
```

Or X-13 may be left to decide whether the effect is present at all:

```julia
res = x13(dataset("airline"); aictest = [:td, :easter], transform = :auto)
```

`aictest` fits the regressors, compares information criteria with and
without, and retains them only where they earn their place. On the
airline series both are retained, and the trading-day F-test is
emphatic:

```
F(1, 128) = 31.06,  p = 1.4e-7
```

Easter is the other built-in worth knowing about. It moves between
March and April, so its effect splits across two months in a manner
that changes every year, and a fixed seasonal factor cannot absorb it.
`Easter[1]` in the output denotes a one-day window before Easter
Sunday.

X-13 has built-in regressors for Easter, Labor Day and Thanksgiving —
three holidays specific to the United States. For Diwali, Chinese New
Year, Eid, or indeed any other such occasion, this package provides
[`custom_holiday_regressor`](@ref) together with a calendar layer;
chapter 5 points the way to these.

## Choosing the ARIMA model

X-13 may search for the model itself, rather than being told one
outright:

```julia
res = x13(dataset("airline"); automdl = true, transform = :auto)
arima_model(res)
```

```
"(0 1 1)(0 1 1)"
```

This is worth a remark. `(0 1 1)(0 1 1)` is the very model Box and
Jenkins fitted to this series by hand in 1970. It is so closely
associated with it that the specification is called the *airline
model*, and it remains the default starting point for monthly economic
series across the profession to this day. X-13's automatic procedure
arrives at it quite independently.

To see what was considered and rejected along the way:

```julia
fivebestmdl(res)
```

```
5-element Vector{@NamedTuple{model::String, bic::Float64}}:
 (model = "(0 1 0)(0 1 1)", bic = -4.007)
 (model = "(1 1 1)(0 1 1)", bic = -3.986)
 (model = "(0 1 1)(0 1 1)", bic = -3.979)
 (model = "(1 1 0)(0 1 1)", bic = -3.977)
 (model = "(0 1 2)(0 1 1)", bic = -3.97)
```

[`fivebestmdl`](@ref) returns the five best candidates with their BIC
values, in rank order. Useful when the chosen model comes as a
surprise (notice `(0 1 1)(0 1 1)` is not even the top BIC here —
automdl weighs more than raw BIC when choosing among close candidates),
and equally useful in judging how decisive the choice truly was: five
candidates within a hair of one another means the selection is close
to arbitrary.

Where only the order is wanted, without the adjustment itself:

```julia
select_order(dataset("airline"))
```

```
(order = (3, 1, 1), seasonal_order = (0, 1, 1, 12), transform = :none)
```

Note that this is a *different* model from the one above —
`select_order` runs `automdl` on its own, with no `aictest`/`transform`
requested, and so searches under different conditions than chapter 3's
fuller `res` does.

## Putting it together

```julia
res = x13(dataset("airline");
          automdl = true,
          outlier = true,
          aictest = [:td, :easter],
          transform = :auto)
```

This is the specification behind every verified number in this guide
(the very one chapter 3 introduced).

The diagnostics, each independently verified against this exact call:

| Diagnostic | Value | Verdict |
|---|---|---|
| Transform | `Log(y)` | multiplicative |
| ARIMA model | `(0 1 1)(0 1 1)` | the airline model |
| Q | 0.20 | pass |
| M7 | 0.203 | identifiable seasonality |
| Failed M statistics | 0 | pass |
| QS, original | 167.65, p = 0.000 | seasonality present |
| QS, adjusted | 0.00, p = 1.000 | seasonality removed |
| Durbin-Watson | 1.95 | no residual autocorrelation |
| Outliers found | 1 (AO, May 1951) | |

## Freezing the result

Automatic selection is convenient while exploring and a liability in
production. Next month's data may well change the chosen model, and
one's published figures will then move for reasons having nothing to
do with the economy at all.

```julia
frozen = static(res)
```

[`static`](@ref) returns a specification with every automatic choice
resolved: the ARIMA order fixed, detected outliers listed explicitly,
the transform pinned in place. Running that specification from then
on stops the model moving underneath one.

One caveat, covered in the docstring itself, is worth repeating here.
Re-running a frozen specification reproduces the original to about six
significant figures, not bit-identically, estimation converging
slightly differently when a model is given outright rather than
searched for. Compare with `isapprox`, not `==`.

## Everything else

These settings cover most cases that arise. The rest of what X-13 is
capable of runs to some 280 pages of Census Bureau documentation.

Some of it is reachable through named keywords, and the [API
reference](../api.md) lists these. Anything without a named keyword
goes through `spec_args`, which passes raw `"block.argument"` pairs
straight through to the specification file:

```julia
res = x13(dataset("airline");
          spec_args = Dict("forecast.maxlead" => "12"))
```

That escape hatch means the package never stands in the way of
anything X-13 itself is able to do.

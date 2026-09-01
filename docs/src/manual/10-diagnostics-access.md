```@meta
CurrentModule = SeasonalAdjustment
```

# Accessing Diagnostics

One paragraph: this page is *access* — which function returns which
number. What the numbers *mean* and how to read them together is the
[Introduction](../introduction/16-why-so-many-diagnostics.md)'s job,
specifically Part V (chapters 16–20); this page deliberately does not
repeat that.

## How do I read any diagnostic by name?

```julia
res.udg["ftest\$Trading Day"]
udg(res, "ftest\$Trading Day")
```

`res.udg` is the raw `Dict{String,String}` X-13's own `.udg` file
parses into — every key the binary writes, unconverted. [`udg`](@ref)
is a thin, non-throwing accessor over the same dict (`nothing` for a
missing key, rather than a `KeyError`). Every typed function below is
built on one or the other.

## How do I get the M statistics and Q?

```julia
m = mstats(res)
m.q, m.m7, m.fail
```

Returns `nothing` for a SEATS run — the M statistics and Q are X-11
constructs with no SEATS equivalent, confirmed directly rather than
assumed. This is not a failure to check for; it means the question
doesn't apply to that run.

## How do I get QS and the F-tests?

```julia
qs(res)                  # (original=, sa=, residual=, irregular=), each (statistic=, pvalue=)
seasonality_tests(res)   # stable/moving-seasonality F-tests, identifiable-seasonality verdict
```

`qs` works for both X-11 and SEATS runs. `seasonality_tests` does not —
it needs an X-11-only `.udg` key (the stable-seasonality F-test
computed from X-11's own D8 table) and returns `nothing` for a
SEATS-only run, the same way `mstats` does.

## How do I get outliers and the model?

```julia
outliers(res)             # every auto-detected outlier: label, type, year, period
outliers(res; full = true) # adds estimate, standard error, t-statistic
outlier_counts(res)        # (ao=, ls=, tc=, rp=, so=, tls=, total=)
arima_model(res)           # "(0 1 1)(0 1 1)"
fivebestmdl(res)           # the 5 candidates automdl actually considered, by BIC
select_order(y)            # order/seasonal_order/transform, without running a full adjustment
```

## How do I get AIC, BIC, coefficients?

```julia
using StatsAPI
StatsAPI.aic(res)
StatsAPI.bic(res)
StatsAPI.coef(res)
StatsAPI.coefnames(res)
StatsAPI.stderror(res)
StatsAPI.dof(res)
StatsAPI.vcov(res)          # regression/ARIMA coefficient covariance matrix, from .rcm/.acm
StatsBase.coeftable(res)    # Estimate/Std.Error/t-value table, no vcov call needed
```

All fully-qualified — none of these are re-exported under a bare name,
since `StatsBase`/`Base` already define generics that would collide.
`StatsAPI.vcov` reads the real covariance matrix from `.rcm`/`.acm`
directly; it throws (by design, not a bug) if the model has no
coefficients to report a covariance for at all.

## What do these numbers mean?

This page stops here on purpose. For what "M7 above 1.0" implies, why
QS and a spectral peak can disagree on the same series, or what a
Ljung-Box failure alongside a clean Q actually means in practice, see
[Part V of the Introduction](../introduction/16-why-so-many-diagnostics.md)
— chapters 16 through 20 cover the full diagnostic battery
conceptually, with real, verified numbers throughout, including cases
where two diagnostics on the same real adjustment genuinely disagree.

---

**See also:** [Getting Started chapter 3](../getting-started/03-was-it-any-good.md)
for the five checks worth running every time, in the order worth
running them. [Introduction Part V](../introduction/16-why-so-many-diagnostics.md)
for why the battery is this large and how to read a disagreement
between two diagnostics.

```@meta
CurrentModule = SeasonalAdjustment
```

# Coming from R or Python

One paragraph: [`x13`](@ref)'s keyword arguments are a genuine superset
of both R's `seas()` and Python's `x13_arima_analysis()` — R-style raw
passthrough for anything without a curated field, layered with
Python's own curated parameter names for discoverability. This page is
a translation aid, not a tutorial; if you already know either tool, most
of this package will look familiar immediately.

## How do I translate a `seas()` call?

| R (`seasonal::seas`) | SeasonalAdjustment.jl |
|---|---|
| `seas(x)` | `x13(y)` |
| `seas(x, regression.variables = c("td"))` | `x13(y; trading = true)` |
| `seas(x, transform.function = "log")` | `x13(y; transform = :log)` |
| `seas(x, outlier = NULL)` | `x13(y; outlier = false)` |
| `seas(x, arima.model = "(0 1 1)(0 1 1)")` | `x13(y; seasonal_order = (0, 1, 1, 12))` |
| `series(m, "d11")` | `res.seasonally_adjusted` (or `series(res, [:d11])` for any other table) |
| `qs(m)` | `qs(res)` |
| `static(m)` | `static(res)` |

R's `...` mechanism passes any spec-argument combination through
dynamically. [`x13`](@ref)'s own `spec_args` is the direct equivalent
for anything without a curated keyword — see
[Specifications](01-specifications.md).

## How do I translate `x13_arima_analysis()`?

| Python (`statsmodels.tsa.x13`) | SeasonalAdjustment.jl |
|---|---|
| `x13_arima_analysis(x)` | `x13(y)` |
| `x13_arima_analysis(x, maxorder=(2,1))` | `x13(y; maxorder = (2, 1))` |
| `x13_arima_analysis(x, maxdiff=(2,1))` | `x13(y; maxdiff = (2, 1))` |
| `x13_arima_analysis(x, outlier=True)` | `x13(y; outlier = true)` |
| `.seasadj` | `res.seasonally_adjusted` |
| `.trend` | `res.trend` |
| `.irregular` | `res.irregular` |
| `.results` (raw text) | `res.run_result` ([`X13RunResult`](@ref), typed) |

`maxorder`/`maxdiff` are named identically to `statsmodels`'s own
parameters on purpose — this is Python's curated-subset layer,
available alongside R's full passthrough on the same call.

## How do I reuse an existing `.spc` file?

```julia
res = import_spc("existing.spc")
```

[`import_spc`](@ref) reads a `.spc` file written by any X-13 tooling —
R, Python, or the binary directly — into an [`X13Result`](@ref)
without hand-translating the spec. It is not a general X-13 grammar
parser (comments and unusual multi-line quoting are not handled), and
one real, confirmed gap: `outlier { types = (ao ls tc) }` sets
`outlier = true` but the specific `types` list is dropped, since
`X13Spec` has no typed field for it yet — check the source `.spc` by
hand if that list matters for your use case.

## Where does this package deliberately differ from R?

Three real, confirmed divergences — collected here because a user
diffing output against R needs them together, not scattered across
docstrings.

**`maxlead` is not forced to zero when a user regressor is present.**
R's `seasonal` cannot extend a user-defined regressor past the sample
end, so it silently sets `forecast.maxlead = 0` whenever one is
present. This package embeds the regressor's data inline and
[`validate!`](@ref) already requires it to cover the series plus one
forecast horizon — so it genuinely *can* extend and forecast, and does
so by default. Set `spec_args = Dict("forecast.maxlead" => "0")`
explicitly to match R's behaviour.

**[`custom_holiday_regressor`](@ref) drops a holiday landing on a
non-trading day.** A holiday that falls on a day that was not a
working day anyway produces no incremental trading-day effect to
explain, so the regressor contributes `0.0` for that occurrence rather
than `1.0`. Both R's and Python's reference pipelines this package was
checked against use a bare month dummy instead, which does not make
this distinction. Output will not match either on a year where the
holiday falls on a weekend — see the
[Moving Holidays](../introduction/11-moving-holidays.md) chapter of the
*Introduction* for the real example this was found on.

**`static()` reproduces to about six significant figures, not
bit-identically.** Re-running a frozen specification converges
slightly differently from the original automatic search, since
estimation is given a starting model rather than searching for one.
Compare with `isapprox`, not `==`, when checking that a frozen spec
reproduces its source.

Each of these is documented in its own function's docstring; this page
exists so a reader migrating from R or Python sees all three in one
place, once, rather than discovering them one at a time.

---

**See also:** [Reproducibility and Production](08-reproducibility.md)
for more on `static()`'s precision. The [Moving Holidays](../introduction/11-moving-holidays.md)
chapter of the *Introduction* for the weekend-drop rule's full context.

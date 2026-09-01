# 5. Where to go next

*≈2 pages. No figures.*

## What you can do now

Adjust a monthly or quarterly series, look at the result, run the five checks
that matter, and change the settings that come up most. That covers a large share
of routine work.

## The three documents

**This guide** is the guided path. You have finished it.

**Introduction to Seasonal Adjustment** explains the concepts. What X-11
actually does with those three passes, why a forecasting model sits in front of
a smoothing procedure, what SEATS does differently, and how to read every
diagnostic rather than just the five here. It is written to be readable without
Julia in front of you, and it is the right next stop if you want to understand
what you have been running.

**API Reference** is the authority on signatures, keywords, defaults and known
gaps. Every function named in this guide has an entry there with more detail
than this guide gives, deliberately. When you want to know what a keyword
accepts, go there and not here.

## Things this guide did not cover

**The other datasets.** `appliance` is the Census Bureau's own worked example
from the X-13 manual, a US retail series with a strong December peak and a real
trading-day effect. Its seasonal shape is completely unlike the airline series,
which makes it a good second thing to try.

```julia
res = x13(dataset("appliance"); aictest = [:td, :easter])
```

**Quarterly data.** Everything here works with `period = 4`. Dates, tick labels
and diagnostics all follow.

```julia
res = x13(dataset("appliance_q"); period = 4)
```

**SEATS.** X-13 contains a second, quite different adjustment engine, based on
decomposing a fitted ARIMA model rather than filtering. `x13(d; seats = true)`
switches to it. The M statistics do not apply; the other diagnostics do.

**Calendar effects outside the US.** X-13's built-in moving holidays are Easter,
Labor Day and Thanksgiving. This package adds a calendar layer and
[`custom_holiday_regressor`](@ref) for anything else. The India NSE calendar
ships as [`INDIA_NSE`](@ref), and Diwali is the worked example, since it moves
between October and November and no fixed seasonal factor can absorb it.

**Many series at once.** [`generate_specs`](@ref) and [`run_x13_batch`](@ref)
run a panel in parallel. Datasets broadcast, so a quick comparison is one line:

```julia
results = x13.(dataset.(["airline", "appliance"]))
```

**Other output tables.** The four component series are four of 281 tables X-13
can write. [`series`](@ref) fetches any of them, re-running automatically if the
table was not saved the first time.

**The full HTML report.** [`open_output`](@ref) opens the binary's own output in
your browser, which is where the exhaustive detail lives.

**Forecasts.** The regARIMA model produces forecasts and prediction intervals,
not just the extension X-11 uses internally.

**Migration.** [`import_spc`](@ref) reads an existing `.spc` file, so specs from
R or from Census tooling come across without hand-translation.

## Reading beyond the documentation

The **X-13ARIMA-SEATS Reference Manual** from the Census Bureau is the
authoritative source on every specification and every option. Chapter 7 is the
per-spec reference and Appendix B lists the output tables.

**Ladiray and Quenneville, *Seasonal Adjustment with the X-11 Method*** (2001)
is the book on X-11 itself, table by table. It predates X-12, so it covers
neither regARIMA nor SEATS, but nothing else explains the filtering at that
resolution.

**Dagum and Bianconcini, *Seasonal Adjustment Methods and Real Time Trend-Cycle
Estimation*** (2016) is the modern treatment and the standard reference for
SEATS.

**Findley, Monsell, Bell, Otto and Chen (1998)**, in the *Journal of Business
and Economic Statistics*, is the design paper for everything X-12 added over
X-11, including the sliding spans and revision history diagnostics.

**Eurostat's ESS Guidelines on Seasonal Adjustment** is free and is about
practice rather than algorithm: when to force annual totals, how often to
re-identify models, what revision policy to adopt.

## A closing note

Two habits are worth carrying forward.

Run the checks. An adjustment that fails a diagnostic still produces a smooth,
plausible line, and nothing about looking at it will tell you.

Freeze the specification before publishing. `static()` exists so that your
figures move when the economy moves, and not when the model selection does.

---

# Verification checklist

Every number in this guide is either verified against the committed fixture or
marked pending. This section is the task list for generating the rest.

## Verified

All against `handoff/udg_and_residuals/auto_test.udg`, produced by

```julia
x13(dataset("airline"); automdl = true, outlier = true,
                        aictest = [:td, :easter])
```

| Chapter | Value |
|---|---|
| 3, 4 | QS original 167.65 / p 0.000; adjusted 0.00 / p 1.000 |
| 3, 4 | Q = 0.20; M7 = 0.203; `fail` = 0 |
| 3 | Durbin-Watson 1.9504; skewness 0.0900; kurtosis 3.0698 |
| 4 | transform `Log(y)`; ARIMA `(0 1 1)(0 1 1)` |
| 4 | `AutoOutlier$AO1951.May`, one AO; neighbours 163, 172, 178 |
| 4 | Trading-day F(1, 128) = 31.06, p = 1.4e-7 |

Also verified, from the dataset files themselves:

| Chapter | Value |
|---|---|
| 2 | `airline`: n = 144, 1949-01 to 1960-12 |

## Pending

Marked `⟨output pending⟩` in the text.

| Chapter | Block |
|---|---|
| 1 | `x13_binary_path()` |
| 2 | `dataset_info("airline")` |
| 2 | `res` show output |
| 2 | `transformfunction(res), arima_model(res)` for the **default** spec |
| 2 | `filters(res)` |
| 2 | `static(res)` |
| 4 | `fivebestmdl(res)` |
| 4 | `select_order(dataset("airline"))` |

Note the fourth row. Chapter 2 uses plain `x13(dataset("airline"))` with no
`automdl`, `outlier` or `aictest`, so its output is **not** the fixture's and
must be generated separately. Do not copy the Chapter 4 values into Chapter 2.

## Figures

Eight, all buildable with the current package. None blocked on W.7 or W.8.

| ID | Kind | Content |
|---|---|---|
| GS-1 | custom | Raw series, seasonal peaks annotated |
| GS-2 | recipe | `plot(res)` |
| GS-3 | recipe | `plot(res; panels = :components)` |
| GS-4 | recipe | `monthplot(res)` |
| GS-5 | recipe | `spectrumplot(res; series = :sa)` |
| GS-6 | recipe | `residplot(res)` |
| GS-7 | custom | `:log` vs `:none` adjusted series plus difference panel |
| GS-8 | recipe | `plot(res; outliers = true)` |

## Package dependencies

W.9 (bundled datasets) must land first. This guide uses `datasets()`,
`dataset()`, `dataset_info()` and the `TSAnalytics.tsvalues`/`tsindex` methods
that let `x13(dataset("airline"))` infer `start`.

`datasets()` output in Chapter 2 assumes four registered datasets including
`iip_india`. If that one is still blocked on licensing when the guide is built,
either drop it from the listing or ship the synthetic fallback, but do not print
a name that `dataset()` cannot then load.

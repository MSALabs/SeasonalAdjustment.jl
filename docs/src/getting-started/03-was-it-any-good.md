```@meta
CurrentModule = SeasonalAdjustment
```

# 3. Was It Any Good?

Seasonal adjustment fails quietly. There is no error, no warning, no
obviously wrong number. One gets a smooth line that looks like an
adjusted series, and it may well be wrong in ways that matter.

There is, accordingly, a battery of diagnostics, unusually large
compared with most statistical procedures. This chapter runs the five
checks worth making every time, in the order worth making them —
against a fuller specification than chapter 2's bare call, one that
actually allows X-13 to make its usual automatic choices:

```julia
res = x13(dataset("airline");
          automdl = true,
          outlier = true,
          aictest = [:td, :easter],
          transform = :auto)
```

This is the specification behind every verified number in this chapter
and the next.

## Check 1: does the seasonal pattern look sensible?

```julia
monthplot(res)
```

![Seasonal factors by month with SI ratios](../assets/gs04-monthplot.png)

**Figure 3.1.** Twelve bands, one per calendar month. The thick
horizontal bar in each band is the estimated seasonal factor. The
vertical stems are the SI ratios, being what the data actually showed
in each individual year before smoothing.

It is read as follows. The bars show the shape of the average year:
July and August well above 1.0, February well below. The stems show
how much year-to-year variation the bar is smoothing through. Tight
stems indicate a stable seasonal pattern, easy to estimate. Widely
scattered stems indicate the pattern is itself moving, and the single
bar is a compromise.

The stems drifting steadily in one direction within a band is the
signal worth watching for. It means that month's seasonal effect is
changing over time, and a single factor is masking a trend.

## Check 2: is there seasonality left?

The point of the exercise is to remove the seasonal pattern. The QS
test asks whether any remains.

```julia
qs(res)
```

| Series | QS statistic | p-value |
|---|---|---|
| original | 167.65 | 0.000 |
| seasonally adjusted | 0.00 | 1.000 |

That is the pattern one wants to see. Strong, highly significant
seasonality in the input. None detectable in the output.

The failure mode is a significant QS on the adjusted series. It means
the procedure did not get everything, and the adjusted figures still
carry a calendar rhythm. On monthly economic data this is, at most
statistical offices, a publication-blocking result.

## Check 3: the M statistics

X-11 produces eleven summary statistics, M1 to M11, and combines these
into an overall Q. Each M targets a different way in which an
adjustment can go wrong: too much irregular relative to trend,
seasonal factors moving too fast, and so on.

The convention is a simple one. **Below 1.0 passes. Above 1.0 fails.**

```julia
m = mstats(res)
m.q, m.m7, m.fail
```

```
(0.20, 0.203, 0)
```

A Q of 0.20 against a threshold of 1.0 is a comfortable pass. `fail`
is the count of individual M statistics exceeding 1.0, and zero is
what one wants to see.

M7 deserves separate mention. It tests whether identifiable
seasonality is present at all, and it is the one most practitioners
quote. An M7 above 1.0 is often taken to mean the series ought not be
seasonally adjusted at all, there being insufficient stable
seasonality to remove. At 0.203, this series has plenty.

[`mstats`](@ref) returns all eleven, plus `q`, `qm2` and `fail`. It
returns `nothing` for a SEATS run, the M statistics being specific to
X-11.

## Check 4: spectral peaks

A seasonal pattern in monthly data shows up as peaks at particular
frequencies. Should those peaks still be present in the *adjusted*
series, seasonality has survived.

```julia
spectrumplot(res; series = :sa)
```

![Spectrum of the adjusted series](../assets/gs05-spectrum.png)

**Figure 3.2.** The spectrum of the adjusted series, with vertical
markers at any seasonal or trading-day frequency X-13 flagged as a
visually significant peak. A clean adjustment carries no markers at
the seasonal frequencies.

For a summary rather than a picture:

```julia
spectral_peaks(res)
```

[`spectral_peaks`](@ref) reports which series show peaks.
[`spectrum_peaks`](@ref) (singular `spectrum`, note) reports at which
frequency, being the finer-grained information the plot itself draws
on.

A trading-day peak carries a different message from a seasonal one. It
says the series responds to the day-of-week composition of the month,
and chapter 4 shows how this may be modelled.

## Check 5: is the model adequate?

The regARIMA model at the front of the pipeline has its own
diagnostics, and these are ordinary time series diagnostics.

```julia
residplot(res)
```

![regARIMA residuals](../assets/gs06-residuals.png)

**Figure 3.3.** Residuals against time, with a zero reference line.
What is being looked for is something resembling noise: no drift, no
fanning out, no runs of same-signed values.

```julia
d = residual_diagnostics(res)
d.durbin_watson, d.skewness, d.kurtosis
```

```
(1.9504, 0.0900, 3.0698)
```

A Durbin-Watson statistic near 2.0 indicates no first-order residual
autocorrelation. Skewness near 0 and kurtosis near 3 are what a normal
distribution gives, so these residuals sit close to normal.

`d.ljung_box` is the full lag-indexed table rather than a single
number, the underlying diagnostic being computed at several lags at
once, with the answer liable to differ between them.

## The checklist

| Check | Function | Want |
|---|---|---|
| Sensible seasonal pattern | [`monthplot`](@ref) | tight stems, no drift within a band |
| Seasonality removed | [`qs`](@ref) | significant on original, not on adjusted |
| Overall quality | [`mstats`](@ref) | Q below 1.0, `fail` of 0 |
| No residual seasonality | [`spectral_peaks`](@ref) | no seasonal peak in `:sa` |
| Model adequate | [`residual_diagnostics`](@ref) | DW near 2, no Ljung-Box rejection |

Two more checks exist and are worth knowing about, even though they
fall beyond this guide. [`seasonality_tests`](@ref) gives the stable
and moving seasonality F-tests along with the identifiable-seasonality
verdict. [`slidingspans`](@ref)/[`revision_history`](@ref) ask a
rather different question again: not whether the adjustment is
correct today, but whether it will still look the same next month (see
chapter 5).

## When a check fails

Do not reach for a different method. Reach instead for the
specification.

A failed QS on the adjusted series, or a seasonal spectral peak,
usually means the model in front of the filter is missing something —
an outlier, a calendar effect, a level shift. These are the subject of
chapter 4.

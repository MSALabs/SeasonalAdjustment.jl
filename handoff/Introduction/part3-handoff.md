# Handoff: Introduction, Part III — regARIMA (Chapters 10–13)

~18 pages, 12 figures. Chapter 9 has its own handoff and is already drafted.

**Master:** `introduction-design.md`
**Written after:** Chapter 9, Part II, Part V, Part I

---

## 0. The blocking picture, honestly

Part III was scoped as the most blocked part of the book: two chapters depending
on `iip_india`, three figures on `componentplot`, one on `forecastplot`.

**Status update (implementation session, post-handoff): fully resolved.**
`componentplot`, `forecastplot` (W.8) and `iip_india` (W.9) all shipped.
**All twelve figures are buildable today.** The paragraph below is kept as a
record of the original scoping, not current status.

Working through it, that is **less severe than it looked.** Eight of twelve
figures are buildable today, and the blocked four cluster in a way that leaves
every chapter writable.

| Figure | Content | Status |
|---|---|---|
| C-3 | Weekday counts per month | **buildable** — pure calendar arithmetic |
| C-4 | Trading-day factors over time | ~~blocked — `componentplot`~~ **RESOLVED** |
| C-5 | TD spectral peak before/after | **buildable** |
| C-6 | Easter date by year | **buildable** — pure calendar |
| C-7 | Easter regressor by month | **buildable** — `easter_regressor` |
| C-8 | Diwali date by year | **buildable** — pure calendar, no series needed |
| C-9 | Diwali regressor, weekend rule marked | **buildable** — `custom_holiday_regressor` |
| C-10 | Diwali effect path | ~~blocked — `componentplot` **and** `iip_india`~~ **RESOLVED** |
| C-11 | AO / LS / TC / SO shapes | **buildable** — synthetic |
| C-12 | COVID outliers on `iip_india` | ~~blocked — `iip_india`~~ **RESOLVED** |
| C-13 | Best-5 model BIC comparison | **buildable and verified** |
| C-14 | Forecast with intervals | ~~blocked — `forecastplot`~~ **RESOLVED** |

**The key realisation for Chapter 11:** the Diwali material is mostly *calendar*
work, not *series* work. Constructing the regressor, the October/November split,
the weekend-drop rule — none of it needs an Indian series. Only the estimated
effect (C-10) does. So the Diwali half of Chapter 11 can be written and largely
illustrated without `iip_india`, with one figure and one paragraph deferred.

---

## 1. Chapters

| Ch | Title | pp | Figures | Primary dataset |
|---|---|---|---|---|
| 10 | Trading Day | 4 | C-3, C-4, C-5 | `appliance` |
| 11 | Moving Holidays | 7 | C-6 … C-10 | `appliance`, calendar |
| 12 | Outliers and Interventions | 4 | C-11, C-12 | `airline`, `iip_india` |
| 13 | Model Selection and Forecasts | 3 | C-13, C-14 | `airline` |

### Verified numbers available

The fixture supplies more of Part III than expected. All from
`auto_test.udg`, on `airline` with `automdl`, `outlier` and
`aictest = [:td, :easter]`:

```
Trading day:   F(1, 128) = 31.0579,  p = 1.4166e-7
Easter[1]:     coef 0.017767,  se 0.007158,  t = 2.4822
AO1951.May:    coef 0.100156,  se 0.020439,  t = 4.9003
Outlier counts: ao 1, ls 0, tc 0, so 0, rp 0, tls 0, total 1
Final regressors: 1-Coefficient Trading Day + Easter[1]
                  + Automatically Identified Outliers
```

So `airline` carries a significant trading-day effect, a significant Easter
effect, and one additive outlier, all with coefficients and standard errors.
That is a complete worked regARIMA example, verified, available now.

---

## 2. Chapter 10 — Trading Day

### What it must establish

That months differ in their day-of-week composition, that this has nothing to do
with seasons, and that it is measurable.

### Outline

| § | pp | Content |
|---|---|---|
| 10.1 | 1 | Months are not interchangeable — **Figure C-3** |
| 10.2 | 1 | Six contrasts and one simplification |
| 10.3 | 1 | Does this series have it? — **Figure C-5** |
| 10.4 | 1 | How large is it? — **Figure C-4** |

**10.1.** Figure C-3 counts each weekday in each month over a few years. A month
with five Saturdays is not the same as one with four, and retail sales know it.
Pure calendar arithmetic, no data, buildable immediately.

**10.2.** The six day-of-week contrasts, leap year, and the one-coefficient
weekday-versus-weekend simplification. Explain *why* six and not seven: the
seventh is determined once the month's length is known, so it would be
collinear with the length-of-month effect.

**10.3.** How X-13 decides. `aictest` fits with and without and compares
information criteria. On `airline` the verdict is emphatic and verified:

```
F(1, 128) = 31.06,  p = 1.4e-7
```

Worth a remark: `airline` is passenger travel, not retail, and a trading-day
effect there is less intuitive than in shop sales. It is nonetheless strongly
present. A reader who assumes trading day is only a retail phenomenon should be
corrected here.

Figure C-5 shows the spectral evidence, which connects to Chapter 18.

**10.4.** The estimated effect as a time series, via `components(res; which =
:trading_day)`. RESOLVED — buildable directly.

### Dataset note

The master assigns `appliance`, and it is the better *explanation* — shopping
days obviously drive retail. But the verified numbers above are on `airline`.

**Recommendation:** explain with `appliance`, generate its own `aictest` result
so the chapter is internally coherent, and use the `airline` figures as the
"you might not expect this one" aside in 10.3. One extra run, and the chapter
gains a genuinely surprising fact.

---

## 3. Chapter 11 — Moving Holidays

**The chapter no other X-13 documentation contains.** Seven pages: about three on
Easter, four on Diwali.

### Outline

| § | pp | Content |
|---|---|---|
| 11.1 | 1 | The problem a fixed seasonal factor cannot solve |
| 11.2 | 1 | Easter — **Figure C-6** |
| 11.3 | 1 | The window model — **Figure C-7** |
| 11.4 | 1.5 | Diwali, and why nothing built in fits — **Figure C-8** |
| 11.5 | 1.5 | Building the regressor — **Figure C-9** |
| 11.6 | 1 | The estimated effect — **Figure C-10** |

**11.1.** A holiday fixed to a calendar date is absorbed by the seasonal factor
for that month. A holiday that *moves between months* cannot be, because the
month it lands in changes from year to year. That single distinction is the
whole chapter.

**11.2.** Easter's date varies across roughly a month and can fall in March or
April. Figure C-6 plots Easter Sunday by year, which makes the March/April split
visible at once. Pure calendar, buildable.

**11.3.** The window model: effect spread over *w* days before Easter, allocated
to months in proportion. `Easter[1]` means a one-day window. Verified on
`airline`:

```
Easter[1]:  coef 0.017767,  se 0.007158,  t = 2.482
```

Also worth explaining: the regressor is centred by subtracting long-run monthly
means, so it does not compete with the seasonal factors it sits alongside.

**11.4.** Diwali moves between October and November, and X-13's built-in
holidays are Easter, Labor Day and Thanksgiving — three US holidays. There is no
built-in for this and none for Chinese New Year or Eid either. Figure C-8 plots
the Diwali date by year from the shipped calendar table. **Buildable now; needs
no series data.**

**11.5.** Constructing it with [`custom_holiday_regressor`](@ref). Figure C-9
shows the resulting regressor with a weekend-dropped year marked.

Explain the weekend rule as the methodological choice it is: a holiday falling
on a day that was not a working day anyway produces no incremental trading
effect, so it is excluded. Both reference pipelines this package was validated
against used a bare month dummy instead. **Say that the package deliberately
differs, and why.** This is one of the few places the book documents a
divergence from R, and it is a divergence in the package's favour.

**11.6.** The estimated effect over time. RESOLVED — both `componentplot` and
`iip_india` are available; the section can be written directly rather than
deferred.

---

## 4. Chapter 12 — Outliers and Interventions

### Outline

| § | pp | Content |
|---|---|---|
| 12.1 | 1.5 | Four shapes — **Figure C-11** |
| 12.2 | 1 | Finding them automatically |
| 12.3 | 1 | A real case — **Figure C-12** |
| 12.4 | 0.5 | When not to trust the detection |

**12.1.** AO, LS, TC and SO as pictures before definitions. Synthetic, four
panels, buildable. The distinction that matters: an AO affects one month, an LS
moves the level permanently, a TC decays back.

**12.2.** Detection is iterative t-testing against a critical value that depends
on series length. The verified example on `airline`:

```
AO1951.May:  coef 0.100156,  se 0.020439,  t = 4.900
counts:      ao 1, ls 0, tc 0, so 0, total 1
```

Make the point that this outlier is **not visible in the levels** — the
surrounding values are 163, 172, 178. Detection works on regARIMA residuals
after differencing. Getting Started chapter 4 raised this; here is where it gets
explained.

**12.3.** COVID on `iip_india` as a real LS/TC signature. RESOLVED —
`iip_india` ships, with a confirmed, dramatic level shift already recorded
in `dataset_info("iip_india")` (April 2020: 54.0, down from 117.2 in March).
Run `outlier = true` on it directly to confirm the shape X-13 detects before
drafting.

**Also worth trying, independent of the above:** run `outlier = true` on
`appliance` and see what it finds. A 192-month retail series through
1972–1988 may well contain a level shift of its own, and if so Chapter 12
gets a second verified example alongside `iip_india`, not instead of it.
One run answers it. If it finds nothing, 12.3 defers.

**12.4.** Detection near a series end is unreliable, because there is not yet
enough data after the event to distinguish a temporary blip from a permanent
shift. A level shift found in the last few months is provisional. This is short,
important, and frequently ignored in practice.

### Boundary

Keep clear of Chapter 8's extreme-value replacement. X-11 downweights an
observation inside the filter and leaves nothing behind; a regARIMA outlier is
estimated, reported, and removable. Both exist, they do different jobs, and
readers conflate them. One explicit paragraph.

---

## 5. Chapter 13 — Model Selection and Forecasts

Short, and it has a genuinely interesting verified result.

### Outline

| § | pp | Content |
|---|---|---|
| 13.1 | 1.5 | How automdl chooses — **Figure C-13** |
| 13.2 | 1 | Forecasts — **Figure C-14** |
| 13.3 | 0.5 | Freezing the choice |

**13.1 carries the chapter**, on the strength of this verified finding:

```
automdl.best5:
  1. (0 1 0)(0 1 1)   BIC -4.007
  2. (1 1 1)(0 1 1)   BIC -3.986
  3. (0 1 1)(0 1 1)   BIC -3.979     <- the model actually chosen
  4. (1 1 0)(0 1 1)   BIC -3.977
  5. (0 1 2)(0 1 1)   BIC -3.970

automdl.first: (0 1 0)(0 1 1)
automdl:       (0 1 1)(0 1 1)
```

**The chosen model ranks third.** The best-BIC candidate was picked at the
identification stage (`automdl.first`) and then rejected downstream, after
estimation and diagnostic checking.

This is worth a page. It corrects a common misreading — that `automdl` simply
minimises an information criterion — and it explains why `fivebestmdl` exists at
all: to show you what was considered, not just what won. It also makes the
practical point that when five candidates sit within 0.04 of each other, the
ranking is close to arbitrary and the choice should not be treated as decisive.

**Verify what rejected the best-BIC candidate** before writing the explanation.
The manual's `automdl` documentation covers the post-identification checks; do
not infer the reason from the numbers alone.

Then the Box-Jenkins note: `(0 1 1)(0 1 1)` is the airline model, fitted by hand
in 1970, and X-13's automatic procedure arrives at it independently.

**13.2.** Forecasts and prediction intervals. Chapter 9 used forecasts as a
means; here they are the output. RESOLVED — `forecast()` and `forecastplot`
are both available.

**13.3.** `static()` and why an automatically selected model should be frozen
before publication. Points back to Getting Started chapter 4 and forward to
Chapter 20's revision discussion.

---

## 6. Boxes

**Gotcha (Ch 13)** — information criteria are not comparable across different
differencing orders, because the models are fitted to different data. The best-5
list holds `d` and `D` fixed for exactly this reason.

**In official statistics (Ch 11)** — most offices fix their moving-holiday
regressors by convention and re-estimate coefficients rather than re-testing
whether the holiday matters each period.

**Under the hood (Ch 10)** — the day-of-week contrast construction and why it
has six columns.

---

## 7. Verification checklist

| Item | Ch | Status |
|---|---|---|
| TD F-test on `airline` | 10 | **verified** |
| TD `aictest` result on `appliance` | 10 | generate |
| Why six contrasts, not seven | 10 | verify |
| Easter[1] coefficient on `airline` | 11 | **verified** |
| Easter window/centring mechanism | 11 | verify from manual |
| Diwali dates from the shipped table | 11 | **verified** (artifact) |
| Weekend-drop rule behaviour | 11 | **verified** (package tests) |
| AO1951.May coefficient and counts | 12 | **verified** |
| Outlier detection on `iip_india` (COVID) | 12 | generate — no longer blocked |
| Outlier detection on `appliance` | 12 | generate — optional second example |
| Outlier critical-value rule | 12 | verify from manual |
| `automdl` best-5 and final | 13 | **verified** |
| What rejects a best-BIC candidate | 13 | **verify from manual** |
| Figures C-3, C-5, C-6, C-7, C-8, C-9, C-11, C-13 | all | build |
| Figures C-4, C-10, C-12, C-14 | 10–13 | RESOLVED — build |

---

## 8. Open questions

1. **RESOLVED (dependency, not the question itself)** — `iip_india` no longer
   needs an `appliance` fallback for 12.3, since it ships directly. Whether
   `outlier = true` on `appliance` *also* finds an LS or TC is still worth one
   run, as an optional second example alongside `iip_india`, not a
   replacement for it.
2. **Should Chapter 10 lead with `appliance` or `airline`?** Recommendation is
   `appliance` for the explanation, `airline` for the surprise. Costs one run.
3. **What rejects the best-BIC candidate in `automdl`?** Central to 13.1 and not
   inferable from the udg alone.
4. **RESOLVED** — `iip_india` ships, so this no longer applies. Chapter 11 can
   use 11.6 and figure C-10 directly.
5. **RESOLVED** — Part III has no remaining hard blockers; all twelve figures
   are buildable, so the original contingency plan (shipping with gaps) is
   moot.

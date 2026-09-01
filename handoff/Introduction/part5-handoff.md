# Handoff: Introduction, Part V — Diagnostics (Chapters 16–20 + Appendix A)

~16 pages, 13 figures. The most valuable part of the book for a practitioner and
the hardest to write well.

**Master:** `introduction-design.md`
**Written after:** Chapter 9, then Part II

---

## 0. The finding that shapes this part

Scoping this handoff meant re-reading the committed `auto_test.udg` fixture in
full. It contains something better than anything a designed example could
provide.

**The airline series — the canonical example, adjusted with sensible defaults —
passes every headline diagnostic and fails three detailed ones.**

| Diagnostic | Result | Verdict |
|---|---|---|
| All eleven M statistics | max is M6 = 0.703 | **pass** |
| Overall Q | 0.20 | **pass**, comfortably |
| `f3.fail` | 0 | **pass** |
| QS on original | 167.65, p = 0.000 | seasonality present |
| QS on adjusted | 0.00, p = 1.000 | **pass**, apparently perfect |
| Spectrum of adjusted, first seasonal frequency | `spcsa.s1: 8.5 +` | **peak flagged** |
| Spectrum of adjusted, second TD frequency | `spcsa.t2: 12.0 +` | **peak flagged** |
| Ljung-Box, lag 3 | 6.813, df 1, p = 0.009 | **fail** |
| Ljung-Box, lag 4 | 7.089, df 2, p = 0.029 | **fail** |
| Residual ACF | significant at lags 3 and 20 | flagged |

All verified, all from the committed fixture.

### Why this matters more than a designed failure

**QS on the adjusted series reports a statistic of exactly 0.00 with p = 1.000,
and the spectrum of that same series has a flagged peak at a seasonal
frequency.** The two diagnostics flatly disagree about whether seasonality
survived.

That disagreement is the entire justification for Part V. It cannot be taught
convincingly with a constructed example, because a reader will suspect the
example was built to make the point. Here it falls out of the most-used series
in the field under ordinary settings.

**Restructure Part V around this.** The arc becomes:

> Chapter 17: it passes. Chapter 18: except the spectrum says otherwise.
> Chapter 19: and the residuals are autocorrelated. Chapter 16 explains why
> that is normal rather than alarming, and why no single number could have
> told you.

### Consequence for prerequisites

The designed "failing dataset" flagged as blocking this part is now **useful but
not blocking.** Airline supplies a real, subtle, verified failure for E-5.

What a second series would still add is E-2, a comparison of Q across a clean and
a poor adjustment. That is one figure, not a chapter. Part V can be written
without it.

---

## 1. Chapters

| Ch | Title | pp | Figures | Blocked |
|---|---|---|---|---|
| 16 | Why So Many Diagnostics? | 3 | — | no |
| 17 | The M Statistics and Q | 4 | E-1, E-2 | E-2 wants a second series |
| 18 | Residual Seasonality | 4 | E-3, E-4, E-5, E-6 | no |
| 19 | Model Adequacy | 3 | E-7, E-8 | no — RESOLVED (`residdiagplot` shipped) |
| 20 | Stability and Revisions | 4 | E-9 … E-12 | no — RESOLVED (`slidingspans`/`revision_history`/`spanplot` shipped) |
| A | A Diagnostic Checklist | 2 | E-13 | no |

**Status update (implementation session, post-handoff):** all five chapters
are now fully writable, not just 16–18. `residdiagplot`, `slidingspans`,
`revision_history` and `spanplot` all shipped with W.7/W.8.

---

## 2. Chapter 16 — Why So Many Diagnostics?

### What it must establish

Why this procedure has dozens of checks when regression gets by with a handful.

### The argument

Chapter 2 established that the decomposition is **not identified**: infinitely
many trend-and-seasonal splits reproduce the same observed series. There is no
true seasonal component to compare an estimate against, and no likelihood ratio
test for "is this the right decomposition".

So the profession built an empirical substitute. Each diagnostic targets one
specific way an adjustment can go wrong, and the battery as a whole is what
stands in for a test that cannot exist.

Three families, which also organise chapters 17–20:

| Question | Diagnostics | Chapter |
|---|---|---|
| Is the output plausible? | M1–M11, Q | 17 |
| Did it actually remove the seasonality? | QS, F-tests, spectrum | 18 |
| Is the model behind it sound? | Ljung-Box, normality, residual ACF | 19 |
| Will it still look like this next month? | sliding spans, revision history | 20 |

### The closing point

None of them is a certificate. Q below 1.0 is necessary, not sufficient. And —
using the §0 finding — **they can disagree with each other**, which is not a
malfunction but a consequence of each measuring something different.

Preview the airline case here in two sentences and let chapters 17–19 deliver it.
No figures; the taxonomy table above is the chapter's visual.

---

## 3. Chapter 17 — The M Statistics and Q

### What it must establish

What the eleven statistics measure, how Q combines them, and where they mislead.

### Outline

| § | pp | Content |
|---|---|---|
| 17.1 | 2 | The eleven, in words — **Figure E-1** |
| 17.2 | 1 | How Q combines them |
| 17.3 | 1 | Where they mislead — **Figure E-2** |

**17.1.** One or two sentences each, in plain language, on what failure looks
like for each. M7 gets a paragraph of its own: it tests whether identifiable
seasonality is present at all, it is the one practitioners quote, and an M7 above
1.0 is often read as "this series should not be adjusted".

**Verify all eleven definitions against Ladiray & Quenneville or the manual
before writing.** The M1–M6 definitions are widely restated and easy to get
subtly wrong; M8–M11 are the ones most often confused with each other, since two
are whole-series and two are recent-years variants of the same quantity. Do not
write these from recollection.

The full verified set from the fixture, usable directly in Figure E-1:

```
M1 0.041   M2 0.042   M3 0.000   M4 0.283   M5 0.190   M6 0.703
M7 0.203   M8 0.418   M9 0.368   M10 0.431  M11 0.418
Q 0.20     Q2 0.22    fail 0
```

Worth remarking on: M3 is exactly 0.000 and M6 is 0.703, seventeen times larger.
The statistics are not on a common scale of "how badly did this go" — they
measure different things and their values are not comparable across the row.

**17.2.** Q is a weighted average, not a mean. **Verify the weights** rather
than describing them loosely. Q2 excludes M2; the fixture gives 0.20 and 0.22.

**17.3.** Their known weaknesses. They were designed for X-11 and do not apply to
SEATS at all — [`mstats`](@ref) returns `nothing` for a SEATS run, which is worth
saying since a reader will otherwise think something broke. They are sensitive to
series length. And a clean Q says nothing about whether the *model* was right,
which Chapter 19 demonstrates on this very series.

---

## 4. Chapter 18 — Residual Seasonality

**The chapter where the §0 finding pays off. Give it room.**

### Outline

| § | pp | Content |
|---|---|---|
| 18.1 | 1 | The QS test — **Figure E-3** |
| 18.2 | 0.75 | The F-tests |
| 18.3 | 1.25 | Reading a spectrum — **Figures E-4, E-6** |
| 18.4 | 1 | When they disagree — **Figure E-5** |

**18.1.** QS is a one-sided test on seasonal-lag autocorrelation. The pattern to
want: significant on the original, insignificant on the adjusted. Verified:
167.65 with p = 0.000 becoming 0.00 with p = 1.000.

**18.2.** The stable and moving seasonality F-tests from D8 and D9, and the
combined identifiable-seasonality verdict, via [`seasonality_tests`](@ref).

**18.3.** How to read a spectrum: seasonal frequencies, the two trading-day
frequencies, and what X-13 counts as a visually significant peak. The `.udg`
reports each frequency as either `nopeak` or a height with a `+` marker.
**Confirm from the manual what the numeric height is measured in and what
threshold earns a `+`** before writing prose about it.

**18.4 is the chapter's centre**, and it is verified:

```
QS on the seasonally adjusted series:   0.00,  p = 1.000
spcsa.s1  (first seasonal frequency):   8.5 +
spcsa.t2  (second TD frequency):       12.0 +
```

QS says the adjusted series has no seasonality left. The spectrum of the same
series has a flagged peak at a seasonal frequency. Both are correct, because
they measure different things: QS tests autocorrelation at seasonal lags,
the spectrum looks for concentrated power at seasonal frequencies, and a small
regular component can register in one and not the other.

What a practitioner should do about it: treat a spectral peak in the adjusted
series as a prompt to look for a missing regressor, and note that `spcsa.dom`
reports `no` here, meaning the peak is flagged but not dominant. A flagged
non-dominant peak on an otherwise clean adjustment is common and not by itself a
reason to reject the result.

Say plainly that this is the most-used series in the field under ordinary
settings. That is what makes the lesson land.

---

## 5. Chapter 19 — Model Adequacy

### What it must establish

That the regARIMA model has its own diagnostics, that they are ordinary time
series diagnostics, and that they can fail while the adjustment looks fine.

### Outline

| § | pp | Content |
|---|---|---|
| 19.1 | 1.5 | Residual autocorrelation — **Figures E-7, E-8** |
| 19.2 | 1 | Normality and other checks |
| 19.3 | 0.5 | What a failure actually means |

**19.1.** Verified, and this is the chapter's hook:

```
lbq$03:   6.813   df 1   p = 0.009
lbq$04:   7.089   df 2   p = 0.029
sigacf   significant at lags 3 and 20
acflimit 1.6
```

**The airline model fails Ljung-Box at lags 3 and 4.** The same model that gives
Q = 0.20, passes all eleven M statistics, and removes the seasonality
completely by QS.

Two things worth explaining rather than glossing:

- X-13 reports **only the lags where the test is significant** (`nlbq: 2`,
  `lblags: 3 4`), so an empty list is the good outcome and a short list is the
  informative one.
- The `acflimit` of 1.6 is X-13's flagging threshold in standard errors, which
  is **not** the 1.96 a reader will expect. Note the difference rather than
  letting them assume.

E-7 (`residdiagplot`) and E-8 (Ljung-Box p-values by lag) are both buildable
directly.

**19.2.** Skewness 0.0900, kurtosis 3.0698, Durbin-Watson 1.9504 — all clean.
So the failure in 19.1 is specifically autocorrelation, not distributional.
That precision is worth drawing out.

**19.3.** A Ljung-Box failure usually means a **missing regressor**, not a wrong
ARIMA order. A calendar effect, an outlier, a level shift. This is the natural
place to point back to Part III.

And the honest verdict on this particular case: the airline model is famously
adequate rather than perfect, the failures are mild, and no practitioner would
reject the adjustment on this evidence. **Say so.** A chapter that reports a
failing p-value without telling the reader whether to care has taught them
nothing.

---

## 6. Chapter 20 — Stability and Revisions

### What it must establish

That these ask a different question from everything before: not "is this right"
but "will it still look like this next month".

### Outline

| § | pp | Content |
|---|---|---|
| 20.1 | 1.5 | Sliding spans — **Figures E-9, E-10** |
| 20.2 | 1.5 | Revision histories — **Figures E-11, E-12** |
| 20.3 | 1 | What to do when it is unstable |

**20.1.** Adjust overlapping spans of the series, compare the estimates for
months common to several. The threshold rules are percentage-of-months criteria.
**Verify the thresholds** from Findley, Monsell, Shulman & Pugh (1990) or the
manual.

**20.2.** Concurrent versus final estimates. This is Chapter 9's argument
measured formally, and the chapter should say so explicitly — the revision fan
drawn there is what a revision history quantifies.

**20.3.** A longer seasonal filter, fewer automatic decisions, or a frozen
specification. Ties to `static()` and to Getting Started chapter 4.

**RESOLVED:** `slidingspans`/`revision_history` (W.7.8) and `spanplot`
(W.8.5) all shipped. The chapter no longer needs to be written last in Part
V for this reason — W.7.8's own open question (whether the summaries land
in `.udg`) is answered: yes, both accessors read rich summary statistics
directly from `.udg`, confirmed against the real binary.

---

## 7. Appendix A — A Diagnostic Checklist

Two pages, pinnable, no prose. The flowchart (E-13) plus a table: what to check,
which function, what value to want, what to do when it fails.

Chapter 16's taxonomy table is the skeleton. This is its operational form.

Per the docs-tree decision, this also appears as a how-to page in the API
Reference. **Generate both from one source** rather than maintaining two copies.

---

## 8. Verification checklist

Unusually well supplied — most of Part V's numbers are already verified.

| Item | Chapter | Status |
|---|---|---|
| M1–M11, Q, Q2, fail | 17 | **verified** (fixture) |
| Definitions of M1–M11 | 17 | **verify from L&Q / manual** |
| Q's weighting scheme | 17 | **verify** |
| QS original and adjusted | 18 | **verified** |
| `spcsa.s1 = 8.5 +`, `spcsa.t2 = 12.0 +`, `spcsa.dom = no` | 18 | **verified** |
| Peak height units and the `+` threshold | 18 | **verify from manual** |
| Ljung-Box at lags 3, 4; `nlbq`, `lblags` | 19 | **verified** |
| `acflimit = 1.6`, sigacf at lags 3 and 20 | 19 | **verified** |
| DW, skewness, kurtosis | 19 | **verified** |
| Sliding-spans thresholds | 20 | verify from Findley et al. |
| Figures E-1, E-3, E-4, E-6, E-8 | 17–19 | build |
| Figures E-2, E-5 | 17, 18 | build (E-2 wants a second series) |
| Figures E-7, E-9, E-11 | 19, 20 | RESOLVED — build |

All fixture values come from a run with `automdl`, `outlier` and
`aictest = [:td, :easter]`. Part V should use that same specification throughout
so every number in the part is internally consistent and matches Getting Started
chapter 4.

---

## 9. Open questions

1. **Should Part V use the fixture spec throughout?** Recommend yes. It makes
   every number verified, matches Getting Started, and means the §0 story holds
   together across four chapters. The cost is that the part demonstrates one
   specification rather than several.
2. **Is a second dataset still wanted for E-2?** No longer blocking. Worth having
   if the near-zero or divergent series arrives anyway, since either could serve.
3. **What are the units of the spectral peak height** (`8.5` in `spcsa.s1`)?
   Needed before §18.3 can describe it accurately.
4. **Does the QS-versus-spectrum disagreement have a standard explanation in the
   literature?** It is a known phenomenon and worth citing rather than presenting
   as a discovery. Check Findley et al. (1998) and the manual's diagnostics
   chapter.
5. **RESOLVED** — Chapter 20 is no longer blocked; W.7.8 and W.8.5 both
   shipped. Part V can be written and illustrated as all five chapters.

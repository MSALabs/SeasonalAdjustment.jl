# SeasonalAdjustment.jl — Development Sequence

## What this is, and the one deliberate exception at its core

SeasonalAdjustment.jl is the destination the broader TSAnalytics.jl
project was originally built toward: official-statistics-grade
seasonal adjustment for Julia — X-11, RegARIMA, and SEATS.

**It also deliberately breaks from that project's own "reference, never
port" principle**, for this package's core functionality specifically.
Rather than reimplement X-11/RegARIMA/SEATS from scratch as a first
step, this package wraps the actual Census Bureau X-13ARIMA-SEATS
binary directly — confirmed, not assumed: `x13org/x13prebuilt` on
GitHub is the exact repository R's own `seasonal`/`x13binary` packages
depend on internally, and Python's `statsmodels.tsa.x13` calls the same
program too. Both of the usual reference ecosystems already trust this
binary for the hardest part of the whole problem — SEATS's spectral
factorization especially. Wrapping it directly gets this package to
correct, production-grade output immediately, rather than spending
months on the hardest mathematics in the entire TSAnalytics.jl roadmap
before shipping anything.

A from-scratch native Julia engine remains a real, planned track
(Part 2 below) — not abandoned, deliberately sequenced behind a working
wrapper.

## Relationship to TSAnalytics.jl

**Confirmed**: `tsvalues`/`tsindex` (TSAnalytics.jl's container-agnostic
series interface) as a baseline dependency either way, so a user can
pass the same series object to either package consistently.

**Open, flagged honestly rather than assumed**: whether `X13Result`
(W.4) should subtype an existing TSAnalytics.jl decomposition abstract
type, if `classical_decompose`/`stl_decompose` share one — this needs a
direct check against the real TSAnalytics.jl source before W.4 is
implemented. If a shared type exists, `X13Result` should subtype it for
consistent display/composition; if not, the light dependency above is
sufficient for Part 1. **Do not guess on this — check the source
directly as the first step of W.4's own handoff, not before.**

Part 2 needs the full, deep dependency regardless of how the above
resolves: Stage 8.3 (`fit_arimax`/`fit_sarimax`), Stage 6.8
(`auto_arima`), Stage 6.3 (the Kalman smoother), and Stage 2.4
(Ljung-Box) from that project directly.

## API design principle — a genuine superset of R and Python, verified precisely

R's `seas()` and Python's `x13_arima_analysis()` are differently
*shaped*, not just differently named, confirmed directly:
```r
seas(x, xreg=NULL, ..., list=NULL)   # `...` accepts ANY spec.argument combination directly -- the full X-13 grammar, dynamically
```
```python
x13_arima_analysis(endog, maxorder=(2,1), maxdiff=(2,1), outlier=True, trading=False, ...)  # a fixed, curated subset only
```
**R exposes the entire X-13 spec grammar dynamically; Python exposes
only a curated subset of it.** Being a genuine superset of both
therefore means R's full-passthrough mechanism is the *foundation*,
with Python's curated option list layered on top for discoverability —
not the reverse. Julia's own `kwargs...` maps onto this directly:
```julia
x13(y; maxorder=(2,1), outlier=true, trading=false,   # Python-style curated ergonomics
       regression_variables=[...], arima_model="...", # R-style direct spec passthrough
       kwargs...)                                      # anything else, forwarded straight into spec generation
```
This is a concrete design requirement for W.4 now, not an aspiration —
confirm both mechanisms are genuinely present before treating that
stage as complete.


## Verification philosophy — Part 1 and Part 2 are genuinely different, stated plainly so they don't get blurred

**Part 1 (the wrapper)**: "matches R" and "matches Python" both reduce
to the same claim — "matches `x13prebuilt`'s own real output" — since
neither reference independently computes anything here; both call the
identical binary this package wraps. Primary verification is therefore
direct binary invocation, already proven working (see the real ground
truth already generated, below). R's and Python's own wrapper packages
serve as a secondary check on *API-level* behavior only.

**Part 2 (the native engine, once started)**: genuine independent
reimplementation, so the full TSAnalytics.jl dual-verification standard
applies exactly as it did throughout that project — real R and Python
execution wherever reachable, with `x13prebuilt`'s own output available
as an even stronger ground truth than usual (confirmed directly: this
program includes X-11, RegARIMA, *and* SEATS all in one binary, so
every native-engine stage has real, authoritative output to check
against, not just a published algorithm description).

---

## Real ground truth already generated — reuse this, don't regenerate it

**The pinned `x13prebuilt` commit**: `61c4043949f43c1ea5ad0fbbc7b6c11fc5073d19`.
Real SHA256 hashes for every platform binary at this commit are already
computed and in `Artifacts.toml` — Linux x86_64, Linux armv7l, Windows,
macOS x86_64, macOS arm64 (the last two share an identical hash in the
source repo — confirm this is a genuine universal binary before
trusting both platform entries blindly).

**The core Box-Jenkins airline passengers series** (1949-1960, 144
monthly observations — the standard benchmark in this entire field),
run through the real binary twice:

*Without any custom regressor* — real D10 (seasonal factors), D11
(seasonally adjusted), D12 (trend-cycle) tables generated directly:
```
D10, Jan-Jun 1949: 0.909187671763704, 0.959401810971537, 1.05757934646024,
                    1.00514879872191, 0.999732566557629, 1.07303952726698
D11, Jan-Mar 1949: 123.186888118198, 122.993305464483, 124.813330027491
D12, Jan-Mar 1949: 123.774514749304, 123.950693749510, 124.289377383170
```

*With a synthetic Diwali-effect user-defined regressor* (proving the
custom-holiday-regressor mechanism, section "W.0" below) — the same
series, same spec otherwise, but with
`regression { variables=(td) user=(diwali) usertype=(holiday) data=(...) }`
added:
```
D10, October factors WITHOUT the custom regressor: 0.898593816033472 (1949), ...
D10, October factors WITH the custom regressor:    0.726751422651829 (1949), ...
```
**The seasonal factor genuinely shifted** — proof the binary actually
used the custom regressor, not just accepted and ignored it.

Two real, practical requirements surfaced while getting this clean run,
both worth keeping for W.2's spec generation:
1. **User-defined regressor data must cover the RegARIMA forecast
   horizon** (a year ahead, by default), not just the historical series
   length — the binary errors clearly (`"forecasts end date ... must
   end on or before user-defined regression variables end date"`) if it
   doesn't, rather than silently truncating.
2. **Combining a RegARIMA model with multiplicative X-11 mode needs an
   explicit `transform { function = log }` spec** — without it, the
   binary errors (`"Multiplicative or log additive seasonal adjustment
   cannot be performed when preadjustment factors are derived from a
   regARIMA model for data which have not been log transformed"`).

All spec files and full 144-month output tables from both runs are
preserved in this package's verification assets — reuse them directly
as test fixtures rather than regenerating from scratch.

---

## Part 1 — wrap `x13prebuilt` (the active track)

| # | What | Needs | Notes |
|---|---|---|---|
| W.0 | Business-day/holiday calendars (India + major markets) — generates the actual user-defined regressors W.2 passes to the binary | `BusinessDays.jl` | Confirmed working end-to-end with the real binary (the Diwali proof above) — not optional once non-Western-calendar effects are wanted. India's fixed-date holidays (Republic Day, Independence Day, Gandhi Jayanti) and Good Friday are algorithmically computable; Diwali/Holi/Eid and most of India's actual trading calendar have no closed-form date formula and need a maintained, year-keyed table sourced from the relevant exchange's own official circular (a real data-sourcing caution surfaced during research: secondary aggregator sites disagreed on one 2026 Diwali date by over two weeks — don't trust aggregators, use NSE's own circular) |
| W.1 | Binary artifact management for `x13prebuilt` (Linux/Windows/macOS) via Julia's Artifacts system | none | `Artifacts.toml` already scaffolded with real SHA256 hashes and verified download URLs, pinned to the commit above; `git-tree-sha1` values are placeholders needing a real Julia runtime to compute (`tools/generate_artifacts.jl` is ready to run for this) |
| W.2 | Spec-file generation (`series{}`, `x11{}`, `regression{}`, `arima{}`, `outlier{}`, user-defined regressor blocks) | W.1, W.0 | Grammar confirmed directly against the real binary, including both practical requirements noted above |
| W.3 | Subprocess invocation + output-table parsing (`d10`/`d11`/`d12`/`d13`, SEATS' own tables) | W.2 | Real output format already confirmed from actual runs — tab-separated, `date\tvalue` per line, a `date\t------\t---...` header row to skip |
| W.4 | Idiomatic Julia API (`x13(y; options...)`) | W.3 | Mirrors R's `seas()` ergonomics; returns a proper Julia struct (`X13Result`), not raw files |

---

## Part 2 — native Julia engine (deferred, not abandoned)

| # | What | Needs | Reference points |
|---|---|---|---|
| S.1 | X-11 filters (Henderson moving averages, iterative seasonal factors) | Julia's standard convolution/filtering primitives only — this is the one native-engine stage genuinely independent of everything else in this chapter | Census Bureau X-11 method documentation; Ladiray & Quenneville, *Seasonal Adjustment with the X-11 Method* (2001); real D10/D11/D12 ground truth now available from `x13prebuilt` directly (above), a categorically stronger verification target than most native-engine work gets |
| S.2 | RegARIMA — calendar regressors (trading-day effects, Easter) | TSAnalytics.jl Stage 8.3, W.0 | X-13ARIMA-SEATS Reference Manual (US Census Bureau, 2009) |
| S.3 | Automatic outlier detection (additive, level-shift, transitory), TRAMO-style | S.2, TSAnalytics.jl Stage 2.4 | Gómez & Maravall's TRAMO/SEATS papers |
| S.4 | The full X-13 pipeline, orchestrating S.1–S.3 | S.1, S.2, S.3 | Census Bureau Reference Manual |
| S.5 | SEATS canonical decomposition, Wiener-Kolmogorov filters | TSAnalytics.jl Stage 6.8, Stage 6.3, S.2 | Gómez & Maravall (1996) — still the hardest single piece across both this package and the broader TSAnalytics.jl roadmap, even with real binary output now available to check against |

### S.1's own verified starting point — the Henderson filter formula

Already confirmed from two independent sources (a working reference
implementation and a US patent document, cross-checked against each
other):
```
For a symmetric Henderson filter of length n = 2m+1:
  m1 = (m+1)^2,  m2 = (m+2)^2,  m3 = (m+3)^2
  d  = 8*(m+2)*(m2-1)*(4*m2-1)*(4*m2-9)*(4*m2-25)
  w[j] = 315 * (m1-j^2) * (m2-j^2) * (m3-j^2) * (3*m2-11*j^2-16) / d
```
Real, hand-checkable target: the 5-term filter's published weights are
`(-0.073, 0.294, 0.558, 0.294, -0.073)`. The defining mathematical
property (exact reproduction of any cubic polynomial) is itself a real,
reference-free test — verify this before anything else once S.1 starts.

---

## The critical path

```
W.0 ──► W.2 ──► W.3 ──► W.4
W.1 (independent, needed by W.2 but can build in parallel)

S.1 (fully independent of the rest of Part 2 — can start any time)
S.2 needs W.0 + TSAnalytics.jl 8.3, then unblocks S.3 and S.5 both
```

**W.0 and S.2 are the two real bottlenecks of this whole package** —
nearly everything downstream, in both parts, eventually depends on one
or the other.

---

## How this gets built

One task at a time, strictly in the order above — each task gets its
own handoff document (verified references, API design, test cases,
honest gaps flagged explicitly) before implementation starts, matching
TSAnalytics.jl's own development standard throughout. Given Part 1's
different verification philosophy (above), each Part 1 handoff should
say plainly that its "R and Python" check is really "matches the
binary directly," rather than imply the traditional dual-independent-
reimplementation standard applies where it doesn't.

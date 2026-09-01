# Handoff: Book Build and Integration

Consolidates the figure manifest, file layout and build pipeline for Getting
Started and the Introduction.

**Chapter handoffs, all complete:**
`ch09-handoff.md`, `part1-handoff.md`, `part2-handoff.md`, `part3-handoff.md`,
`part4-handoff.md`, `part5-handoff.md`

**Status update (implementation session, post-handoff):** every `W.7.x`/
`W.8.x` blocker below and the `iip_india` licensing blocker are now
**resolved** -- W.7 and W.8 shipped in full (forecast/backcast/components/
vcov/coeftable/summary/force/seasonalma/slidingspans/revision_history, and
all five plot recipes: `seasonalplot`, `forecastplot`, `residdiagplot`,
`componentplot`, `spanplot`), and `iip_india` ships as a bundled dataset
(`dataset("iip_india")`) with a real, verified COVID level shift. Blocker
markers below are left in place as a record of what was true when this
document was written, with `RESOLVED` noted inline rather than silently
deleted. The only blockers still open are the near-zero (B-12) and divergent
(D-6) datasets, neither of which exists yet. Chapter 9 is now built (prose,
both figures, worked example, test coverage) -- see
`book/src/introduction/09-end-of-series.md`.

---

## 1. Figure manifest

Sixty figures. **Kind** determines who builds it:

- **R** — one call to a package recipe
- **C** — custom, written with Plots in the figure script
- **X** — needs derivation code (filters computed in Julia)
- **D** — a diagram, no data

### Getting Started (8)

| ID | Ch | Kind | Dataset | Content | Blocker |
|---|---|---|---|---|---|
| GS-1 | 2 | C | airline | Raw series, peaks annotated | — |
| GS-2 | 2 | R | airline | `plot(res)` | — |
| GS-3 | 2 | R | airline | `plot(; panels=:components)` | — |
| GS-4 | 3 | R | airline | `monthplot` | — |
| GS-5 | 3 | R | airline | `spectrumplot(; series=:sa)` | — |
| GS-6 | 3 | R | airline | `residplot` | — |
| GS-7 | 4 | C | airline | `:log` vs `:none` + difference | — |
| GS-8 | 4 | R | airline | `plot(; outliers=true)` | — |

### Part I — Foundations (6)

| ID | Ch | Kind | Dataset | Content | Blocker |
|---|---|---|---|---|---|
| A-1 | 1 | C | **appliance** | Raw, December spike annotated | — |
| A-2 | 2 | R | appliance | `seasonalplot` | ~~W.8.1~~ RESOLVED |
| A-3 | 2 | D | — | Decomposition schematic | — |
| A-4 | 2 | C | airline | Multiplicative vs additive | — |
| A-5 | 3 | D | — | Lineage timeline | — |
| A-6 | 3 | D | — | Two philosophies | — |

A-1's dataset changed from `iip_india` per `part1-handoff.md` §1.

### Part II — X-11 (13)

| ID | Ch | Kind | Dataset | Content | Blocker |
|---|---|---|---|---|---|
| B-1 | 4 | C | airline | Centred 12-term MA | — |
| B-2 | 4 | C | airline | SI ratios by month | — |
| B-3 | 4 | C | airline | Convergence over 3 passes | — |
| B-4 | 5 | **X** | — | Henderson 13-term weights | — |
| B-5 | 5 | **X** | airline | Henderson 9/13/23 applied | — |
| B-6 | 6 | C | airline | 3×3 vs 3×5 vs 3×9 on SI ratios | — |
| B-7 | 6 | **X** | — | Seasonal filter gain functions | — |
| B-8 | 5 | **X** | — | Asymmetric end-filter weights | — |
| B-9 | 8 | R | airline | `monthplot` | — |
| B-10 | 8 | C | airline | Irregular with sigma limits | — |
| B-11 | 7 | R | airline | D10–D13 four-panel | — |
| B-12 | 8 | C | **near-zero** | Four decomposition modes | **dataset** |
| B-13 | 6 | C | airline | MSR and filter choice | — |

### Part III — regARIMA (14)

| ID | Ch | Kind | Dataset | Content | Blocker |
|---|---|---|---|---|---|
| C-1 | 9 | C | airline | Revision fan, no extension | — |
| C-2 | 9 | C | airline | Revision fan, with extension | — |
| C-3 | 10 | C | — | Weekday counts per month | — |
| C-4 | 10 | R | appliance | Trading-day factors | ~~W.7.4 + W.8.4~~ RESOLVED |
| C-5 | 10 | C | appliance | TD spectral peak | — |
| C-6 | 11 | C | — | Easter date by year | — |
| C-7 | 11 | C | — | Easter regressor by month | — |
| C-8 | 11 | C | — | Diwali date by year | — |
| C-9 | 11 | C | — | Diwali regressor, weekend rule | — |
| C-10 | 11 | R | iip_india | Diwali effect path | ~~W.7.4 + W.8.4 + data~~ RESOLVED |
| C-11 | 12 | C | — | AO/LS/TC/SO shapes | — |
| C-12 | 12 | R | iip_india | COVID outliers | ~~data~~ RESOLVED |
| C-13 | 13 | C | airline | Best-5 model BIC | — |
| C-14 | 13 | R | airline | Forecast with intervals | ~~W.7.2 + W.8.2~~ RESOLVED |

C-3, C-6, C-7, C-8, C-9 need **no series data at all** — pure calendar
arithmetic. That is what keeps Chapter 11 writable without `iip_india`.

### Part IV — SEATS (6)

| ID | Ch | Kind | Dataset | Content | Blocker |
|---|---|---|---|---|---|
| D-1 | 14 | D | — | Model → components → filter | — |
| D-2 | 14 | **X** | airline | Model spectrum split | — (may become D) |
| D-3 | 14 | **X** | airline | WK vs X-11 filter weights | — (may become D) |
| D-4 | 15 | C | airline | Both engines overlaid | — |
| D-5 | 15 | C | airline | Their difference | — |
| D-6 | 15 | C | **divergent** | A genuine disagreement | **dataset** |

### Part V — Diagnostics (13)

| ID | Ch | Kind | Dataset | Content | Blocker |
|---|---|---|---|---|---|
| E-1 | 17 | C | airline | M1–M11 with threshold | — |
| E-2 | 17 | C | multiple | Q across series | soft — wants a poor case |
| E-3 | 18 | C | airline | QS before/after | — |
| E-4 | 18 | R | airline | Four spectra | — |
| E-5 | 18 | C | **airline** | Peak in the adjusted series | — |
| E-6 | 18 | C | airline | TD peak annotated | — |
| E-7 | 19 | R | airline | `residdiagplot` | ~~W.8.3~~ RESOLVED |
| E-8 | 19 | C | airline | Ljung-Box p by lag | — |
| E-9 | 20 | R | appliance | Sliding spans | ~~W.7.8 + W.8.5~~ RESOLVED |
| E-10 | 20 | C | appliance | Flagged months | ~~W.7.8~~ RESOLVED |
| E-11 | 20 | R | appliance | Revision history | ~~W.7.8 + W.8.5~~ RESOLVED |
| E-12 | 20 | C | appliance | Revision by lag | ~~W.7.8~~ RESOLVED |
| E-13 | A | D | — | Diagnostic flowchart | — |

E-5 no longer needs a designed failing series. Per `part5-handoff.md` §0, the
airline fixture reports `spcsa.s1: 8.5 +` — a flagged seasonal peak in the
adjusted series — alongside a QS of 0.00 with p = 1.000.

---

## 2. What blocks what

**Superseded — see the status update at the top of this document.** All rows
below except the last three are resolved; kept as a record of the original
scoping.

| Blocker | Figures | Count | Status |
|---|---|---|---|
| ~~W.7.8 + W.8.5~~ (spans) | E-9, E-10, E-11, E-12 | 4 | **RESOLVED** |
| ~~W.7.4 + W.8.4~~ (components) | C-4, C-10 | 2 | **RESOLVED** |
| ~~`iip_india` licensing~~ | C-10, C-12 | 2 | **RESOLVED** — bundled, see `dataset("iip_india")` |
| ~~W.7.2 + W.8.2~~ (forecast) | C-14 | 1 | **RESOLVED** |
| ~~W.8.1~~ (`seasonalplot`) | A-2 | 1 | **RESOLVED** |
| ~~W.8.3~~ (`residdiagplot`) | E-7 | 1 | **RESOLVED** |
| near-zero dataset | B-12 | 1 | still open |
| divergent series | D-6 | 1 | still open |
| second series (soft) | E-2 | — | still open (soft) |

**Fifty-eight of sixty are buildable today.** Only B-12 and D-6 remain
blocked, both on a dataset that does not exist yet.

The sliding-spans chain's own prerequisite -- whether the summaries land in
`.udg` -- was W.5's unanswered open question 3. It is now answered: yes, both
`slidingspans` and `revision_history` read rich summary statistics directly
from `.udg` (`ss*`/`s2.*`/`s3.*` and `r0N.lag00.*`/`revspan` respectively,
confirmed directly against the real binary). Chapter 20 is fully unblocked.

---

## 3. File layout

```
book/
  src/
    getting-started/
      01-installation.md
      02-first-adjustment.md
      03-was-it-any-good.md
      04-beyond-defaults.md
      05-where-next.md
    introduction/
      01-why-adjust.md
      02-decomposition.md
      03-origins.md
      04-x11-by-hand.md
      05-trend-filters.md
      06-seasonal-filters.md
      07-bcd-tables.md
      08-extreme-values-modes.md
      09-end-of-series.md
      10-trading-day.md
      11-moving-holidays.md
      12-outliers.md
      13-model-selection.md
      14-decomposing-a-model.md
      15-x11-vs-seats.md
      16-why-so-many-diagnostics.md
      17-m-statistics.md
      18-residual-seasonality.md
      19-model-adequacy.md
      20-stability-revisions.md
      A-checklist.md
      B-further-reading.md
  examples/
    gs02.jl gs03.jl gs04.jl
    ch04.jl … ch20.jl
  figures/
    make_figures.jl
    derivations.jl        # Henderson weights, gain functions, WK filter
    out/                  # committed SVG + PNG
  build/
    to_pdf.sh
    to_documenter.jl
```

`derivations.jl` is separate from `make_figures.jl` because the five **X**
figures need real computation that will be reused and tested, not plotting code.

---

## 4. The build rule

**No Documenter `@example` blocks in book chapters.** They execute at build time,
so the PDF cannot reproduce them, CI needs the X-13 binary for every docs build,
and the two outputs drift.

Instead:

1. `make_figures.jl` generates all 60 once into `figures/out/`, committed
2. Chapters reference them as plain image paths
3. Code blocks in chapters are **display-only**, extracted from `examples/chNN.jl`
4. `test/test_book_examples.jl` runs those scripts under the usual
   `x13_binary_available()` gate

Code stays honest without build-time execution. Figures stay honest via §6.

### Figure naming

`fig-<doc>-<id>-<slug>.<ext>`

`fig-gs-02-original-vs-adjusted.svg`, `fig-intro-B04-henderson-weights.svg`

SVG for line art and diagrams, PNG at 2× where the point count is high.

### Cross-references

Chapters link to API docstrings with `[`mstats`](@ref)` and never restate them.
Documenter resolves `@ref` natively; the PDF build rewrites it to a URL against
the published docs.

---

## 5. Documenter integration

1. Copy `book/src/**.md` into `docs/src/`
2. Copy `book/figures/out/` into `docs/src/assets/figures/`
3. Rewrite image paths `../figures/out/` → `assets/figures/`
4. Add to `makedocs` `pages` in the agreed tree order:

```julia
pages = [
    "Home" => "index.md",
    "Getting Started" => [ ... 5 entries ... ],
    "Introduction to Seasonal Adjustment" => [ ... 22 entries ... ],
    "API Reference" => "api.md",
]
```

5. Add `test/test_book_examples.jl` to `runtests.jl`
6. **Add a CI job that regenerates figures and fails on any diff**

### Fix before adding 27 pages to the build

`residplot!`, `monthplot!` and `spectrumplot!` currently render their docstrings
**twice each** on the API page. `@userplot`'s generated mutating forms are being
caught by both an explicit `@docs` entry and an autodocs block. `residplot`'s
docstring is long, so this is several thousand redundant words on an already
large page.

---

## 6. The staleness guard

Pre-generated figures are the right call and they go stale silently. Step 6
above is what makes that loud: regenerate in CI, diff against the committed
files, fail on mismatch.

Without it, a change to a recipe's default produces a book whose figures no
longer match its own code, and nobody finds out.

Allow a tolerance for non-deterministic rendering if SVG output is not
byte-stable across versions — compare rendered raster output at low resolution
rather than raw SVG if that turns out to be a problem.

---

## 7. Writing and build order

| Phase | Content | Gated on |
|---|---|---|
| 1 | Getting Started, 5 chapters, 8 figures | done |
| 2 | Chapter 9 | done |
| 3 | Chapters 4–8 (Part II) + `derivations.jl` | B-12 dataset for one figure |
| 4 | Chapters 16–19 (Part V) | — |
| 5 | Chapters 1–3 (Part I) | — |
| 6 | Chapters 10–13 (Part III) | — |
| 7 | Chapters 14–15 (Part IV) | — |
| 8 | Chapter 20 | — |
| 9 | Home page, appendices | everything above settled |

Phase 1 proves the whole pipeline end to end on eight figures before 52 more
depend on it. Phase 3 produces `derivations.jl`, which is also the first real
cross-validation of a filter implementation in this project.

---

## 8. Remaining deliverable

**The Home page.** One page: what the package is, the single-call example, the
bundled binary, and links to the other three sections. Written last, once the
others settle, per `introduction-design.md` §8.

That is the only piece of the docs tree with no handoff and no draft.

---

## 9. Open questions

1. **PDF toolchain** — Pandoc → Typst, or Pandoc → LaTeX? Typst unless someone
   has strong LaTeX preferences.
2. **Two PDFs or one?** Two matches the Documenter split and lets Getting Started
   circulate alone. Leaning two.
3. **Is SVG output byte-stable enough for the diff guard?** Decides whether §6
   compares SVG or rendered raster.
4. **Who draws the six diagrams** (A-3, A-5, A-6, D-1, E-13, plus D-2/D-3 if they
   become schematics)? Hand-drawn SVG looks better and diagrams age slowly.
5. **Does `derivations.jl` eventually move into the package** as part of the
   native engine, or stay book-side permanently? It should stay book-side until
   the engine has its own tested implementation, then be deleted rather than
   duplicated.

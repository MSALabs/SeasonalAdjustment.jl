# Design: *Introduction to Seasonal Adjustment*

Twenty chapters plus an appendix, ~85 pages, 52 figures. Chapters are the unit
of work and the unit of handoff; the five parts exist only to group the table of
contents.

**Companion documents**
- `book-build-handoff.md` — figure inventory and source architecture
- Getting Started — the tutorial this follows
- API Reference — the authority on signatures

---

## 1. Purpose and boundary

Getting Started teaches a reader to *run* an adjustment. The API Reference says
what every keyword does. Neither explains what the program is doing or how to
think about the answer.

That is this book's only job. It should read as an explanation of
X-13ARIMA-SEATS that happens to use SeasonalAdjustment.jl for its examples,
rather than as package documentation that happens to explain things. A reader
should be able to follow it without Julia open.

### Rules

**Never** restate a keyword table, a default, an R or Python parity note, a
design rationale, or a verification history. All of that belongs to the API
Reference.

**Always** name and link rather than document:

> M7 below 1.0 indicates identifiable seasonality. [`mstats`](@ref) returns it
> alongside the other ten.

**Assume** Getting Started has been read. Do not re-explain installation,
`X13Result` fields, or the five basic checks.

### The spine

> **Seasonal adjustment has two rival philosophies, and X-13 ships both.**

X-11 is an empirical filter refined by practitioners, with no model of the data.
SEATS is model-based signal extraction, where the filter is *implied by* a fitted
model rather than chosen from a menu. Part II is one philosophy, Part IV the
other, Part III what they share, Part V how you tell whether either worked.

Chapter 3 sets this up. Everything after refers back to it.

---

## 2. Table of contents

### Part I — Foundations

| Ch | Title | pp | Figures | Dataset |
|---|---|---|---|---|
| 1 | Why Adjust? | 4 | A-1 | `iip_india` |
| 2 | The Decomposition and Its Ambiguity | 4 | A-2, A-3, A-4 | `iip_india`, `airline` |
| 3 | Where X-13 Came From | 4 | A-5, A-6 | — |

### Part II — The X-11 Method

| Ch | Title | pp | Figures | Dataset |
|---|---|---|---|---|
| 4 | X-11 by Hand | 5 | B-1, B-2, B-3 | `airline` |
| 5 | Trend Filters | 5 | B-4, B-5, B-8 | `airline` |
| 6 | Seasonal Filters | 5 | B-6, B-7, B-13 | `airline` |
| 7 | The B, C and D Tables | 3 | B-11 | `airline` |
| 8 | Extreme Values and Decomposition Modes | 3 | B-9, B-10, B-12 | `airline`, near-zero |

### Part III — The regARIMA Front End

| Ch | Title | pp | Figures | Dataset |
|---|---|---|---|---|
| 9 | The End-of-Series Problem | 5 | C-1, C-2 | `airline` |
| 10 | Trading Day | 4 | C-3, C-4, C-5 | `appliance` |
| 11 | Moving Holidays | 7 | C-6 … C-10 | `appliance`, `iip_india` |
| 12 | Outliers and Interventions | 4 | C-11, C-12 | `iip_india` |
| 13 | Model Selection and Forecasts | 3 | C-13, C-14 | `airline` |

### Part IV — SEATS

| Ch | Title | pp | Figures | Dataset |
|---|---|---|---|---|
| 14 | Decomposing a Model | 5 | D-1, D-2, D-3 | `airline` |
| 15 | X-11 and SEATS Compared | 4 | D-4, D-5, D-6 | `airline`, divergent |

### Part V — Diagnostics

| Ch | Title | pp | Figures | Dataset |
|---|---|---|---|---|
| 16 | Why So Many Diagnostics? | 3 | — | — |
| 17 | The M Statistics and Q | 4 | E-1, E-2 | all + failing |
| 18 | Residual Seasonality | 4 | E-3, E-5, E-6 | `appliance`, failing |
| 19 | Model Adequacy | 3 | E-7, E-8 | `airline` |
| 20 | Stability and Revisions | 4 | E-9 … E-12 | `appliance` |

### Appendix

| | Title | pp | Figures |
|---|---|---|---|
| A | A Diagnostic Checklist | 2 | E-13 |
| B | Further Reading | 1 | — |

**Total ~85 pages.** Chapter 11 at seven pages is the longest by design; it is
the chapter no other X-13 documentation has.

Figure E-4 (four spectra side by side) moves into Chapter 18 alongside E-3;
Chapter 20 absorbs the sliding-spans and revision figures.

---

## 3. What each chapter must establish

Only the argument, not the outline. The outline belongs in the chapter's own
handoff.

**1. Why Adjust?** That the question "is the economy improving" cannot be
answered from raw monthly data. Lead with Indian examples — Diwali shifting
between October and November, the harvest cycle, the fiscal year ending in March
— rather than generic ones.

**2. The Decomposition and Its Ambiguity.** That observed = trend × seasonal ×
irregular, and that **the decomposition is not identified.** Infinitely many
splits reproduce the same series; every method is a set of conventions for
choosing one. Saying this early is what makes Chapter 16 land. Multiplicative
versus additive belongs here as the first such convention.

**3. Where X-13 Came From.** Method II → X-11 (1965) → X-11-ARIMA (Dagum, 1980)
→ X-12-ARIMA (1998) → X-13 (2012), each step as a problem someone hit. Ends on
the two-philosophies framing. The name story is worth telling: X-11 was the
eleventh experimental version, published as a *program* with no underlying
model, which is what made statisticians uneasy for thirty years.

**4. X-11 by Hand.** That X-11 is comprehensible. Build a three-pass version in
about fifteen lines: moving-average, subtract, average by calendar month,
subtract, repeat. Show it converging. Then reveal this *is* X-11 with sixty
years of refinements. **Inline in the text, clearly labelled a toy, not
exported** — a naive X-11 in the docs of a package whose Part 2 goal is a
correct native engine would invite confusion.

**5. Trend Filters.** What a Henderson filter is and why length matters. The
asymmetric end filters set up Chapter 9's entire argument, so end this chapter
pointing at it.

**6. Seasonal Filters.** The 3×3 through 3×15 family and stable. Gain functions
are where a reader learns to *see* what a filter does. The moving seasonality
ratio and the automatic choice, read back with [`filters`](@ref).

**7. The B, C and D Tables.** What the letters mean, why three passes. Map to
`X13Result` fields once, then use table names throughout. Point at
`handoff/x13-saveable-tables.md` for the other 277.

**8. Extreme Values and Decomposition Modes.** Sigma limits and replacement, and
why pseudo-additive exists.

**9. The End-of-Series Problem.** *The best argument in the book.* X-11's filters
are symmetric in the middle and asymmetric at the ends, so the most recent
months — the only ones anyone cares about — get the worst treatment and the
largest revisions. Two figures: adjusted at successive endpoints, then the same
with forecast extension. After this, a forecasting model in front of a smoother
stops looking strange.

**10. Trading Day.** That months contain different numbers of Mondays and this
has nothing to do with the season. Worked on `appliance`, which the Census
Bureau chose precisely because its spectrum shows a trading-day component.

**11. Moving Holidays.** Easter first (~3 pp), since it is built in and familiar;
then Diwali (~4 pp), the same problem where no built-in exists. The weekend-drop
rule in [`custom_holiday_regressor`](@ref) explained as the methodological
improvement it is. **No other X-13 documentation contains this chapter.**

**12. Outliers and Interventions.** AO, LS and TC as pictures before
definitions. COVID on `iip_india` as a real signature. Include the warning that
detection near a series end is unreliable.

**13. Model Selection and Forecasts.** Compressed deliberately; Getting Started
covered the mechanics. Adds only the caution about comparing information criteria
across differencing orders.

**14. Decomposing a Model.** That SEATS derives its filter from the data's own
fitted model rather than choosing from a menu. Canonical decomposition and
admissibility get a paragraph each and an "Under the hood" box.

**15. X-11 and SEATS Compared.** Same series, both engines, and an honest
verdict: mostly it does not matter, and when it does, Part V is how you find out.

**16. Why So Many Diagnostics?** *The intellectual payoff.* Regression gets by
with a handful of checks; seasonal adjustment has dozens. Because neither engine
is derived from a testable model — Chapter 2 said the decomposition is not
identified, and this is the consequence. The battery is an empirical substitute
for a likelihood ratio test.

**17. The M Statistics and Q.** All eleven in words, the weighting behind Q, and
their known weaknesses. A reader who treats Q as a certificate will be misled.

**18. Residual Seasonality.** QS, the stable and moving seasonality F-tests, and
the spectral evidence. Why a seasonal peak in the *adjusted* series is bad news
and a trading-day peak means something else.

**19. Model Adequacy.** Ljung-Box, normality, the residual panel.

**20. Stability and Revisions.** That sliding spans and revision histories answer
a different question from everything before — not "is this right" but "will it
still look like this next month", which is what official statistics cares about.

---

## 4. Recurring devices

**"What X-13 actually did"** — a boxed `static(res)` dump after any example
using automatic selection. Teaches spec-reading without a spec-reading chapter.

**"Under the hood"** — short, optional, skippable. Where the mathematics would
go if this were the academic book. **These boxes are the seam where the full
book attaches**; each becomes a section there. Written with that in mind, the
larger book gets an outline for free.

**"In official statistics"** — what national statistical offices actually do at
each decision point, from the ESS Guidelines.

**"Gotcha"** — the save-keyword trap, forced transforms across comparison runs,
end-of-series outlier unreliability, comparing AICs across differencing orders.

---

## 5. Prerequisites

### Datasets — decide before writing the chapter, not during

**Status update (implementation session, post-handoff):** the first two rows
below are resolved. A series that fails its diagnostics was never designed —
Part V's own §0 finding is that the `airline` fixture itself already fails
several detailed diagnostics (QS-vs-spectrum disagreement, Ljung-Box at lags
3 and 4), which turned out to be more persuasive than a constructed example.
`iip_india` shipped as a bundled dataset. The remaining two rows are still
open.

| Need | Blocks | Status |
|---|---|---|
| ~~A series that **fails** its diagnostics~~ | Ch 17, 18, Ch 16's argument | **RESOLVED** — `airline`'s own fixture supplies it |
| ~~`iip_india` licensing~~ | Ch 1, 2, 11, 12 | **RESOLVED** — bundled, `dataset("iip_india")` |
| Near-zero / zero-crossing series | Ch 8 | still open |
| X-11/SEATS divergent series | Ch 15 | still open |

### Blocked figures

**RESOLVED.** The seven figures below needed W.7/W.8, both of which shipped
in full: A-2 (`seasonalplot`), C-4 and C-10 (`componentplot`), C-14
(`forecastplot`), E-7 (`residdiagplot`), E-9 and E-11 (`spanplot`). None of
the 52 chapter figures are blocked on the package any longer — only B-12
(near-zero dataset) and D-6 (divergent dataset) remain open, and both are
dataset gaps, not package gaps.

---

## 6. Writing order

Not sequential. Introductions written first promise what the body does not
deliver.

1. **Chapter 9** — five pages, two figures, buildable now, best argument in the
   book. Establishes voice on material that rewards it. **Done** — see
   `book/src/introduction/09-end-of-series.md`.
2. **Chapters 4–8** (Part II) — buildable except B-12. The custom filter figures
   are real work and double as verification artifacts for the native engine.
   **Done** — see `book/src/introduction/04-x11-by-hand.md` through
   `08-extreme-values-modes.md`. B-12 shipped as a labelled synthetic
   schematic (see that chapter's own note) since no near-zero dataset
   exists yet.
3. **Chapters 16–20** (Part V), all five chapters — no longer blocked; Part
   V's own §0 finding (the airline fixture already fails several detailed
   diagnostics) means the designed failing dataset was never actually needed.
   **Done** — see `book/src/introduction/16-why-so-many-diagnostics.md`
   through `20-stability-revisions.md` and `A-checklist.md`.
4. **Chapters 1–3** (Part I) — after II and V, so the framing reflects what the
   technical chapters established.
5. **Chapters 10–13** — `iip_india` and `componentplot` both shipped; no
   longer blocked.
6. **Chapters 14–15** (Part IV) last.

---

## 7. Handoff strategy

**Not one handoff for all twenty chapters, and not twenty handoffs.**

A single document covering twenty chapters would run to eighty pages and be
written entirely against guesses. Twenty documents would duplicate the shared
decisions — dataset, figure conventions, API boundary — in every one.

**Recommended: this document as the master, plus one handoff per part, written
just-in-time.**

| Handoff | Covers | Write when |
|---|---|---|
| (this) | structure, conventions, spine, prerequisites | now |
| Part II | Ch 4–8 | before Ch 4 |
| Part III | Ch 9–13 | before Ch 9 |
| Part V | Ch 16–20 | before Ch 16 |
| Part I | Ch 1–3 | after II and V |
| Part IV | Ch 14–15 | last |

Five part handoffs of roughly 10–15 pages each. Each carries section outlines,
figure specifications, the dataset assignment, available verified numbers, and
the API boundary for its chapters.

**Just-in-time matters more than the granularity.** Writing all five now repeats
the mistake the W.5 rewrite exposed: designing against recollection instead of
against what is actually there. The Part I handoff written after Part II exists
will be materially better, because the framing will describe chapters that have
been written rather than chapters that are imagined.

Since Chapter 9 comes first in the writing order and sits in Part III, its
handoff is the one to write next — or, if that feels heavy for a single chapter,
write Chapter 9 directly from this document and let the Part III handoff follow.

---

## 8. One remaining deliverable

The docs tree is Home, Getting Started, Introduction, API Reference. **Home
already exists** (`docs/src/index.md`) and needs no rewrite — it already
covers what the package is, the single-call example, and the bundled binary.
It currently links only to Getting Started and API Reference; add the third
link to Introduction once this book has at least one part published, and
leave the rest of the page alone.

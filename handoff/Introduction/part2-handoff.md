# Handoff: Introduction, Part II — The X-11 Method (Chapters 4–8)

~21 pages, 13 figures, `airline` throughout except one figure.

**Status: done.** See `book/src/introduction/04-x11-by-hand.md` through
`08-extreme-values-modes.md`, `book/examples/derivations.jl`, `ch04.jl`,
`ch06.jl`, and `test/test_book_examples.jl`'s "Chapter 4"/"Chapter 5"/
"Chapter 6" testsets. Real bugs caught and fixed during writing: Henderson-9's
closed-form denominator (summed to 1.75, not 1 -- fixed by normalising the
numerator by its own sum instead) and the toy X-11's convergence step
(dividing the running `sa` by the trend each pass instead of the original
`y`, which oscillates instead of converging). B-12 shipped as a labelled
synthetic schematic, not real data -- no near-zero dataset exists yet.

**Master:** `introduction-design.md`
**Precedes:** written after Chapter 9, which is already drafted from its own handoff

---

## 0. Why this part is different from the others

Part II does double duty. It is the reader's explanation of X-11, and it is
**the specification for SA Part 2, the native Julia engine.**

The custom figures here — Henderson weights, gain functions, asymmetric end
filters — cannot be drawn without computing those filters in Julia. That is the
same derivation work the native engine requires. Draw them once and they serve
as both illustration and verification artifact.

Two consequences for how this part gets written:

**Verify every filter against the binary.** A figure showing Henderson weights
that disagree with what X-13 actually applies is worse than no figure, because
it will be trusted. Where a computed filter can be checked against `.udg` or a
saved table, check it and record the result.

**Keep the derivation code out of the package.** It belongs in
`book/examples/`, not in `src/`. When the native engine lands it will have its
own tested implementation, and two competing versions would be worse than one.

---

## 1. Chapters

| Ch | Title | pp | Figures |
|---|---|---|---|
| 4 | X-11 by Hand | 5 | B-1, B-2, B-3 |
| 5 | Trend Filters | 5 | B-4, B-5, B-8 |
| 6 | Seasonal Filters | 5 | B-6, B-7, B-13 |
| 7 | The B, C and D Tables | 3 | B-11 |
| 8 | Extreme Values and Decomposition Modes | 3 | B-9, B-10, B-12 |

**Dataset: `airline` throughout**, except B-12 which needs the near-zero series
(prerequisite, §7). Airline's lack of calendar effects and outliers is exactly
why Part II can stay clean — complications arrive in Part III.

### Verified numbers available

From the committed `auto_test.udg` fixture, usable directly:

| Value | Key | Chapter |
|---|---|---|
| Trend filter: 9-term Henderson | `finaltrendma: 9` | 5 |
| Seasonal filter: 3×3, chosen by MSR | `sfmsr: 3x3`, `seasonalma: MSR` | 6 |
| Decomposition mode: multiplicative | `finmode: multiplicative` | 8 |

Note the fixture spec includes `outlier` and `aictest`, which this part's
examples will not. **Confirm these three still hold under a plain
`x13(dataset("airline"))` before quoting them**, since filter selection depends
on the irregular and the irregular depends on what was pre-adjusted.

---

## 2. Chapter 4 — X-11 by Hand

### What it must establish

That X-11 is comprehensible. A reader who finishes this chapter should be able
to describe the algorithm to someone else.

### Outline

| § | pp | Content |
|---|---|---|
| 4.1 | 1 | The idea in four steps, in words |
| 4.2 | 1.5 | Implementing it — **Figure B-1, B-2** |
| 4.3 | 1 | Iterating — **Figure B-3** |
| 4.4 | 1.5 | The reveal, and what the real thing adds |

**4.1.** Estimate the trend by moving average. Divide it out. Average what
remains by calendar month to get the seasonal pattern. Divide that out too.
Four sentences, no code yet.

**4.2.** The same thing in about fifteen lines of Julia. Figure B-1 shows the
centred 12-term average tracking through the seasonal swing; B-2 shows the
detrended values scattered by calendar month, which is the first time a reader
sees SI ratios and should be labelled as such.

**4.3.** Run it three times, plot the seasonal factors after each pass (B-3),
show them converging. Explain why iterating helps at all: a better trend gives
better SI ratios, which give a better seasonal, which gives a better trend.

**4.4 is the payoff.** This *is* X-11. Then, honestly, what the toy leaves out:

| Toy | Real X-11 | Chapter |
|---|---|---|
| simple moving average | Henderson filter, length chosen from the data | 5 |
| mean by calendar month | a seasonal filter chosen from a family | 6 |
| three identical passes | B, C, D passes doing different jobs | 7 |
| no outlier handling | sigma limits and replacement | 8 |
| multiplicative only | four decomposition modes | 8 |
| no forecast extension | regARIMA front end | 9 (already written) |

**That table is the syllabus for the rest of the book**, and presenting it as
"here is what we skipped" is better than presenting it as a plan.

### Constraints

The toy stays **inline in the text, clearly labelled a toy, not exported and not
in `src/`**. State plainly that it is pedagogical and that the package uses the
Census binary. A naive X-11 in the documentation of a package whose Part 2 goal
is a correct native engine will otherwise cause confusion.

Do not compare the toy's output to `x13()`'s numerically. It will differ, the
differences are the subject of chapters 5–8, and a side-by-side invites the
reader to conclude the toy is broken.

---

## 3. Chapter 5 — Trend Filters

### What it must establish

Why a plain moving average is not good enough, what Henderson's filter optimises,
and that the filter has ends — which is Chapter 9's problem, already met.

### Outline

| § | pp | Content |
|---|---|---|
| 5.1 | 1 | Moving averages: the 2×12 construction for even periods |
| 5.2 | 1.5 | Henderson's criterion — **Figure B-4** |
| 5.3 | 1 | Length matters — **Figure B-5** |
| 5.4 | 0.75 | Choosing the length automatically |
| 5.5 | 0.75 | The ends — **Figure B-8** |

**5.1.** A 12-term average of monthly data is not centred on an observation, so
X-11 averages two of them. Worth one clear paragraph: this trips people up and
the explanation is short.

**5.2.** Henderson filters minimise the roughness of the smoothed output —
specifically the sum of squared third differences — subject to reproducing a
cubic polynomial exactly. State that; do not derive it. **Verify the criterion
statement against Ladiray & Quenneville before writing**, since it is easy to
state slightly wrong.

Figure B-4 is the 13-term weights as a bar chart. Two features to point out: the
weights are symmetric, and the outer ones go **negative**, which is why a
Henderson filter can sharpen a turning point rather than merely blurring it.

**5.3.** The 9, 13 and 23-term filters on the same data. Longer means smoother
and slower to react.

**5.4.** X-11 picks the length from the I/C ratio — the size of the irregular
relative to the trend movement. For `airline`, `finaltrendma` reports 9. Read it
back with [`filters`](@ref) rather than asserting it.

**5.5.** Half a page, because Chapter 9 has already made the argument. Show the
asymmetric weights (B-8), note that they are what forecast extension avoids
using, and point back.

### Boxes

**Under the hood** — the Henderson derivation. Becomes a full section in the
academic book; write it as a compressed version of that.

**Gotcha** — a longer trend filter is not "better". It trades responsiveness for
smoothness, and at a turning point that trade goes the wrong way.

---

## 4. Chapter 6 — Seasonal Filters

### What it must establish

That the seasonal filter operates on a different object from the trend filter —
the cycle-subseries, not the series — and that "3×5" is a description of the
filter's construction rather than an arbitrary label.

### Outline

| § | pp | Content |
|---|---|---|
| 6.1 | 1 | Filtering across years, not along the series |
| 6.2 | 1 | What 3×3, 3×5, 3×9 mean |
| 6.3 | 1.5 | What each one does — **Figures B-6, B-7** |
| 6.4 | 1.5 | The moving seasonality ratio — **Figure B-13** |

**6.1 is the conceptual hurdle** and deserves the first page on its own. The
seasonal filter smooths *all the Januaries*, then all the Februaries, and so on.
It moves across years at a fixed point in the calendar, not along the calendar.
A reader who misses this will misread everything else in the chapter.

This is also where [`monthplot`](@ref)'s layout finally makes sense, so
forward-reference figure B-9 in Chapter 8.

**6.2.** A 3×5 filter is a 3-term moving average of a 5-term moving average, so
it spans seven years. Give the span of each family member; the name stops being
opaque immediately.

**6.3.** B-6 applies three filters to the same SI ratios: shorter tracks a
moving seasonal, longer is more stable. B-7 shows the gain functions, which is
where a reader learns to *see* what a filter does rather than infer it from
output.

**6.4.** The MSR compares year-to-year movement in the seasonal against the
irregular, and X-11 selects a filter from it. For `airline`, `sfmsr` reports
`3x3` chosen by `MSR`.

**Do not state the MSR threshold values from recall.** X-11's selection rule has
specific cutoffs with an "uncertain" band that triggers a second pass. Take them
from the Census manual's X-11 spec documentation or Ladiray & Quenneville, and
mark them verified when you do.

---

## 5. Chapter 7 — The B, C and D Tables

### What it must establish

That the table names are learnable rather than arbitrary, and why there are
three passes.

### Outline

| § | pp | Content |
|---|---|---|
| 7.1 | 1 | Why iterate three times |
| 7.2 | 1.5 | The naming scheme — **Figure B-11** |
| 7.3 | 0.5 | Where to look things up |

**7.1.** Each pass produces a better estimate of the components, which lets the
next pass detect extreme values more accurately, which improves the estimate
again. B is crude, C uses B's extreme-value information, D is final. Chapter 4's
convergence figure already showed the principle; this names it.

**7.2 carries the chapter.** The mnemonic worth giving a reader:

> Within the core block, the second digit means the same thing in every pass.
> **10** is seasonal factors, **11** is the seasonally adjusted series, **12**
> is the trend-cycle, **13** is the irregular. So B10, C10 and D10 are the same
> quantity at three stages of refinement, and D10 is the one you use.

That single sentence makes 12 table names learnable instead of memorised.

**Verify the mnemonic's range before writing it.** It holds for the 10–13 block;
it does not extend to every table in every pass, and the chapter should say how
far it goes rather than implying more than is true. Check against
`handoff/x13-saveable-tables.md`.

Then map to `X13Result` fields once, and use the table names from then on —
which is what the rest of the book and the whole profession do.

**7.3.** Point at the reference file for the other 277 tables and at
[`series`](@ref) for fetching them. Half a page.

### Box

**Gotcha** — the save keyword is not the table number. The holiday factor series
is table A7 but you request it with `regression.holiday` and it lands in `.hol`.
Only `a10` and `a13` are spelled as their numbers. This is a real trap that has
already caused one wrong gap analysis in this project.

---

## 6. Chapter 8 — Extreme Values and Decomposition Modes

### What it must establish

That X-11 downweights unusual observations rather than deleting them, and that
the decomposition mode is a modelling choice with consequences.

### Outline

| § | pp | Content |
|---|---|---|
| 8.1 | 1.5 | Sigma limits and graduated weights — **Figures B-9, B-10** |
| 8.2 | 1.5 | Four modes — **Figure B-12** |

**8.1.** An unusual month distorts the seasonal factor for that calendar month
in *every* year, because the factor is estimated from all of them. X-11's
response is to measure the irregular's spread, flag values beyond a lower sigma
limit, and give them a **graduated weight** that falls to zero at an upper
limit. Values are replaced by an average of neighbouring years, not dropped.

Figure B-9 is [`monthplot`](@ref) — SI ratios against the fitted seasonal factor,
which is the single most informative X-11 chart and the payoff of Chapter 6.
B-10 draws the irregular with the sigma limits marked.

**Verify the default sigma limits against the binary** rather than quoting the
commonly cited pair from memory. They are settable, and the default should be
read back rather than asserted.

Distinguish clearly from Chapter 12's outliers: X-11's extreme-value replacement
is internal to the filter and leaves no regressor behind, whereas a regARIMA
outlier is estimated and reported. Both exist, they do different jobs, and
conflating them is a common confusion.

**8.2.** Multiplicative, additive, pseudo-additive, log-additive. The decision
rule in one line each. Pseudo-additive earns its paragraph: it exists for series
where the level approaches zero, so a multiplicative factor would explode and an
additive one would be wrong in the interior.

Figure B-12 needs the near-zero dataset. On `airline` this comparison is
meaningless, since the series never approaches zero and is emphatically
multiplicative.

### Box

**In official statistics** — mode choice is usually fixed by convention within a
statistical series and not re-tested each period, because a mode switch makes
the published history incomparable.

---

## 7. Prerequisites

| Need | Blocks | Status |
|---|---|---|
| Near-zero / zero-crossing dataset | Figure B-12 only | **outstanding** |
| Henderson weight computation | B-4, B-5, B-8 | write in `book/examples/` |
| Gain function computation | B-7 | write in `book/examples/` |
| MSR thresholds | §6.4 prose | verify from manual |
| Default sigma limits | §8.1 prose | verify from binary |
| Henderson criterion statement | §5.2 prose | verify from L&Q |

Only the first blocks a figure. The rest are facts to confirm rather than
capabilities to build, and Chapter 8 can be written with B-12 pending.

**If the near-zero dataset does not arrive in time**, §8.2 can run on prose plus
a schematic rather than real data, with the figure added later. Say so in the
caption rather than quietly shipping four pages that promise a comparison the
book does not make.

---

## 8. Figures needing derivation code

These four cannot be produced by calling the package. They need filters computed
in Julia, in `book/examples/ch05.jl` and `ch06.jl`.

| ID | Needs |
|---|---|
| B-4 | Henderson weights, 13-term |
| B-5 | Henderson weights, 9 / 13 / 23-term, applied |
| B-7 | Gain functions of the seasonal filter family |
| B-8 | Musgrave asymmetric end-filter weights |

**Verify each against the binary where possible.** The trend filter length X-13
selected is readable from `filters(res)`, so at minimum confirm that applying
your computed 9-term Henderson to the SA series reproduces D12 closely. If it
does not, the weights are wrong and the figure would mislead.

This check is worth doing carefully. It is the first real cross-validation of a
filter implementation in this project and it is the foundation the native engine
will build on.

---

## 9. Verification checklist

| Item | Chapter | Status |
|---|---|---|
| Toy X-11 runs and converges in 3 passes | 4 | generate |
| `filters(res)` under plain `x13(dataset("airline"))` | 5, 6, 8 | **generate — may differ from the fixture** |
| Henderson weights match a published table | 5 | verify |
| Computed 9-term Henderson reproduces D12 | 5 | **generate — validates the derivation** |
| Henderson criterion statement | 5 | verify from L&Q |
| MSR threshold values | 6 | verify from manual |
| Mnemonic's range across the table families | 7 | verify from reference file |
| Default sigma limits | 8 | verify from binary |
| All 13 figures | all | build |

The second row matters more than it looks. The fixture's `finaltrendma: 9` and
`sfmsr: 3x3` come from a run with outlier detection and calendar regressors on.
Part II's examples use neither, and filter selection depends on the irregular.
**Generate the plain-spec values before quoting any of them.**

---

## 10. Open questions

1. **Does the plain-spec run give the same filters as the fixture?** If not,
   chapters 5, 6 and 8 quote different numbers from Getting Started chapter 4,
   which is fine but must be deliberate and consistent.
2. **How much of the toy X-11 should appear as code versus prose?** Fifteen
   lines is readable inline; thirty is not. If it grows past twenty, move the
   body to `book/examples/ch04.jl` and show only the core loop.
3. **Should Chapter 4's toy be multiplicative-only?** Yes, almost certainly —
   handling both modes doubles the code for no pedagogical gain, and Chapter 8
   covers modes properly.
4. **Does `filters` report the trend filter length per-period or once?** Affects
   how §5.4 is phrased. Check the return shape.
5. **Is 21 pages right for Part II?** It is the longest part and the most
   technical. If it runs long, Chapter 7 compresses most safely — it is
   reference-shaped and much of it is a pointer to the table reference file.

# Handoff: Introduction, Part IV — SEATS (Chapters 14–15)

~9 pages, 6 figures. The last part written, and the one with the widest gap
between what the reader needs and what the package can demonstrate.

**Master:** `introduction-design.md`
**Written after:** everything else

---

## 0. The scope question, answered

This has been deferred through every previous design document. Decide it now.

The package exposes `seats = true` and little else. No `noadmiss`, no `rmod`, no
SEATS-specific diagnostics beyond what applies to any adjusted series.
[`mstats`](@ref) returns `nothing` for a SEATS run, because the M statistics are
X-11 constructs.

Two readings were on the table: cut Part IV to seven pages and admit the
treatment is lighter, or grow the package first.

**Recommendation: keep the nine pages, and shift the balance.**

The book is an explanation of X-13ARIMA-SEATS, not a tour of what this package
happens to wrap. A reader who finishes Part II understanding X-11 and then gets
four thin pages on SEATS has been told, implicitly, that SEATS is a footnote. It
is not — it is what most of Europe uses.

So: **the concepts get their full space; the package-driven examples shrink.**
Chapter 14 is largely explanation with two derived figures. Chapter 15 is where
the package does the work, and it can do more than expected — see §3.

One consequence worth accepting rather than hiding: writing this part will
surface exactly which SEATS capabilities are missing. That is useful output, the
same way Part II's filter figures double as verification artifacts for the native
engine. **Record the gaps as they appear**; they are the seed of a future
handoff.

---

## 1. Chapters

| Ch | Title | pp | Figures |
|---|---|---|---|
| 14 | Decomposing a Model | 5 | D-1, D-2, D-3 |
| 15 | X-11 and SEATS Compared | 4 | D-4, D-5, D-6 |

`airline` throughout, plus the divergent series for D-6 if it exists.

---

## 2. Chapter 14 — Decomposing a Model

### What it must establish

That SEATS derives its filter from the data's own fitted model rather than
choosing one from a menu, and that this is a genuinely different idea rather
than a variation on X-11.

### Outline

| § | pp | Content |
|---|---|---|
| 14.1 | 1.25 | A filter you did not choose — **Figure D-1** |
| 14.2 | 1.5 | Splitting the model — **Figure D-2** |
| 14.3 | 1.25 | The filter that falls out — **Figure D-3** |
| 14.4 | 1 | When it does not work |

**14.1 is the whole contrast and should be stated sharply.**

Part II showed X-11 selecting a seasonal filter from a family — 3×3, 3×5, 3×9 —
using the moving seasonality ratio. The family is fixed in advance; the data
picks a member.

SEATS does not have a family. It fits an ARIMA model to the series, decomposes
*that model* into component models, and the optimal filter follows from the
decomposition. Two series with different dynamics get genuinely different
filters, not two members of the same list.

Frame it as the answer to an objection a thoughtful reader of Part II will
already have formed: *where did those filter families come from, and why those?*
X-11's answer is decades of practice. SEATS' answer is the model.

**14.2.** The mechanism, without derivation. An ARIMA model implies an
autocovariance structure, and equivalently a spectrum. That spectrum has power
concentrated at seasonal frequencies and power spread elsewhere. The
decomposition assigns each part to a component, with each component itself an
ARIMA model.

Figure D-2 is that split drawn: the model's spectrum, and the trend, seasonal
and irregular pieces it is divided into. This is the figure that makes the
chapter comprehensible and it needs care.

**Under the hood** box: partial fractions on the autocovariance generating
function, one paragraph, pointing at Dagum & Bianconcini. This box becomes a
full section in the academic book.

**14.3.** Given component models, the minimum-mean-squared-error filter follows
— the Wiener-Kolmogorov filter. Figure D-3 compares its weights against X-11's
implied filter for the same series, which is the moment a reader sees that these
are two ways of doing the same job rather than two unrelated procedures.

**14.4 is more important than its length suggests.** The decomposition is not
always possible. Some fitted models admit no valid split into components with
non-negative spectra, and SEATS then either fails or replaces the model with a
nearby one that does decompose. That is what `noadmiss` controls, and it has no
X-11 analogue at all.

Say plainly that this is a real limitation of the model-based approach, not a
software quirk. X-11 always produces an answer; SEATS sometimes cannot.

**Verify the `noadmiss` default and its exact behaviour** before writing. R's
`seasonal` sets `seats.noadmiss = "yes"` in its base specification, which
suggests the binary's own default differs — worth knowing which.

---

## 3. Chapter 15 — X-11 and SEATS Compared

### The realisation that gives this chapter a spine

The obvious way to compare two adjustments is the diagnostic scorecard. **That
does not work here**, because M1–M11 and Q are X-11 constructs and
[`mstats`](@ref) returns `nothing` for a SEATS run.

That looks like an obstacle and is actually the chapter's most interesting
point: **there is no common quality score.** The field's most-quoted summary
statistic cannot arbitrate between the field's two methods.

What *does* apply to both:

| Diagnostic | Works for SEATS | Why |
|---|---|---|
| [`qs`](@ref) | yes | tests any series for seasonal autocorrelation |
| [`spectral_peaks`](@ref) | yes | computed from the output series |
| [`seasonality_tests`](@ref) | yes | F-tests on the adjusted series |
| [`residual_diagnostics`](@ref) | yes | regARIMA is shared by both engines |
| [`mstats`](@ref) | **no** | X-11 construct |
| [`filters`](@ref) | **no** | SEATS has no filter family |

So the comparison is made on residual seasonality and spectral evidence, not on
Q. That is a real methodological constraint and it should be presented as one.

### Outline

| § | pp | Content |
|---|---|---|
| 15.1 | 1.5 | Same series, both engines — **Figures D-4, D-5** |
| 15.2 | 1.25 | Judging them without a common score |
| 15.3 | 0.75 | Where they diverge — **Figure D-6** |
| 15.4 | 0.5 | Which should you use |

**15.1.** `airline` through both engines. D-4 overlays the adjusted series; D-5
shows their difference **at an honest scale**. Resist the temptation to plot the
difference on an axis that makes it look dramatic. If the two agree closely, the
figure should show that they agree closely — that is the finding.

Note that the components arrive in different tables: X-11's D10–D13 against
SEATS' S10–S18. Both are in `_KNOWN_TABLES`, reachable through
[`series`](@ref).

**15.2.** Run QS, the F-tests and the spectral peaks on both outputs and compare.
Then the honest observation from §3: there is no single number.

This connects directly to Part V. Chapter 16 argued the diagnostic battery exists
because the decomposition is not identified. Here is the consequence in its
sharpest form — two methods, two different conventions for an unidentified split,
and no test that adjudicates.

**15.3.** A series where the two genuinely disagree. **Needs the divergent
dataset**, which has to be found rather than designed. Run both engines over
everything shipped and see whether one of them supplies the case; if not, this
section shrinks to a paragraph noting that divergence is uncommon and describing
when it arises.

**15.4.** The verdict, given plainly:

- Most of the time the two agree closely enough that the choice does not matter.
- SEATS is preferred where the ARIMA model is a good description and a coherent
  statistical framework is wanted.
- X-11 is more robust when the model fits poorly, and it always produces an
  answer.
- Institutional convention usually decides in practice, and there is nothing
  wrong with that.

**In official statistics** box: European offices largely adopted TRAMO/SEATS
while the US kept X-11, and JDemetra+ and X-13 reflect that split. It is
convention and tooling as much as statistics.

---

## 4. Figures

| ID | Kind | Content | Status |
|---|---|---|---|
| D-1 | diagram | Model → components → filter | draw |
| D-2 | derived | Model spectrum split into components | **needs derivation code** |
| D-3 | derived | WK filter weights vs X-11's implied filter | **needs derivation code** |
| D-4 | custom | Both adjusted series overlaid | buildable |
| D-5 | custom | Their difference, honest scale | buildable |
| D-6 | custom | A divergent case | needs a divergent series |

D-2 and D-3 are the same kind of work as Part II's filter figures: computed in
Julia in `book/examples/`, not produced by calling the package. They are harder
than Part II's, because the component models have to be derived from the fitted
ARIMA rather than taken from a published weight table.

**If D-2 and D-3 prove too costly**, both can be replaced by schematics that
convey the shape without claiming numerical accuracy — clearly labelled as
schematic. That is a legitimate choice for an introduction, and better than
shipping a computed figure that has not been verified against anything.

---

## 5. Verification checklist

| Item | Ch | Status |
|---|---|---|
| `x13(dataset("airline"); seats = true)` runs | 14, 15 | generate |
| Which `X13Result` fields populate for a SEATS run | 15 | **verify — may differ from X-11** |
| S10–S18 reachable via `series` | 15 | verify |
| `mstats` returns `nothing` for SEATS | 15 | **verify — the chapter's spine** |
| `qs`, `spectral_peaks`, `seasonality_tests` work on SEATS output | 15 | **verify** |
| SEATS-specific udg keys, if any | 14, 15 | **generate and record** |
| `noadmiss` default and behaviour | 14 | verify |
| Does any shipped series diverge between engines? | 15 | **generate — decides §15.3** |
| WK filter derivation | 14 | derive, or use a schematic |

The second and fifth rows are load-bearing. If `X13Result`'s component fields do
not populate for a SEATS run, every example in Chapter 15 changes shape. If the
common diagnostics do not work on SEATS output, §15.2's argument collapses.
**Check both before drafting.**

---

## 6. Gaps to record while writing

Not book content. A note for the writer, feeding a later package handoff.

The SEATS spec has options the package does not surface: `noadmiss`, `rmod`,
`maxit`, and the choice between finite and semi-infinite filters. There are
SEATS-specific diagnostics in the binary's output that nothing reads back.
Chapter 14 will make it obvious which of these a user would actually want.

**Write them down as they come up.** By the end of Part IV there will be a
short, concrete, motivated list — which is a far better basis for a package
handoff than guessing at the surface in advance. This is the same pattern that
produced the W.7 list.

---

## 7. Open questions

1. **Do the component fields populate for a SEATS run?** Blocks Chapter 15's
   examples. Check first.
2. **Are D-2 and D-3 worth deriving, or should they be schematics?** Depends on
   how much work the component-model derivation turns out to be. Decide after
   one attempt, not in advance.
3. **Does a divergent series exist among what is shipped?** Decides whether
   §15.3 is a section or a paragraph. One batch run answers it.
4. **Should Part IV say what the package does not expose?** My view: no, not in
   the book. A reader wants to understand SEATS, not to audit the wrapper. Keep
   the gap list in §6 and out of the prose.
5. **Is Part IV still the right place to end the book?** Chapter 15 closes on
   "which should you use", which is a reasonable last note. The alternative is
   moving Part V after it so the book ends on the checklist. **Recommend keeping
   the current order** — diagnostics apply to both engines, so they belong after
   both have been introduced, and the checklist appendix already gives the reader
   a practical closing artifact.

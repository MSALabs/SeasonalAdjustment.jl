# Handoff: Introduction, Chapter 9 — The End-of-Series Problem

First chapter to be written. ~5 pages, 2 figures, `airline` only, fully
unblocked by W.7/W.8.

**Master:** `introduction-design.md`
**Format note:** this is the first chapter handoff. If the shape works, the
remaining chapters get part-level handoffs on the same pattern; if it does not,
adjust before writing four more.

---

## 0. Why this chapter goes first

It contains the best argument in the book, it needs nothing that does not exist
today, and it is the chapter that makes the rest of Part III inevitable.

Without it, a reader meeting regARIMA asks a reasonable question: why is there a
*forecasting* model bolted onto the front of a *smoothing* procedure? Every
other treatment answers that with "for forecast extension", which restates the
mechanism rather than the motivation. This chapter answers it with two pictures.

Writing it first also establishes voice on material that rewards care, rather
than on an introduction that would have to promise things not yet written.

---

## 1. What the chapter must establish

In order, and each one earns its space:

1. **The months a reader cares about are the ones X-11 estimates worst.** Not a
   flaw to be apologised for — a structural consequence of using symmetric
   filters on a series that has an end.
2. **Why:** a symmetric filter needs observations on both sides. At the end of
   the series they do not exist, so X-11 substitutes asymmetric filters that use
   only what is available.
3. **The cost is revision.** Each month's estimate changes as later data
   arrives, and the change is largest for the most recent estimates.
4. **Dagum's fix:** forecast the series forward, then run the *symmetric* filter
   over the extended data. The asymmetric filter is never used at all.
5. **It works, measurably.** Not "it should help" — a number.
6. **Therefore regARIMA.** The forecasting model exists to serve the filter.
   Everything in chapters 10–13 is refinement of that model.

The chapter should end with the reader wanting Chapter 10, not merely willing to
read it.

---

## 2. Section outline

| § | Title | pp | Content |
|---|---|---|---|
| 9.1 | The months that matter most | 1 | The problem stated before any mechanism |
| 9.2 | Why the ends are different | 1 | Symmetric vs asymmetric; callback to Ch 5 |
| 9.3 | Watching a series get revised | 1.5 | **Figure C-1** |
| 9.4 | Dagum's fix | 0.75 | Forecast extension, X-11-ARIMA, 1980 |
| 9.5 | The same experiment again | 1 | **Figure C-2** + the number |
| 9.6 | What this means in practice | 0.75 | Concurrent adjustment, revision policy |

**9.1** opens with the practitioner's situation, not the algorithm. A statistical
office publishes an adjusted figure for last month; next month it changes. Why?

**9.2** is short and leans on Chapter 5, which already introduced the Henderson
filter and its asymmetric end variants. Do not re-derive. One or two sentences
plus a pointer back is enough, and figure B-8 has already shown the weights.

**9.3** is the chapter's centre.

**9.4** the historical turn. Dagum at Statistics Canada, X-11-ARIMA, 1980. The
idea in one sentence: if the trouble is that the future has not arrived, forecast
it.

**9.5** repeats 9.3's experiment with extension on, and delivers the quantitative
result from §4 below.

**9.6** concurrent versus forward-factor adjustment, and why revision policy is
a published policy at statistical offices rather than an implementation detail.

---

## 3. Figure specifications

Both are custom (written with Plots directly in `make_figures.jl`, not package
recipes). They are the two most important custom figures in the book and deserve
iteration.

### Common construction

```
dataset:   airline  (144 obs, 1949-01 .. 1960-12)
vintages:  series truncated at 1957-12, 1958-06, 1958-12,
                              1959-06, 1959-12, 1960-06, 1960-12
           (7 vintages, 6-month steps, shortest = 108 obs = 9 years)
spec:      transform = :log  (FIXED -- see the Gotcha in §5)
           automdl = true
           outlier = false
plot:      x-axis 1956-01 .. 1960-12
           one line per vintage, each ending at its own endpoint
           final vintage drawn heavier as "the answer"
```

Shortest vintage is 9 years, comfortably past [`validate!`](@ref)'s three-year
minimum, so no vintage should fail.

### Figure C-1 — without forecast extension

```julia
spec_args = Dict("forecast.maxlead" => "0")
```

**Expected reading.** The lines coincide through the interior and separate as
each approaches its own endpoint. The fan shape is the point: the same month has
several different "official" values depending on when you asked.

Annotate one month explicitly — pick one where the spread is widest — with the
range of estimates it received across vintages.

### Figure C-2 — with forecast extension

Identical, with extension on. Lines should be visibly tighter near the ends.

**Verify what the default actually is.** Do not assume. Run both and read
`nfcst` back from `.udg` to confirm how many forecast periods were used in each
case:

```julia
udg(res, "nfcst")
```

If the no-extension case does not report zero, the `spec_args` above did not take
effect and both figures show the same thing.

### Presentation

Identical axes, identical scale, identical colours across both figures. The
reader compares them by flipping between two pages, and any cosmetic difference
will be misread as a result.

---

## 4. The quantitative result

A picture invites "how much?", and answering it is what separates this chapter
from every other treatment of the same idea.

For each month *t* in a window covered by at least two vintages:

- **concurrent estimate** — from the earliest vintage whose data ends at *t*
- **final estimate** — from the full-sample vintage
- **revision** — `(final − concurrent) / concurrent`

Report **mean absolute revision** in percent, with and without extension:

```
without forecast extension:   ⟨generate⟩ %
with forecast extension:      ⟨generate⟩ %
reduction:                    ⟨generate⟩ %
```

Also report the **largest single revision** in each case, which is often the more
persuasive number for a practitioner.

**Do not predict the direction or magnitude in the prose before generating it.**
The literature reports substantial reductions, but the size on this particular
series with this particular vintage schedule is an empirical question. Write the
sentence after seeing the number.

If the reduction turns out to be small, that is publishable too and the chapter
should say so honestly. A modest number with an explanation is better than a
dramatic one that does not reproduce.

---

## 5. Boxes

### Gotcha — fix the transform across vintages

**This is the most important box in the chapter and it is a real bug, not a
hypothetical.**

If `transform = :auto` is left on, each vintage re-runs the log test on its own
data. A shorter vintage can select `:none` where the full sample selects `:log`.
Multiplicative seasonal factors sit near 1.0; additive ones sit in raw level
units. The resulting "revision" is then a units mismatch reported as
instability, and it will be large and meaningless.

The reference Python pipeline this package was validated against records exactly
this as a bug found and fixed during development. Pin `transform = :log` in both
figures and say why in the box.

The same applies to any comparison across differently-sized samples: ablation
studies, split-half stability checks, sliding spans. State the general rule.

### Under the hood — the asymmetric filters

Where Musgrave's asymmetric end filters come from, and the criterion they
minimise. Three or four sentences, pointing at Ladiray & Quenneville. **This box
becomes a full section in the academic book** — write it as a compressed version
of that section rather than as a footnote.

### In official statistics — revision policy

Concurrent adjustment (re-estimate everything each period) versus forward-factor
projection (fix factors for a year ahead). Why offices publish a revision policy.
Reference the ESS Guidelines. Half a page at most.

---

## 6. API boundary

**Do not** document `spec_args`, `maxlead`, or `transform` keyword values. Name
them, link them, move on.

**Do** reference `udg(res, "nfcst")` as the way to check what happened, since
that is an interpretive point rather than a signature.

**Assume** Getting Started chapter 4 has been read, so `transform`, `automdl`
and `static` need no introduction.

**Forward-reference** Chapter 13 for forecast accuracy and prediction intervals.
This chapter uses forecasts as a means; Chapter 13 treats them as an end.

**Backward-reference** Chapter 5 for the filters themselves and Chapter 7 for
where in the B/C/D sequence the extension is applied.

---

## 7. Example script

`book/examples/ch09.jl`, called by both `make_figures.jl` and
`test/test_book_examples.jl`.

```julia
# Returns everything both figures and the prose need, computed once.
function ch09_vintages(; extend::Bool)
    d = dataset("airline")
    ends = [(1957,12), (1958,6), (1958,12), (1959,6),
            (1959,12), (1960,6), (1960,12)]
    map(ends) do (y, m)
        n = (y - 1949) * 12 + m
        sub = (date = d.date[1:n], value = d.value[1:n])
        res = x13(sub;
                  transform = :log,          # FIXED -- see the Gotcha
                  automdl   = true,
                  spec_args = extend ? Dict{String,String}() :
                                       Dict("forecast.maxlead" => "0"))
        (endpoint = Date(y, m, 1), result = res, nfcst = udg(res, "nfcst"))
    end
end
```

The `nfcst` field is returned deliberately so the test can assert the
experiment's premise rather than trusting it.

---

## 8. Verification checklist

Nothing in this chapter can use the committed `auto_test.udg` fixture — that is
a full-sample run with `outlier` and `aictest` on, and this chapter uses seven
truncated runs with neither. **Every number here is generated.**

| Item | Status |
|---|---|
| All 7 vintages run without error, shortest = 108 obs | generate |
| `nfcst == 0` for every no-extension vintage | generate — **asserts the premise** |
| `nfcst > 0` for every extension vintage | generate |
| `transformfunction(res) === :log` for all 14 runs | generate — **asserts the Gotcha fix** |
| Mean absolute revision, without extension | generate |
| Mean absolute revision, with extension | generate |
| Largest single revision, both cases | generate |
| Figure C-1 | build |
| Figure C-2 | build |

The second and fourth rows are not decoration. If `nfcst` is not zero without
extension, the two figures are the same experiment. If any vintage picks a
different transform, the revisions are a units artefact.

Add both as assertions in `test/test_book_examples.jl`, not merely as things to
eyeball once.

---

## 9. Open questions

1. **Is forecast extension X-13's default when no `forecast` spec is given?** I
   have not verified this and the chapter's framing depends on it. If extension
   is *not* on by default, Figure C-2 needs an explicit `maxlead` and the prose
   changes from "turn it off" to "turn it on". Settle by reading `nfcst` on a
   bare run before drafting.
2. **Seven vintages or five?** Seven gives a fuller fan; five is less cluttered.
   Build both and choose visually.
3. **Six-month or three-month steps?** Three-month steps over two years would
   give a denser fan on a shorter window. Worth trying if seven six-month
   vintages look sparse.
4. **Should the revision measure be on the SA series (D11) or the seasonal
   factors (D10)?** D11 is what gets published and is the honest choice. D10
   revisions are usually larger and would make a more dramatic figure, which is
   a reason to be careful rather than a reason to use them. Recommend D11, and
   mention D10 in a sentence.
5. **Does `x13` accept a truncated `NamedTuple` slice directly**, inferring
   `start` from the sliced dates? The script above assumes so. If not, pass
   `start = (1949, 1)` explicitly, since every vintage begins at the same date.

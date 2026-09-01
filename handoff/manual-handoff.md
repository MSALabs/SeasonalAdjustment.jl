# Handoff: The Manual

Ten pages, ~50 pages of prose, shipped complete before the Introduction.

**Guide:** `manual-writing-guide.md` — read it first for the boundary rules
**Master style:** every section heading answerable as "How do I …"

---

## 0. Two blockers, before anything is written

### 0.1 W.9 (bundled datasets) gates the whole Manual

Every snippet in this Manual should be runnable as written. That means every
snippet needs data, and the only data the package will ship is `dataset()`.

Without W.9, every page either hardcodes a 144-element vector or asks the reader
to supply data — and a snippet a reader cannot run is a snippet that teaches
nothing.

**Land W.9 before writing.** It is the smallest of the outstanding work items
and it unblocks fifty pages.

If it slips, the fallback is a single `_manual_series()` helper defined once on
the Specifications page and referenced everywhere else, which is worse but
survivable. Do not let ten pages each invent their own example data.

### 0.2 The Manual ships before the Introduction

The guide's rule is "link to the Introduction and stop". Those links will not
resolve, and Documenter fails the build on unresolved `@ref`.

**Convention to adopt now:**

```markdown
!!! note "Why this matters"
    A seasonal filter that is too short tracks noise; too long and it misses a
    changing pattern. <!-- MANUAL-CONCEPT: replace with link to Intro ch. 6 -->
```

Rules for these:

- **One or two sentences, never a paragraph.** If it needs more, the task is
  wrong for a Manual page.
- **Always tagged** with the `MANUAL-CONCEPT` comment and the target chapter.
- **Collected in a checklist** at `docs/MANUAL-CONCEPT.md` as they are written,
  so converting them later is mechanical rather than archaeological.

Expect fewer than fifteen across fifty pages. More than that means concepts are
leaking into the Manual.

---

## 1. The redundancy contract

Four sections, six possible overlaps. This is the binding constraint, so make it
explicit.

| Pair | Rule | Concrete example |
|---|---|---|
| Getting Started ↔ Manual | GS walks **one path with defaults**. Manual covers **tasks beyond it**. | GS ch. 4 says "freeze before publishing" in two sentences. Manual 2.8 explains how, and why it is not bit-identical. |
| Introduction ↔ Manual | Intro is **why**. Manual is **how**. | Intro ch. 11 explains why a moving holiday needs a regressor. Manual 2.5 shows how to build one for an unshipped calendar. |
| Manual ↔ API Reference | Manual shows **one worked call per task**. API lists **every keyword and accepted value**. | Manual: `series(res, :d8)`. API: `reeval`, `verbose`, the full table set. |
| Home ↔ any | Home is a landing page. It links; it does not teach. | — |

### The three sentences never to write in the Manual

1. Anything beginning "Seasonal adjustment is…"
2. Any table of a function's accepted keyword values
3. Any sentence that would sit equally well in a docstring

### The duplication that is allowed

**One line of setup per page.** Every page may open with the same
`res = x13(dataset("airline"))` so each stands alone from a search result. That
is not redundancy; that is a page being usable.

---

## 2. Page specifications

Sections are given as the "How do I …" questions they answer. Claude Code writes
the prose; these are the tasks and the traps.

### 2.1 Specifications — 6 pp

**Functions:** `X13Spec`, `render`, `validate!`, `write_spec`, `spec_args`

| Section | Notes |
|---|---|
| When do I need more than `x13()`? | The page's real job. Three tiers: `x13()` keywords → `spec_args` → building an `X13Spec`. |
| How do I set a spec argument with no keyword? | `spec_args`, `"block.argument"` form, value rendering |
| How do I see what specification was generated? | `render` |
| How do I check a specification before running? | `validate!`, its rules, why fast failure matters |
| How do I write a `.spc` file? | `write_spec` |
| How do I change one setting on an existing spec? | copy constructor |

**Traps to include:** a named field beats `spec_args` on collision and warns;
`validate!` cannot check passthrough content; `print`-only keywords (`all`,
`none`, `brief`) are invalid in `save`.

### 2.2 Output and tables — 6 pp

**Functions:** `series`, `parse_table`, `parse_output`, the `X13Result` fields

| Section | Notes |
|---|---|
| Where is the adjusted series? | Four fields, mapped to D10–D13 once |
| How do I get a table that was not saved? | `series`, the automatic re-run and its `@info` |
| How do I get several extra tables? | Vector form, **one** re-run for the union |
| How do I find the right table name? | The reference file, and how to read it |
| How do I read a table file directly? | `parse_table`, `parse_output` |

**Give the save-keyword trap its own section.** Table A7 is requested as
`regression.holiday` and lands in `.hol`; `save = (a7)` does nothing; only `a10`
and `a13` are spelled as their numbers. This is the most likely thing on the
page for a reader to get wrong.

**Check before writing:** `_KNOWN_TABLES` currently holds 17 of 281 tables
(W.7.1 outstanding). Either land W.7.1 first or say plainly which tables are
reachable today.

### 2.3 Many series at once — 5 pp

**Functions:** `generate_specs`, `run_x13_batch`

| Section | Notes |
|---|---|
| How do I build specifications for a panel? | `generate_specs` |
| How do I run them? | `run_x13_batch`, threading |
| How do I handle one series failing? | Do not lose the other 499 |
| How do I collect diagnostics across a panel? | **The most valuable section on the page** |

The last section has no single function behind it. Write a worked loop producing
one row per series — series name, transform, model, Q, M7, QS p-value on the
adjusted series, outlier count, converged — as a `DataFrame` or `NamedTuple`
vector. That table is what a production user actually wants and nothing else in
the documentation supplies it.

### 2.4 Coming from R or Python — 6 pp

**Functions:** `import_spc`, plus translation tables

| Section | Notes |
|---|---|
| How do I translate a `seas()` call? | Side-by-side table |
| How do I translate `x13_arima_analysis()`? | Side-by-side table |
| How do I reuse an existing `.spc`? | `import_spc` |
| Where does this package deliberately differ from R? | **The section that matters most** |

The divergence list, collected in one place for the first time:

- `maxlead` is **not** forced to zero when a user regressor is present. R's
  `seasonal` cannot extend user regressors; this package embeds them inline and
  can. Set `maxlead = 0` explicitly to match R.
- `custom_holiday_regressor` drops a holiday falling on a non-working day. Both
  reference pipelines use a bare month dummy. Output will not match either.
- `static()` reproduces to about six significant figures, not bit-identically.
  Compare with `isapprox`.

Each is in its own docstring already. A user diffing against R needs them
together.

### 2.5 Calendars and regressors — 6 pp

**Functions:** `Calendar`, `TableCalendar`, `INDIA_NSE`, `isbusinessday`,
`isholiday`, `isweekend`, `adjust`, `advance`, `businessdaysbetween`,
`holidaylist`, `trading_day_regressors`, `easter_regressor`,
`custom_holiday_regressor`, `easter_date`

| Section | Notes |
|---|---|
| How do I check whether a date is a trading day? | The BusinessDays-style API |
| How do I build a calendar the package does not ship? | `TableCalendar` from a date list |
| How do I build a holiday regressor from dates? | `custom_holiday_regressor` |
| How do I add trading-day or Easter regressors? | The built-ins |
| How do I do any of this for quarterly data? | `freq = :quarter` throughout |

The second section is the page's reason to exist. The Introduction explains
Diwali; nothing explains how a reader adds Chinese New Year or Eid themselves.

### 2.6 Plots — 4 pp

**Functions:** `plot`, `residplot`, `monthplot`, `spectrumplot`

| Section | Notes |
|---|---|
| How do I plot a result? | |
| How do I show components instead of an overlay? | `panels = :components` |
| How do I plot growth rates? | `transform = :pc` / `:pcy` |
| How do I mark outliers? | |
| Which backend should I use? | **Nothing else answers this** |
| How do I save a figure? | |

Keep it short — docstrings carry the keywords. The backend question is the
page's unique contribution: `RecipesBase` imposes no backend, so the reader must
choose, and nothing tells them how.

### 2.7 Datasets — 3 pp

**Functions:** `dataset`, `datasets`, `dataset_info` — **all blocked on W.9**

| Section | Notes |
|---|---|
| What ships with the package? | `datasets()` |
| How do I load one as a DataFrame or TSFrame? | The sink argument |
| How do I cite one? | `dataset_info` |
| How do I use my own data instead? | **More important than the first three** |

The last section is the one a reader actually needs and the easiest to forget on
a page about bundled data. Cover plain `Vector` plus `start`, and the
`tsvalues`/`tsindex` protocol for custom containers.

### 2.8 Reproducibility and production — 5 pp

**Functions:** `static`

| Section | Notes |
|---|---|
| How do I freeze an automatic model? | `static` |
| Why is a frozen spec not bit-identical? | Estimation converges differently when the model is given rather than searched |
| What should I store with published figures? | The spec, the version, the binary version |
| How often should I re-identify? | Policy, not package behaviour |

Mark the last two clearly as convention, drawing on the ESS Guidelines. A reader
should not mistake editorial advice for API behaviour.

### 2.9 Running X-13 directly — 4 pp

**Functions:** `run_x13`, `X13RunResult`, `open_output`, `x13_binary_path`,
`x13_binary_available`

| Section | Notes |
|---|---|
| How do I run a spec I built by hand? | `run_x13` |
| Where do the output files go? | Temp dir lifetime |
| How do I keep the directory for inspection? | |
| How do I see the binary's warnings? | `X13RunResult` |
| How do I open the full HTML output? | `open_output` |
| How do I check the binary is working? | `x13_binary_available` |

### 2.10 Accessing diagnostics — 5 pp

**Functions:** `udg`, `mstats`, `qs`, `outliers`, `outlier_counts`,
`fivebestmdl`, `seasonality_tests`, `residual_diagnostics`, `spectral_peaks`,
`spectrum_peaks`, `filters`, `transformfunction`, `arima_model`, `select_order`,
StatsAPI methods

| Section | Notes |
|---|---|
| How do I read any diagnostic by name? | `udg`, its type conversion |
| How do I get the M statistics and Q? | `mstats` |
| How do I get QS and the F-tests? | `qs`, `seasonality_tests` |
| How do I get outliers and the model? | `outliers`, `arima_model`, `fivebestmdl` |
| How do I get AIC, BIC, coefficients? | The StatsAPI methods |
| What do these numbers mean? | **Link to Intro ch. 16–20 and stop** |

The last row is the whole boundary. This page is access; the book is meaning.

Note `vcov` currently throws by design and `mstats` returns `nothing` for a
SEATS run — both worth a sentence so neither reads as a failure.

---

## 3. House style

### Page template

```markdown
# Working with specifications

One paragraph: what this page covers, when you need it, and the simpler
alternative if one exists.

## When do I need more than `x13()`?

...

## How do I set a spec argument that has no keyword?

One or two sentences of setup.

​```julia
res = x13(dataset("airline");
          spec_args = Dict("forecast.maxlead" => "12"))
​```

One sentence on what to watch for.
See [`X13Spec`](@ref) for the full keyword list.
```

### Rules

- **Snippets: five to ten lines, runnable as written**, using a bundled dataset
- **One task per section.** Two snippets means two sections
- **End sections with a link, not an explanation**
- **Show output when it is under ten lines**; skip it otherwise
- **Prefer the simplest thing that works** — show `x13()` unless the page is
  about the lower layer
- **No figures.** Figures belong to the Introduction

---

## 4. Testing

Every snippet is extracted into `docs/examples/manual/<page>.jl` and run by
`test/test_manual_examples.jl`, gated on `x13_binary_available()`.

Same pattern as the book: display-only fenced blocks in the Markdown, real
scripts behind them, so code that stops working fails CI even though the docs
never execute.

Add one test asserting the `MANUAL-CONCEPT` checklist in `docs/MANUAL-CONCEPT.md`
matches the tagged comments in the sources, so none is silently lost before the
Introduction ships.

---

## 5. Sequencing

| Step | Why |
|---|---|
| 1. Land W.9 (datasets) | Gates every snippet in the Manual |
| 2. Land W.7.1 (`_KNOWN_TABLES`) | Page 2.2 documents 17 of 281 tables otherwise |
| 3. Write 2.1, 2.2, 2.3, 2.4 | The gaps a tester hits in week one |
| 4. Write 2.5 – 2.8 | |
| 5. Write 2.9, 2.10 | Most overlap with existing material; least urgent |
| 6. Convert `MANUAL-CONCEPT` markers | When the Introduction ships |
| 7. Flatten the API Reference | The Manual now carries discovery |

Steps 1 and 2 are package work, not writing, and both are small.

---

## 6. What would help from you

Four things, in order of how much they unblock:

1. **A decision on W.9 and W.7.1 sequencing.** If both land first, the Manual is
   clean. If not, say which fallback you prefer: a shared `_manual_series()`
   helper, or hardcoded vectors per page.
2. **The batch diagnostics table in 2.3.** Which columns does a production run
   at your scale actually want? You have fitted SARIMA at 30-million-series
   scale; that section should reflect real practice rather than my guess at it.
3. **Any divergence from R I have missed** for 2.4. I have three; you have been
   making these calls for months and there may be more.
4. **Production policy for 2.8.** Re-identification frequency and what to archive
   alongside published figures are conventions, and yours may differ from the
   ESS default.

Nothing else needs you. The rest is mechanical given the specs above.

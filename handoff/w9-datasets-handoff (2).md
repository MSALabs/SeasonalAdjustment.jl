# Handoff: W.9 — Bundled Datasets

For a fresh session with no prior context. Design rationale is in
`dataset-api-design.md` (rev 2); this document is the implementation.

**Two datasets ship with this handoff as real, verified CSV files.** Two more
are outstanding and their blockers are named in §7.

---

## 1. The roster

| Name | Freq | n | Span | Status |
|---|---|---|---|---|
| `airline` | 12 | 144 | 1949-01 .. 1960-12 | **data attached, verified** |
| `appliance` | 12 | 192 | 1972-07 .. 1988-06 | **data attached, verified** |
| `appliance_q` | 4 | 64 | 1972-Q3 .. 1988-Q2 | attached, derived — see §7.1 |
| `iip_india` | 12 | — | — | blocked on licensing, §7.2 |

Total on disk: **12 KB**. All three attached files are `date,value` CSV with an
ISO date and a `Float64` value, one observation per row.

### 1.1 `airline`

Monthly totals of international airline passengers, in thousands. Box and
Jenkins' Series G, and the most recognised series in time series analysis.
Already this package's verification baseline
(`handoff/verification/airline_baseline/`), so book output and test fixtures
agree by construction.

Verified on generation:

```
n = 144   sum = 40363   mean = 280.2986
sha256 = 9312906f56e35f92...
```

The mean matches the canonical AirPassengers value, which is the check that the
transcription is right.

Seasonal shape, monthly means as a ratio to the overall mean:

```
Jan 0.86  Feb 0.84  Mar 0.96  Apr 0.95  May 0.97  Jun 1.11
Jul 1.25  Aug 1.25  Sep 1.08  Oct 0.95  Nov 0.83  Dec 0.93
```

Summer-peaked, trough in November. Strongly multiplicative: the swing grows with
the level, which is why X-13 selects a log transform.

**Provenance.** Box, G.E.P. and Jenkins, G.M. (1976), *Time Series Analysis:
Forecasting and Control*, Series G. Public domain, redistributed for decades,
ships in base R as `AirPassengers`.

### 1.2 `appliance`

Monthly retail sales of household appliance stores, 1972-07 to 1988-06.

**Transcribed verbatim from the X-13ARIMA-SEATS Reference Manual v1.1 (April
2015), Chapter 3, Examples 3.1–3.4.** This is the Census Bureau's own worked
example, chosen by them because its spectrum reveals a trading-day component.
Being a US federal government publication, it is public domain and safely
redistributable.

```
n = 192   sum = 248096   mean = 1292.1667
sha256 = d8752510b5d01541...
```

Seasonal shape:

```
Jan 0.92  Feb 0.86  Mar 0.95  Apr 0.91  May 0.95  Jun 1.01
Jul 0.95  Aug 0.96  Sep 0.94  Oct 0.97  Nov 1.06  Dec 1.52
```

December at 1.52, February at 0.86. A retail Christmas peak, and a **completely
different seasonal structure from `airline`**. That contrast is why both belong
in the book: one summer-peaked and smooth, one with a single dominant month.

**Why this series and not another.** The manual walks it through a four-stage
workflow (default X-11 → identify → estimate → adjust), so a reader can hold the
manual open beside the book and follow the same arc in Julia. Nothing else has
that property.

**Units are unconfirmed.** The manual gives the title and the numbers but not the
unit. Likely millions of USD. Record `units = "unknown"` rather than guessing;
see §7.3.

---

## 2. Storage

### Location

```
data/
  airline.csv
  appliance.csv
  appliance_q.csv
  DATASETS.md        # provenance, human-readable
```

**Plain CSV, not artifacts.** Artifacts are the right call for the X-13 binary
and the calendar tables, where size and platform variation justify the
machinery. Twelve kilobytes does not. A committed CSV is inspectable, diffable,
and needs no `Artifacts.toml` entry or hash management.

### Format

```
date,value
1949-01-01,112.0
1949-02-01,118.0
```

Header row, ISO-8601 date, `Float64` value. For quarterly series the date is the
**first month of the quarter** (Q1→01, Q2→04, Q3→07, Q4→10), which is exactly the
convention [`parse_table`](@ref) already uses for `YYYYQQ` output tables. One
convention across the package.

### Reading without CSV.jl

Taking CSV.jl as a dependency to read 12 KB of bundled data would be the same
mistake the sink pattern exists to avoid, with the added irony that CSV.jl is
where the pattern comes from.

```julia
function _read_dataset_csv(path)
    lines = readlines(path)
    n = length(lines) - 1
    dates  = Vector{Date}(undef, n)
    values = Vector{Float64}(undef, n)
    for i in 1:n
        d, v = split(lines[i + 1], ',')
        dates[i]  = Date(d)                 # ISO parses with no format string
        values[i] = parse(Float64, v)
    end
    (date = dates, value = values)
end
```

`Date(str)` parses ISO-8601 natively. That is the reason for choosing the format.

---

## 3. API

Full rationale in `dataset-api-design.md`. The implementation:

```julia
const _CACHE = Dict{String, NamedTuple}()

function _dataset_table(name::AbstractString)
    key = String(name)
    haskey(_REGISTRY, key) || throw(ArgumentError(
        "unknown dataset $(repr(key)). Available: $(join(sort(collect(keys(_REGISTRY))), ", "))"))
    get!(_CACHE, key) do
        _read_dataset_csv(joinpath(_DATA_DIR, key * ".csv"))
    end
end

dataset(name::AbstractString) = deepcopy(_dataset_table(name))
dataset(name::AbstractString, sink) = sink(_dataset_table(name))
dataset(name::Symbol, args...) = dataset(String(name), args...)

datasets() = sort(collect(keys(_REGISTRY)))
datasets(sink) = sink(_metadata_table())

dataset_info(name::AbstractString) = _REGISTRY[String(name)]
```

Three points that are easy to get wrong.

**`deepcopy` on the no-sink path.** The cache holds one copy; a user who mutates
what they got back would otherwise corrupt every later call in the session, and
the failure would surface somewhere unrelated. The sink path does not need it,
because sinks materialise their own storage.

**No `dataset(names::AbstractVector)` method.** Deliberate. Broadcasting is the
vector story. If both existed, `dataset(names)` and `dataset.(names)` would be
different operations spelled almost identically. Say so in the docstring so it
does not get helpfully added later.

**Let sink failures through.** `dataset("airline", Vector)` should fail with
`MethodError: no method matching Vector(::NamedTuple...)`, which is accurate and
points at the real problem. No custom fallback error.

### Confirmed sinks

| Sink | Works | Note |
|---|---|---|
| *(none)* | ✔ | `NamedTuple`, itself a Tables.jl column table |
| `DataFrame` | ✔ | |
| `TSFrame` | ✔ | **Confirmed**: TSFrames documents `CSV.read(path, TSFrame)`, so its constructor accepts a Tables.jl source |
| `Tables.rowtable` | ✔ | |
| `Tables.matrix` | ✔ | mixed `Date`/`Float64` gives `Matrix{Any}` |
| `TimeArray` | unverified | use `x -> TimeArray(x; timestamp = :date)` if the bare form needs a hint |

### `DatasetInfo`

```julia
struct DatasetInfo
    name      :: String
    title     :: String
    source    :: String
    url       :: String
    licence   :: String
    citation  :: String
    frequency :: Int
    n         :: Int
    span      :: Tuple{Date,Date}
    units     :: String
    retrieved :: Union{Date,Nothing}
    notes     :: String
end
```

Populated for the two shipped datasets:

```julia
"airline" => DatasetInfo(
    "airline",
    "International airline passengers",
    "Box & Jenkins (1976), Series G",
    "",
    "Public domain",
    "Box, G.E.P. and Jenkins, G.M. (1976). Time Series Analysis: " *
        "Forecasting and Control. Holden-Day. Series G.",
    12, 144, (Date(1949,1,1), Date(1960,12,1)),
    "thousands of passengers", nothing,
    "The canonical seasonal adjustment example. Strongly multiplicative; " *
    "X-13 selects a log transform. Also this package's verification baseline."),

"appliance" => DatasetInfo(
    "appliance",
    "Monthly retail sales of household appliance stores",
    "US Census Bureau, X-13ARIMA-SEATS Reference Manual v1.1, Ch. 3",
    "https://www.census.gov/data/software/x13as.html",
    "Public domain (US federal government work)",
    "U.S. Census Bureau (2015). X-13ARIMA-SEATS Reference Manual, " *
        "Version 1.1, Chapter 3, Examples 3.1-3.4.",
    12, 192, (Date(1972,7,1), Date(1988,6,1)),
    "unknown", nothing,
    "The manual's own worked example, chosen because its spectrum reveals " *
    "a trading-day component. Units are not stated in the source."),
```

Give it a `show` method that prints as an attribution block, so
`dataset_info("appliance")` answers "may I publish a chart of this".

### The convenience method

```julia
TSAnalytics.tsvalues(d::NamedTuple{(:date, :value)}) = d.value
TSAnalytics.tsindex(d::NamedTuple{(:date, :value)})  = d.date
```

Two lines, and because [`x13`](@ref) already infers `start` from `tsindex(y)`:

```julia
res = x13(dataset("airline"))
```

That is the Getting Started opening example, and it removes the `airline()`
loader currently listed as a blocker in the guide's verification checklist.

---

## 4. Tests

`test/test_datasets.jl`, no binary required except where noted.

```julia
@testset "datasets -- discovery" begin
    @test "airline" in datasets()
    @test "appliance" in datasets()
    @test issorted(datasets())
end

@testset "airline -- shape and content" begin
    d = dataset("airline")
    @test length(d.value) == 144
    @test d.date[1] == Date(1949, 1, 1)
    @test d.date[end] == Date(1960, 12, 1)
    @test sum(d.value) == 40363.0
    @test mean(d.value) ≈ 280.2986 atol = 1e-4
    @test d.value[1] == 112.0
    @test d.value[end] == 432.0
    @test all(diff(d.date) .== Month(1))
end

@testset "appliance -- shape and content" begin
    d = dataset("appliance")
    @test length(d.value) == 192
    @test d.date[1] == Date(1972, 7, 1)
    @test d.date[end] == Date(1988, 6, 1)
    @test sum(d.value) == 248096.0
    @test d.value[1] == 530.0
    @test d.value[end] == 2520.0
end

@testset "seasonal shape is as documented" begin
    # guards against a silently reordered or corrupted file: the two
    # datasets have deliberately different seasonal structures
    for (name, peak, trough) in (("airline", 7, 11), ("appliance", 12, 2))
        d = dataset(name)
        gm = mean(d.value)
        shape = [mean(d.value[month.(d.date) .== m]) / gm for m in 1:12]
        @test argmax(shape) == peak
        @test argmin(shape) == trough
    end
end

@testset "appliance_q -- quarterly convention" begin
    d = dataset("appliance_q")
    @test length(d.value) == 64
    @test d.date[1] == Date(1972, 7, 1)          # Q3 -> month 7
    @test all(month.(d.date) .∈ Ref([1, 4, 7, 10]))
    @test all(diff(d.date) .== Month(3))
    @test sum(d.value) == sum(dataset("appliance").value)   # derived, §7.1
end

@testset "mutation safety" begin
    a = dataset("airline"); a.value[1] = -999.0
    @test dataset("airline").value[1] == 112.0
end

@testset "unknown name lists what is available" begin
    err = try dataset("airlines") catch e; sprint(showerror, e) end
    @test occursin("airline", err)
    @test occursin("appliance", err)
end

@testset "Symbol names accepted" begin
    @test dataset(:airline).value == dataset("airline").value
end

@testset "no vector method exists -- broadcasting is the vector story" begin
    @test !hasmethod(dataset, Tuple{Vector{String}})
end

@testset "broadcasting" begin
    ds = dataset.(["airline", "appliance"])
    @test length(ds) == 2
    @test length(ds[1].value) == 144
    @test length(dataset.(datasets())) == length(datasets())
end

@testset "Tables.jl interface" begin
    d = dataset("airline")
    @test Tables.istable(d)
    @test Tables.columnnames(d) == (:date, :value)
    @test length(dataset("airline", Tables.rowtable)) == 144
    @test size(dataset("airline", Tables.matrix)) == (144, 2)
end

@testset "dataset_info" begin
    i = dataset_info("appliance")
    @test i.frequency == 12
    @test i.n == 192
    @test occursin("Census", i.source)
    @test !isempty(i.licence)
    for name in datasets()                      # provenance is never blank
        @test !isempty(dataset_info(name).licence)
        @test !isempty(dataset_info(name).citation)
    end
end

@testset "x13 accepts a dataset directly" begin
    if x13_binary_available()
        res = x13(dataset("airline"))
        @test res.dates[1] == Date(1949, 1, 1)   # start inferred, not passed
        @test length(res.seasonally_adjusted) == 144
        res_q = x13(dataset("appliance_q"); period = 4)
        @test length(res_q.seasonally_adjusted) == 64
    end
end
```

### Extended suite

`DataFrame` and `TSFrame` go in `test/extended/`, gated the way the R
cross-validation suite already is, so a plain `Pkg.test()` needs neither package.

```julia
@testset "extended -- DataFrame and TSFrame sinks" begin
    using DataFrames, TSFrames
    df = dataset("airline", DataFrame)
    @test nrow(df) == 144
    @test names(df) == ["date", "value"]

    ts = dataset("airline", TSFrame)
    @test nrow(ts) == 144
    # TSFrames consumes one column as the Date index, so a (date, value)
    # table must yield exactly ONE remaining column. Getting this wrong
    # produces a 2-column TSFrame with an integer index that still looks
    # plausible, so assert the shape rather than just the type.
    @test ncol(ts) == 1
    @test eltype(index(ts)) == Date
end
```

---

## 5. Known outlier, worth a test

X-13 detects an additive outlier at **May 1951** in `airline` under the
fixture's specification, and it is recorded in `auto_test.udg` as
`AutoOutlier$AO1951.May`.

The surrounding values are `163.0, 172.0, 178.0` for April, May and June. **It is
not visually obvious.** Detection happens on regARIMA residuals after
differencing, not on levels.

That makes it a useful teaching point for Getting Started chapter 4, and a good
regression test: if the data file were ever silently reordered or corrupted, the
detected outlier would move.

---

## 6. Documentation

`data/DATASETS.md` carries provenance in human-readable form, duplicating the
`DatasetInfo` content. The struct is for programs; the file is for whoever opens
the repository and asks where the numbers came from.

Add a short API Reference section for `dataset`, `datasets` and `dataset_info`,
following the existing docstring conventions.

---

## 7. Outstanding

### 7.1 `appliance_q` is derived, not published

It is `appliance` aggregated to quarters: 192 months → 64 quarters, 1972-Q3 to
1988-Q2, sums preserved exactly.

**Ship it, but describe it honestly.** It exists to exercise `period = 4` —
quarterly dates, `Q1`–`Q4` tick labels, quarterly outlier labels, the
quarterly-scaled `seasonal_ma` in [`filters`](@ref). For that job it is
adequate, and it has one genuine teaching virtue: the same underlying data at
two frequencies, so the book can compare directly.

For anything substantive it is weak, because aggregation washes out the
trading-day and moving-holiday structure that makes quarterly adjustment
interesting. A real published quarterly series would be better and should
replace it when one is sourced. Set `notes` to say all of this.

### 7.2 `iip_india` is blocked on licensing

The chapter that distinguishes this package from every other X-13 wrapper needs
a real Indian monthly series with a Diwali effect and the COVID period. MOSPI
data is generally freely usable but the terms need checking.

Five figures and two chapters depend on it. **Resolve before Part C of the
book.**

If licensing cannot be cleared, the fallback is a synthetic series from a known
DGP with a Diwali effect and a COVID level shift injected. Weaker
pedagogically, but it keeps the chapter runnable and has the compensating virtue
that the true components are known.

### 7.3 Two small unknowns

`appliance` units are not stated in the manual. Record `"unknown"` rather than
guessing; correct it if a Census source gives them.

`TimeArray` as a bare sink is unverified. The lambda form works regardless, so
this only affects what the docstring can promise.

---

## 8. Files attached

| File | Rows | SHA-256 (first 16) |
|---|---|---|
| `airline.csv` | 144 + header | `9312906f56e35f92` |
| `appliance.csv` | 192 + header | `d8752510b5d01541` |
| `appliance_q.csv` | 64 + header | `515aed844aa2a198` |

Drop into `data/`. The checksums are worth committing to the test suite so a
corrupted file fails CI rather than quietly changing every figure in the book.

---

## 9. Adding datasets later

### The recipe

Adding a dataset is four steps and touches no API:

1. Drop `data/<name>.csv` in the documented format
2. Add a `DatasetInfo` entry to `_REGISTRY`
3. Add a `@testset` with length, span, checksum and a shape assertion
4. Add a row to `data/DATASETS.md`

`datasets()`, `dataset()`, broadcasting and every sink pick it up automatically,
because the registry is the single source of truth. Nothing in §3 changes.

### Size limits

Keep `data/` under roughly 1 MB total and individual files under ~200 KB. Beyond
that the artifact machinery starts to earn its cost. Eight monthly series of
this length is about 25 KB, so there is plenty of headroom.

### Add a `kind` field first

Before any more datasets land, extend `DatasetInfo`:

```julia
kind :: Symbol    # :published | :derived | :synthetic
```

`appliance_q` is already `:derived` and the struct currently has no way to say
so, leaving it to prose in `notes`. Several datasets below will be `:synthetic`
by design. A reader plotting a figure from the book deserves to know which
category they are looking at without reading a paragraph.

---

## 10. What the Introduction still needs

The figure inventory in `book-production-plan.md` implies dataset requirements
the current four cannot meet. Listed here so they are not discovered mid-chapter.

### 10.1 A series that FAILS its diagnostics

**The most important gap, and the easiest to overlook.**

Figures E-2 (Q across good and bad series) and E-5 (a residual-seasonality
failure with peaks annotated) cannot be drawn if every shipped dataset adjusts
cleanly. `airline` and `appliance` both pass comfortably — Q of 0.20 for the
airline fixture.

Part E is the most valuable part of the book and it is about recognising
failure. Teaching that with only successful examples is not possible.

**Recommend synthetic.** A series with a deliberately fast-moving seasonal
pattern, or seasonality too weak to identify, gives a controlled and explainable
failure. Hunting for a real series that fails is slower and the explanation is
murkier. Label it `:synthetic` and say in `notes` exactly which diagnostic it is
built to fail.

### 10.2 A near-zero or zero-crossing series

Figure B-12 compares multiplicative, additive and pseudo-additive modes. That
comparison is meaningless on strictly positive, strongly multiplicative data,
and both current datasets are exactly that.

Pseudo-additive exists for series with values at or near zero, which is the case
the figure needs to show. A real candidate would be better than synthetic here,
since the mode choice is a substantive judgement rather than a mechanical one.

### 10.3 A series where X-11 and SEATS diverge

Figure D-6. Most of the time the two engines broadly agree, which is the honest
message of Part D — but a chapter that only shows agreement cannot explain when
the choice matters.

This one has to be found rather than designed, and it may fall out of running
both engines over whatever datasets end up shipped. Worth checking early.

### 10.4 A short series

Near the three-complete-years minimum [`validate!`](@ref) enforces. Useful for
demonstrating the limits, the error message, and why sliding spans need length.
Trivial to construct by truncating an existing series.

### 10.5 A series with a level shift

If `iip_india` clears licensing, COVID supplies this. If it does not, LS and TC
need their own example, because `airline`'s only detected outlier is a single AO
and figure C-11 needs all four shapes.

---

## 11. The one thing that is not "add later"

The mechanics are trivial. The **editorial** dependency is not.

Chapter text and figure captions bake in which dataset illustrates which point.
Writing Part E around `airline` and then discovering it needs a failing series
means rewriting Part E, not adding a file.

So: decide **which dataset carries which argument** before writing a chapter,
even if the file itself lands later. A placeholder name in the registry with the
data pending is cheap; a rewritten chapter is not.

Priority order, by when the book needs them:

| Need | Blocks | Urgency |
|---|---|---|
| failing series (10.1) | Part E, the most valuable part | **before writing Part E** |
| `iip_india` (§7.2) | Parts A and C | before Part C |
| near-zero series (10.2) | Figure B-12 | before Part B is finalised |
| divergent series (10.3) | Figure D-6 | Part D is last anyway |
| short series (10.4) | minor | any time |

---

## 12. `iip_india` — sourcing decision

**Resolved: open government data under GODL-India.**

### The licence works

The Government Open Data License – India (GODL-India), issued under the National
Data Sharing and Accessibility Policy, grants a **worldwide, royalty-free,
non-exclusive licence to use, adapt, publish, translate, display, add value and
create derivative works, for both commercial and non-commercial purposes, in
perpetuity.**

That covers everything this package needs: redistributing a series inside a Julia
package, plotting it in a book, and adapting it (log transforms, truncation).

Three conditions attach.

**Attribution is mandatory and its format is specified.** Section 5 of the
licence gives the template:

```
[Data Provider], [Year of Publication], [Name of Data],
[Repository/Website], [Version and/or Date of Publication (dd/mm)],
[DOI / URL / URI]. Published under [Licence Name]: [licence URL]
```

Pleasingly, `DatasetInfo` already has the right shape — `source`, `url`,
`citation`, `retrieved` and `licence` map one-to-one onto those slots. Populate
them from the template rather than paraphrasing.

**Non-endorsement.** The documentation must not suggest the data provider
endorses this package. Nothing currently does; keep it that way in the
`dataset_info` `show` output.

**No warranty**, and no guarantee of continued supply. Worth one line in `notes`.

### Choosing the series

Criteria, in priority order:

1. **Monthly**, and long enough to contain a pre-COVID stretch, COVID, and the
   recovery
2. **Shows a Diwali effect** — a consumption or production series responds; a
   purely financial one may not. Consumer-durables-type components will show it
   more clearly than a broad aggregate
3. **Strictly positive and well away from zero**, so the log transform is
   available and the multiplicative decomposition is the right one
4. **Recognisable** — a reader should know what they are looking at

### The rebasing trap

**IIP has been rebased** (2004-05 base to 2011-12 base). A spliced series across
a rebasing carries a level shift and a scale change that have nothing to do with
seasonality, and X-13 will dutifully detect it as an LS.

**Use a single base period.** From 2012-04 onward gives roughly 170 monthly
observations through 2026 — comfortably enough, with COVID near the middle,
which is exactly where Chapter 12 wants it. Do not splice across the break to
gain a few more years.

Check the same question for any alternative series before choosing it.

### It is a snapshot, and must say so

IIP is **revised** — provisional figures are restated in later releases. A
dataset shipped in the package is a snapshot at one retrieval date, and a reader
who downloads fresh data will not reproduce the book's figures exactly.

Record the retrieval date in `DatasetInfo.retrieved` (GODL requires the date
anyway) and say plainly in `notes` that the series is a point-in-time snapshot,
not a live feed. This is the same discipline as `static()`: figures should move
when you decide they move.

### Checklist

- [ ] Series selected against the four criteria above
- [ ] Single base period, no splice
- [ ] Downloaded from data.gov.in; exact dataset URL recorded
- [ ] Retrieval date recorded
- [ ] `DatasetInfo` populated from the GODL §5 attribution template
- [ ] `notes` covers the snapshot caveat, the base period, and no-warranty
- [ ] `kind = :published`
- [ ] Checksum test added, as for `airline` and `appliance`
- [ ] Diwali effect confirmed present before committing — run
      `x13` with a `custom_holiday_regressor` and check the coefficient is
      significant. **A series with no detectable Diwali effect is the wrong
      series for this book**, however good it looks otherwise.

That last item is the one to do before anything else. Chapters 1, 11 and 12 and
five figures all assume the effect is visible; if the chosen series does not show
it, better to find that out now than in Part III.

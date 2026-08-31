# Handoff: W.7 — Forecasts, Missing Values, Component Tables, `vcov`

For a fresh session with no prior context. Same treatment as W.0–W.6: verified
references first, complete API with argument values, fixture-grounded tests.

**Depends on:** W.5 (`series`, `spec_args`, StatsAPI contract), W.6 (recipes)
**Companion:** `w8-chart-gaps-handoff.md`
**Required reading:** `handoff/reference/x13-saveable-tables.md` — commit it first

---

## 0. Read the reference file before anything else

`handoff/reference/x13-saveable-tables.md` is the authoritative catalogue of all
281 saveable X-13 tables, cross-compiled from `seasonal`'s `SPECS.csv` and
`series.R` plus the Census Reference Manual. It exists because **an earlier gap
analysis for this work guessed the save keywords and got them wrong.**

The specific trap, restated because it is the single most likely thing to be got
wrong again: the save keyword is *not* the X-11 table number. The holiday factor
series is table A7, but you request it with `regression.holiday` and it lands in
`.hol`. `save = (a7)` does nothing. Only `a10` and `a13` happen to be spelled as
their table numbers.

---

## 1. Deliverables

| ID | Deliverable | Effort |
|----|-------------|--------|
| W.7.1 | Widen `_KNOWN_TABLES` from the reference catalogue | ~30 LOC |
| W.7.2 | `forecast` / `backcast` accessors with extended dates | ~120 LOC |
| W.7.3 | Missing-value support (`-99999` + `.mv`) | ~80 LOC |
| W.7.4 | Component-factor accessors (`.td`, `.hol`, `.usr`, `.otl`) | ~70 LOC |
| W.7.5 | `StatsAPI.vcov` via `estimate { save = (rcm) }` | ~60 LOC |
| W.7.6 | `summary()` and `update()` | ~90 LOC |
| W.7.7 | `force` and `seasonalma` typed fields | ~40 LOC |
| W.7.8 | Sliding-spans and history accessors | ~80 LOC |

---

## 2. W.7.1 — Widen `_KNOWN_TABLES`

Currently 17 symbols: `b1 c17 d8 d9 d10 d11 d12 d13 s10–s18 rsd fct fvr`. The
catalogue has 281. `series()` already re-runs with any table added to `save`, so
the whitelist is the only thing gating them.

**Don't hand-transcribe.** Generate the Julia constant from the reference file's
tables, or commit `SPECS.csv`'s `is.save == TRUE` rows as a package data file and
build the `Set` at load time. A hand-typed list of 281 symbols will contain
errors.

Also fold in the spectrum tables. `_SPECTRUM_TABLE_FOR_SERIES` maps to
`sp0`/`sp1`/`sp2`/`spr` through its own path logic, so `spectrumplot` works while
`series(r, :sp0)` throws. Two mechanisms for one job — make `_spectrum_series`
call `series()`.

Note the reference file's `print`/`save` distinction: `none`, `all`,
`alltables`, `default` and `brief` are **print-only and invalid in `save`**. If
`spec_args` lets someone write `"x11.save" => "all"`, `validate!` should reject
it.

---

## 3. W.7.2 — Forecasts and backcasts

### What the catalogue settles

| Save keyword | Ext | Contents |
|---|---|---|
| `forecast.forecasts` | `.fct` | point forecasts **on the original scale, with upper and lower prediction interval limits** |
| `forecast.backcasts` | `.bct` | same, backwards |
| `forecast.transformed` | `.ftr` | forecasts on the transformed scale with standard errors |
| `forecast.transformedbcst` | `.btr` | backcasts, transformed scale |
| `forecast.variances` | `.fvr` | forecast error variances, transformed scale |

So `.fct` already carries point, lower and upper. The interval does **not** need
assembling from `.fvr`. `.bct` is missing from `_KNOWN_TABLES` entirely.

### API

```julia
forecast(r::X13Result;  level = 0.95) -> (dates=, point=, lower=, upper=)
backcast(r::X13Result;  level = 0.95) -> same
```

| Argument | Values | Default | Meaning |
|---|---|---|---|
| `level` | `Float64` in (0,1) | `0.95` | Interval width. Maps to `forecast { probability = }`. Changing it forces a re-run, since the limits are computed by the binary. |

### The extended date axis — this is the actual work

Forecast rows sit *past* `r.dates[end]`. Generate them from `r.spec.period` and
the horizon:

```julia
_extend_dates(last::Date, n::Int, period::Int) =
    [last + (period == 12 ? Dates.Month(i) : Dates.Month(3i)) for i in 1:n]
```

Backcasts extend backwards from `r.dates[1]`. Reuse whatever `x13()` already
does to build `r.dates` rather than writing a second date-generator — a
divergence between them would be invisible and wrong.

### Horizon and program limits

`forecast.maxlead` defaults to 12 in X-13. **Program limit `pfcst = 120`**
(Manual Table 2.2, read directly) caps forecasts and backcasts. Add a
`validate!` rule: `maxlead > 120` throws before the subprocess, matching every
other `validate!` rule's fast-fail convention.

Two more limits worth adding as rules while you are there, from the same table:
`pobs = 780` maximum series length, `pureg = 52` maximum user-defined
regressors, `pb = 80` maximum regression variables including auto-detected
outliers.

### Interaction with the W.5 `maxlead` decision

W.5 deliberately left `maxlead` unset rather than forcing `0`, on the grounds
that this package *can* extend user regressors where R's `seasonal` cannot. This
deliverable is what makes that decision pay off — until now the capability was
unreachable. Add a test that forecasts work **with** a `custom_holiday_regressor`
present, since that is precisely the case R cannot do.

---

## 4. W.7.3 — Missing values

### What the catalogue settles

The 2015 Manual's Chapter 1 states missing values are not allowed. **That
statement is stale.** `seasonal`'s `na.x13()` is one line — substitute `NA` with
`-99999`, X-13's default missing code — and `series.seriesmvadj` (`.mv`) returns
the series with missing values replaced by regARIMA estimates.

No `missingcode` argument is needed at the default value. Confirm against the
binary whether a non-default `series { missingcode = }` is also accepted before
exposing one.

### API

```julia
x13(y; missing_action = :error, kwargs...)
```

| Value | Behaviour | R equivalent |
|---|---|---|
| `:error` | Throw on any `NaN`/`missing` in `y` | — (the safe default) |
| `:x13` | Substitute `-99999`, let X-13 interpolate via AO regressors | `na.action = na.x13` |
| `:omit` | Drop leading/trailing missings, throw on interior ones | `na.action = na.omit` |

Default `:error`. Silently substituting a sentinel would be the wrong default
for an official-statistics package — the caller should say so explicitly.

Companion accessor:

```julia
interpolated(r::X13Result) -> Vector{Float64}   # the .mv table
```

### Traps

- `y::Vector{Float64}` can hold `NaN` but not `missing`. Accept
  `AbstractVector{Union{Missing,Float64}}` at the `x13()` boundary and convert.
- `-99999` is a **legitimate value** for some series. Warn if `y` already
  contains it and `missing_action == :x13`.
- Under `transform = :log`, a `-99999` sentinel is negative. Confirm the binary
  handles the ordering correctly rather than assuming; the `validate!` rule that
  rejects non-positive data under a log transform must not fire on sentinels.

---

## 5. W.7.4 — Component-factor accessors

The estimated *time path* of each regression effect. Given the India calendar
layer, `.hol` and `.usr` are the point of this deliverable: `coef()` gives the
Diwali coefficient, these give the month-by-month factor.

```julia
components(r::X13Result; which = :all) -> NamedTuple
```

| `which` | Save keyword | Ext |
|---|---|---|
| `:trading_day` | `regression.tradingday` | `.td` |
| `:holiday` | `regression.holiday` | `.hol` |
| `:user` | `regression.userdef` | `.usr` |
| `:outlier` | `regression.outlier` | `.otl` |
| `:ao` / `:ls` / `:tc` / `:so` | `regression.aoutlier` etc. | `.ao` `.ls` `.tc` `.so` |
| `:all` | all present | — |

Fetch through `series()` so the re-run machinery and its `@info` announcement
are reused. Return `nothing` for components the model doesn't contain rather
than throwing — a run with no holiday regressor has no `.hol`.

**Which spec owns the `save`:** these are `regression` spec tables, not `x11`.
`X13Spec` renders `regression { ... }` already; `series()`'s re-run path must add
the table to the right block. Check how `series()` currently routes `save`
symbols to blocks — if it assumes `x11`, that is a bug this deliverable exposes.

---

## 6. W.7.5 — `vcov`

W.5 made `StatsAPI.vcov` throw, correctly reasoning that `.udg` carries standard
errors but no covariance matrix. **The reasoning was right and the conclusion is
now obsolete:** `estimate.regcmatrix` (`.rcm`) is documented as the correlation
matrix under `print` and the **covariance matrix under `save`**.
`estimate.armacmatrix` (`.acm`) is the same for ARMA parameters.

```julia
StatsAPI.vcov(r::X13Result) -> Matrix{Float64}
```

Fetch `.rcm` via `series()`, re-running when absent. Keep the existing named
error only for the genuinely unavailable case — a run with no regression
variables at all.

### Verify before trusting

The print/save duality means the *same table code* yields a correlation matrix
in one context and a covariance matrix in another. Confirm which you actually
get by checking `sqrt.(diag(V))` against `stderror(r)` — they must match. If
they don't, you have the correlation matrix and need to rescale. **Assert this
in the test**, don't just check the shape.

Row/column order must match `coefnames(r)`. `_coefficient_lines` recovers order
by re-reading `.udg` for exactly this reason; `.rcm`'s own ordering needs
checking against it.

Once `vcov` exists, `coeftable` can carry t-statistics and p-values, which is
what R's `summary.seas` prints.

---

## 7. W.7.6 — `summary()` and `update()`

```julia
summary(r::X13Result)              -> X13Summary   # with its own show
update(r::X13Result; kwargs...)    -> X13Result
```

`summary` composes existing accessors: `coeftable` (now with p-values from
W.7.5), then transform, ARIMA model, `nobs`/`nefobs`, AIC/BIC, QS on original
and SA, M7 and Q, Ljung-Box, and the outlier list. No new capability.

`update` is `X13Spec(r.spec; kwargs...)` then `x13`. `series()` already does this
internally — extract the shared path rather than writing it twice.

---

## 8. W.7.7 — `force` and `seasonalma`

**`force`** — forcing SA totals to annual originals. Required by several
national statistical offices.

```julia
force::Union{Nothing,Symbol} = nothing   # :none | :denton | :regress
force_target::Symbol = :original          # :original | :caladjust | :permprioradj | :both
```

Tables: `force.seasadjtot` (`.saa`), `force.forcefactor` (`.ffc`),
`force.saround` (`.rnd`). Confirm the `target` value list against Manual
Table 7.15 — it was past the fetch limit and is **not** verified here.

**`seasonalma`** — the seasonal filter choice, a substantive methodological
decision currently reachable only as a raw string. The fixture shows it
defaulting to `MSR` across all twelve months.

```julia
seasonalma::Union{Nothing,Symbol,Vector{Symbol}} = nothing
# :s3x1 :s3x3 :s3x5 :s3x9 :s3x15 :stable :x11default :msr
```

X-13 accepts either one filter for all periods or one per period — hence the
`Vector` option. Confirm the accepted keyword spellings against Manual
Table 7.55 before implementing; the list above is from Chapter 3's worked
example plus the fixture, not from the filter table itself.

---

## 9. W.7.8 — Sliding spans and history

W.5 made both blocks *requestable* via `spec_args`. Nothing reads the results.
The fixture confirms `sspans`, `history` and `historysa` exist as `.udg` keys,
reading `no` when not requested.

Saveable tables:

| Sliding spans | Ext | | History | Ext |
|---|---|---|---|---|
| `slidingspans.sfspans` | `.sfs` | | `history.saestimates` | `.sae` |
| `slidingspans.chngspans` | `.chs` | | `history.sarevisions` | `.sar` |
| `slidingspans.ychngspans` | `.ycs` | | `history.chngestimates` | `.che` |
| `slidingspans.tdspans` | `.tds` | | `history.chngrevisions` | `.chr` |
| | | | `history.trendestimates` | `.tre` |
| | | | `history.lkhdhistory` | `.lkh` |

```julia
slidingspans(r::X13Result) -> NamedTuple
revision_history(r::X13Result; estimates = [:sadj, :sadjchng]) -> NamedTuple
```

**Do this step first and record the result**, because it decides scope: run once
with both blocks on and diff the resulting `.udg` against the committed fixture.
If the summary statistics (the percentage-of-months-exceeding thresholds, the
average absolute revision) land in `.udg`, both accessors are dictionary reads.
If they don't, they must come from the saved tables above — still no HTML
parsing, but more assembly.

This is W.5 open question 3, still open.

---

## 10. Test plan

`test/test_forecast.jl`, `test/test_components.jl`, `test/test_missing.jl`.
House convention: `@testset` per task, `x13_binary_available()` gate with
`@warn` skip, literals from committed fixtures.

### 10.1 Table catalogue

```julia
@testset "_KNOWN_TABLES -- catalogue completeness" begin
    @test length(SeasonalAdjustment._KNOWN_TABLES) > 250
    for t in (:fct, :bct, :ftr, :btr, :fvr, :hol, :td, :usr, :otl, :ao, :ls,
              :tc, :so, :a10, :a13, :rcm, :acm, :mv, :saa, :ffc, :rnd,
              :sfs, :chs, :ycs, :tds, :sae, :sar, :che, :chr, :tre, :lkh,
              :acf, :pcf, :ac2, :sp0, :sp1, :sp2, :spr, :a1, :a18, :a19, :rmx)
        @test t in SeasonalAdjustment._KNOWN_TABLES
    end
end

@testset "_KNOWN_TABLES -- X-11 table numbers are NOT the save keywords" begin
    # the trap the reference file exists to prevent
    for bogus in (:a6, :a7, :a8, :a9)
        @test !(bogus in SeasonalAdjustment._KNOWN_TABLES)
    end
    @test :hol in SeasonalAdjustment._KNOWN_TABLES   # A7 is spelled `hol`
    @test :td  in SeasonalAdjustment._KNOWN_TABLES   # A6 is spelled `td`
    @test :a10 in SeasonalAdjustment._KNOWN_TABLES   # but A10 IS spelled a10
end

@testset "print-only keywords rejected in save" begin
    y = collect(100.0:1.0:243.0)
    for kw in ("all", "none", "alltables", "default", "brief")
        @test_throws ArgumentError X13Spec(y; start = (1949,1),
            spec_args = Dict("x11.save" => kw))
    end
end

@testset "spectrum tables go through series(), not a private path" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1))
        @test series(res, :sp1) isa Vector{Float64}     # threw before W.7
    end
end
```

### 10.2 Forecasts

```julia
@testset "forecast -- shape and interval ordering" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), maxlead = 12)
        f = forecast(res)
        @test length(f.point) == 12
        @test length(f.dates) == length(f.lower) == length(f.upper) == 12
        @test all(f.lower .< f.point .< f.upper)
    end
end

@testset "forecast -- dates continue past the sample, no gap or overlap" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), maxlead = 12)
        f = forecast(res)
        @test f.dates[1] == res.dates[end] + Dates.Month(1)
        @test f.dates[end] == Date(1961, 12)
        @test all(diff(f.dates) .== Dates.Month(1))
        @test f.dates[1] > res.dates[end]
    end
end

@testset "forecast -- quarterly steps by 3 months" begin
    if x13_binary_available()
        res = x13(QUARTERLY_Y; period = 4, start = (1990,1), maxlead = 8)
        f = forecast(res)
        @test length(f.point) == 8
        @test all(diff(f.dates) .== Dates.Month(3))
    end
end

@testset "backcast -- extends backwards from dates[1]" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1),
                  spec_args = Dict("forecast.maxback" => "12"))
        b = backcast(res)
        @test length(b.point) == 12
        @test b.dates[end] == res.dates[1] - Dates.Month(1)
        @test b.dates[1] == Date(1948, 1)
        @test all(b.lower .< b.point .< b.upper)
    end
end

@testset "forecast -- WITH a user regressor (R's seasonal cannot do this)" begin
    if x13_binary_available()
        reg = custom_holiday_regressor(Date(1949,1), Date(1962,12), INDIA_NSE,
                                       y -> Date(y, 11, 1))
        res = x13(AIRLINE_Y; start = (1949,1), regression_user = reg,
                  regression_usertype = :holiday, maxlead = 12)
        f = forecast(res)
        @test length(f.point) == 12
        @test all(isfinite, f.point)
    end
end

@testset "forecast -- level widens the interval" begin
    if x13_binary_available()
        n = forecast(x13(AIRLINE_Y; start=(1949,1), maxlead=12); level = 0.95)
        w = forecast(x13(AIRLINE_Y; start=(1949,1), maxlead=12); level = 0.99)
        @test all((w.upper .- w.lower) .> (n.upper .- n.lower))
    end
end

@testset "forecast -- pfcst=120 program limit enforced before the subprocess" begin
    y = collect(100.0:1.0:243.0)
    @test_throws ArgumentError X13Spec(y; start = (1949,1), maxlead = 121)
    @test X13Spec(y; start = (1949,1), maxlead = 120) isa X13Spec
end

@testset "forecast -- nothing when no forecast block was requested" begin
    if x13_binary_available()
        @test forecast(x13(AIRLINE_Y; start = (1949,1))) !== nothing  # re-runs
    end
end
```

### 10.3 Missing values

```julia
@testset "missing -- :error is the default and throws" begin
    y = copy(AIRLINE_Y); y[20] = NaN
    @test_throws ArgumentError x13(y; start = (1949,1))
    @test_throws ArgumentError x13(y; start = (1949,1), missing_action = :error)
end

@testset "missing -- :x13 substitutes -99999 in the rendered spec" begin
    y = copy(AIRLINE_Y); y[20] = NaN
    s = X13Spec(y; start = (1949,1), missing_action = :x13)
    @test occursin("-99999", render(s))
    @test !occursin("NaN", render(s))
end

@testset "missing -- :x13 runs and interpolates the gap" begin
    if x13_binary_available()
        y = copy(AIRLINE_Y); y[20] = NaN
        res = x13(y; start = (1949,1), missing_action = :x13)
        @test all(isfinite, res.seasonally_adjusted)
        mv = interpolated(res)
        @test length(mv) == length(y)
        @test isfinite(mv[20])
        @test mv[20] != -99999.0
        @test mv[[1, 50, 144]] ≈ y[[1, 50, 144]]   # non-missing untouched
    end
end

@testset "missing -- Union{Missing,Float64} accepted at the boundary" begin
    y = Vector{Union{Missing,Float64}}(AIRLINE_Y); y[20] = missing
    if x13_binary_available()
        @test x13(y; start = (1949,1), missing_action = :x13) isa X13Result
    end
end

@testset "missing -- warn when -99999 is already a real value" begin
    y = copy(AIRLINE_Y); y[5] = -99999.0; y[20] = NaN
    @test_logs (:warn,) X13Spec(y; start = (1949,1), missing_action = :x13)
end

@testset "missing -- log transform does not reject the sentinel" begin
    if x13_binary_available()
        y = copy(AIRLINE_Y); y[20] = NaN
        res = x13(y; start = (1949,1), missing_action = :x13, transform = :log)
        @test transformfunction(res) === :log
    end
end

@testset "missing -- :omit drops edges, throws on interior" begin
    y = copy(AIRLINE_Y); y[1] = NaN
    @test x13(y; start = (1949,2), missing_action = :omit) isa X13Result skip=!x13_binary_available()
    y2 = copy(AIRLINE_Y); y2[70] = NaN
    @test_throws ArgumentError x13(y2; start = (1949,1), missing_action = :omit)
end
```

### 10.4 Components

```julia
@testset "components -- holiday factors from a user regressor" begin
    if x13_binary_available()
        reg = custom_holiday_regressor(Date(1949,1), Date(1960,12), INDIA_NSE,
                                       y -> Date(y, 11, 1))
        res = x13(AIRLINE_Y; start = (1949,1), regression_user = reg,
                  regression_usertype = :holiday)
        c = components(res)
        @test c.user !== nothing
        @test length(c.user) == length(res.observed)
        @test !all(≈(1.0), c.user)          # a real, non-degenerate effect
    end
end

@testset "components -- trading day present only when td is in the model" begin
    if x13_binary_available()
        with = x13(AIRLINE_Y; start = (1949,1), trading = true)
        @test components(with; which = :trading_day) !== nothing
        without = x13(AIRLINE_Y; start = (1949,1))
        @test components(without; which = :trading_day) === nothing
    end
end

@testset "components -- outlier factors align with outliers()" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), outlier = true, automdl = true)
        otl = components(res; which = :outlier)
        if otl !== nothing
            @test length(otl) == length(res.observed)
            i = findfirst(!ismissing, outliers(res))
            @test otl[i] != 1.0        # multiplicative: 1.0 means no effect
        end
    end
end

@testset "components -- save is routed to the regression block, not x11" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), trading = true)
        _ = components(res; which = :trading_day)     # must not error
        @test occursin("regression", render(res.spec))
    end
end
```

### 10.5 `vcov`

```julia
@testset "vcov -- is the COVARIANCE matrix, not the correlation matrix" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), trading = true, automdl = true)
        V = vcov(res)
        @test size(V, 1) == size(V, 2)
        @test issymmetric(V) || V ≈ V'
        # THE decisive check: diagonal must reproduce stderror
        @test sqrt.(diag(V)) ≈ stderror(res) rtol=1e-6
        # a correlation matrix has a unit diagonal -- this must NOT hold
        @test !all(≈(1.0), diag(V))
    end
end

@testset "vcov -- row order matches coefnames" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), trading = true, automdl = true)
        @test size(vcov(res), 1) == length(coefnames(res))
    end
end

@testset "vcov -- still a named error with no regression variables" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12))
        @test_throws ErrorException vcov(res)
    end
end

@testset "coeftable -- gains p-values once vcov exists" begin
    if x13_binary_available()
        ct = coeftable(x13(AIRLINE_Y; start=(1949,1), trading=true, automdl=true))
        @test length(ct.colnms) >= 4
        @test any(contains("Pr"), ct.colnms) || any(contains("p"), lowercase.(ct.colnms))
    end
end
```

### 10.6 Sliding spans, history, `force`, `seasonalma`, `summary`, `update`

```julia
@testset "slidingspans -- udg keys flip and summaries are reachable" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), spec_args = Dict("slidingspans" => ""))
        @test udg(res, "sspans") == "yes"
        ss = slidingspans(res)
        @test ss !== nothing
        # RECORD the answer to W.5 open question 3:
        @info "new udg keys under slidingspans" setdiff(keys(udg(res)), keys(BASE_UDG))
    end
end

@testset "revision_history -- sae/sar reachable" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1),
                  spec_args = Dict("history.estimates" => "(sadj sadjchng)"))
        @test udg(res, "history") == "yes"
        h = revision_history(res)
        @test length(h.sa_estimates) > 0
    end
end

@testset "force -- saa totals match the original annual totals" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), force = :denton)
        saa = series(res, :saa)
        for yr in 0:11
            idx = (12yr + 1):(12yr + 12)
            @test sum(saa[idx]) ≈ sum(res.observed[idx]) rtol=1e-6
        end
    end
end

@testset "force -- unforced SA does NOT match annual totals (control)" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1))
        @test !isapprox(sum(res.seasonally_adjusted[1:12]),
                        sum(res.observed[1:12]); rtol = 1e-6)
    end
end

@testset "seasonalma -- accepted values render; a fixed filter changes D10" begin
    y = collect(100.0:1.0:243.0)
    for f in (:s3x1, :s3x3, :s3x5, :s3x9, :s3x15, :stable, :x11default, :msr)
        @test occursin("seasonalma", render(X13Spec(y; start=(1949,1), seasonalma=f)))
    end
    @test_throws ArgumentError X13Spec(y; start = (1949,1), seasonalma = :nonsense)
    if x13_binary_available()
        a = x13(AIRLINE_Y; start=(1949,1), seasonalma = :s3x3)
        b = x13(AIRLINE_Y; start=(1949,1), seasonalma = :s3x9)
        @test !(a.seasonal_factors ≈ b.seasonal_factors)
        @test udg(a, "sfmsr") != udg(b, "sfmsr") skip=true   # confirm key first
    end
end

@testset "summary -- composes without error and names the model" begin
    s = sprint(show, MIME"text/plain"(), summary(RESULT_FROM_FIXTURE))
    @test occursin("(0 1 1)(0 1 1)", s)
    @test occursin("144", s)
end

@testset "update -- changes one setting, preserves the rest" begin
    if x13_binary_available()
        base = x13(AIRLINE_Y; start = (1949,1), transform = :log)
        upd  = update(base; outlier = true)
        @test transformfunction(upd) === :log
        @test upd.spec.outlier == true
        @test base.spec.outlier == false        # original untouched
    end
end
```

---

## 11. Sequencing

```
COMMIT handoff/reference/x13-saveable-tables.md
  └─> W.7.1 widen _KNOWN_TABLES ──┬──> W.7.2 forecast/backcast ──> W.8 forecast plot
                                   ├──> W.7.4 components ────────> W.8 component plot
                                   ├──> W.7.5 vcov ──────────────> W.7.6 summary
                                   └──> W.7.8 slidingspans/history > W.8 stability plots
W.7.3 missing values   [independent]
W.7.7 force/seasonalma [independent, but confirm Manual Tables 7.15/7.55 first]
```

W.7.1 gates almost everything. W.7.8's first step (the udg diff) should run early
regardless of sequence, since it settles a question standing since W.5.

---

## 12. Open questions

1. **Does `series()` route `save` symbols to the right spec block?** W.7.4
   depends on `regression`-spec tables. If the re-run path hardcodes `x11`, that
   is a latent bug.
2. **Is `.rcm` under `save` really the covariance matrix?** The
   `sqrt.(diag(V)) ≈ stderror(r)` assertion decides it. If it fails, rescale from
   the correlation matrix using `stderror`.
3. **Do sliding-spans/history summaries appear in `.udg`?** W.5 open question 3.
   Test 10.6 records the answer.
4. **`force.target` and `seasonalma` accepted value lists.** Manual Tables 7.15
   and 7.55 were past the fetch limit. Confirm against the binary or a fuller
   copy of the manual before shipping W.7.7.
5. **Does `series { missingcode = }` accept a non-default value?** Only `-99999`
   is confirmed.
6. **AR and user-regressor coefficient key spelling** — still open from W.5. The
   forecast fixture in W.7.2 should use an AR-bearing model so this closes as a
   side effect.

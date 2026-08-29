# Handoff: W.5 — Diagnostics API and `seasonal`-Parity Functions

For a fresh session picking this up with no prior context. Same treatment as
W.0–W.4a: verified references first, full API design with every argument and
its accepted values, then an explicit test plan.

**Companion:** `handoff/w6-plot-recipes.md` (plots, deliberately separate).

---

## 0. Scope reality check — read this first

Part 1 (W.0–W.4a) is complete. The remaining gap against R's `seasonal` is
**almost entirely an accessor layer over data the package already retrieves.**

`x13()` already sets `udg=true` on every run and stores the result in
`X13Result.udg::Dict{String,String}`. The committed fixture
`handoff/udg_and_residuals/auto_test.udg` is 376 lines and contains, verified
by direct inspection this session:

| What R exposes | `.udg` key(s) | Fixture value |
|---|---|---|
| `AIC(x)` | `aic` | `0.946662093458382E+03` |
| `BIC(x)` | `bic` | `0.963913277397589E+03` |
| — | `aicc`, `hq` | `0.947339512813220E+03`, `0.953672020420599E+03` |
| `logLik(x)` | `loglikelihood` | `0.267963217574308E+03` |
| `nobs(x)` | `nobs`, `nefobs` | `144`, `131` |
| `coef(x)` | `1-Coefficient Trading Day$Weekday`, `Easter[1]$Easter[1]`, `MA$Nonseasonal$01$01`, `MA$Seasonal$12$12`, `AutoOutlier$AO1951.May` | each `est se t` |
| `outlier(x)` | `AutoOutlier$…`, `outlier.ao/.ls/.tc/.rp/.so/.tls/.total` | `AO1951.May`, `outlier.total: 1` |
| `transformfunction(x)` | `aictrans`, `transform` | `Log(y)`, `Automatic selection` |
| ARIMA model | `arimamdl` | `(0 1 1)(0 1 1)` |
| `fivebestmdl(x)` | `automdl.best5.mdl01`–`05`, `automdl.best5.bic01`–`05` | `(0 1 0)(0 1 1)`, `-4.007` |
| `qs(x)` | `qsori`, `qssadj`, `qsrsd`, `qsirr` (+ `qss*`, `*evadj` variants) | `167.64858 0.00000` |
| M-statistics, Q | `f3.m01`–`f3.m11`, `f3.q`, `f3.qm2`, `f3.fail` | `f3.m07: 0.203`, `f3.q: 0.20` |
| F-tests, MCD | `f2.fsb1`, `f2.fsd8`, `f2.kw`, `f2.msf`, `f2.ic`, `f2.is`, `f2.mcd`, `f2.idseasonal` | `f2.fsd8: 215.358 0.00` |
| Residual diagnostics | `durbinwatson`, `skewness`, `kurtosis`, `lbq`, `nlbq`, `sigacf`, `nsigacf` | `0.19503780E+01`, `0.0900`, `3.0698` |
| Spectral peaks | `peaks.seas`, `peaks.td`, `peaks.tukey.*` | `peaks.seas: rsd sa`, `peaks.td: sa irr` |
| Spectrum values | `spcori.s1`–`s5`, `spcori.t1`–`t2`, `spcori.dom`, `s1.freq`/`s1.index`, and the `spcsa.`/`spcirr.`/`spcrsd.` families | `spcori.s1: 21.0 +`, `s1.freq: 0.08333333` |
| Filters chosen | `seasonalma`, `finaltrendma`, `trendma`, `finalur` | `MSR ×12`, `9`, `default`, `none` |
| Mode / span | `samode`, `finmode`, `span`, `modelspan`, `nfcst`, `prioradj` | `multiplicative`, `1st month,1949 to 12th month,1960` |
| Convergence | `converged`, `niter`, `nreg`, `nmodel` | `yes`, `2`, `3`, `2` |
| Sliding spans / history run? | `sspans`, `history` | `no`, `no` |

**No HTML parsing is required for any of this.** That closes the concern the
W.4 addendum raised, in the same way it already closed the transform-resolution
question.

Two format facts confirmed from the fixture and needed throughout:

- Numbers are Fortran E-notation (`0.946662093458382E+03`). Julia's
  `parse(Float64, s)` handles this directly — no preprocessing.
- Several values are **multi-field**: `qsori` is `statistic p-value`;
  coefficient lines are `estimate std-error t-statistic`; `f2.fsb1` is
  `F p-value`; `spcori.s1` is `value flag` where the flag is `+`/`-`/blank.

---

## 1. Deliverables

| ID | Deliverable | Depends on | Est. |
|----|-------------|-----------|------|
| W.5.1 | Typed `.udg` accessor layer | — | ~200 LOC |
| W.5.2 | StatsAPI contract on `X13Result` | W.5.1 | ~80 LOC |
| W.5.3 | `series()` with automatic re-run | — | ~70 LOC |
| W.5.4 | Arbitrary spec passthrough (`spec_args`) | — | ~60 LOC |
| W.5.5 | `seasonal`-parity convenience functions | W.5.1 | ~120 LOC |
| W.5.6 | `select_order`, `out`, `import_spc` | W.5.4 | ~150 LOC |

W.5.4 is worth doing early: it retires the standing requests for named
`forecast`/`slidingspans`/`history` fields by making every unmodelled spec
block expressible.

---

## 2. W.5.1 — Typed `.udg` accessor layer

New file `src/diagnostics.jl`.

### Design principle

`parse_udg` stays exactly as it is — raw `Dict{String,String}`, no numeric
coercion, for the reasons its own docstring gives. This layer sits on top and
**never throws for a missing key**; it returns `nothing`. A `.udg` from a SEATS
run, a quarterly run, or a run without `automdl` legitimately lacks whole
families of keys, and an accessor that throws would make every caller wrap in
`haskey`.

### Private helpers

```julia
_udg_float(d, key)             -> Union{Float64,Nothing}
_udg_int(d, key)               -> Union{Int,Nothing}
_udg_fields(d, key)            -> Union{Vector{String},Nothing}   # whitespace split
_udg_floats(d, key)            -> Union{Vector{Float64},Nothing}
_udg_indexed(d, prefix, n)     -> Vector{Union{Float64,Nothing}}  # f3.m01..f3.m11
```

`_udg_indexed` handles the zero-padded families (`f3.m01`, not `f3.m7`) — a
formatting detail that will cause silent `nothing`s if missed.

### Public accessors

All take `X13Result` and dispatch to a `Dict` method so they're testable
against the fixture with no binary.

```julia
udg(r::X13Result)                          -> Dict{String,String}
udg(r::X13Result, key::AbstractString)     -> Union{String,Nothing}
udg(r::X13Result, keys::AbstractVector)    -> Dict{String,String}
```

Mirrors R's `udg(x, stats = NULL)`. Deliberately **not** matching R's
`simplify`/`fail` arguments: `fail` is unnecessary given the `nothing`
convention, and `simplify` is an R-vector idiom with no Julia analogue.

```julia
transformfunction(r)  -> Union{Symbol,Nothing}    # :log | :none
```

Reuse `static()`'s existing resolution exactly — the confirmed asymmetry where
`aictrans: Log(y)` appears only when log wins, and `transform` reads
`No transformation` otherwise. **Extract that logic from `static()` into this
function and have `static()` call it**, rather than duplicating.

| Return | Condition |
|---|---|
| `:log` | `aictrans == "Log(y)"` |
| `:none` | `transform == "No transformation"` |
| `:log` | `transform == "Log(y)"` (explicit, non-automatic spec) |
| `:none` | `transform == "None"` |
| `nothing` | anything else — never guess |

```julia
arima_model(r)  -> Union{String,Nothing}          # `arimamdl`, e.g. "(0 1 1)(0 1 1)"
```

```julia
mstats(r) -> Union{NamedTuple,Nothing}
# (m1=…, m2=…, …, m11=…, q=…, qm2=…, fail=…)
```

`f3.fail` is an `Int` count, the rest `Float64`. Return `nothing` only if `f3.q`
itself is absent (a SEATS run has no M-statistics at all).

```julia
qs(r; which = :all) -> NamedTuple
```

| `which` | Returns |
|---|---|
| `:all` (default) | `(original=…, sa=…, residual=…, irregular=…)`, each `(statistic, pvalue)` or `nothing` |
| `:original` | `(statistic, pvalue)` from `qsori` |
| `:sa` | from `qssadj` |
| `:residual` | from `qsrsd` |
| `:irregular` | from `qsirr` |

R's `qs()` returns all rows as a matrix; `:all` is the closer analogue.
Deliberately does **not** expose the `qss*` (extreme-value-adjusted) and
`*evadj` variants at this level — add later if a caller needs them; they are
still reachable through `udg(r, "qssori")`.

```julia
outliers(r; full = false) -> Vector{NamedTuple}
```

Parses `AutoOutlier$<TYPE><YEAR>.<MONTH>` keys. `AO1951.May` in the fixture.
W.4a already confirmed that stripping the `AutoOutlier$` prefix yields a string
the binary re-accepts verbatim, so **do not convert the month name to a number**.

| `full` | Element shape |
|---|---|
| `false` (default) | `(label="AO1951.May", type=:ao, year=1951, period=5)` |
| `true` | above plus `estimate`, `stderror`, `tstat` from the three value fields |

Matches R's `outlier(x, full = FALSE)`. Type symbols: `:ao`, `:ls`, `:tc`,
`:rp`, `:so`, `:tls`. Also expose the counts:

```julia
outlier_counts(r) -> NamedTuple   # (ao=, ls=, tc=, rp=, so=, tls=, total=)
```

```julia
fivebestmdl(r) -> Union{Vector{NamedTuple},Nothing}
# [(model="(0 1 0)(0 1 1)", bic=-4.007), …] — up to 5, in rank order
```

Reads `automdl.best5.mdl01`–`05` paired with `automdl.best5.bic01`–`05`. Returns
`nothing` when `automdl` didn't run. Stops at the first missing index rather
than assuming five.

```julia
seasonality_tests(r) -> Union{NamedTuple,Nothing}
# (stable_f = (F, p),          # f2.fsb1
#  stable_d8_f = (F, p),       # f2.fsd8
#  kruskal_wallis = (χ², p),   # f2.kw
#  moving_seasonality = (F, p),# f2.msf
#  identifiable = true/false)  # f2.idseasonal, "yes"/"no"
```

Nothing in R's `seasonal` exposes these as a function — they're summary output
only. This is a genuine addition, not just parity.

```julia
residual_diagnostics(r) -> NamedTuple
# (durbin_watson=, skewness=, kurtosis=, ljung_box=, n_ljung_box=,
#  n_sig_acf=, n_sig_pacf=)
```

```julia
spectral_peaks(r) -> NamedTuple
# (seasonal = [:rsd, :sa], trading_day = [:sa, :irr])
```

`peaks.seas: rsd sa` → the series in which a visually significant seasonal peak
remains. Empty vector when the key value is `none` or absent. This is what the
Python pipeline scraped from HTML as `trading_day_peak_warning`.

```julia
filters(r) -> NamedTuple
# (seasonal_ma = ["MSR", …], trend_ma = 9, mode = :multiplicative,
#  sa_mode = "auto-mode seasonal adjustment", unit_root = "none")
```

### Explicitly deferred

Spectrum *values* (`spcori.s1`–`s5`, `s1.freq`/`s1.index`, and the `spcsa.`/
`spcirr.`/`spcrsd.` families) are parsed in the plot handoff, not here — they're
only useful as a chart. `d8b.*` and `d9a.*` likewise.

---

## 3. W.5.2 — StatsAPI contract on `X13Result`

TSAnalytics' design principle 1 is "StatsAPI-first" and `ARXModel` honours the
full contract. `X13Result` currently honours none of it. Every value needed is
in `.udg` per §0.

```julia
StatsAPI.aic(r::X13Result)             -> Float64
StatsAPI.bic(r::X13Result)             -> Float64
StatsAPI.aicc(r::X13Result)            -> Float64
StatsAPI.loglikelihood(r::X13Result)   -> Float64
StatsAPI.nobs(r::X13Result)            -> Int         # `nobs`
StatsAPI.residuals(r::X13Result)       -> Vector{Float64}   # already a field
StatsAPI.coef(r::X13Result)            -> Vector{Float64}
StatsAPI.coefnames(r::X13Result)       -> Vector{String}
StatsAPI.stderror(r::X13Result)        -> Vector{Float64}
StatsAPI.dof(r::X13Result)             -> Int         # `nreg` + `nmodel`
```

### Coefficient extraction

The coefficient block is identified by lines whose key contains `$` and whose
value splits into exactly three parseable floats. From the fixture:

```
1-Coefficient Trading Day$Weekday: +0.294969914081430E-02 … …
Easter[1]$Easter[1]:               +0.177673735674792E-01 … …
AutoOutlier$AO1951.May:            +0.100155824411322E+00 … …
MA$Nonseasonal$01$01:              +0.11562041392576E+00  … …
MA$Seasonal$12$12:                 +0.49736001930226E+00  … …
```

Note `MA$Nonseasonal$01$01` has **four** `$`-separated segments, not two. The
name for `coefnames` should be the full key minus any leading `N-Coefficient `
prefix, so the fixture yields
`["Trading Day$Weekday", "Trading Day$Sat/Sun", "Easter[1]", "AO1951.May", "MA$Nonseasonal$01$01", "MA$Seasonal$12$12"]`.
Ordering must be deterministic — **sort by the key's line order in the file, not
by `Dict` iteration order**, which means `parse_udg` needs to preserve order or
the accessor needs to re-read. Prefer the latter: an `_udg_ordered_keys(path)`
helper, or change `parse_udg` to return an `OrderedDict`-like structure. Flag
this as a decision point; a `Dict` was the right call for W.4a's purposes and
this is the first caller that cares.

`vcov` is **not** implementable — `.udg` carries standard errors but no
covariance matrix. Define it to throw a clear named error saying so, in the same
style as `durbin_watson_test(method=:exact)` and `fit_garch(dist=:t)`.

Also add `Base.show(io, ::MIME"text/plain", r::X13Result)` — a compact summary
in the shape of R's `summary.seas`: model, transform, N, AIC/BIC, Q, and the
outlier count. Use `StatsBase.CoefTable` for the coefficient block, matching
`ARXModel`.

---

## 4. W.5.3 — `series()` with automatic re-run

R's `series(x, "d8")` notices the table wasn't saved, re-runs with it added, and
returns it. SA currently forces the user down to
`X13Spec`/`run_x13`/`parse_output` and rebuild the spec by hand, because `x13()`
rejects `save=` outright.

```julia
series(r::X13Result, table::Symbol; reeval = true) -> Vector{Float64}
series(r::X13Result, tables::AbstractVector{Symbol}; reeval = true)
    -> Dict{Symbol,Vector{Float64}}
```

| `reeval` | Behaviour |
|---|---|
| `true` (default) | If `table` isn't in `r.spec.save`, build `X13Spec(r.spec; save = union(existing, requested))`, re-run, and return. Matches R's default. |
| `false` | Throw `ArgumentError` naming the table and telling the caller to add it to `save`. Matches R's `reeval = FALSE`. |

R also has `verbose = TRUE`, which prints a note when it re-runs. Use `@info`
rather than a keyword — the Julia idiom, and it's suppressible through the
logging system.

**Design note.** The `X13Spec(base; kwargs...)` copy-constructor already exists
(added for `static()` in W.4a), so this needs no new spec machinery. Cache the
re-run result on the returned object or document plainly that repeated calls
re-run; R caches, and a caller looping over ten tables would otherwise spawn ten
subprocesses.

Accepted table symbols should be validated against the union of X-11 (`:d8`,
`:d9`, `:d10`–`:d13`, `:c17`, `:b1`, …), SEATS (`:s10`–`:s13`, `:s14`–`:s18`)
and regARIMA (`:rsd`, `:fct`, `:fvr`) tables, with an error naming the closest
match on a typo. Do not silently pass an unknown symbol to the binary.

---

## 5. W.5.4 — Arbitrary spec passthrough

R's `...` means `seasonal` never needs updating when someone wants a spec block
the author didn't anticipate. SA's named-field design means `forecast`,
`slidingspans`, `history`, `check`, `pickmdl`, `force` and every other block are
currently inexpressible.

Add one field to `X13Spec`:

```julia
spec_args::Dict{String,String}    # "forecast.maxlead" => "0"
```

and a matching kwarg accepting either form:

```julia
X13Spec(y; spec_args = Dict("forecast.maxlead" => "0",
                            "slidingspans" => "",
                            "history.estimates" => "(sadj sadjchng)"))
```

### Rendering rules

1. Group by the part before the first `.` — that's the block name.
2. A key with **no** dot and an empty value renders as an empty block:
   `slidingspans { }`.
3. Values are emitted **verbatim**, no quoting or escaping. This is a raw
   passthrough by design, exactly like `arima_model`, and its docstring should
   say so in the same words: `validate!` will not catch a syntax error here, the
   binary will.
4. A `spec_args` key naming a block a typed field already renders (`transform`,
   `x11`, `automdl`, `regression`, `estimate`, `series`, `arima`, `seats`,
   `outlier`) must throw at `validate!` time. Two sources of truth for one block
   is the silent-misconfiguration case worth failing loudly on.

This is the cleanest resolution of the standing `forecast`/`slidingspans`/
`history` requests: three named fields become one general mechanism, and the
`maxlead` default question below becomes the caller's, not the package's.

### The `maxlead` question, resolved

Both reference pipelines force `forecast.maxlead = 0` whenever a user regressor
is present, because R's `seasonal` **cannot extend a user regressor past the
sample end**. SA embeds regressor data inline and `validate!` already requires
it to cover the series plus one forecast horizon — so SA *can* extend and
forecast properly.

**Recommendation: change nothing by default.** Do not force `maxlead = 0`. Users
wanting R parity write `spec_args = Dict("forecast.maxlead" => "0")`. Document
the divergence in `X13Spec`'s docstring, in the same style as `partrans`
documenting its deliberate choice of R's convention over Python's. Then add a
crossval case both ways so the divergence is tested, not assumed.

---

## 6. W.5.5 / W.5.6 — Remaining parity functions

```julia
select_order(y; kwargs...) -> NamedTuple
# (order = (p,d,q), seasonal_order = (P,D,Q,s), transform = :log)
```

Matches `statsmodels.tsa.x13.x13_arima_select_order`. Thin: run with
`automdl`, parse `arimamdl`, return. Accepts the same kwargs as `x13()`.

```julia
open_output(r::X13Result)     # R's `out()`
```

Writes the HTML output and opens it with the platform handler
(`xdg-open`/`open`/`start`). Guard behind a check that the file exists; the
binary only writes it on a successful run.

```julia
import_spc(path) -> X13Spec
```

R's `import.spc()`. Real migration value for anyone arriving from R or Census
tooling with existing `.spc` files. Parse blocks into the typed fields where one
exists, everything else into `spec_args` (W.5.4). **Sequence this last** — it is
the only item here that needs a real parser rather than a lookup, and it depends
on W.5.4 existing.

Deliberately **not** in scope: `composite` (multi-series composite adjustment),
`na.action` (a package-wide missing-data policy, tracked separately), `view()`
(a Shiny app, no Julia analogue worth building), `identify()` (interactive
click-loop, tied to R's base graphics event model).

---

## 7. Test plan

Follow the existing split: structural tests run everywhere; anything needing
the binary is gated on `x13_binary_available()`. New file `test/test_diagnostics.jl`,
added to `runtests.jl` after `test_api.jl`.

### 7.1 Accessors against the committed fixture — no binary needed

The fixture `handoff/udg_and_residuals/auto_test.udg` makes the entire accessor
layer testable with zero subprocess calls. Every value below was read from it
directly this session and can be asserted as a literal.

```julia
@testset "udg accessors -- committed fixture, no binary" begin
    d = parse_udg(joinpath(@__DIR__, "..", "handoff", "udg_and_residuals", "auto_test.udg"))

    # --- scalars, Fortran E-notation parses natively
    @test _udg_float(d, "aic")           ≈ 946.662093458382
    @test _udg_float(d, "bic")           ≈ 963.913277397589
    @test _udg_float(d, "aicc")          ≈ 947.339512813220
    @test _udg_float(d, "hq")            ≈ 953.672020420599
    @test _udg_float(d, "loglikelihood") ≈ 267.963217574308
    @test _udg_int(d, "nobs")            == 144
    @test _udg_int(d, "nefobs")          == 131
    @test _udg_int(d, "nreg")            == 3
    @test _udg_int(d, "nmodel")          == 2

    # --- missing keys return nothing, never throw
    @test _udg_float(d, "no.such.key")   === nothing
    @test _udg_int(d,   "no.such.key")   === nothing

    # --- transform resolution (the W.4a asymmetry)
    @test transformfunction(d) === :log      # aictrans == "Log(y)"
    @test d["transform"] == "Automatic selection"   # top-level stays generic

    # --- ARIMA model
    @test arima_model(d) == "(0 1 1)(0 1 1)"

    # --- M-statistics: zero-padded keys
    m = mstats(d)
    @test m.m7 ≈ 0.203
    @test m.q  ≈ 0.20
    @test m.qm2 ≈ 0.22
    @test m.fail == 0
    @test length(filter(!isnothing, [m.m1,m.m2,m.m3,m.m4,m.m5,m.m6,
                                     m.m7,m.m8,m.m9,m.m10,m.m11])) == 11

    # --- QS: two fields per key
    q = qs(d)
    @test q.original.statistic ≈ 167.64858
    @test q.original.pvalue    ≈ 0.0
    @test q.sa.statistic       ≈ 0.0
    @test q.sa.pvalue          ≈ 1.0
    @test q.residual.pvalue    ≈ 1.0
    @test qs(d; which = :original).statistic ≈ 167.64858

    # --- outliers
    o = outliers(d)
    @test length(o) == 1
    @test o[1].label  == "AO1951.May"      # month name NOT converted (W.4a)
    @test o[1].type   === :ao
    @test o[1].year   == 1951
    of = outliers(d; full = true)[1]
    @test of.estimate ≈ 0.100155824411322
    @test of.stderror ≈ 0.0204386646810968
    @test of.tstat    ≈ 4.90031154060440
    c = outlier_counts(d)
    @test c.ao == 1 && c.ls == 0 && c.total == 1

    # --- five best models
    fb = fivebestmdl(d)
    @test length(fb) == 5
    @test fb[1].model == "(0 1 0)(0 1 1)"
    @test fb[1].bic   ≈ -4.007
    @test issorted([f.bic for f in fb])          # rank order preserved

    # --- seasonality F-tests
    s = seasonality_tests(d)
    @test s.stable_d8_f == (215.358, 0.00)
    @test s.stable_f    == (164.889, 0.00)
    @test s.kruskal_wallis == (132.948, 0.00)
    @test s.moving_seasonality == (3.557, 0.02)
    @test s.identifiable === true                 # "yes"

    # --- residual diagnostics
    rd = residual_diagnostics(d)
    @test rd.durbin_watson ≈ 1.9503780
    @test rd.skewness ≈ 0.0900
    @test rd.kurtosis ≈ 3.0698
    @test rd.n_sig_acf == 2

    # --- spectral peaks (what the Python pipeline scraped from HTML)
    sp = spectral_peaks(d)
    @test sp.seasonal     == [:rsd, :sa]
    @test sp.trading_day  == [:sa, :irr]

    # --- filters
    f = filters(d)
    @test f.trend_ma == 9
    @test f.mode === :multiplicative
    @test all(==("MSR"), f.seasonal_ma)
    @test length(f.seasonal_ma) == 12
end
```

### 7.2 Accessor edge cases

```julia
@testset "udg accessors -- absent families return nothing, not errors" begin
    d = Dict("nobs" => "144")                       # a near-empty udg
    @test mstats(d)             === nothing          # SEATS run: no f3.*
    @test fivebestmdl(d)        === nothing          # no automdl
    @test seasonality_tests(d)  === nothing
    @test outliers(d)           == NamedTuple[]      # empty, not nothing
    @test outlier_counts(d).total === nothing
    @test spectral_peaks(d).seasonal == Symbol[]
end

@testset "transformfunction -- all four confirmed strings, and no guessing" begin
    @test transformfunction(Dict("aictrans" => "Log(y)"))            === :log
    @test transformfunction(Dict("transform" => "No transformation")) === :none
    @test transformfunction(Dict("transform" => "Log(y)"))            === :log
    @test transformfunction(Dict("transform" => "None"))              === :none
    @test transformfunction(Dict("transform" => "Square root"))       === nothing
    @test transformfunction(Dict{String,String}())                    === nothing
end

@testset "fivebestmdl -- stops at first gap, doesn't assume 5" begin
    d = Dict("automdl.best5.mdl01" => "(0 1 1)(0 1 1)", "automdl.best5.bic01" => "-4.0",
             "automdl.best5.mdl02" => "(1 1 0)(0 1 1)", "automdl.best5.bic02" => "-3.9")
    @test length(fivebestmdl(d)) == 2
end

@testset "outliers -- every type symbol round-trips" begin
    for (key, sym) in [("AO1951.May", :ao), ("LS1960.Jan", :ls), ("TC1955.Dec", :tc),
                       ("RP1958.Mar", :rp), ("SO1957.Jun", :so), ("TLS1959.Feb", :tls)]
        d = Dict("AutoOutlier\$$key" => "+0.1E+00 +0.2E-01 +0.5E+01")
        o = outliers(d)[1]
        @test o.label == key && o.type === sym
    end
end
```

### 7.3 StatsAPI contract

```julia
@testset "StatsAPI on X13Result -- fixture-backed" begin
    r = _result_from_fixture()      # helper: X13Result with udg from the fixture
    @test aic(r)  ≈ 946.662093458382
    @test bic(r)  ≈ 963.913277397589
    @test loglikelihood(r) ≈ 267.963217574308
    @test nobs(r) == 144
    @test dof(r)  == 5                      # nreg 3 + nmodel 2

    @test length(coef(r)) == length(coefnames(r)) == length(stderror(r))
    @test "Easter[1]" in coefnames(r)
    @test "MA\$Seasonal\$12\$12" in coefnames(r)      # four-segment key survives
    i = findfirst(==("AO1951.May"), coefnames(r))
    @test coef(r)[i]     ≈ 0.100155824411322
    @test stderror(r)[i] ≈ 0.0204386646810968

    # ordering is file order, not Dict order -- run twice, must match
    @test coefnames(r) == coefnames(r)
    @test coefnames(_result_from_fixture()) == coefnames(r)

    @test_throws ErrorException vcov(r)      # named error, not a wrong answer
end

@testset "show(::X13Result) -- summary block" begin
    r = _result_from_fixture()
    s = sprint(show, MIME"text/plain"(), r)
    @test occursin("(0 1 1)(0 1 1)", s)
    @test occursin("Log", s)
    @test occursin("144", s)
end
```

### 7.4 `series()` — needs the binary

```julia
if x13_binary_available()
@testset "series() -- re-runs for an unsaved table" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0,1,1,12))
    @test !(:d8 in something(r.spec.save, Symbol[]))
    d8 = series(r, :d8)                       # must re-run, not throw
    @test length(d8) == length(r.observed)
    @test all(isfinite, d8)
end

@testset "series() -- already-saved table does NOT re-run" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0,1,1,12))
    @test series(r, :d10) == r.seasonal_factors
end

@testset "series(reeval=false) -- throws naming the table" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0,1,1,12))
    @test_throws ArgumentError series(r, :d8; reeval = false)
end

@testset "series() -- vector form, one re-run not N" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0,1,1,12))
    out = series(r, [:d8, :d9, :c17])
    @test Set(keys(out)) == Set([:d8, :d9, :c17])
end

@testset "series() -- unknown table errors before spawning" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0,1,1,12))
    @test_throws ArgumentError series(r, :d99)
end
end
```

### 7.5 `spec_args` passthrough

```julia
@testset "spec_args -- renders a block with no typed field" begin
    s = X13Spec(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12),
                spec_args = Dict("forecast.maxlead" => "0"))
    txt = render(s)
    @test occursin("forecast {", txt)
    @test occursin("maxlead = 0", txt)
end

@testset "spec_args -- dotless key with empty value renders an empty block" begin
    s = X13Spec(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12),
                spec_args = Dict("slidingspans" => ""))
    @test occursin("slidingspans { }", render(s))
end

@testset "spec_args -- multiple keys group into one block" begin
    s = X13Spec(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12),
                spec_args = Dict("history.estimates" => "(sadj sadjchng)",
                                 "history.savelog"   => "all"))
    txt = render(s)
    @test count("history {", txt) == 1
    @test occursin("estimates = (sadj sadjchng)", txt)
    @test occursin("savelog = all", txt)
end

@testset "spec_args -- collision with a typed block throws at validate!" begin
    for k in ["transform.function", "x11.save", "automdl.maxorder",
              "regression.variables", "estimate.save", "series.title",
              "arima.model", "seats.save", "outlier.types"]
        @test_throws ArgumentError X13Spec(AIRLINE_Y; start = (1949,1),
            seasonal_order = (0,1,1,12), spec_args = Dict(k => "x"))
    end
end

@testset "spec_args -- values pass through verbatim, no quoting" begin
    s = X13Spec(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12),
                spec_args = Dict("check.print" => "(acf pacf)"))
    @test occursin("print = (acf pacf)", render(s))
end

if x13_binary_available()
@testset "spec_args -- slidingspans/history actually run and populate udg" begin
    r = x13(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12),
            spec_args = Dict("slidingspans" => "",
                             "history.estimates" => "(sadj sadjchng)"))
    @test r.udg["sspans"]  == "yes"      # fixture has "no" for a plain run
    @test r.udg["history"] == "yes"
end

@testset "spec_args -- a syntactically invalid block surfaces the binary's error" begin
    @test_throws ErrorException x13(AIRLINE_Y; start = (1949,1),
        seasonal_order = (0,1,1,12), spec_args = Dict("forecast.maxlead" => "banana"))
end

@testset "maxlead -- default is NOT forced to 0, and 0 is reachable" begin
    r_default = x13(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12))
    r_zero    = x13(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12),
                    spec_args = Dict("forecast.maxlead" => "0"))
    @test r_default.udg["nfcst"] != r_zero.udg["nfcst"]
end
end
```

### 7.6 Cross-validation against R — extend the existing grid

`test/extended/` already has `CrossvalCase`, `r_helper.R` and
`python_helper.py`. Extend rather than duplicate.

| Case | R call | Assert |
|---|---|---|
| AIC/BIC/logLik | `AIC(m)`, `BIC(m)`, `logLik(m)` | match to `1e-6` |
| Coefficients | `coef(m)` | same names (modulo R's naming), same values to `1e-8` |
| Outliers | `outlier(m, full = TRUE)` | same labels, same est/se/t |
| Transform | `transformfunction(m)` | `:log` ↔ `"log"` |
| Five best | `fivebestmdl(m)` | same 5 models in the same order |
| QS | `qs(m)` | same statistics and p-values |
| `series` | `series(m, "d8")` | element-wise to the grid's existing 2e-3 tolerance |
| `spc` | `spc(m)` | **the diff worth having** — R's rendered spec vs `render(spec)` |

The `spc(m)` comparison is the single highest-value case: it pins down every
default `seas()` injects that SA may or may not match, in one artifact. Commit
R's output as a fixture so the comparison runs without R installed.

Expected, documented divergences to assert rather than "fix":

- `forecast.maxlead` — R forces `0` with `xreg`, SA does not (§5)
- `regression.aictest` — R defaults to `c("td","easter")`, SA to `Symbol[]`
- Holiday regressor — `custom_holiday_regressor` drops weekend-falling holidays;
  R's `genhol` does not

---

## 8. Sequencing

```
W.5.4 spec_args ──┬──> W.5.6 import_spc
                  └──> (retires forecast/slidingspans/history requests)

W.5.1 udg accessors ──┬──> W.5.2 StatsAPI + show
                      └──> W.5.5 qs/outliers/fivebestmdl/transformfunction

W.5.3 series()  [independent]
```

**Do W.5.1 first.** It is fixture-testable with no binary, it unblocks two other
items, and it converts `static()`'s private extraction into tested public
surface.

---

## 9. Open questions

1. **Key ordering.** `coefnames`/`coef` need file order, which `Dict` doesn't
   preserve. Change `parse_udg` to keep order, add a separate ordered-key
   helper, or sort by a derived rule? Changing `parse_udg`'s return type is a
   breaking change to a W.4a-tested function — prefer the helper.
2. **`series()` caching.** Cache the re-run on the result, or document that
   repeated calls re-run? R caches. Caching needs `X13Result` to be mutable or
   to carry a `Dict` scratch field.
3. Does `.udg` for a **SEATS** run carry `f3.*` at all, or does `mstats` always
   return `nothing` there? Only one X-11 fixture is committed — generate a SEATS
   one and commit it alongside.
4. Does a **quarterly** `.udg` change any key names (`f3.m01`–`m11` presumably
   still 11, but `seasonalma` has 4 entries not 12)? Commit a quarterly fixture.
5. `coefnames` collision: two trading-day coefficients share the
   `1-Coefficient Trading Day$` prefix (`Weekday`, `Sat/Sun`). Confirmed
   distinct in the fixture, but check a `td` spec with all six regressors.
6. Should `select_order` re-use `x13()` or run a leaner spec (no `x11`) for
   speed? R has no equivalent; Python's runs the full analysis.

# Handoff: W.8 — Remaining Chart Gaps

For a fresh session with no prior context. Extends W.6's four recipes.

**Depends on:** W.6 (recipe infrastructure), W.7 (forecast, components, slidingspans accessors)
**Companion:** `w7-functionality-gaps-handoff.md`
**Reference:** `handoff/reference/x13-saveable-tables.md`

---

## 0. Where W.6 left things

Four recipes exist, all via `RecipesBase.@userplot`: `plot` (overlay and
components), `residplot`, `monthplot`, `spectrumplot`. That is already one more
than R's `seasonal` ships.

Two W.6 findings carry forward and must not be relearned:

- **`RecipesBase.is_key_supported` has no fallback method** until a real backend
  defines one, and `@recipe`'s generated keyword-cleanup hits it for any recipe
  with keyword arguments. `test/test_plots.jl` stubs
  `RecipesBase.is_key_supported(::Symbol) = true`. Every recipe below has
  keywords, so all of them need that stub in place.
- **Plain series-type `Val{:name}` recipes do not work here.** W.6 confirmed a
  bare type recipe on `X13Result` silently shadows the named recipes.
  `@userplot` is the working construct — follow it.

---

## 1. Deliverables

| ID | Recipe | Blocked on | Effort |
|----|--------|-----------|--------|
| W.8.1 | `seasonalplot` — year-over-year | — | ~70 LOC |
| W.8.2 | `forecastplot` | W.7.2 | ~60 LOC |
| W.8.3 | `residdiagplot` — ACF + normality panel | — (`.acf`/`.pcf` are saveable) | ~90 LOC |
| W.8.4 | `componentplot` — TD / holiday / outlier factors | W.7.4 | ~50 LOC |
| W.8.5 | `spanplot` — sliding spans / revision history | W.7.8 | ~80 LOC |

W.8.1 and W.8.3 are unblocked and can start immediately.

---

## 2. W.8.1 — `seasonalplot`

**The genuinely missing chart, and the only one here with real geometry.**

`monthplot` is a *subseries* plot: one band per calendar period, points within
the band. `seasonalplot` is its transpose — calendar period on the x-axis, one
line per year, all overlaid. R's `forecast::ggseasonplot` / `feasts::gg_season`.

They answer different questions. Subseries shows whether a given month's *level*
has drifted. Seasonal shows whether the *shape of the year* is changing, which
is what makes an evolving seasonal pattern obvious at a glance. Nothing in the
Julia ecosystem provides either.

```julia
RecipesBase.@userplot SeasonalPlot
@recipe function f(sp::SeasonalPlot; series = :seasonal, polar = false, highlight = nothing)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `series` | `:observed`, `:seasonal`, `:sa`, `:trend`, `:irregular` | `:seasonal` | Which component to lay out |
| `polar` | `true`, `false` | `false` | Wrap onto a polar axis (`gg_season`'s `polar=TRUE`) |
| `highlight` | `nothing`, `:last`, `Int`, `Vector{Int}` | `nothing` | Emphasise given year(s); everything else drawn muted |

### Geometry

One series per calendar year. x = period index `1:period`, y = that year's
values. Partial years at either end plot short rather than being dropped — a
truncated final year is exactly what a user wants to see.

```julia
_seasonal_layout(values, dates, period) ->
    Vector{@NamedTuple{year::Int, x::Vector{Int}, y::Vector{Float64}}}
```

Ticks `Jan`–`Dec` or `Q1`–`Q4`, same labels `monthplot` already produces —
**reuse that helper, don't write a second one.**

Year labelling: R places the year at each line's right end rather than in a
legend, which matters when there are 12+ years. Set `label` per series and let
the backend decide; note the divergence from R in the docstring.

### Shared design with TSAnalytics

W.6 §7 established that `_subseries_layout` is deliberately period-generic and
`X13Result`-free so it can move to TSA later. `_seasonal_layout` must be written
the same way — it takes values, dates and period, nothing else. TSA needs both
for `STLDecomposition` and plain series.

---

## 3. W.8.2 — `forecastplot`

```julia
RecipesBase.@userplot ForecastPlot
@recipe function f(fp::ForecastPlot; backcast = false, level = 0.95, history = nothing)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `backcast` | `true`, `false` | `false` | Also draw the backcast extension |
| `level` | `Float64` in (0,1) | `0.95` | Interval width, passed to `forecast()` |
| `history` | `nothing`, `Int` | `nothing` | Show only the last *n* observations before the forecast |

Observed series, then the forecast extension as a distinct series, with the
prediction interval as a shaded ribbon between `lower` and `upper`.

**The join matters.** The forecast line must connect to the last observed point,
not start floating one period later. Prepend `(dates[end], observed[end])` to
the forecast series. The ribbon does *not* get that treatment — it starts at the
first forecast period, since there is no interval at a known observation.

W.7.2 confirmed `.fct` already carries point, lower and upper on the original
scale, so nothing needs back-transforming here.

---

## 4. W.8.3 — `residdiagplot`

The standard X-13 residual review panel. W.7's reference work surfaced that the
inputs come **straight from the binary** rather than needing recomputation:

| Save keyword | Ext | Contents |
|---|---|---|
| `check.acf` | `.acf` | residual ACF with standard errors and Ljung-Box Q per lag |
| `check.pacf` | `.pcf` | residual PACF with standard errors |
| `check.acfsquared` | `.ac2` | ACF of squared residuals (ARCH check) |

Plus `skewness`, `kurtosis`, `durbinwatson`, `normalitytest` already in `.udg`.

```julia
RecipesBase.@userplot ResidDiagPlot
@recipe function f(rd::ResidDiagPlot; panels = [:series, :acf, :histogram], lags = 24)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `panels` | any of `:series`, `:acf`, `:pacf`, `:acfsquared`, `:histogram`, `:qq` | `[:series, :acf, :histogram]` | Which panels, in order |
| `lags` | `Int` | `24` | Lags for the ACF/PACF panels |

Use the binary's own `.acf`/`.pcf` rather than recomputing from `r.residuals` —
that way the bands match what X-13 itself reports, and the Ljung-Box column is
consistent with `lbq$*` in `.udg`.

`:qq` needs a normal quantile function. `TSAnalytics` is already a dependency
and has `jarque_bera_test`; check whether it exposes a normal quantile before
adding any new dependency for this.

---

## 5. W.8.4 — `componentplot`

```julia
RecipesBase.@userplot ComponentPlot
@recipe function f(cp::ComponentPlot; which = :all, reference = true)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `which` | `:all`, `:trading_day`, `:holiday`, `:user`, `:outlier` | `:all` | Which factor series, via W.7.4's `components()` |
| `reference` | `true`, `false` | `true` | Draw the no-effect line — `1.0` multiplicative, `0.0` additive |

The reference line must follow the decomposition mode: read `finmode` from
`.udg` (the fixture shows `finmode: multiplicative`) rather than assuming.

Components absent from the model are skipped silently, not drawn as flat lines.
Under `which = :all` with no regression effects at all, throw a clear
`ArgumentError` rather than emitting an empty plot.

**This is the chart that closes the India-calendar loop.** `coef()` gives the
Diwali coefficient; this shows its month-by-month path.

---

## 6. W.8.5 — `spanplot`

```julia
RecipesBase.@userplot SpanPlot
@recipe function f(sp::SpanPlot; kind = :slidingspans, estimate = :seasonal)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `kind` | `:slidingspans`, `:history` | `:slidingspans` | Which diagnostic |
| `estimate` | `:seasonal`, `:sa`, `:change`, `:yearchange`, `:trend` | `:seasonal` | Which quantity |

Sliding spans: each span's estimate as its own line, so divergence between spans
is visible directly. History: concurrent versus most-recent estimate, with the
revision as a second panel.

Do this last. It is blocked on W.7.8, whose own scope depends on an unanswered
question (whether the summaries land in `.udg`).

---

## 7. Test plan

`test/test_plots.jl`, extending W.6's structure. Same three levels: Level 1
`apply_recipe` with no backend, Level 2 numeric correctness, Level 3 opt-in
real-backend smoke tests behind `SEASONALADJUSTMENT_EXTENDED_TESTS=1`.

The `RecipesBase.is_key_supported(::Symbol) = true` stub and the `_apply_named`
helper already exist at the top of that file — reuse them.

### 7.1 `seasonalplot`

```julia
@testset "seasonalplot -- one series per year" begin
    rd = _apply_named(:seasonalplot, RESULT)
    @test length(rd) == 12                       # 1949-1960, 144 obs
end

@testset "seasonalplot -- x is the period index, not a date" begin
    rd = _apply_named(:seasonalplot, RESULT)
    @test rd[1].args[1] == collect(1:12)
    @test eltype(rd[1].args[1]) <: Integer
end

@testset "seasonalplot -- each line carries that year's values in order" begin
    rd = _apply_named(:seasonalplot, RESULT; series = :seasonal)
    @test rd[1].args[2] ≈ RESULT.seasonal_factors[1:12]
    @test rd[12].args[2] ≈ RESULT.seasonal_factors[133:144]
end

@testset "seasonalplot -- IS the transpose of monthplot" begin
    # the property that makes this a distinct chart, not a restyling
    sp = _apply_named(:seasonalplot, RESULT)
    mp = _apply_named(:monthplot, RESULT; siratios = false)
    @test length(sp) == 12                        # 12 years
    @test length(first(sp[1].args[2])) == 1       # scalar per period
    @test length(sp[1].args[1]) == 12             # 12 periods per line
    @test length(mp[1].args[1]) == 12             # 12 years per band
    @test sort(vcat([d.args[2] for d in sp]...)) ≈
          sort(vcat([d.args[2] for d in first(mp, 12)]...))   # same data
end

@testset "seasonalplot -- partial final year plots short, is not dropped" begin
    rd = _apply_named(:seasonalplot, RAGGED_RESULT)   # 145 obs
    @test length(rd) == 13
    @test length(rd[13].args[1]) == 1
end

@testset "seasonalplot -- quarterly gives 4 x-positions and Q labels" begin
    rd = _apply_named(:seasonalplot, QUARTERLY_RESULT)
    @test rd[1].args[1] == collect(1:4)
    @test rd[1].plotattributes[:xticks][2] == ["Q1", "Q2", "Q3", "Q4"]
end

@testset "seasonalplot -- monthly tick labels reuse monthplot's helper" begin
    a = _apply_named(:seasonalplot, RESULT)[1].plotattributes[:xticks][2]
    b = _apply_named(:monthplot,    RESULT)[1].plotattributes[:xticks][2]
    @test a == b == ["Jan","Feb","Mar","Apr","May","Jun",
                     "Jul","Aug","Sep","Oct","Nov","Dec"]
end

@testset "seasonalplot -- series selector picks the right component" begin
    for (sym, fld) in ((:observed, :observed), (:sa, :seasonally_adjusted),
                       (:trend, :trend), (:irregular, :irregular),
                       (:seasonal, :seasonal_factors))
        rd = _apply_named(:seasonalplot, RESULT; series = sym)
        @test rd[1].args[2] ≈ getfield(RESULT, fld)[1:12]
    end
    @test_throws ArgumentError _apply_named(:seasonalplot, RESULT; series = :bogus)
end

@testset "seasonalplot -- highlight mutes the rest" begin
    rd = _apply_named(:seasonalplot, RESULT; highlight = :last)
    alphas = [get(d.plotattributes, :alpha, 1.0) for d in rd]
    @test alphas[end] > alphas[1]
    rd2 = _apply_named(:seasonalplot, RESULT; highlight = [1949, 1960])
    @test count(a -> a == maximum(alphas), [get(d.plotattributes, :alpha, 1.0) for d in rd2]) == 2
end

@testset "seasonalplot -- layout helper is X13Result-free and period-generic" begin
    L = SeasonalAdjustment._seasonal_layout(collect(1.0:24.0),
            [Date(1949,1) + Dates.Month(i) for i in 0:23], 12)
    @test length(L) == 2
    @test L[1].year == 1949 && L[1].y ≈ collect(1.0:12.0)
    @test L[2].y ≈ collect(13.0:24.0)
    L4 = SeasonalAdjustment._seasonal_layout(collect(1.0:24.0),
            [Date(1990,1) + Dates.Month(3i) for i in 0:23], 4)
    @test length(L4) == 6
end
```

### 7.2 `forecastplot`

```julia
@testset "forecastplot -- observed + forecast + ribbon" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), maxlead = 12)
        rd = _apply_named(:forecastplot, res)
        @test length(rd) >= 3
        @test any(d -> haskey(d.plotattributes, :ribbon) ||
                       get(d.plotattributes, :seriestype, :path) === :path, rd)
    end
end

@testset "forecastplot -- forecast line JOINS the last observation" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), maxlead = 12)
        rd = _apply_named(:forecastplot, res)
        fc = rd[2]
        @test fc.args[1][1] == res.dates[end]              # prepended
        @test fc.args[2][1] ≈ res.observed[end]
        @test length(fc.args[1]) == 13                     # 1 + 12
    end
end

@testset "forecastplot -- ribbon starts AT the first forecast, not the join" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), maxlead = 12)
        rib = last(_apply_named(:forecastplot, res))
        @test length(rib.args[1]) == 12
        @test rib.args[1][1] == res.dates[end] + Dates.Month(1)
    end
end

@testset "forecastplot -- history=n truncates the observed series only" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), maxlead = 12)
        rd = _apply_named(:forecastplot, res; history = 24)
        @test length(rd[1].args[1]) == 24
        @test length(rd[2].args[1]) == 13     # forecast unaffected
    end
end

@testset "forecastplot -- backcast=true adds a leading extension" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1),
                  spec_args = Dict("forecast.maxback" => "12"))
        rd = _apply_named(:forecastplot, res; backcast = true)
        @test any(d -> minimum(d.args[1]) < res.dates[1], rd)
    end
end
```

### 7.3 `residdiagplot`

```julia
@testset "residdiagplot -- default 3 panels with a layout" begin
    rd = _apply_named(:residdiagplot, RESULT)
    @test haskey(rd[1].plotattributes, :layout)
    @test length(rd) >= 3
end

@testset "residdiagplot -- panels argument controls count and order" begin
    @test length(_apply_named(:residdiagplot, RESULT; panels = [:series])) >= 1
    rd = _apply_named(:residdiagplot, RESULT; panels = [:acf, :pacf])
    @test any(d -> occursin("PACF", string(get(d.plotattributes, :title, ""))), rd)
    @test_throws ArgumentError _apply_named(:residdiagplot, RESULT; panels = [:bogus])
end

@testset "residdiagplot -- ACF comes from .acf, not recomputed" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), automdl = true)
        rd = _apply_named(:residdiagplot, res; panels = [:acf], lags = 24)
        acf_panel = rd[1]
        @test length(acf_panel.args[2]) == 24
        # binary's own values, so they must match .acf's first column
        @test acf_panel.args[2] ≈ first.(series(res, :acf))[1:24] rtol=1e-8
    end
end

@testset "residdiagplot -- confidence bands drawn" begin
    rd = _apply_named(:residdiagplot, RESULT; panels = [:acf])
    @test any(d -> get(d.plotattributes, :seriestype, :path) in (:hline, :path) &&
                   haskey(d.plotattributes, :fillrange), rd) ||
          count(d -> get(d.plotattributes, :seriestype, :path) === :hline, rd) >= 2
end

@testset "residdiagplot -- errors on a result with no residuals" begin
    @test_throws ArgumentError _apply_named(:residdiagplot, NO_RESID_RESULT)
end
```

### 7.4 `componentplot`

```julia
@testset "componentplot -- reference line follows finmode" begin
    rd = _apply_named(:componentplot, RESULT; reference = true)
    hl = filter(d -> get(d.plotattributes, :seriestype, :path) === :hline, rd)
    @test !isempty(hl)
    @test hl[1].args[1] == [1.0]                     # fixture is multiplicative
    @test udg(RESULT, "finmode") == "multiplicative" # the source of that 1.0
end

@testset "componentplot -- additive mode uses a 0.0 reference" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), x11_mode = :additive, trading = true)
        rd = _apply_named(:componentplot, res)
        hl = filter(d -> get(d.plotattributes, :seriestype, :path) === :hline, rd)
        @test hl[1].args[1] == [0.0]
    end
end

@testset "componentplot -- absent components skipped, not flat-lined" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), trading = true)   # no holiday
        rd = _apply_named(:componentplot, res; which = :all)
        for d in rd
            get(d.plotattributes, :seriestype, :path) === :hline && continue
            @test !all(≈(first(d.args[2])), d.args[2])
        end
    end
end

@testset "componentplot -- clear error when the model has no regression effects" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949,1), seasonal_order = (0,1,1,12))
        @test_throws ArgumentError _apply_named(:componentplot, res; which = :all)
    end
end
```

### 7.5 Real-backend smoke tests

Extend W.6's existing extended-suite block rather than adding a second one.

```julia
@testset "extended -- W.8 recipes render real images" begin
    using Plots; gr()
    for f in (() -> seasonalplot(RESULT),
              () -> seasonalplot(RESULT; highlight = :last),
              () -> seasonalplot(QUARTERLY_RESULT),
              () -> forecastplot(FORECAST_RESULT),
              () -> forecastplot(FORECAST_RESULT; history = 24),
              () -> residdiagplot(RESULT),
              () -> componentplot(TD_RESULT))
        p = f()
        @test p isa Plots.Plot
        io = IOBuffer(); show(io, MIME"image/png"(), p)
        @test length(take!(io)) > 1000
    end
end
```

### 7.6 Fixtures

W.6 built the `auto_test` family (`.d8`, `.d10`–`.d13`, `.rsd`, `.sp0`–`.spr`)
from one real binary run, verified byte-identical to `auto_test.udg`. **Extend
that same run** rather than starting a second family — add
`estimate { save = (rsd acf pcf) }`, `forecast { maxlead = 12 maxback = 12
save = (fct bct fvr) }`, `regression { save = (td hol usr otl) }`. One run, one
consistent story, same discipline W.6 used.

Note the W.6 correction: **residuals are `nobs`-length, not `nefobs`-length.**
`auto_test.rsd` has 144 data rows. Any new residual-based fixture inherits that.

---

## 8. Sequencing

```
W.8.1 seasonalplot   [unblocked -- start here]
W.8.3 residdiagplot  [unblocked -- .acf/.pcf need only W.7.1]

W.7.2 forecast   ──> W.8.2 forecastplot
W.7.4 components ──> W.8.4 componentplot
W.7.8 spans      ──> W.8.5 spanplot   [last; W.7.8 scope still uncertain]
```

---

## 9. Open questions

1. **Should `_seasonal_layout` live in SA or move straight to TSAnalytics?** SA
   already depends on TSA, and TSA needs both this and `_subseries_layout` for
   its own recipes. Starting in TSA avoids a later move — but TSA's recipe work
   is not yet scoped. W.6 left the same question open for `_subseries_layout`;
   answer both together.
2. **Year labelling in `seasonalplot`** — R labels each line's right end rather
   than using a legend, which matters past ~12 years. Backend-dependent in
   Julia; decide and document.
3. **Does TSAnalytics expose a normal quantile function** for the `:qq` panel? If
   not, is a `Distributions.jl` dependency justified for one panel? Probably not
   — drop `:qq` and keep `:histogram`.
4. **`polar = true`** — does the target backend support polar axes uniformly?
   Plots.jl does; Makie differs. Consider deferring until a backend is settled.
5. **Does `.acf` carry the confidence bands**, or only the standard errors from
   which they are computed? Decides whether W.8.3 draws bands directly or derives
   them.

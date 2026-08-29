# Handoff: W.6 — Plot Recipes via RecipesBase.jl

For a fresh session picking this up with no prior context. Same treatment as
W.0–W.5: verified references, complete API design with argument values, and a
test plan that works **without a plotting backend installed**.

**Depends on:** W.5.3 (`outlier`, `transformfunction`, `peaks`), W.5.4 (`series`, for D8)
**Reference:** R `seasonal`'s `R/plot.R` and `R/identify.R`, read directly;
`statsmodels` `X13ArimaAnalysisResult.plot`

---

## 0. Why RecipesBase, and why it doesn't break the dependency rule

`RecipesBase.jl` has **zero dependencies of its own** and pulls in no plotting
backend. It defines only the `@recipe` macro and a plot-attribute protocol. A
recipe compiles to a method returning data and attributes; nothing draws until
the user loads Plots.jl, StatsPlots, or a Makie backend that speaks the
protocol.

Adding it to `[deps]` costs a package that installs in under a second and adds
no transitive load. Same category as `Optim.jl` in TSAnalytics — infrastructure,
not a statistical algorithm this package should own.

The alternative is every consumer reimplementing outlier marking, SI-ratio
overlays and component-panel layout. For a package positioned explicitly against
R's `seasonal`, shipping the diagnostics but none of the four plots `seasonal`
ships is a visible gap.

**Scope note:** SA only. TSAnalytics needs its own recipes (`ACFResult`,
`STLDecomposition`, `ClassicalDecomposition`, a generic seasonal-subseries plot);
`monthplot` below is deliberately designed so the generic layout can later move
to TSA and SA's becomes a thin specialisation. See §7.

---

## 1. What the references ship

**R `seasonal`** — four plots, all X-13-specific:

```r
plot.seas(x, outliers = TRUE, trend = FALSE, main = "Original and Adjusted Series",
          xlab = "Time", ylab = "", transform = c("none", "PC", "PCY"), ...)

residplot(x, outliers = TRUE, main = "residuals of regARIMA",
          xlab = "Time", ylab = "", ...)

monthplot.seas(x, choice = c("seasonal", "irregular"), main, ...)

identify.seas(x, type = c("ao", "tc", "ls"), ...)     # interactive
```

`monthplot.seas` is the subtle one. From `R/plot.R`:

```r
monthplot(x$data[,'seasonal'], ylab = "", lwd = 2, col = "red", ...)
monthplot(siratio(x), col = "blue", type = "h", add = TRUE)
```

Two layers: the **seasonal factor** by calendar month as a thick red line, plus
the **SI ratios** overlaid as blue vertical stems (`type = "h"`). The SI ratios
are the point of the chart — they show the scatter the seasonal factor smooths
through. A monthplot without them is half the diagnostic.

**Python** — one: `X13ArimaAnalysisResult.plot()`, a four-panel
observed/trend/seasadj/irregular stack.

**SA** — none.

---

## 2. Deliverables

| ID | Recipe | Matches | Effort |
|----|--------|---------|--------|
| W.6.1 | `plot(::X13Result)` | `plot.seas` + Python's `.plot()` | ~90 LOC |
| W.6.2 | `residplot(::X13Result)` | `residplot` | ~40 LOC |
| W.6.3 | `monthplot(::X13Result)` | `monthplot.seas` | ~80 LOC |
| W.6.4 | `spectrumplot(::X13Result)` | — (new; `seasonal` has none) | ~50 LOC |

`identify.seas` is deliberately out of scope: an interactive click-loop tied to
R's base-graphics event model, with no clean Julia equivalent.

`Project.toml` gains `RecipesBase = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"`.
Exports gain `residplot`, `monthplot`, `spectrumplot` (the `plot` recipe needs
no export).

---

## 3. W.6.1 — `plot(::X13Result)`

Two shapes in one recipe, selected by `panels`.

```julia
@recipe function f(r::X13Result;
                   panels    = :overlay,
                   outliers  = true,
                   trend     = false,
                   transform = :none)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `panels` | `:overlay`, `:components` | `:overlay` | `:overlay` is R's `plot.seas` — original and adjusted on one axis. `:components` is Python's four-panel observed/SA/trend/irregular stack. |
| `outliers` | `true`, `false` | `true` | Mark detected outliers, labelled by type |
| `trend` | `true`, `false` | `false` | Add the trend-cycle as a third line (`:overlay` only; ignored with a warning under `:components`, where it is already a panel) |
| `transform` | `:none`, `:pc`, `:pcy` | `:none` | Levels; period-on-period growth; year-on-year growth |

`transform` is R's `c("none", "PC", "PCY")` lower-cased to Julia convention. R
computes `PC` as `(x - lag(x,-1)) / lag(x,-1)` and `PCY` at lag `-frequency`.
Apply to **every** series including the trend, and drop the leading undefined
entries rather than emitting `NaN`.

Outlier markers come from `outlier(r; full = false)` (W.5.3) — a vector the
length of the series with `"AO"`/`"LS"`/`"TC"` at outlier dates and `missing`
elsewhere. Plot as a scatter over the adjusted line. Under `transform != :none`
the marker's y-position must come from the **transformed** adjusted series, not
the level.

Series labels `"Original"` and `"Seasonally Adjusted"`, matching R's legend
wording, plus `"Trend"` when `trend = true`.

---

## 4. W.6.2 — `residplot(::X13Result)`

```julia
@recipe function f(::Type{Val{:residplot}}, r::X13Result; outliers = true)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `outliers` | `true`, `false` | `true` | Mark outlier dates on the residual series |

`r.residuals` already exists as a field.

**The length trap:** residuals run to `nefobs` (131 in the committed fixture),
not `nobs` (144) — differencing costs observations. The date axis must be the
*last* `length(residuals)` entries of `r.dates`, and the outlier vector sliced
to match. Getting this wrong shifts every residual by 13 months and the chart
still looks plausible, which is why §8.3 tests it in both directions.

Add a zero reference line. R doesn't draw one, but regARIMA residuals are
mean-zero by construction and it costs nothing.

---

## 5. W.6.3 — `monthplot(::X13Result)`

The chart with real content.

```julia
@recipe function f(::Type{Val{:monthplot}}, r::X13Result;
                   choice   = :seasonal,
                   siratios = true)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `choice` | `:seasonal`, `:irregular` | `:seasonal` | Which component to lay out by calendar period |
| `siratios` | `true`, `false` | `true` | Overlay SI ratios as vertical stems (R's second layer) |

### Layout

For period `p` (12 or 4), split into `p` cycle-subseries. Subseries `k` occupies
x-positions `[k-1, k)`, its `n_k` points evenly spaced within that band, with a
horizontal mean bar across it:

```
x_positions = (k - 1) .+ ((0:n_k-1) .+ 0.5) ./ n_k
```

Tick labels `Jan`–`Dec` for `period = 12`, `Q1`–`Q4` for `period = 4`, centred
at `k - 0.5`.

### SI ratios — the dependency on W.5.4

SI ratios come from **table D8** (final unmodified SI ratios), which is *not* in
the default save set. The recipe must call `series(r, :d8)`, which triggers a
re-run when D8 wasn't saved.

**A recipe silently spawning a subprocess is bad behaviour.** Two acceptable
resolutions:

1. `siratios = true` calls `series(r, :d8; verbose = true)`, so the re-run is
   announced — consistent with W.5.4's own contract.
2. Add `:d8` to `x13()`'s always-saved set alongside D10–D13, so it is simply
   present.

**Recommendation: option 2.** `x13()` already always requests residuals and the
full D10–D13 quartet because `X13Result`'s contract is a fully-populated result;
D8 fits that argument exactly. Then `series(r, :d8)` never re-runs for an
`x13()`-produced result, and option 1 remains the fallback for hand-built
`X13Spec` runs.

For `choice = :irregular` the overlay is meaningless (SI ratios *are* seasonal
plus irregular); ignore `siratios` with a warning.

### Quarterly

Must work for `period = 4`. Follow the convention `_quarterly_periods` in
`calendars.jl` established.

---

## 6. W.6.4 — `spectrumplot(::X13Result)`

Neither reference ships this, but W.5.3's `peaks` accessor makes it nearly free,
and spectral peaks are how residual seasonality and trading-day effects are
actually judged in official statistics.

```julia
@recipe function f(::Type{Val{:spectrumplot}}, r::X13Result; series = :sa)
```

| Attribute | Values | Default | Meaning |
|---|---|---|---|
| `series` | `:original`, `:sa`, `:irregular`, `:residual` | `:sa` | Which spectrum — maps to udg prefixes `spcori`, `spcsa`, `spcirr`, `spcrsd` |

Plot the spectrum with vertical markers at the seasonal frequencies (`s1`–`s5`)
and the two trading-day frequencies (`t1`, `t2`), highlighting those udg reports
as peaks. The fixture shows the value format: `spcrsd.s1: "15.2 +"` (a peak,
`+` = visually significant) versus `spcrsd.s2: "nopeak"`.

The spectrum values themselves need table `sp0`/`sp1`/`sp2` via `series()`.
**Confirm those table names against the binary before scoping** — they are not
in the committed fixture, and this is the one recipe whose data source is
unverified.

---

## 7. Shared design with TSAnalytics

`monthplot`'s layout is a generic seasonal-subseries plot — `forecast::
ggseasonplot`, `feasts::gg_subseries`, R's `stats::monthplot`. Nothing in the
Julia ecosystem has one.

Write the geometry as a small internal function taking `(values, period)` and
returning subseries positions and means, so the same code can move to TSA later
and SA's `monthplot` becomes that plus the SI-ratio layer. Do **not** duplicate
the layout math when TSA's version lands.

Same for W.6.1's `:components` layout: TSA needs the identical shape for
`STLDecomposition` and `ClassicalDecomposition`.

---

## 8. Test plan

Testing recipes without a backend is the central problem. Three levels, in
`test/test_plots.jl`, included from `runtests.jl` after `test_api.jl`.

### 8.1 Level 1 — `RecipesBase.apply_recipe`, no backend

`RecipesBase.apply_recipe(d, args...)` returns a `Vector{RecipeData}`, each with
`.args` (the plotted data) and `.plotattributes`. Runs with **no plotting
package installed at all**, and is where most assertions belong.

```julia
using RecipesBase
_apply(r; kw...) = RecipesBase.apply_recipe(Dict{Symbol,Any}(kw...), r)

@testset "plot(::X13Result) -- overlay produces 2 series by default" begin
    rd = _apply(RESULT)
    @test length(rd) == 2
    labels = [get(d.plotattributes, :label, "") for d in rd]
    @test "Original" in labels
    @test "Seasonally Adjusted" in labels
end

@testset "plot -- trend=true adds a third series" begin
    rd = _apply(RESULT; trend = true)
    @test length(rd) == 3
    @test "Trend" in [get(d.plotattributes, :label, "") for d in rd]
end

@testset "plot -- outliers=true adds a scatter series" begin
    rd_off = _apply(RESULT; outliers = false)
    rd_on  = _apply(RESULT; outliers = true)
    @test length(rd_on) == length(rd_off) + 1
    scat = rd_on[end]
    @test get(scat.plotattributes, :seriestype, :path) === :scatter
    @test length(scat.args[1]) == 1          # exactly one AO in the fixture
end

@testset "plot -- outliers=true with zero outliers adds NO empty series" begin
    rd = _apply(NO_OUTLIER_RESULT; outliers = true)
    @test length(rd) == 2                    # not 3 with an empty scatter
end

@testset "plot -- data equals the struct fields, not a copy that drifted" begin
    rd = _apply(RESULT)
    @test rd[1].args[2] ≈ RESULT.observed
    @test rd[2].args[2] ≈ RESULT.seasonally_adjusted
    @test rd[1].args[1] == RESULT.dates
end

@testset "plot -- panels=:components produces 4 series with a layout" begin
    rd = _apply(RESULT; panels = :components)
    @test length(rd) == 4
    @test haskey(rd[1].plotattributes, :layout)
end

@testset "plot -- trend=true under :components warns and is ignored" begin
    rd = @test_logs (:warn,) _apply(RESULT; panels = :components, trend = true)
    @test length(rd) == 4
end
```

### 8.2 Level 2 — transform correctness

`transform` is real arithmetic and deserves numeric assertions, not shape checks.

```julia
@testset "plot -- transform=:pc matches the R formula exactly" begin
    rd = _apply(RESULT; transform = :pc)
    y  = RESULT.observed
    expected = (y[2:end] .- y[1:end-1]) ./ y[1:end-1]
    @test rd[1].args[2] ≈ expected
    @test length(rd[1].args[1]) == length(expected)     # dates dropped in step
end

@testset "plot -- transform=:pcy uses lag = period, not lag 1" begin
    rd = _apply(RESULT; transform = :pcy)
    y, p = RESULT.observed, 12
    expected = (y[p+1:end] .- y[1:end-p]) ./ y[1:end-p]
    @test rd[1].args[2] ≈ expected
    @test length(rd[1].args[2]) == length(y) - 12
end

@testset "plot -- transform=:pcy on a QUARTERLY result lags by 4" begin
    rd = _apply(QUARTERLY_RESULT; transform = :pcy)
    @test length(rd[1].args[2]) == length(QUARTERLY_RESULT.observed) - 4
end

@testset "plot -- no NaN/Inf reaches the backend under any transform" begin
    for t in (:none, :pc, :pcy)
        for d in _apply(RESULT; transform = t)
            @test all(isfinite, d.args[2])
        end
    end
end

@testset "plot -- outlier markers sit on the TRANSFORMED series" begin
    rd = _apply(RESULT; transform = :pc, outliers = true)
    scat, line = rd[end], rd[2]
    mx = scat.args[1][1]
    i = findfirst(==(mx), line.args[1])
    @test scat.args[2][1] ≈ line.args[2][i]
end

@testset "plot -- invalid attribute values throw, never silently default" begin
    @test_throws ArgumentError _apply(RESULT; transform = :bogus)
    @test_throws ArgumentError _apply(RESULT; panels = :bogus)
end
```

### 8.3 `residplot`

```julia
@testset "residplot -- date axis aligns to nefobs, not nobs" begin
    rd = _apply_named(:residplot, RESULT)
    n = length(RESULT.residuals)
    @test n == nobs_effective(RESULT)
    @test n < length(RESULT.dates)                       # 131 vs 144
    @test rd[1].args[1] == RESULT.dates[end-n+1:end]     # tail-aligned
    @test rd[1].args[1][end] == RESULT.dates[end]
end

@testset "residplot -- outlier markers sliced to the residual window" begin
    rd = _apply_named(:residplot, RESULT; outliers = true)
    n = length(RESULT.residuals)
    for d in rd
        @test all(x -> x in RESULT.dates[end-n+1:end], d.args[1])
    end
end

@testset "residplot -- an outlier BEFORE the residual window is dropped" begin
    # AO1951.May is inside the window for the fixture; construct the
    # opposite case so the slice logic is exercised in both directions
    rd = _apply_named(:residplot, EARLY_OUTLIER_RESULT; outliers = true)
    @test length(rd) == 1                                # line only, no scatter
end

@testset "residplot -- zero reference line present" begin
    rd = _apply_named(:residplot, RESULT)
    @test any(d -> get(d.plotattributes, :seriestype, :path) === :hline, rd)
end

@testset "residplot -- errors clearly on a result with no residuals" begin
    @test_throws ArgumentError _apply_named(:residplot, NO_RESID_RESULT)
end
```

### 8.4 `monthplot`

```julia
@testset "monthplot -- 12 subseries bands for monthly" begin
    rd = _apply_named(:monthplot, RESULT)
    bands = filter(d -> get(d.plotattributes, :seriestype, :path) === :path, rd)
    @test length(bands) >= 12
end

@testset "monthplot -- x positions stay inside their band" begin
    rd = _apply_named(:monthplot, RESULT)
    for (k, d) in enumerate(first(rd, 12))
        @test all(k - 1 .<= d.args[1] .<= k)
    end
end

@testset "monthplot -- 4 bands and Q labels for quarterly" begin
    rd = _apply_named(:monthplot, QUARTERLY_RESULT)
    ticks = rd[1].plotattributes[:xticks]
    @test length(ticks[1]) == 4
    @test ticks[2] == ["Q1", "Q2", "Q3", "Q4"]
end

@testset "monthplot -- monthly tick labels" begin
    ticks = _apply_named(:monthplot, RESULT)[1].plotattributes[:xticks]
    @test ticks[2][1] == "Jan" && ticks[2][12] == "Dec"
    @test ticks[1] ≈ collect(0.5:1:11.5)
end

@testset "monthplot -- mean bar equals the subseries mean" begin
    rd = _apply_named(:monthplot, RESULT)
    sf = RESULT.seasonal_factors
    jan = sf[1:12:end]
    means = filter(d -> get(d.plotattributes, :linewidth, 1) > 2, rd)
    @test means[1].args[2][1] ≈ mean(jan)
end

@testset "monthplot -- siratios=true adds a stem layer from D8" begin
    rd_off = _apply_named(:monthplot, RESULT; siratios = false)
    rd_on  = _apply_named(:monthplot, RESULT; siratios = true)
    @test length(rd_on) > length(rd_off)
    stems = filter(d -> get(d.plotattributes, :seriestype, :path) === :sticks, rd_on)
    @test !isempty(stems)
end

@testset "monthplot -- D8 present without a re-run (x13() saves it)" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949, 1))
        @test_logs _apply_named(:monthplot, res; siratios = true)   # no @info re-run
    end
end

@testset "monthplot -- choice=:irregular ignores siratios with a warning" begin
    rd = @test_logs (:warn,) _apply_named(:monthplot, RESULT;
                                          choice = :irregular, siratios = true)
    @test isempty(filter(d -> get(d.plotattributes, :seriestype, :path) === :sticks, rd))
end

@testset "monthplot -- choice=:irregular plots the irregular, not the seasonal" begin
    rd = _apply_named(:monthplot, RESULT; choice = :irregular, siratios = false)
    vals = vcat([d.args[2] for d in first(rd, 12)]...)
    @test sort(vals) ≈ sort(RESULT.irregular)
end

@testset "monthplot -- ragged subseries (n not a multiple of period)" begin
    # 145 observations: January has 13 points, December 12
    rd = _apply_named(:monthplot, RAGGED_RESULT)
    @test length(rd[1].args[1]) == 13
    @test length(rd[12].args[1]) == 12
    @test all(0 .<= rd[1].args[1] .<= 1)      # still inside band 1
end

@testset "monthplot -- subseries layout helper is period-generic" begin
    # guards the shared-with-TSA design in section 7
    pos, means = SeasonalAdjustment._subseries_layout(collect(1.0:24.0), 12)
    @test length(pos) == 12 && length(means) == 12
    @test means[1] ≈ mean([1.0, 13.0])
    pos4, _ = SeasonalAdjustment._subseries_layout(collect(1.0:24.0), 4)
    @test length(pos4) == 4
end
```

### 8.5 `spectrumplot`

```julia
@testset "spectrumplot -- series selector maps to the right udg prefix" begin
    for (sym, prefix) in ((:original, "spcori"), (:sa, "spcsa"),
                          (:irregular, "spcirr"), (:residual, "spcrsd"))
        rd = _apply_named(:spectrumplot, RESULT; series = sym)
        @test occursin(prefix, string(get(rd[1].plotattributes, :label, "")))
    end
    @test_throws ArgumentError _apply_named(:spectrumplot, RESULT; series = :bogus)
end

@testset "spectrumplot -- peak markers match the peaks() accessor" begin
    rd = _apply_named(:spectrumplot, RESULT; series = :residual)
    marked = filter(d -> get(d.plotattributes, :seriestype, :path) === :vline, rd)
    # fixture: spcrsd.s1 and .s4 are peaks; .s2, .s3, .s5 are "nopeak"
    @test length(vcat([d.args[1] for d in marked]...)) == 2
end

@testset "spectrumplot -- nopeak everywhere draws no markers" begin
    rd = _apply_named(:spectrumplot, FLAT_SPECTRUM_RESULT)
    @test isempty(filter(d -> get(d.plotattributes, :seriestype, :path) === :vline, rd))
end
```

### 8.6 Level 3 — smoke tests with a real backend (opt-in)

Recipes can pass `apply_recipe` and still fail inside a backend. One smoke test
per recipe in `test/extended/`, gated on the existing
`SEASONALADJUSTMENT_EXTENDED_TESTS=1` flag so a plain `Pkg.test()` never needs
Plots.jl.

```julia
@testset "extended -- every recipe renders without error" begin
    using Plots; gr()
    for f in (() -> plot(RESULT),
              () -> plot(RESULT; panels = :components),
              () -> plot(RESULT; transform = :pc, trend = true),
              () -> residplot(RESULT),
              () -> monthplot(RESULT),
              () -> monthplot(RESULT; choice = :irregular),
              () -> monthplot(QUARTERLY_RESULT),
              () -> spectrumplot(RESULT))
        p = f()
        @test p isa Plots.Plot
        io = IOBuffer(); show(io, MIME"image/png"(), p)
        @test length(take!(io)) > 1000      # a real image, not a blank canvas
    end
end
```

### 8.7 Fixtures

`RESULT` and friends are built once at the top of `test_plots.jl` from
`handoff/udg_and_residuals/auto_test.udg` plus the committed
`handoff/verification/airline_baseline/airline_official.d1{0,1,2,3}` tables — so
**the whole Level 1 and 2 suite runs with no binary and no backend**. Only
`QUARTERLY_RESULT`, `RAGGED_RESULT` and the extended smoke tests need more.

Follow `test_api.jl`'s existing pattern of reading fixture data out of the
committed `.spc` with a regex rather than hardcoding a second copy of the
airline series.

---

## 9. Sequencing

```
W.5.3 accessors ──> W.6.1 plot ──> W.6.2 residplot
W.5.4 series()  ──> W.6.3 monthplot        [or: add :d8 to x13()'s save set]
W.5.3 peaks()   ──> W.6.4 spectrumplot     [table names unverified -- do last]
```

W.6.1 and W.6.2 can start as soon as `outlier()` exists. W.6.3 needs the D8
decision made first. W.6.4 is last because its data source is the only
unverified one in this document.

---

## 10. Open questions

1. **Add `:d8` to `x13()`'s always-saved set?** §5's recommendation is yes.
   Decide before W.6.3; it changes `X13Result`'s contract.
2. **Which table holds the spectrum values** — `sp0`/`sp1`/`sp2` or something
   else? Confirm against the binary before scoping W.6.4.
3. **Should `X13Result` gain a `period` field?** The recipes need it for tick
   labels and the `:pcy` lag, and currently must reach through `r.spec.period`.
4. **Marker style for outlier types.** R prints the type string as the plotting
   character. Julia could use distinct marker shapes with a legend instead —
   arguably clearer, but a divergence worth deciding deliberately.
5. **Does the subseries layout helper belong in SA at all,** or should it start
   in TSA and be imported? SA already depends on TSA, so starting it there
   avoids a later move — but TSA's recipe work isn't scoped yet.

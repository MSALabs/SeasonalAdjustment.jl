# test/test_plots.jl -- W.6
#
# Test plan follows handoff/w6-plot-recipes-handoff.md section 8, adapted
# to what this session actually verified -- see development-sequence.md's
# W.6 row for the real corrections made along the way (the handoff's own
# "residuals are shorter than dates" premise turned out to be wrong,
# confirmed directly by re-running the real binary twice; the spectrumplot
# residual-series peak count in its own test 8.5 was also wrong, 3 not 2,
# confirmed directly against the committed fixture).
#
# Testing recipes without a backend: RecipesBase.jl's own
# `is_key_supported` has NO fallback method until a real plotting
# backend (Plots.jl etc.) defines one -- confirmed directly this session
# (a real MethodError, not a guess) that ANY recipe with keyword
# arguments hits this via `@recipe`'s own generated keyword-cleanup code,
# even though the handoff's own framing ("runs with no plotting package
# installed at all") suggested otherwise. The standard, documented
# workaround (used by RecipesBase-dependent packages' own test suites)
# is a trivial test-only stub, added below -- never shipped in package
# source, since a real backend provides the genuine definition.

using RecipesBase
using Statistics: mean

RecipesBase.is_key_supported(::Symbol) = true

_apply(r; kw...) = RecipesBase.apply_recipe(Dict{Symbol,Any}(kw...), r)

# residplot/monthplot/spectrumplot are RecipesBase.@userplot wrappers,
# not plain series-type (Val{:name}) recipes -- confirmed directly this
# session that a plain series-type recipe does NOT work here, since
# X13Result already has its own bare type recipe for plot(r), which
# RecipesPipeline's own argument-type-based dispatch always applies
# first, before `seriestype` is ever consulted (see residplot's own
# docstring in src/plots.jl for the full real-binary-confirmed story).
const _USERPLOT_WRAPPERS = Dict(
    :residplot => SeasonalAdjustment.ResidPlot,
    :monthplot => SeasonalAdjustment.MonthPlot,
    :spectrumplot => SeasonalAdjustment.SpectrumPlot,
    :seasonalplot => SeasonalAdjustment.SeasonalPlot,
    :forecastplot => SeasonalAdjustment.ForecastPlot,
    :residdiagplot => SeasonalAdjustment.ResidDiagPlot,
    :componentplot => SeasonalAdjustment.ComponentPlot,
    :spanplot => SeasonalAdjustment.SpanPlot,
)
function _apply_named(name::Symbol, args...; kw...)
    wrapper = get(_USERPLOT_WRAPPERS, name, nothing)
    wrapper === nothing && throw(ArgumentError("_apply_named: unknown recipe :$name"))
    return RecipesBase.apply_recipe(Dict{Symbol,Any}(kw...), wrapper(args))
end

const _PLOTS_DIR = joinpath(@__DIR__, "..", "handoff", "udg_and_residuals")

# ---------------------------------------------------------------------
# Fixtures -- RESULT and its variants all come from ONE real, consistent
# binary run (auto_test.spc + estimate{save=(rsd)} + spectrum{save=(sp0
# sp1 sp2 spr)} + d8 added to x11{save=...}, confirmed via a direct diff
# this session that the resulting arimamdl/aic/nobs/nefobs are BYTE-
# IDENTICAL to the already-committed, already-tested auto_test.udg -- so
# this doesn't introduce a second, inconsistent "auto_test" story, just
# the additional real output tables W.6 needs that weren't requested
# when auto_test.udg was first generated for W.4a).
# ---------------------------------------------------------------------

function _build_result(; udg = parse_udg(joinpath(_PLOTS_DIR, "auto_test.udg")), residuals = nothing)
    d10 = parse_table(joinpath(_PLOTS_DIR, "auto_test.d10"))
    d11 = parse_table(joinpath(_PLOTS_DIR, "auto_test.d11"))
    d12 = parse_table(joinpath(_PLOTS_DIR, "auto_test.d12"))
    d13 = parse_table(joinpath(_PLOTS_DIR, "auto_test.d13"))
    dates = first.(d10)
    spc = read(joinpath(_PLOTS_DIR, "auto_test.spc"), String)
    m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
    y = parse.(Float64, split(m.captures[1]))
    resid = residuals === nothing ? last.(parse_table(joinpath(_PLOTS_DIR, "auto_test.rsd"))) : residuals
    spec = X13Spec(y; start = (Dates.year(dates[1]), Dates.month(dates[1])), period = 12,
                    seasonal_order = (0, 1, 1, 12), save = [:d10, :d11, :d12, :d13, :d8])
    run_result = X13RunResult(true, "", String[], String[], _PLOTS_DIR, "auto_test")
    return X13Result(y, last.(d11), last.(d12), last.(d10), last.(d13), resid, udg, dates, spec, run_result)
end

const RESULT = _build_result()

const NO_OUTLIER_RESULT = _build_result(
    udg = Dict(k => v for (k, v) in RESULT.udg if !startswith(k, "AutoOutlier\$") && !startswith(k, "outlier.")),
)

const NO_RESID_RESULT = _build_result(residuals = Float64[])

# A synthetic, explicitly-not-a-real-run fixture -- exercises the
# defensive tail-alignment/outlier-dropping logic in a case that has NOT
# been observed against the real binary (see residplot's own docstring:
# real .rsd output was confirmed twice this session to always match
# r.dates in length, contrary to the handoff's original assumption).
# Kept as a robustness check of the SLICING LOGIC, not a claim about
# real X-13 behavior.
const SHORT_RESID_RESULT = _build_result(residuals = last.(parse_table(joinpath(_PLOTS_DIR, "auto_test.rsd")))[14:end])

# All spcsa.* peaks forced to "nopeak" -- a synthetic udg edit (not a
# second real run) paired with RESULT's own real .sp1 curve file, since
# spectrumplot's peak MARKERS are computed purely from udg (see
# spectrum_peaks) independently of the curve data itself.
const FLAT_SPECTRUM_RESULT = _build_result(
    udg = Dict(k => (startswith(k, "spcsa.s") || startswith(k, "spcsa.t") ? "nopeak" : v) for (k, v) in RESULT.udg),
)

# Synthetic (no real binary run) -- period=4 and a 145-length monthly
# series purely to exercise the plotting geometry's own period-
# generic/ragged-length handling; siratios explicitly disabled below
# since there is no real D8 file backing these to read.
function _synthetic_result(n::Integer, period::Integer)
    y = Float64[100.0 + 10.0 * sin(2pi * i / period) + i * 0.3 for i in 0:n-1]
    dates = period == 12 ? [Date(2000, 1) + Dates.Month(i) for i in 0:n-1] :
        [Date(2000, 1) + Dates.Month(3 * i) for i in 0:n-1]
    spec = X13Spec(y; period = period, seasonal_order = (0, 1, 1, period))
    run_result = X13RunResult(true, "", String[], String[], mktempdir(), "synthetic")
    seasonal_factors = Float64[10.0 * sin(2pi * i / period) for i in 0:n-1]
    irregular = Float64[0.1 * ((-1)^i) for i in 1:n]
    return X13Result(y, y .- seasonal_factors, y .- seasonal_factors .- irregular, seasonal_factors,
                      irregular, Float64[], Dict{String,String}(), dates, spec, run_result)
end

const QUARTERLY_RESULT = _synthetic_result(40, 4)
const RAGGED_RESULT = _synthetic_result(145, 12)

# ---------------------------------------------------------------------
# 8.1 Level 1 -- RecipesBase.apply_recipe, no backend
# ---------------------------------------------------------------------

@testset "plot(::X13Result) -- overlay produces 2 line series (outliers=false)" begin
    # outliers=true is the recipe's own default (matching R's own
    # outliers=TRUE) and RESULT genuinely has one real outlier in its
    # fixture data, so a bare `_apply(RESULT)` legitimately returns 3
    # series (2 lines + 1 marker), not 2 -- confirmed directly, not a
    # recipe bug. outliers=false here isolates just the 2 line series.
    rd = _apply(RESULT; outliers = false)
    @test length(rd) == 2
    labels = [get(d.plotattributes, :label, "") for d in rd]
    @test "Original" in labels
    @test "Seasonally Adjusted" in labels
end

@testset "plot -- trend=true adds a third series" begin
    rd = _apply(RESULT; trend = true, outliers = false)
    @test length(rd) == 3
    @test "Trend" in [get(d.plotattributes, :label, "") for d in rd]
end

@testset "plot -- outliers=true adds a scatter series" begin
    rd_off = _apply(RESULT; outliers = false)
    rd_on = _apply(RESULT; outliers = true)
    @test length(rd_on) == length(rd_off) + 1
    scat = rd_on[end]
    @test get(scat.plotattributes, :seriestype, :path) === :scatter
    @test length(scat.args[1]) == 1   # exactly one AO in the fixture
end

@testset "plot -- outliers=true with zero outliers adds NO empty series" begin
    rd = _apply(NO_OUTLIER_RESULT; outliers = true)
    @test length(rd) == 2
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

@testset "plot -- invalid attribute values throw, never silently default" begin
    @test_throws ArgumentError _apply(RESULT; transform = :bogus)
    @test_throws ArgumentError _apply(RESULT; panels = :bogus)
end

# ---------------------------------------------------------------------
# 8.2 Level 2 -- transform correctness
# ---------------------------------------------------------------------

@testset "plot -- transform=:pc matches the standard formula exactly" begin
    rd = _apply(RESULT; transform = :pc)
    y = RESULT.observed
    expected = (y[2:end] .- y[1:end-1]) ./ y[1:end-1]
    @test rd[1].args[2] ≈ expected
    @test length(rd[1].args[1]) == length(expected)
end

@testset "plot -- transform=:pcy uses lag = period, not lag 1" begin
    rd = _apply(RESULT; transform = :pcy)
    y, p = RESULT.observed, RESULT.spec.period
    expected = (y[p+1:end] .- y[1:end-p]) ./ y[1:end-p]
    @test rd[1].args[2] ≈ expected
    @test length(rd[1].args[2]) == length(y) - p
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
    @test i !== nothing
    @test scat.args[2][1] ≈ line.args[2][i]
end

# ---------------------------------------------------------------------
# 8.3 residplot
# ---------------------------------------------------------------------

@testset "residplot -- real .rsd length equals nobs, NOT nefobs (a real correction)" begin
    # Confirmed directly this session (re-running the real binary twice,
    # once via auto_test's own spec, once via resid_test's -- see
    # residplot's own docstring): .rsd always has one row per original
    # observation. This is the opposite of the handoff's own §4 claim.
    @test length(RESULT.residuals) == length(RESULT.dates)
    @test nobs_effective(RESULT) < StatsAPI.nobs(RESULT)   # nefobs IS still a real, smaller, separate count
end

@testset "residplot -- date axis is r.dates directly when lengths already match" begin
    rd = _apply_named(:residplot, RESULT)
    @test rd[1].args[1] == RESULT.dates
end

@testset "residplot -- outlier markers sliced to the residual window" begin
    rd = _apply_named(:residplot, RESULT; outliers = true)
    # the :hline reference-line series' x-args are a plain Float64
    # ([0.0]), not dates -- only check the date-axis series (:path and
    # :scatter), matching what _outlier_marker_points actually produces.
    for d in rd
        get(d.plotattributes, :seriestype, :path) === :hline && continue
        @test all(x -> x in RESULT.dates, d.args[1])
    end
end

@testset "residplot -- synthetic shorter-residuals case tail-aligns correctly" begin
    n = length(SHORT_RESID_RESULT.residuals)
    @test n < length(SHORT_RESID_RESULT.dates)
    rd = _apply_named(:residplot, SHORT_RESID_RESULT)
    @test rd[1].args[1] == SHORT_RESID_RESULT.dates[end-n+1:end]
    @test rd[1].args[1][end] == SHORT_RESID_RESULT.dates[end]
end

@testset "residplot -- zero reference line present" begin
    rd = _apply_named(:residplot, RESULT)
    @test any(d -> get(d.plotattributes, :seriestype, :path) === :hline, rd)
end

@testset "residplot -- errors clearly on a result with no residuals" begin
    @test_throws ArgumentError _apply_named(:residplot, NO_RESID_RESULT)
end

# ---------------------------------------------------------------------
# 8.4 monthplot
# ---------------------------------------------------------------------

@testset "monthplot -- 12 subseries bands + 12 mean bars + 12 SI stems" begin
    rd = _apply_named(:monthplot, RESULT)
    @test length(rd) == 36
    paths = filter(d -> get(d.plotattributes, :seriestype, :path) === :path, rd)
    @test length(paths) == 24   # 12 raw + 12 mean bars
end

@testset "monthplot -- x positions stay inside their band" begin
    rd = _apply_named(:monthplot, RESULT)
    for (k, d) in enumerate(first(rd, 12))
        @test all(k - 1 .<= d.args[1] .<= k)
    end
end

@testset "monthplot -- 4 bands and Q labels for quarterly" begin
    rd = _apply_named(:monthplot, QUARTERLY_RESULT; siratios = false)
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
    rd_on = _apply_named(:monthplot, RESULT; siratios = true)
    @test length(rd_on) > length(rd_off)
    stems = filter(d -> get(d.plotattributes, :seriestype, :path) === :sticks, rd_on)
    @test !isempty(stems)
end

@testset "monthplot -- D8 present without a re-run (x13() saves it, W.6)" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949, 1))
        @test :d8 in res.spec.save
        @test_logs _apply_named(:monthplot, res; siratios = true)   # no @info re-run
    else
        @warn "skipping monthplot D8-no-rerun test: x13_binary_available() is false in this environment"
    end
end

@testset "monthplot -- choice=:irregular ignores siratios with a warning" begin
    rd = @test_logs (:warn,) _apply_named(:monthplot, RESULT; choice = :irregular, siratios = true)
    @test isempty(filter(d -> get(d.plotattributes, :seriestype, :path) === :sticks, rd))
end

@testset "monthplot -- choice=:irregular plots the irregular, not the seasonal" begin
    rd = _apply_named(:monthplot, RESULT; choice = :irregular, siratios = false)
    vals = vcat([d.args[2] for d in first(rd, 12)]...)
    @test sort(vals) ≈ sort(RESULT.irregular)
end

@testset "monthplot -- ragged subseries (n not a multiple of period)" begin
    # 145 observations: January has 13 points, December has 12
    rd = _apply_named(:monthplot, RAGGED_RESULT; siratios = false)
    @test length(rd[1].args[1]) == 13
    @test length(rd[12].args[1]) == 12
    @test all(0 .<= rd[1].args[1] .<= 1)
end

@testset "monthplot -- unrecognized choice throws" begin
    @test_throws ArgumentError _apply_named(:monthplot, RESULT; choice = :bogus)
end

@testset "monthplot -- subseries layout helper is period-generic" begin
    pos, means = SeasonalAdjustment._subseries_layout(collect(1.0:24.0), 12)
    @test length(pos) == 12 && length(means) == 12
    @test means[1] ≈ mean([1.0, 13.0])
    pos4, _ = SeasonalAdjustment._subseries_layout(collect(1.0:24.0), 4)
    @test length(pos4) == 4
end

# ---------------------------------------------------------------------
# 8.5 spectrumplot
# ---------------------------------------------------------------------

@testset "spectrumplot -- series selector maps to the right udg prefix" begin
    for (sym, prefix) in ((:original, "spcori"), (:sa, "spcsa"), (:irregular, "spcirr"), (:residual, "spcrsd"))
        rd = _apply_named(:spectrumplot, RESULT; series = sym)
        @test occursin(prefix, string(get(rd[1].plotattributes, :label, "")))
    end
    @test_throws ArgumentError _apply_named(:spectrumplot, RESULT; series = :bogus)
end

@testset "spectrumplot -- peak markers match the peaks() accessor (real fixture: 3, not 2)" begin
    # A real correction to the handoff's own test 8.5, which claimed 2:
    # the committed fixture's spcrsd family actually has THREE "+"
    # entries (s1, s4, AND t2 -- confirmed by direct inspection of
    # auto_test.udg, not assumed from the handoff's own worked example).
    rd = _apply_named(:spectrumplot, RESULT; series = :residual)
    marked = filter(d -> get(d.plotattributes, :seriestype, :path) === :vline, rd)
    @test length(marked) == 3
    peaks = spectrum_peaks(RESULT; series = :residual)
    @test length(filter(p -> p.significant, peaks)) == 3
end

@testset "spectrumplot -- nopeak everywhere draws no markers" begin
    rd = _apply_named(:spectrumplot, FLAT_SPECTRUM_RESULT)
    @test isempty(filter(d -> get(d.plotattributes, :seriestype, :path) === :vline, rd))
end

@testset "spectrumplot -- curve data is the real spectrum file, not synthetic" begin
    rd = _apply_named(:spectrumplot, RESULT; series = :sa)
    curve = rd[1]
    @test length(curve.args[1]) > 10
    @test all(isfinite, curve.args[2])
    @test issorted(curve.args[1])   # frequencies increase monotonically
end

# ---------------------------------------------------------------------
# W.8 -- seasonalplot/forecastplot/residdiagplot/componentplot/spanplot.
# Same Level 1 (apply_recipe, no backend) structural style as W.6 above.
# A regression-bearing X13Result (trading=true + transform=:log, per
# the real, confirmed finding this session that X-13's implicit default
# x11 mode is multiplicative and needs an explicit transform whenever a
# regression block is present) is built once, real-binary-gated, for
# forecastplot/residdiagplot/componentplot's tests that genuinely need
# re-run machinery (.fct/.acf/.td aren't in RESULT's own committed
# fixture save list).
# ---------------------------------------------------------------------

@testset "seasonalplot -- one series per year, x is the period index not a date" begin
    rd = _apply_named(:seasonalplot, RESULT)
    @test length(rd) == 12 # 1949-1960, 144 obs -> 12 calendar years
    @test rd[1].args[1] == collect(1:12)
    @test eltype(rd[1].args[1]) <: Integer
end

@testset "seasonalplot -- each line carries that year's values in order" begin
    rd = _apply_named(:seasonalplot, RESULT; series = :seasonal)
    @test rd[1].args[2] ≈ RESULT.seasonal_factors[1:12]
    @test rd[12].args[2] ≈ RESULT.seasonal_factors[133:144]
end

@testset "seasonalplot -- IS the transpose of monthplot (same data, different layout)" begin
    sp = _apply_named(:seasonalplot, RESULT)
    mp = _apply_named(:monthplot, RESULT; siratios = false)
    @test length(sp) == 12                  # 12 years
    @test length(sp[1].args[1]) == 12       # 12 periods per line
    @test length(mp[1].args[1]) == 12       # 12 years per band
    @test sort(vcat([d.args[2] for d in sp]...)) ≈
          sort(vcat([d.args[2] for d in first(mp, 12)]...))
end

@testset "seasonalplot -- partial final year plots short, is not dropped" begin
    rd = _apply_named(:seasonalplot, RAGGED_RESULT) # 145 obs
    @test length(rd) == 13
    @test length(rd[13].args[1]) == 1
end

@testset "seasonalplot -- quarterly gives 4 x-positions and Q labels" begin
    rd = _apply_named(:seasonalplot, QUARTERLY_RESULT)
    @test rd[1].args[1] == collect(1:4)
    @test rd[1].plotattributes[:xticks][2] == ["Q1", "Q2", "Q3", "Q4"]
end

@testset "seasonalplot -- monthly tick labels reuse monthplot's own label constant" begin
    a = _apply_named(:seasonalplot, RESULT)[1].plotattributes[:xticks][2]
    b = _apply_named(:monthplot, RESULT)[1].plotattributes[:xticks][2]
    @test a == b == ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
end

@testset "seasonalplot -- series selector picks the right component; bogus throws" begin
    for (sym, fld) in ((:observed, :observed), (:sa, :seasonally_adjusted),
                        (:trend, :trend), (:irregular, :irregular), (:seasonal, :seasonal_factors))
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
    n_full = count(a -> a == 1.0, [get(d.plotattributes, :alpha, 1.0) for d in rd2])
    @test n_full == 2
end

@testset "_seasonal_layout -- X13Result-free, period-generic" begin
    L = SeasonalAdjustment._seasonal_layout(collect(1.0:24.0),
        [Date(1949, 1) + Dates.Month(i) for i in 0:23], 12)
    @test length(L) == 2
    @test L[1].year == 1949 && L[1].y ≈ collect(1.0:12.0)
    @test L[2].y ≈ collect(13.0:24.0)
    L4 = SeasonalAdjustment._seasonal_layout(collect(1.0:24.0),
        [Date(1990, 1) + Dates.Month(3i) for i in 0:23], 4)
    @test length(L4) == 6
end

@testset "residdiagplot -- default 3 panels with a layout; panels controls count/order" begin
    rd = _apply_named(:residdiagplot, RESULT)
    @test haskey(rd[1].plotattributes, :layout)
    @test length(rd) >= 3
    @test length(_apply_named(:residdiagplot, RESULT; panels = [:series])) >= 1
    @test_throws ArgumentError _apply_named(:residdiagplot, RESULT; panels = [:bogus])
    @test_throws ArgumentError _apply_named(:residdiagplot, RESULT; panels = [:qq])
end

@testset "residdiagplot -- panels=[:acf,:pacf] titles both panels, confidence bands drawn" begin
    rd = _apply_named(:residdiagplot, RESULT; panels = [:acf, :pacf])
    @test any(d -> occursin("PACF", string(get(d.plotattributes, :title, ""))), rd)
    @test count(d -> get(d.plotattributes, :seriestype, :path) === :hline, rd) >= 2
end

@testset "residdiagplot -- errors on a result with no residuals" begin
    @test_throws ArgumentError _apply_named(:residdiagplot, NO_RESID_RESULT)
end

@testset "componentplot -- reference line follows finmode (real fixture is multiplicative)" begin
    @test udg(RESULT, "finmode") == "multiplicative"
    rd = _apply_named(:componentplot, RESULT; reference = true, which = :trading_day)
    hl = filter(d -> get(d.plotattributes, :seriestype, :path) === :hline, rd)
    @test !isempty(hl)
    @test hl[1].args[1] == [1.0]
end

@testset "componentplot -- which=:all throws with no regression effects at all" begin
    @test_throws ArgumentError _apply_named(:componentplot, RESULT; which = :all)
end

@testset "componentplot -- unrecognized which throws" begin
    @test_throws ArgumentError _apply_named(:componentplot, RESULT; which = :bogus)
end

@testset "spanplot -- unrecognized kind throws" begin
    @test_throws ArgumentError _apply_named(:spanplot, RESULT; kind = :bogus)
end

@testset "spanplot -- named error when slidingspans/history weren't requested" begin
    @test_throws ArgumentError _apply_named(:spanplot, RESULT; kind = :slidingspans)
    @test_throws ArgumentError _apply_named(:spanplot, RESULT; kind = :history)
end

if x13_binary_available()
    # A single shared regression-bearing run for the W.8 tests that
    # genuinely need re-run machinery (.fct/.acf/.td aren't in RESULT's
    # own committed save list) -- built once per testset to avoid one
    # subprocess per @test.
    const _W8_REG_RESULT = x13(AIRLINE_Y; start = (1949, 1), trading = true, transform = :log, maxlead = 12)

    @testset "forecastplot -- observed + forecast + ribbon, in that order" begin
        rd = _apply_named(:forecastplot, _W8_REG_RESULT)
        @test length(rd) >= 3
        fc = rd[2]
        @test fc.args[1][1] == _W8_REG_RESULT.dates[end]       # prepended join
        @test fc.args[2][1] ≈ _W8_REG_RESULT.observed[end]
        @test length(fc.args[1]) == 13                         # 1 + 12
        rib = last(rd)
        @test haskey(rib.plotattributes, :ribbon)
        @test length(rib.args[1]) == 12
        @test rib.args[1][1] == _W8_REG_RESULT.dates[end] + Dates.Month(1) # NOT the join point
    end

    @testset "forecastplot -- history=n truncates the observed series only" begin
        rd = _apply_named(:forecastplot, _W8_REG_RESULT; history = 24)
        @test length(rd[1].args[1]) == 24
        @test length(rd[2].args[1]) == 13 # forecast unaffected
    end

    @testset "forecastplot -- backcast=true adds a leading extension before dates[1]" begin
        res = x13(AIRLINE_Y; start = (1949, 1), trading = true, transform = :log,
            spec_args = Dict("forecast.maxback" => "12"))
        rd = _apply_named(:forecastplot, res; backcast = true)
        @test any(d -> minimum(d.args[1]) < res.dates[1], rd)
    end

    @testset "residdiagplot -- ACF comes from .acf, matches _check_series directly" begin
        rd = _apply_named(:residdiagplot, _W8_REG_RESULT; panels = [:acf], lags = 24)
        acf_panel = rd[1]
        @test length(acf_panel.args[2]) == 24
        @test acf_panel.args[2] ≈ SeasonalAdjustment._check_series(_W8_REG_RESULT, :acf)[1:24] rtol = 1e-8
    end

    @testset "componentplot -- trading-day factors, non-degenerate, matches components()" begin
        rd = _apply_named(:componentplot, _W8_REG_RESULT; which = :trading_day, reference = false)
        @test length(rd) == 1
        @test rd[1].args[2] ≈ components(_W8_REG_RESULT; which = :trading_day)
        @test !all(==(rd[1].args[2][1]), rd[1].args[2])
    end

    @testset "componentplot -- additive mode uses a 0.0 reference line" begin
        # Synthetic finmode edit, not a fresh real run: confirmed
        # directly that requesting x11_mode=:additive alongside ANY
        # regression content is not reliably honored end to end (a
        # trading=true regressor hits its own separate leap-year error;
        # a plain easter[1] regressor with transform=:none runs
        # successfully but .udg's own finmode still reports
        # "multiplicative" -- X-13 apparently keeps multiplicative
        # preadjustment internally whenever a regARIMA model is present,
        # regardless of the requested x11 mode). This isolates what the
        # test actually checks -- componentplot's OWN reference-line
        # logic reading `finmode` -- from that separate, unresolved
        # binary-mode-negotiation question.
        additive_udg = Dict(k => (k == "finmode" ? "additive" : v) for (k, v) in RESULT.udg)
        res = _build_result(udg = additive_udg)
        rd = _apply_named(:componentplot, res; which = :trading_day)
        hl = filter(d -> get(d.plotattributes, :seriestype, :path) === :hline, rd)
        @test hl[1].args[1] == [0.0]
    end

    @testset "componentplot -- absent components skipped, not flat-lined, under which=:all" begin
        rd = _apply_named(:componentplot, _W8_REG_RESULT; which = :all) # only trading, no holiday/user/outlier
        for d in rd
            get(d.plotattributes, :seriestype, :path) === :hline && continue
            @test !all(==(d.args[2][1]), d.args[2])
        end
        @test length(filter(d -> get(d.plotattributes, :seriestype, :path) !== :hline, rd)) == 1
    end

    @testset "spanplot -- slidingspans bar chart reachable once requested" begin
        res = x13(AIRLINE_Y; start = (1949, 1), spec_args = Dict("slidingspans" => ""))
        rd = _apply_named(:spanplot, res; kind = :slidingspans)
        @test length(rd) == 1
        @test get(rd[1].plotattributes, :seriestype, :path) === :bar
        @test length(rd[1].args[2]) == 12
    end

    @testset "spanplot -- history line reachable once requested" begin
        res = x13(AIRLINE_Y; start = (1949, 1), spec_args = Dict("history.estimates" => "(sadj sadjchng)"))
        rd = _apply_named(:spanplot, res; kind = :history)
        @test length(rd) == 1
        @test !isempty(rd[1].args[2])
    end
else
    @warn "skipping W.8 real-binary plot tests: x13_binary_available() is false in this environment"
end

# ---------------------------------------------------------------------
# 8.6 Level 3 -- smoke tests with a real backend live in
# test/extended/ (gated on SEASONALADJUSTMENT_EXTENDED_TESTS=1, same
# convention as the R/Python cross-validation suite), since a plain
# `Pkg.test()` should never need Plots.jl installed.
# ---------------------------------------------------------------------

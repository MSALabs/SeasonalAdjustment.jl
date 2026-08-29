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
# 8.6 Level 3 -- smoke tests with a real backend live in
# test/extended/ (gated on SEASONALADJUSTMENT_EXTENDED_TESTS=1, same
# convention as the R/Python cross-validation suite), since a plain
# `Pkg.test()` should never need Plots.jl installed.
# ---------------------------------------------------------------------

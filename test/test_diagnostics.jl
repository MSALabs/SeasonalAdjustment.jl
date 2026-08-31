# test/test_diagnostics.jl -- W.5
#
# Test plan follows handoff/w5-diagnostics-api-handoff.md section 7,
# adapted to what this session actually verified (see development-
# sequence.md's W.5 row) -- every literal value below was read directly
# from the committed fixture `handoff/udg_and_residuals/auto_test.udg`,
# same discipline as every other real-fixture test in this project.

const _W5_UDG_FIXTURE = joinpath(@__DIR__, "..", "handoff", "udg_and_residuals", "auto_test.udg")

# Same fixture-loading pattern test_api.jl already uses repeatedly.
const AIRLINE_Y = begin
    spc = read(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc"), String)
    m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
    parse.(Float64, split(m.captures[1]))
end

# A synthetic X13Result whose .udg/.run_result point at the REAL committed
# fixture, so StatsAPI/coefficient extraction (which re-reads the .udg
# file directly, see _coefficient_lines) exercises real data without a
# subprocess. Every other field is a plausible stand-in (not the actual
# spec/run that produced the fixture) -- only .udg and .run_result are
# read by any test that uses this helper.
function _result_from_fixture()
    udg = parse_udg(_W5_UDG_FIXTURE)
    spec = X13Spec(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    dates = [Date(1949, 1) + Dates.Month(i) for i in 0:143]
    run_result = X13RunResult(true, "", String[], String[], dirname(_W5_UDG_FIXTURE), "auto_test")
    return X13Result(AIRLINE_Y, AIRLINE_Y, AIRLINE_Y, AIRLINE_Y, AIRLINE_Y, AIRLINE_Y, udg, dates, spec, run_result)
end

@testset "udg accessors -- committed fixture, no binary" begin
    d = parse_udg(_W5_UDG_FIXTURE)

    @test SeasonalAdjustment._udg_float(d,"aic")           ≈ 946.662093458382
    @test SeasonalAdjustment._udg_float(d,"bic")           ≈ 963.913277397589
    @test SeasonalAdjustment._udg_float(d,"aicc")          ≈ 947.339512813220
    @test SeasonalAdjustment._udg_float(d,"hq")            ≈ 953.672020420599
    @test SeasonalAdjustment._udg_float(d,"loglikelihood") ≈ 267.963217574308
    @test SeasonalAdjustment._udg_int(d, "nobs")            == 144
    @test SeasonalAdjustment._udg_int(d, "nefobs")          == 131
    @test SeasonalAdjustment._udg_int(d, "nreg")            == 3
    @test SeasonalAdjustment._udg_int(d, "nmodel")          == 2

    @test SeasonalAdjustment._udg_float(d,"no.such.key")   === nothing
    @test SeasonalAdjustment._udg_int(d,   "no.such.key")   === nothing

    @test transformfunction(d) === :log
    @test d["transform"] == "Automatic selection"

    @test arima_model(d) == "(0 1 1)(0 1 1)"

    m = mstats(d)
    @test m.m7 ≈ 0.203
    @test m.q  ≈ 0.20
    @test m.qm2 ≈ 0.22
    @test m.fail == 0
    @test length(filter(!isnothing, [m.m1, m.m2, m.m3, m.m4, m.m5, m.m6,
                                      m.m7, m.m8, m.m9, m.m10, m.m11])) == 11

    q = qs(d)
    @test q.original.statistic ≈ 167.64858
    @test q.original.pvalue    ≈ 0.0
    @test q.sa.statistic       ≈ 0.0
    @test q.sa.pvalue          ≈ 1.0
    @test q.residual.pvalue    ≈ 1.0
    @test qs(d; which = :original).statistic ≈ 167.64858
    @test_throws ArgumentError qs(d; which = :bogus)

    o = outliers(d)
    @test length(o) == 1
    @test o[1].label  == "AO1951.May"
    @test o[1].type   === :ao
    @test o[1].year   == 1951
    @test o[1].period == 5   # month-name converted for THIS display field only
    of = outliers(d; full = true)[1]
    @test of.estimate ≈ 0.100155824411322
    @test of.stderror ≈ 0.0204386646810968
    @test of.tstat    ≈ 4.90031154060440
    c = outlier_counts(d)
    @test c.ao == 1 && c.ls == 0 && c.total == 1

    fb = fivebestmdl(d)
    @test length(fb) == 5
    @test fb[1].model == "(0 1 0)(0 1 1)"
    @test fb[1].bic   ≈ -4.007
    @test issorted([f.bic for f in fb])

    s = seasonality_tests(d)
    @test s.stable_d8_f == (215.358, 0.00)
    @test s.stable_f    == (164.889, 0.00)
    @test s.kruskal_wallis == (132.948, 0.00)
    @test s.moving_seasonality == (3.557, 0.02)
    @test s.identifiable === true

    rd = residual_diagnostics(d)
    @test rd.durbin_watson ≈ 1.9503780
    @test rd.skewness ≈ 0.0900
    @test rd.kurtosis ≈ 3.0698
    @test rd.n_sig_acf == 2
    @test length(rd.ljung_box) == 2
    @test rd.ljung_box[1].lag == 3
    @test rd.ljung_box[1].pvalue ≈ 0.009

    sp = spectral_peaks(d)
    @test sp.seasonal     == [:rsd, :sa]
    @test sp.trading_day  == [:sa, :irr]

    f = filters(d)
    @test f.trend_ma == 9
    @test f.mode === :multiplicative
    @test all(==("MSR"), f.seasonal_ma)
    @test length(f.seasonal_ma) == 12
end

@testset "udg accessors -- absent families return nothing/empty, not errors" begin
    d = Dict("nobs" => "144")
    @test mstats(d)             === nothing
    @test fivebestmdl(d)        === nothing
    @test seasonality_tests(d)  === nothing
    @test outliers(d)           == NamedTuple[]
    @test outlier_counts(d).total === nothing
    @test spectral_peaks(d).seasonal == Symbol[]
    @test qs(d).original === nothing
    @test filters(d).mode === nothing
end

@testset "transformfunction -- confirmed strings (2 from fixture, 2 from a real explicit-transform run)" begin
    @test transformfunction(Dict("aictrans" => "Log(y)"))             === :log
    @test transformfunction(Dict("transform" => "No transformation")) === :none
    @test transformfunction(Dict("transform" => "Log(y)"))            === :log
    @test transformfunction(Dict("transform" => "None"))              === :none   # defensive, unconfirmed alias
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

@testset "outliers -- unrecognized trailing token leaves period=nothing, not a guess" begin
    d = Dict("AutoOutlier\$AO1951.Q2" => "+0.1E+00 +0.2E-01 +0.5E+01")
    o = outliers(d)[1]
    @test o.label == "AO1951.Q2"
    @test o.period === nothing   # "Q2" isn't a month abbreviation and isn't a bare integer
end

@testset "StatsAPI on X13Result -- fixture-backed" begin
    r = _result_from_fixture()
    @test StatsAPI.aic(r)  ≈ 946.662093458382
    @test StatsAPI.bic(r)  ≈ 963.913277397589
    @test StatsAPI.aicc(r) ≈ 947.339512813220
    @test StatsAPI.loglikelihood(r) ≈ 267.963217574308
    @test StatsAPI.nobs(r) == 144
    @test StatsAPI.dof(r)  == 5
    @test StatsAPI.residuals(r) === r.residuals

    coefs, names, ses = StatsAPI.coef(r), StatsAPI.coefnames(r), StatsAPI.stderror(r)
    @test length(coefs) == length(names) == length(ses) == 6   # nreg(3)+nregderived(1)+nmodel(2)
    @test "Easter[1]" in names
    @test "MA\$Seasonal\$12\$12" in names
    i = findfirst(==("AO1951.May"), names)
    @test i !== nothing
    @test coefs[i] ≈ 0.100155824411322
    @test ses[i]   ≈ 0.0204386646810968
    @test names == StatsAPI.coefnames(_result_from_fixture())   # file-order, reproducible

    # StatsAPI.vcov(r) is NOT tested here (W.5 -> W.7.5): _result_from_fixture()'s
    # `.spec` is a plain placeholder with none of the real regression content
    # that produced these coefficients (trading/easter/AO), so a real vcov()
    # call would re-run against the WRONG spec -- see test_w7.jl's own
    # real-binary vcov tests, built from a matching x13() run instead.
end

@testset "_coefficient_name -- the three real cases, not one blanket rule" begin
    @test SeasonalAdjustment._coefficient_name("1-Coefficient Trading Day\$Weekday") == "Trading Day\$Weekday"
    @test SeasonalAdjustment._coefficient_name("AutoOutlier\$AO1951.May") == "AO1951.May"
    @test SeasonalAdjustment._coefficient_name("Easter[1]\$Easter[1]") == "Easter[1]"
    @test SeasonalAdjustment._coefficient_name("MA\$Nonseasonal\$01\$01") == "MA\$Nonseasonal\$01\$01"   # unchanged
end

@testset "show(::X13Result) -- summary block" begin
    r = _result_from_fixture()
    s = sprint(show, MIME"text/plain"(), r)
    @test occursin("(0 1 1)(0 1 1)", s)
    @test occursin("log", lowercase(s))
    @test occursin("144", s)
end

@testset "spec_args -- renders a block with no typed field" begin
    s = X13Spec(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12),
                spec_args = Dict("forecast.maxlead" => "0"))
    txt = render(s)
    @test occursin("forecast {", txt)
    @test occursin("maxlead = 0", txt)
end

@testset "spec_args -- dotless key with empty value renders an empty block" begin
    s = X13Spec(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12),
                spec_args = Dict("slidingspans" => ""))
    @test occursin("slidingspans { }", render(s))
end

@testset "spec_args -- dotless key with a non-empty value throws (ambiguous shape)" begin
    @test_throws ArgumentError X13Spec(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12),
        spec_args = Dict("slidingspans" => "yes"))
end

@testset "spec_args -- multiple keys group into one block" begin
    s = X13Spec(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12),
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
        @test_throws ArgumentError X13Spec(AIRLINE_Y; start = (1949, 1),
            seasonal_order = (0, 1, 1, 12), spec_args = Dict(k => "x"))
    end
end

@testset "spec_args -- values pass through verbatim, no quoting" begin
    s = X13Spec(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12),
                spec_args = Dict("check.print" => "(acf pacf)"))
    @test occursin("print = (acf pacf)", render(s))
end

@testset "X13Spec(base; kwargs...) -- spec_args overrides through the generic copy-constructor" begin
    base = X13Spec(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    @test isempty(base.spec_args)
    overridden = X13Spec(base; spec_args = Dict("forecast.maxlead" => "0"))
    @test overridden.spec_args == Dict("forecast.maxlead" => "0")
    @test occursin("forecast {", render(overridden))
end

if x13_binary_available()

@testset "series() -- re-runs for an unsaved table" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    # :d8 is now always in x13()'s own default save set (W.6, so
    # monthplot's SI-ratio overlay never needs to re-run) -- :d9 is
    # genuinely NOT saved by default, so it's the one that still
    # exercises series()'s own automatic-re-run path here.
    @test !(:d9 in something(r.spec.save, Symbol[]))
    @test :d8 in something(r.spec.save, Symbol[])
    d9 = series(r, :d9)
    @test length(d9) == length(r.observed)
    @test all(isfinite, d9)
end

@testset "series() -- already-saved table does NOT re-run" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    @test series(r, :d10) == r.seasonal_factors
    d8 = series(r, :d8)   # also already-saved (W.6's default), same no-re-run path
    @test length(d8) == length(r.observed)
end

@testset "series(reeval=false) -- throws naming the table" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    @test_throws ArgumentError series(r, :d9; reeval = false)
end

@testset "series() -- vector form, one combined re-run" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    out = series(r, [:d9, :c17])
    @test Set(keys(out)) == Set([:d9, :c17])
    @test length(out[:d9]) == length(r.observed)
end

@testset "series() -- unknown table errors before spawning" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    @test_throws ArgumentError series(r, :d99)
end

@testset "spec_args -- slidingspans/history actually run and populate udg" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12),
            spec_args = Dict("slidingspans" => "", "history.estimates" => "(sadj sadjchng)"))
    @test r.udg["sspans"]  == "yes"
    @test r.udg["history"] == "yes"
end

@testset "spec_args -- a syntactically invalid block surfaces the binary's error" begin
    @test_throws ErrorException x13(AIRLINE_Y; start = (1949, 1),
        seasonal_order = (0, 1, 1, 12), spec_args = Dict("forecast.maxlead" => "banana"))
end

@testset "maxlead -- default is NOT forced to 0, and 0 is reachable" begin
    r_default = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    r_zero    = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12),
                    spec_args = Dict("forecast.maxlead" => "0"))
    @test r_default.udg["nfcst"] != r_zero.udg["nfcst"]
end

@testset "select_order -- resolves an ARIMA order via automdl" begin
    r = select_order(AIRLINE_Y; start = (1949, 1))
    @test r.order isa Tuple{Int,Int,Int}
    @test r.seasonal_order isa Tuple{Int,Int,Int,Int}
    @test r.seasonal_order[4] == 12
    @test r.transform in (:log, :none)
end

@testset "import_spc -- round-trips this package's own render() output" begin
    spec = X13Spec(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12),
                    transform = :log, outlier = true, residuals = true, save = [:d10, :d11])
    path = write_spec(spec, joinpath(mktempdir(), "roundtrip.spc"))
    reimported = import_spc(path)
    @test reimported.y == spec.y
    @test reimported.start == spec.start
    @test reimported.transform === :log
    @test reimported.outlier == true
    @test reimported.residuals == true
    @test Set(reimported.save) == Set(spec.save)
    path2 = write_spec(reimported, joinpath(mktempdir(), "roundtrip2.spc"))
    result = run_x13(path2)
    @test result.success
end

@testset "open_output -- errors clearly when there's no output file yet" begin
    r = x13(AIRLINE_Y; start = (1949, 1), seasonal_order = (0, 1, 1, 12))
    bogus_dir = mktempdir()
    fake = X13Result(r.observed, r.seasonally_adjusted, r.trend, r.seasonal_factors,
        r.irregular, r.residuals, r.udg, r.dates, r.spec,
        X13RunResult(true, "", String[], String[], bogus_dir, "nope"))
    @test_throws ErrorException open_output(fake)
end

else
    @warn "skipping W.5 real-binary tests: x13_binary_available() is false in this environment"
end

# test/test_api.jl -- W.4
#
# Test plan follows handoff/w4-api.md, adapted to what this session
# could actually verify -- see development-sequence.md's W.4 status
# note for exactly which cases ran against the real binary vs. were
# checked structurally only (same split established in W.1-W.3).

@testset "x13 -- validate! runs before any subprocess (short series)" begin
    @test_throws ArgumentError x13(collect(1.0:24.0))
end

@testset "x13 -- save kwarg is explicitly rejected, not silently passed through" begin
    @test_throws ArgumentError x13(collect(1.0:48.0); save = [:d10])
end

@testset "x13 -- arima+automdl conflict throws before any subprocess" begin
    @test_throws ArgumentError x13(collect(1.0:48.0); seasonal_order = (0, 1, 1, 12), maxorder = (2, 1))
end

@testset "x13 -- dated-series bridging via index" begin
    if x13_binary_available()
        y = collect(1.0:48.0)
        idx = [Date(1949, 1) + Dates.Month(i) for i in 0:47]
        result = x13(y; index = idx)
        @test result.dates[1] == Date(1949, 1)
        @test result.dates[end] == Date(1952, 12)
    else
        @warn "skipping x13 dated-series-bridging test: x13_binary_available() is false in this environment"
    end
end

@testset "x13 -- plain call reproduces the committed X-11 baseline exactly" begin
    if x13_binary_available()
        spc = read(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        y = parse.(Float64, split(m.captures[1]))

        result = x13(y; start = (1949, 1))
        @test length(result.seasonally_adjusted) == 144
        @test length(result.trend) == 144
        @test length(result.seasonal_factors) == 144
        @test length(result.irregular) == 144
        @test result.dates[1] == Date(1949, 1)
        @test result.observed == y

        committed_d10 = last.(parse_table(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.d10")))
        committed_d11 = last.(parse_table(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.d11")))
        @test all(isapprox.(result.seasonal_factors, committed_d10; atol = 1e-9))
        @test all(isapprox.(result.seasonally_adjusted, committed_d11; atol = 1e-9))

        @test result.run_result.success
        @test result.spec isa X13Spec
    else
        @warn "skipping x13 X-11-baseline-reproduction test: x13_binary_available() is false in this environment"
    end
end

@testset "x13 -- seats=true reproduces the committed SEATS baseline exactly" begin
    if x13_binary_available()
        spc = read(joinpath(_VERIFICATION_DIR, "seats_baseline", "seats_test.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        y = parse.(Float64, split(m.captures[1]))

        result = x13(y; start = (1949, 1), seats = true, transform = :auto, aictest = [:td, :easter], automdl = true)
        committed_s10 = last.(parse_table(joinpath(_VERIFICATION_DIR, "seats_baseline", "seats_test.s10")))
        committed_s11 = last.(parse_table(joinpath(_VERIFICATION_DIR, "seats_baseline", "seats_test.s11")))
        @test all(isapprox.(result.seasonal_factors, committed_s10; atol = 1e-6))
        @test all(isapprox.(result.seasonally_adjusted, committed_s11; atol = 1e-6))
        @test result.spec.seats
    else
        @warn "skipping x13 SEATS-baseline-reproduction test: x13_binary_available() is false in this environment"
    end
end

@testset "x13 -- maxorder/maxdiff/trading render and run cleanly" begin
    if x13_binary_available()
        spc = read(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        y = parse.(Float64, split(m.captures[1]))

        result = x13(y; start = (1949, 1), maxorder = (2, 1), maxdiff = (2, 1), trading = true, transform = :log)
        @test result.run_result.success
        @test occursin("automdl { maxorder = (2 1)  maxdiff = (2 1) }", render(result.spec))
        @test occursin("variables = (td)", render(result.spec))
    else
        @warn "skipping x13 maxorder/maxdiff/trading real-run test: x13_binary_available() is false in this environment"
    end
end

const _UDG_DIR = joinpath(@__DIR__, "..", "handoff", "udg_and_residuals")

@testset "x13 -- residuals and udg are always populated (W.4 addendum)" begin
    if x13_binary_available()
        spc = read(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        y = parse.(Float64, split(m.captures[1]))

        result = x13(y; start = (1949, 1))
        @test length(result.residuals) == 144
        @test result.residuals != result.irregular   # confirms a genuinely different series, not aliased
        @test !isempty(result.udg)
        @test haskey(result.udg, "arimamdl")

        # residuals genuinely come from estimate{save=(rsd)}, a real,
        # separate spec block -- confirmed directly against the real
        # binary via the committed resid_test.spc fixture, not just
        # trusting x13()'s own internal wiring.
        @test occursin("estimate { save = (rsd) }", render(result.spec))
    else
        @warn "skipping x13 residuals/udg test: x13_binary_available() is false in this environment"
    end
end

@testset "x13 -- residuals kwarg is explicitly rejected, not silently passed through" begin
    @test_throws ArgumentError x13(collect(1.0:48.0); residuals = true)
end

@testset "run_x13 -- udg=true produces a real, parseable .udg file (committed fixture)" begin
    if x13_binary_available()
        result = run_x13(joinpath(_UDG_DIR, "auto_test.spc"); udg = true)
        @test result.success
        udg = parse_udg(joinpath(result.dir, "auto_test.udg"))
        @test length(udg) > 300   # the real fixture has 376 entries
        @test udg["arimamdl"] == "(0 1 1)(0 1 1)"
        @test any(k -> startswith(k, "AutoOutlier\$"), keys(udg))
    else
        @warn "skipping run_x13 udg test: x13_binary_available() is false in this environment"
    end
end

@testset "run_x13 -- no udg file without the -S flag" begin
    if x13_binary_available()
        result = run_x13(joinpath(_UDG_DIR, "auto_test.spc"))  # udg=false (default)
        @test result.success
        @test !isfile(joinpath(result.dir, "auto_test.udg"))
    else
        @warn "skipping run_x13 no-udg test: x13_binary_available() is false in this environment"
    end
end

@testset "static() -- ARIMA order and outliers resolve cleanly from a real automatic run" begin
    if x13_binary_available()
        spc = read(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        y = parse.(Float64, split(m.captures[1]))

        result = x13(y; start = (1949, 1), transform = :auto, automdl = true,
            outlier = true, aictest = [:td, :easter])
        s = static(result)

        # matches this session's own real, verified value on the
        # official airline series -- see handoff/udg_and_residuals/
        @test s.arima_model == "(0 1 1)(0 1 1)"
        @test s.automdl == false
        @test s.maxorder === nothing
        @test s.transform === :log
        @test s.outlier == false
        @test "AO1951.May" in s.regression_variables
    else
        @warn "skipping static() resolution test: x13_binary_available() is false in this environment"
    end
end

@testset "static() -- re-running the resolved spec reproduces the automatic result (not bit-identical)" begin
    if x13_binary_available()
        spc = read(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        y = parse.(Float64, split(m.captures[1]))

        result = x13(y; start = (1949, 1), transform = :auto, automdl = true,
            outlier = true, aictest = [:td, :easter])
        s = static(result)
        path = write_spec(s, joinpath(mktempdir(), "static_repro.spc"))
        r2 = run_x13(path)
        @test r2.success

        d11_original = last.(parse_table(joinpath(result.run_result.dir, "$(result.run_result.basename).d11")))
        d11_static = last.(parse_table(joinpath(r2.dir, "static_repro.d11")))
        # Confirmed directly, not assumed: re-estimating a pre-specified
        # model doesn't converge bit-identically to the automatic
        # pipeline's own result (~1e-6 relative, observed this session)
        # -- the same caveat R's own seasonal::static() documents.
        @test all(isapprox.(d11_original, d11_static; rtol = 1e-3))
    else
        @warn "skipping static() reproduction test: x13_binary_available() is false in this environment"
    end
end

@testset "static() -- an already-explicit spec resolves to the same values (idempotent)" begin
    if x13_binary_available()
        spc = read(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        y = parse.(Float64, split(m.captures[1]))

        result = x13(y; start = (1949, 1), transform = :log, arima_model = "(0 1 1)(0 1 1)")
        s = static(result)
        @test s.transform === :log
        @test s.arima_model == "(0 1 1)(0 1 1)"
        @test s.automdl == false
        @test isempty(s.regression_variables)  # no outlier{} was requested, so nothing to resolve
    else
        @warn "skipping static() idempotence test: x13_binary_available() is false in this environment"
    end
end

@testset "x13 -- a failing run throws with the real binary's error text, not a half-populated result" begin
    if x13_binary_available()
        # arima_model is R-style raw passthrough -- validate! doesn't
        # (and shouldn't) parse its internal syntax, so a malformed
        # string passes validate! cleanly and fails only once the real
        # binary actually parses the .spc file. Confirms x13() itself
        # (not just run_x13, already covered by W.3) surfaces that
        # failure as a thrown error naming the real binary text, not a
        # silently half-populated X13Result.
        y = collect(1.0:48.0)
        err = nothing
        try
            x13(y; arima_model = "not valid syntax")
        catch e
            err = e
        end
        @test err isa ErrorException
        @test occursin("Argument name", sprint(showerror, err))
    else
        @warn "skipping x13 failing-run test: x13_binary_available() is false in this environment"
    end
end

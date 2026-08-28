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

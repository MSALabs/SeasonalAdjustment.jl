# test/test_run_parse.jl -- W.3
#
# Test plan follows handoff/w3-run-parse.md section 4, adapted to what
# this session could actually verify -- see development-sequence.md's
# W.3 status note for exactly which cases ran against the real binary
# vs. were checked structurally only (same split as W.1/W.2).

const _VERIFICATION_DIR = joinpath(@__DIR__, "..", "handoff", "verification")

@testset "parse_table -- X-11 D-tables, real fixture" begin
    d11 = parse_table(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.d11"))
    @test length(d11) == 144
    @test d11[1] == (Date(1949, 1), 124.546106577719)  # confirmed directly against the committed fixture
    @test all(v -> v[2] > 0, d11)  # seasonally adjusted airline passengers must stay positive
end

@testset "parse_table -- SEATS S-tables, real fixture" begin
    # Confirms section 1's finding directly: SEATS tables use .sNN, not
    # .dNN, but the exact same internal parser handles both.
    s11 = parse_table(joinpath(_VERIFICATION_DIR, "seats_baseline", "seats_test.s11"))
    @test length(s11) == 144
    @test s11[1][1] == Date(1949, 1)
    @test s11[1][2] ≈ 122.847234947105
end

@testset "parse_table -- regARIMA residuals (.rsd), real fixture (W.4 addendum)" begin
    # estimate { save = (rsd) } -- a distinct spec block from x11{}/
    # seats{}, but the same tab-separated table format, confirmed
    # directly against a real fixture.
    rsd_dir = joinpath(@__DIR__, "..", "handoff", "udg_and_residuals")
    rsd = parse_table(joinpath(rsd_dir, "resid_test.rsd"))
    @test length(rsd) == 144
    @test rsd[1] == (Date(1949, 1), -0.00183687953416382)  # confirmed directly against the committed fixture
end

@testset "parse_udg -- real fixture, no binary needed (W.4 addendum)" begin
    udg_dir = joinpath(@__DIR__, "..", "handoff", "udg_and_residuals")
    udg = parse_udg(joinpath(udg_dir, "auto_test.udg"))
    @test length(udg) == 376  # confirmed directly: the committed fixture's real line count
    @test udg["arimamdl"] == "(0 1 1)(0 1 1)"
    @test udg["outlier.total"] == "1"
    @test any(k -> startswith(k, "AutoOutlier\$"), keys(udg))
    # every line in the real fixture has exactly one colon and no
    # duplicate keys -- confirmed directly, so a plain Dict loses
    # nothing; this is a regression check on that finding, not a guess.
    @test count(":", read(joinpath(udg_dir, "auto_test.udg"), String)) == 376
end

@testset "run_x13 / parse_output -- real invocation, typed result" begin
    if x13_binary_available()
        spec_path = joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc")
        result = run_x13(spec_path)
        @test result.success
        @test isempty(result.errors)
        @test result.dir != dirname(spec_path)  # ran in a scratch dir, not the fixture dir itself
        @test isfile(joinpath(result.dir, "airline_official.spc"))  # the fixture dir itself is untouched

        tables = parse_output(result, [:d10, :d11, :d12, :d13])
        @test length(tables[:d10]) == 144
        committed_d11 = parse_table(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.d11"))
        @test all(isapprox.(last.(tables[:d11]), last.(committed_d11); atol = 1e-9))
    else
        @warn "skipping run_x13 real-invocation test: x13_binary_available() is false in this environment"
    end
end

@testset "run_x13 -- the real minimum-length error, typed not raw text" begin
    if x13_binary_available()
        short_spec = joinpath(_VERIFICATION_DIR, "w2_length_grid", "batch_1.spc")  # the real 24-month failing case
        result = run_x13(short_spec)
        @test !result.success
        @test any(e -> occursin("3 complete years", e), result.errors)
    else
        @warn "skipping minimum-length-error test: x13_binary_available() is false in this environment"
    end
end

@testset "bulk: run + parse every case from W.2's real 24-case length grid" begin
    if x13_binary_available()
        # These 24 fixtures use a bare `x11 { }` with no `save=` clause --
        # confirmed directly (`grep -H "x11" .../w2_length_grid/*.spc`)
        # that all 24 files are identical on this point. They were built
        # by W.2's own handoff to probe the minimum-length boundary only,
        # not table output: a bare x11{} makes X-13 compute the
        # adjustment but write no output table files at all (also
        # confirmed directly -- a successful run's scratch dir contains
        # only .html/.spc/_err.html/_log.html, no .dNN). So this test
        # checks only success/failure against the known boundary, not
        # parse_output/d10 -- asserting d10 existence here would be
        # testing something these fixtures were never built to produce.
        for i in 1:24
            spec_path = joinpath(_VERIFICATION_DIR, "w2_length_grid", "batch_$i.spc")
            result = run_x13(spec_path)
            length_ok = i > 3   # cases 1-3 are the confirmed 24-month failures
            @test result.success == length_ok
            if !result.success
                @test any(e -> occursin("3 complete years", e), result.errors)
            end
        end
    else
        @warn "skipping W.2 length-grid bulk run: x13_binary_available() is false in this environment"
    end
end

@testset "run_x13_batch -- parallel and serial produce IDENTICAL results" begin
    if x13_binary_available()
        specs = [joinpath(_VERIFICATION_DIR, "w2_length_grid", "batch_$i.spc") for i in 4:24]  # skip the known-failing cases
        par = run_x13_batch(specs; parallel = true)
        serial = run_x13_batch(specs; parallel = false)
        @test length(par) == length(serial) == length(specs)
        for i in eachindex(specs)
            @test par[i].success == serial[i].success
            @test par[i].success  # sanity: all of 4:24 should succeed (36+ months)
            @test par[i].errors == serial[i].errors
            @test isempty(par[i].warnings) == isempty(serial[i].warnings)
        end
    else
        @warn "skipping run_x13_batch parallel-vs-serial test: x13_binary_available() is false in this environment"
    end
end

@testset "run_x13_batch -- timing, reported not asserted (see comment)" begin
    # handoff/w3-run-parse.md's own async-task design was benchmarked
    # for real this session (not just structurally reasoned from the
    # Python finding): N=20, serial 1.02s vs parallel 0.54s (1.89x);
    # N=100, serial 15.67s vs parallel 5.62s (2.79x) -- see
    # development-sequence.md's W.3 row. A hard `t_parallel < t_serial`
    # assertion here turned out to be a real bug in its own right, not
    # just this environment's noise: confirmed directly against real CI
    # (macOS/Windows/older-Julia runners), where shared/virtualized
    # hardware with few cores gave the OPPOSITE result on some runs (one
    # observed: parallel 2.14s vs serial 0.47s). Timing is not a
    # reliable correctness signal on arbitrary CI hardware, so this is
    # now a reported-but-not-asserted observation instead of a gate.
    if x13_binary_available()
        specs = [joinpath(_VERIFICATION_DIR, "w2_length_grid", "batch_$i.spc") for i in 4:15]
        t_serial = @elapsed run_x13_batch(specs; parallel = false)
        t_parallel = @elapsed run_x13_batch(specs; parallel = true)
        @info "run_x13_batch timing (this environment)" t_serial t_parallel
    else
        @warn "skipping run_x13_batch timing test: x13_binary_available() is false in this environment"
    end
end

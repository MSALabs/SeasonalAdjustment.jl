# test/test_spec.jl -- W.2
#
# Test plan follows handoff/w2-spec.md section 4, adapted to what this
# session could actually verify -- see development-sequence.md's W.2
# status note for exactly which cases ran against the real binary vs.
# were checked structurally only.

@testset "minimum length -- real, confirmed boundary" begin
    short = collect(1.0:24.0)
    @test_throws ArgumentError X13Spec(short)  # validate! catches this BEFORE any subprocess

    ok = collect(1.0:36.0)
    spec = X13Spec(ok)   # must NOT throw -- 36 is the real, confirmed working boundary
    @test spec isa X13Spec
    @test occursin("series {", render(spec))
    @test occursin("data = (", render(spec))
end

@testset "the three validate! checks, each triggered directly" begin
    y = collect(1.0:48.0)
    x = collect(1.0:48.0)

    # check 2: regressor doesn't cover the +12 forecast horizon
    short_regressor = zeros(48)  # matches series length exactly, not 48+12=60
    @test_throws ArgumentError X13Spec(y; regression_user = short_regressor, regression_usertype = :holiday)
    ok_regressor = zeros(60)
    @test X13Spec(y; regression_user = ok_regressor, regression_usertype = :holiday) isa X13Spec

    # check 3: regARIMA (a regression block present, via exog) + multiplicative without transform=:log
    @test_throws ArgumentError X13Spec(y; exog = x, x11_mode = :multiplicative, transform = nothing)
    @test X13Spec(y; exog = x, x11_mode = :multiplicative, transform = :log) isa X13Spec
    # multiplicative alone, no regression block at all, is fine without transform=:log
    @test X13Spec(y; x11_mode = :multiplicative) isa X13Spec

    # an unrecognized x11_mode is also caught by validate!, not left to blow up at render time
    @test_throws ArgumentError X13Spec(y; x11_mode = :bogus)
end

@testset "render -- X-13's short mode keywords, not the full words" begin
    # A real bug found this session: x11{mode=...} requires mult/add/
    # logadd/pseudoadd -- the full word ("multiplicative") is a real
    # parse error against the actual binary ("Argument name
    # \"multiplicative\" not found"). Confirmed the fix directly too.
    y = collect(1.0:48.0)
    for (sym, keyword) in (
        :multiplicative => "mult",
        :additive => "add",
        :logadditive => "logadd",
        :pseudoadditive => "pseudoadd",
    )
        spec = X13Spec(y; x11_mode = sym)
        @test occursin("mode = $keyword", render(spec))
    end
end

@testset "render -- seasonal_order builds the arima model string" begin
    y = collect(1.0:48.0)
    spec = X13Spec(y; seasonal_order = (0, 1, 1, 12))
    @test occursin("arima { model = (0 1 1)(0 1 1)12 }", render(spec))

    spec2 = X13Spec(y; order = (1, 0, 0), seasonal_order = (0, 1, 1, 12))
    @test occursin("arima { model = (1 0 0)(0 1 1)12 }", render(spec2))

    # R-style raw passthrough takes priority over the curated fields
    spec3 = X13Spec(y; arima_model = "(2 1 0)", seasonal_order = (0, 1, 1, 12))
    @test occursin("arima { model = (2 1 0) }", render(spec3))
    @test !occursin("(0 1 1)12", render(spec3))
end

@testset "render -- seats vs x11 block selection" begin
    y = collect(1.0:48.0)
    @test occursin("x11 { save = (d10 d11 d12 d13) }", render(X13Spec(y)))
    @test occursin("seats { save = (s10 s11 s12 s13) }", render(X13Spec(y; seats = true)))
    @test occursin("save = (d10)", render(X13Spec(y; save = [:d10])))
end

@testset "render -- estimate{save=(rsd)} block, residuals field (W.4 addendum)" begin
    y = collect(1.0:48.0)
    @test !occursin("estimate", render(X13Spec(y)))  # residuals=false by default -- no block at all
    @test occursin("estimate { save = (rsd) }", render(X13Spec(y; residuals = true)))
end

@testset "X13Spec(base::X13Spec; kwargs...) -- copy-constructor overrides only the named fields" begin
    y = collect(1.0:48.0)
    base = X13Spec(y; automdl = true, transform = :auto)
    overridden = X13Spec(base; arima_model = "(0 1 1)(0 1 1)", automdl = false, transform = :log)
    @test overridden.arima_model == "(0 1 1)(0 1 1)"
    @test overridden.automdl == false
    @test overridden.transform === :log
    @test overridden.y == base.y                    # untouched fields copy through unchanged
    @test overridden.start == base.start

    @test_throws ArgumentError X13Spec(base; not_a_real_field = 1)

    # the override still gets validate!'d -- an override combination
    # that violates a real rule throws just like a fresh construction
    # would, not silently accepted.
    @test_throws ArgumentError X13Spec(base; arima_model = "(0 1 1)(0 1 1)", automdl = true)
end

@testset "generate_specs -- parallel matches serial" begin
    series_list = [collect(1.0:48.0) .+ i for i in 1:20]
    options_list = [(;) for _ in 1:20]
    par = generate_specs(series_list, options_list; parallel = true)
    serial = generate_specs(series_list, options_list; parallel = false)
    @test length(par) == length(serial) == 20
    for i in 1:20
        @test render(par[i]) == render(serial[i])
    end

    @test_throws ArgumentError generate_specs(series_list, options_list[1:end-1])
end

@testset "write_spec -- writes and returns the path" begin
    spec = X13Spec(collect(1.0:36.0))
    path = joinpath(mktempdir(), "test.spc")
    ret = write_spec(spec, path)
    @test ret == path
    @test read(path, String) == render(spec)
end

@testset "bulk: varied length x seed x option combination (structural, 120 cases)" begin
    # Extends handoff/w2-spec.md's own 120-case grid to actually run,
    # not just design -- structural checks only here (fast, no
    # subprocess); a real-binary spot-check subset follows below.
    lengths = [36, 48, 60, 84, 120, 144, 180, 240]
    seeds = 1:5
    option_sets = [(;), (; transform = :log), (; outlier = true)]

    count = 0
    for len in lengths, seed in seeds, opts in option_sets
        rng = Random.MersenneTwister(seed * 1000 + len)
        y = max.(100 .+ cumsum(randn(rng, len) .* 0.5) .+ 10 .* sin.(2π .* (1:len) ./ 12), 1.0)
        spec = X13Spec(y; opts...)
        rendered = render(spec)
        @test occursin("series {", rendered)
        @test occursin("data = (", rendered)
        @test length(spec.y) == len
        count += 1
    end
    @test count == length(lengths) * length(seeds) * length(option_sets)  # == 120
end

@testset "real-binary spot check: a representative subset of the grid above" begin
    if x13_binary_available()
        cases = [(36, 1, (;)), (48, 2, (; transform = :log)), (240, 3, (; outlier = true)), (144, 5, (;))]
        for (len, seed, opts) in cases
            rng = Random.MersenneTwister(seed * 1000 + len)
            y = max.(100 .+ cumsum(randn(rng, len) .* 0.5) .+ 10 .* sin.(2π .* (1:len) ./ 12), 1.0)
            spec = X13Spec(y; opts...)
            path = joinpath(mktempdir(), "spotcheck.spc")
            write_spec(spec, path)
            result = run_x13(path)
            @test result.success
            @test isempty(result.errors)
        end
    else
        @warn "skipping real-binary spot check: x13_binary_available() is false in this environment"
    end
end

@testset "CAPSTONE: W.0's regressor through W.2's spec builder reproduces the exact documented value" begin
    # Closes the loop one level higher than W.0's own capstone test:
    # instead of hand-assembling .spc text, this goes through X13Spec/
    # render() directly -- the real, intended pipeline. Confirmed this
    # session to reproduce diwali_official.spc's exact October 1949
    # value (0.753973303751993) when regression_variables=["td"] is
    # included alongside the user regressor (both are present in the
    # original proof; omitting "td" produces a different, still valid,
    # but non-matching result -- confirmed directly, not assumed).
    if x13_binary_available()
        spc = read(joinpath(@__DIR__, "..", "handoff", "verification", "airline_baseline", "airline_official.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        y = parse.(Float64, split(m.captures[1]))

        synthetic_diwali(year::Integer) = (1949 <= year <= 1961) ? ((year - 1949) % 3 == 0 ? Date(year, 10, 10) : Date(year, 11, 10)) : nothing
        no_weekend_cal = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set{Int}())
        reg = custom_holiday_regressor(Date(1949, 1, 1), Date(1961, 12, 31), no_weekend_cal, synthetic_diwali)

        spec = X13Spec(
            y;
            start = (1949, 1),
            transform = :log,
            regression_variables = ["td"],
            regression_user = reg,
            regression_usertype = :holiday,
            regression_user_name = :diwali,
            x11_mode = :multiplicative,
            save = [:d10],
        )
        path = joinpath(mktempdir(), "w2capstone.spc")
        write_spec(spec, path)
        result = run_x13(path)
        @test result.success
        d10 = parse_output(result, [:d10])[:d10]
        oct1949 = only(filter(t -> t[1] == Date(1949, 10), d10))
        @test oct1949[2] ≈ 0.753973303751993 atol = 1e-9
    else
        @warn "skipping W.0-through-W.2 capstone: x13_binary_available() is false in this environment"
    end
end

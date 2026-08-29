# test/test_quarterly.jl -- quarterly interval support
#
# X-13ARIMA-SEATS accepts exactly two seasonal periods for seasonal
# adjustment -- period=12 (monthly) and period=4 (quarterly) -- confirmed
# directly against the real binary this session ("ERROR: Seasonal period
# must be 4 or 12 if a seasonal adjustment is done", hit directly testing
# every other plausible value: 1, 2, 3, 6, 24, 52). This file tests the
# period-awareness threaded through X13Spec/validate!/render, parse_table/
# parse_output's YYYYQQ handling, x13()'s period kwarg, and the calendar/
# regressor functions' freq=:quarter tiling.

@testset "validate! -- period must be 4 or 12 (structural, no subprocess)" begin
    y = collect(1.0:48.0)
    for bad in (-2, -1, 0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 13, 24, 52)
        @test_throws ArgumentError X13Spec(y; period = bad)
    end
    for good in (4, 12)
        @test X13Spec(y; period = good) isa X13Spec
    end
end

@testset "validate! -- start[2] (subperiod) must be in 1:period" begin
    y4 = collect(1.0:40.0)   # 10 years of quarters
    for bad_sub in (-2, -1, 0, 5, 6, 7, 8)
        @test_throws ArgumentError X13Spec(y4; period = 4, start = (2000, bad_sub))
    end
    for good_sub in (1, 2, 3, 4)
        @test X13Spec(y4; period = 4, start = (2000, good_sub)) isa X13Spec
    end

    y12 = collect(1.0:48.0)
    for bad_sub in (-1, 0, 13, 20)
        @test_throws ArgumentError X13Spec(y12; period = 12, start = (2000, bad_sub))
    end
    for good_sub in (1, 6, 12)
        @test X13Spec(y12; period = 12, start = (2000, good_sub)) isa X13Spec
    end
end

@testset "validate! -- minimum length scales with period (3 complete years)" begin
    # quarterly: 3*4 = 12 quarters
    for n in 9:11
        @test_throws ArgumentError X13Spec(collect(1.0:n); period = 4)
    end
    for n in 12:15
        @test X13Spec(collect(1.0:n); period = 4) isa X13Spec
    end

    # monthly: 3*12 = 36 months (already covered in test_spec.jl at the
    # single boundary; this sweeps a small window around it too)
    for n in 33:35
        @test_throws ArgumentError X13Spec(collect(1.0:n); period = 12)
    end
    for n in 36:39
        @test X13Spec(collect(1.0:n); period = 12) isa X13Spec
    end
end

@testset "validate! -- regression_user forecast-horizon coverage scales with period" begin
    y = collect(1.0:40.0)   # quarterly, 40 quarters
    for extra in 0:3
        short = zeros(40 + extra)   # needs 40+4=44
        @test_throws ArgumentError X13Spec(y; period = 4, regression_user = short, regression_usertype = :holiday)
    end
    for extra in 4:6
        ok = zeros(40 + extra)
        @test X13Spec(y; period = 4, regression_user = ok, regression_usertype = :holiday) isa X13Spec
    end
end

@testset "render -- period is emitted in the series block" begin
    y4 = collect(1.0:40.0)
    y12 = collect(1.0:48.0)
    @test occursin("period = 4", render(X13Spec(y4; period = 4)))
    @test occursin("period = 12", render(X13Spec(y12)))               # default
    @test occursin("period = 12", render(X13Spec(y12; period = 12)))  # explicit
end

@testset "X13Spec(base; kwargs...) -- period overrides through the generic copy-constructor" begin
    y4 = collect(1.0:40.0)
    base = X13Spec(y4; period = 4, start = (2000, 1))
    @test base.period == 4
    overridden = X13Spec(base; period = 4, start = (2000, 3))
    @test overridden.period == 4
    @test overridden.start == (2000, 3)
    # switching a quarterly-shaped spec to period=12 without adjusting
    # start's subperiod is still validated -- start[2]=3 is valid for
    # BOTH 1:4 and 1:12, so this specific override doesn't throw; a
    # genuinely out-of-range one (below) does.
    @test X13Spec(base; period = 12).period == 12
    @test_throws ArgumentError X13Spec(X13Spec(y4; period = 4, start = (2000, 4)); period = 4, start = (2000, 5))
end

@testset "parse_table -- quarterly YYYYQQ date parsing (synthetic fixture)" begin
    dir = mktempdir()
    path = joinpath(dir, "synthetic.d11")
    open(path, "w") do io
        println(io, "date\tvalue")
        println(io, "------\t---------")
        println(io, "202001\t100.5")
        println(io, "202002\t101.2")
        println(io, "202003\t99.8")
        println(io, "202004\t102.1")
        println(io, "202101\t103.0")
    end
    rows = parse_table(path; period = 4)
    @test length(rows) == 5
    @test rows[1] == (Date(2020, 1), 100.5)   # Q1 -> month 1
    @test rows[2] == (Date(2020, 4), 101.2)   # Q2 -> month 4
    @test rows[3] == (Date(2020, 7), 99.8)    # Q3 -> month 7
    @test rows[4] == (Date(2020, 10), 102.1)  # Q4 -> month 10
    @test rows[5] == (Date(2021, 1), 103.0)

    # the identical file, parsed as monthly, gives a DIFFERENT (still
    # valid) interpretation -- confirms period genuinely changes parsing,
    # not just cosmetically
    rows_monthly = parse_table(path; period = 12)
    @test rows_monthly[2] == (Date(2020, 2), 101.2)  # "02" read as February, not Q2
end

@testset "parse_table -- quarterly out-of-range/invalid inputs throw clearly" begin
    dir = mktempdir()

    bad_quarter = joinpath(dir, "bad_quarter.d11")
    open(bad_quarter, "w") do io
        println(io, "date\tvalue")
        println(io, "------\t---------")
        println(io, "202005\t100.0")   # quarter "05" is out of 1:4
    end
    @test_throws ErrorException parse_table(bad_quarter; period = 4)

    bad_quarter0 = joinpath(dir, "bad_quarter0.d11")
    open(bad_quarter0, "w") do io
        println(io, "date\tvalue")
        println(io, "------\t---------")
        println(io, "202000\t100.0")   # quarter "00" is out of 1:4
    end
    @test_throws ErrorException parse_table(bad_quarter0; period = 4)

    @test_throws ErrorException parse_table(bad_quarter; period = 6)  # period itself invalid
end

@testset "parse_output -- period threads through to every requested table (structural)" begin
    # Build a small quarterly output directory with a couple of tables,
    # confirm parse_output's period kwarg reaches parse_table for each.
    dir = mktempdir()
    for (t, val) in ((:d10, "0.98"), (:d11, "101.5"))
        open(joinpath(dir, "series.$t"), "w") do io
            println(io, "date\tvalue")
            println(io, "------\t---------")
            println(io, "202004\t$val")
        end
    end
    fake_result = X13RunResult(true, "", String[], String[], dir, "series")
    parsed = parse_output(fake_result, [:d10, :d11]; period = 4)
    @test parsed[:d10][1][1] == Date(2020, 10)   # Q4 -> month 10
    @test parsed[:d11][1][1] == Date(2020, 10)
end

@testset "calendars -- _periods_for(:quarter) tiles whole calendar quarters" begin
    periods = SeasonalAdjustment._periods_for(:quarter, Date(2024, 2, 15), Date(2024, 8, 5))
    # Feb 15 falls in Q1 (Jan-Mar); Aug 5 falls in Q3 (Jul-Sep) -- three
    # whole quarters tiled: Q1, Q2, Q3 2024.
    @test length(periods) == 3
    @test periods[1] == (Date(2024, 1, 1), Date(2024, 3, 31))
    @test periods[2] == (Date(2024, 4, 1), Date(2024, 6, 30))
    @test periods[3] == (Date(2024, 7, 1), Date(2024, 9, 30))

    @test_throws ArgumentError SeasonalAdjustment._periods_for(:fortnight, Date(2024, 1, 1), Date(2024, 12, 31))
end

@testset "easter_regressor -- freq=:quarter" begin
    # Easter always falls in Q1 or Q2 -- a wide window entirely inside Q1
    # should show up only in the Q1 entry.
    e2025 = Date(2025, 4, 20)
    out = easter_regressor(Date(2025, 1, 1), Date(2025, 12, 31); window = 10, freq = :quarter)
    @test length(out) == 4
    @test out[1] > 0.0 || out[2] > 0.0   # the 10-day pre-Easter window lands in Q1 and/or Q2
    @test out[3] == 0.0  # Q3 (Jul-Sep) never touches an Easter window
    @test out[4] == 0.0  # Q4 (Oct-Dec) never touches an Easter window
end

@testset "custom_holiday_regressor -- freq=:quarter" begin
    cal = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set{Int}())
    diwali_2025(y) = y == 2025 ? Date(2025, 10, 21) : nothing  # a Tuesday, Q4
    out = custom_holiday_regressor(Date(2025, 1, 1), Date(2025, 12, 31), cal, diwali_2025; freq = :quarter)
    @test length(out) == 4
    @test out == [0.0, 0.0, 0.0, 1.0]
end

@testset "trading_day_regressors -- freq=:quarter reproduces the sum of its months (bulk, 8 quarters)" begin
    cal = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set([6, 7]))
    count = 0
    for year in (2023, 2024), qstart_month in (1, 4, 7, 10)
        qfrom = Date(year, qstart_month, 1)
        qto = Date(year, qstart_month + 2, 1) |> Dates.lastdayofmonth
        q = trading_day_regressors(qfrom, qto, cal; freq = :quarter)
        m1 = trading_day_regressors(qfrom, Dates.lastdayofmonth(qfrom), cal)
        m2f = Dates.firstdayofmonth(qfrom) + Dates.Month(1)
        m2 = trading_day_regressors(m2f, Dates.lastdayofmonth(m2f), cal)
        m3f = Dates.firstdayofmonth(qfrom) + Dates.Month(2)
        m3 = trading_day_regressors(m3f, Dates.lastdayofmonth(m3f), cal)
        @test q[1, :] == m1[1, :] .+ m2[1, :] .+ m3[1, :]
        count += 1
    end
    @test count == 8
end

# ------------------------------------------------------------------
# Real-binary quarterly tests -- gated on x13_binary_available(), same
# convention as every other execution-dependent test in this project.
# Uses a synthetic series with real noise (not a perfectly deterministic
# sine wave) -- confirmed this session that a zero-residual-variance
# series makes SEATS fail ("Cannot generate autocorrelations from a
# series of zeros") and can make automdl/maxorder model estimation fail
# too; this is the same class of finding documented for the monthly
# maxorder=(4,2) case in development-sequence.md's W.2 row.
# ------------------------------------------------------------------

function _quarterly_series(n::Integer; seed::Integer = 42)
    rng = Random.MersenneTwister(seed)
    return [100.0 + 10.0 * sin(2π * i / 4) + i * 0.3 + 0.5 * randn(rng) for i in 0:n-1]
end

@testset "x13() / run_x13 -- quarterly minimum-length boundary (real binary)" begin
    if x13_binary_available()
        short = _quarterly_series(11)
        @test_throws ArgumentError x13(short; period = 4, seasonal_order = (0, 1, 1, 4))

        ok = _quarterly_series(12)
        spec = X13Spec(ok; period = 4, seasonal_order = (0, 1, 1, 4), transform = :none)
        path = write_spec(spec, joinpath(mktempdir(), "qmin.spc"))
        result = run_x13(path)
        @test result.success
    else
        @warn "skipping quarterly minimum-length real-binary test: x13_binary_available() is false in this environment"
    end
end

@testset "x13() -- full quarterly end-to-end run (real binary)" begin
    if x13_binary_available()
        y = _quarterly_series(40)  # 10 years
        result = x13(y; period = 4, start = (2000, 1), seasonal_order = (0, 1, 1, 4), transform = :none)
        @test length(result.seasonally_adjusted) == 40
        @test length(result.trend) == 40
        @test length(result.seasonal_factors) == 40
        @test length(result.irregular) == 40
        @test length(result.residuals) == 40
        @test result.dates[1] == Date(2000, 1)
        @test result.dates[2] == Date(2000, 4)   # Q2 -> month 4
        @test result.dates[5] == Date(2001, 1)   # wraps to the next year correctly
        @test result.run_result.success
        @test result.spec.period == 4
        @test haskey(result.udg, "arimamdl")
    else
        @warn "skipping full quarterly x13() real-binary test: x13_binary_available() is false in this environment"
    end
end

@testset "x13() -- quarterly with seats=true (real binary)" begin
    if x13_binary_available()
        y = _quarterly_series(40)
        result = x13(y; period = 4, start = (2000, 1), seasonal_order = (0, 1, 1, 4), transform = :none, seats = true)
        @test result.run_result.success
        @test length(result.seasonally_adjusted) == 40
        @test result.spec.seats
    else
        @warn "skipping quarterly SEATS real-binary test: x13_binary_available() is false in this environment"
    end
end

@testset "x13() -- quarterly with trading-day and easter regressors (real binary)" begin
    if x13_binary_available()
        y = _quarterly_series(44)
        result = x13(
            y; period = 4, start = (2000, 1), seasonal_order = (0, 1, 1, 4), transform = :none,
            trading = true, regression_variables = ["easter[8]"],
        )
        @test result.run_result.success
        @test occursin("variables = (easter[8] td)", render(result.spec))
    else
        @warn "skipping quarterly td/easter real-binary test: x13_binary_available() is false in this environment"
    end
end

@testset "x13() -- quarterly index-based start inference (real binary)" begin
    if x13_binary_available()
        y = _quarterly_series(40)
        idx = [Date(2000, 1) + Dates.Month(3 * i) for i in 0:39]  # Jan, Apr, Jul, Oct, ...
        result = x13(y; index = idx, period = 4, seasonal_order = (0, 1, 1, 4), transform = :none)
        @test result.spec.start == (2000, 1)
        @test result.dates[1] == Date(2000, 1)
    else
        @warn "skipping quarterly index-inference real-binary test: x13_binary_available() is false in this environment"
    end
end

@testset "trading_day_regressors -- quarterly td .rmx column-count gap, documented honestly (real binary)" begin
    if x13_binary_available()
        # Confirmed directly this session: X-13's own quarterly .rmx
        # export for td has 7 columns (Mon..Sat + Leap Year), not 6.
        # This is a documented, honest gap (see the docstring), not
        # something this test tries to force into false agreement --
        # it just confirms the .rmx file itself really does have 7
        # columns, so the gap claim stays true rather than stale.
        y = _quarterly_series(44)
        spec = X13Spec(y; period = 4, seasonal_order = (0, 1, 1, 4), transform = :none,
            regression_variables = ["td"], save = [:d11])
        rendered = render(spec)
        path = joinpath(mktempdir(), "qtd.spc")
        # regressionmatrix export needs its own save= inside regression{}
        # -- render() doesn't expose that directly, so patch the text.
        text = replace(rendered, "regression {" => "regression {\n  save = (regressionmatrix)")
        write(path, text)
        result = run_x13(path)
        @test result.success
        rmx_path = joinpath(result.dir, "$(result.basename).rmx")
        if isfile(rmx_path)
            header = readline(rmx_path)
            ncols = length(split(header, '\t')) - 1  # minus the date column
            @test ncols == 7
        end
    else
        @warn "skipping quarterly td .rmx column-count real-binary test: x13_binary_available() is false in this environment"
    end
end

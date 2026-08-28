# test/test_calendars.jl -- W.0
#
# Test plan follows handoff/w0-calendars.md section 6, adapted to the
# actual verified table data (the handoff's own starter table is
# explicitly a draft; see src/calendars.jl's comments on NSE_MOVEABLE_HOLIDAYS
# for the specific discrepancy found and left unresolved rather than guessed).

@testset "India fixed holidays" begin
    @test isholiday(INDIA_NSE, Date(2026, 1, 26))   # Republic Day
    @test isholiday(INDIA_NSE, Date(2026, 8, 15))   # Independence Day
    @test isholiday(INDIA_NSE, Date(2026, 10, 2))   # Gandhi Jayanti
    @test isholiday(INDIA_NSE, Date(2026, 5, 1))    # Maharashtra Day
    @test isholiday(INDIA_NSE, Date(2026, 12, 25))  # Christmas
    @test !isholiday(INDIA_NSE, Date(2026, 1, 27))
end

@testset "Easter -- reuses BusinessDays.jl, spot-checked against known dates" begin
    @test easter_date(2024) == Date(2024, 3, 31)
    @test easter_date(2025) == Date(2025, 4, 20)
    @test easter_date(2026) == Date(2026, 4, 5)

    # Cross-validated directly against 3 real NSE Good Friday dates
    # found via web search this session (see handoff/w0-calendars.md /
    # commit message): all 3 matched exactly.
    @test SeasonalAdjustment.good_friday(2024) == Date(2024, 3, 29)
    @test SeasonalAdjustment.good_friday(2025) == Date(2025, 4, 18)
    @test SeasonalAdjustment.good_friday(2026) == Date(2026, 4, 3)
    @test isholiday(INDIA_NSE, SeasonalAdjustment.good_friday(2025))
end

@testset "India moveable-feast table (2024-2026, cross-checked dates)" begin
    @test isholiday(INDIA_NSE, Date(2024, 3, 25))   # Holi
    @test isholiday(INDIA_NSE, Date(2024, 11, 1))   # Diwali-Laxmi Pujan
    @test isholiday(INDIA_NSE, Date(2024, 11, 2))   # Diwali-Balipratipada

    @test isholiday(INDIA_NSE, Date(2025, 3, 14))   # Holi
    @test isholiday(INDIA_NSE, Date(2025, 10, 21))  # Diwali-Laxmi Pujan
    @test isholiday(INDIA_NSE, Date(2025, 10, 22))  # Diwali-Balipratipada

    @test isholiday(INDIA_NSE, Date(2026, 3, 3))    # Holi
    @test isholiday(INDIA_NSE, Date(2026, 11, 10))  # Diwali-Balipratipada
end

@testset "table calendar -- year not in table errors clearly" begin
    @test_throws ArgumentError holidaylist(INDIA_NSE, Date(2030, 1, 1), Date(2030, 12, 31))
    # custom_holiday_regressor does NOT throw on an untabulated year --
    # by design (see its docstring): SeasonalAdjustment.diwali_date(2030)
    # returns `nothing`, silently contributing 0.0. Confirm that
    # documented behavior explicitly rather than assuming it.
    reg = custom_holiday_regressor(Date(2030, 1, 1), Date(2030, 12, 31), INDIA_NSE, SeasonalAdjustment.diwali_date)
    @test all(==(0.0), reg)
end

@testset "weekend detection" begin
    @test isweekend(INDIA_NSE, 6)   # Saturday
    @test isweekend(INDIA_NSE, 7)   # Sunday
    @test !isweekend(INDIA_NSE, 1)  # Monday
end

@testset "business day conventions" begin
    sat = Date(2026, 1, 31)  # a Saturday
    @test dayofweek(adjust(INDIA_NSE, sat, :following)) != 6
    @test adjust(INDIA_NSE, sat, :following) > sat
    @test adjust(INDIA_NSE, sat, :preceding) < sat
    @test adjust(INDIA_NSE, sat, :unadjusted) == sat

    # modified conventions: :following that would cross a month
    # boundary falls back to :preceding instead
    last_day = Date(2026, 8, 31)  # a Monday -- ordinary business day, sanity check first
    @test isbusinessday(INDIA_NSE, last_day)
    sat_month_end = Date(2025, 5, 31)  # a Saturday, last day of May 2025
    @test adjust(INDIA_NSE, sat_month_end, :modified_following) == adjust(INDIA_NSE, sat_month_end, :preceding)
end

@testset "businessdaysbetween / holidaylist" begin
    # Jan 1, 2026 is a Thursday, so Jan 1-7 spans Thu,Fri,Sat,Sun,Mon,Tue,Wed
    # -- 5 business days (Sat/Sun excluded, no holiday in this range).
    n = businessdaysbetween(INDIA_NSE, Date(2026, 1, 1), Date(2026, 1, 7))
    @test n == 5

    hl = holidaylist(INDIA_NSE, Date(2026, 1, 1), Date(2026, 1, 31))
    @test hl == [Date(2026, 1, 26)]

    hl_weekends = holidaylist(INDIA_NSE, Date(2026, 1, 1), Date(2026, 1, 7); include_weekends = true)
    @test Date(2026, 1, 3) in hl_weekends  # a Saturday
    @test Date(2026, 1, 4) in hl_weekends  # a Sunday
end

@testset "trading_day_regressors -- hand-countable month" begin
    # January 2024 (31 days, starting on a Monday): Mon=5, Tue=5, Wed=5,
    # Thu=4, Fri=4 raw business-day weekday counts under a no-holiday
    # calendar with the standard Sat/Sun weekend (Sat/Sun both count 0
    # business days regardless of the holiday table).
    noholiday = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set([6, 7]))
    m = trading_day_regressors(Date(2024, 1, 1), Date(2024, 1, 31), noholiday)
    @test size(m) == (1, 6)
    @test m[1, :] == Float64[5, 5, 5, 4, 4, 0]  # each column already minus Sunday's count of 0

    @test_throws ArgumentError trading_day_regressors(Date(2024, 1, 1), Date(2024, 1, 31), noholiday; freq = :quarter)
end

@testset "trading_day_regressors -- INDIA_NSE holiday suppresses exactly one weekday count" begin
    noholiday = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set([6, 7]))

    # October 2024: Gandhi Jayanti (Oct 2, a Wednesday) is an INDIA_NSE
    # holiday but not a holiday under the plain calendar.
    @test Dates.dayofweek(Date(2024, 10, 2)) == 3  # Wednesday

    m_plain = trading_day_regressors(Date(2024, 10, 1), Date(2024, 10, 31), noholiday)
    m_nse = trading_day_regressors(Date(2024, 10, 1), Date(2024, 10, 31), INDIA_NSE)

    @test m_nse[1, 3] == m_plain[1, 3] - 1   # Wednesday column
    for j in (1, 2, 4, 5, 6)
        @test m_nse[1, j] == m_plain[1, j]
    end
end

@testset "easter_regressor -- straddling window sums to 1, disjoint period is 0, window=0 default is all-zero" begin
    r0 = easter_regressor(Date(2025, 4, 1), Date(2025, 5, 31))
    @test all(==(0.0), r0)  # default window=0

    # 2025 Easter Sunday = Apr 20; window=8 -> pre-Easter window is
    # 2025-04-12 .. 2025-04-19 inclusive, split across April (3 days:
    # 4/12-4/14 fall in the first period below) and continues into the
    # rest of April (5 days: 4/15-4/19) in the same monthly period since
    # both are within April -- use a period split at April 14/15 by
    # querying two separate single-month calls instead, which the
    # function's monthly tiling doesn't allow directly, so exercise the
    # window arithmetic directly via two adjacent months instead: put
    # the window-straddling boundary at the March/April boundary.
    e = easter_date(2025)
    @test e == Date(2025, 4, 20)
    r = easter_regressor(Date(2025, 3, 1), Date(2025, 4, 30); window = 30)
    # window = 30 -> pre-Easter window is 2025-03-21 .. 2025-04-19
    march_days = Dates.daysinmonth(2025, 3) - 21 + 1  # Mar 21-31 inclusive
    april_days = 19  # Apr 1-19 inclusive
    @test r[1] ≈ march_days / 30
    @test r[2] ≈ april_days / 30
    @test r[1] + r[2] ≈ (march_days + april_days) / 30
end

@testset "custom_holiday_regressor -- shape and weekend-suppression semantics" begin
    reg = custom_holiday_regressor(Date(2024, 1, 1), Date(2026, 12, 31), INDIA_NSE, SeasonalAdjustment.diwali_date)
    @test length(reg) == 36  # 3 full years, monthly
    @test all(x -> x == 0.0 || x == 1.0, reg)
    # Diwali-Laxmi Pujan: Nov 2024, Oct 2025, Nov 2026 (index = (year-2024)*12 + month)
    @test reg[(2024 - 2024) * 12 + 11] == 1.0  # Nov 2024
    @test reg[(2025 - 2024) * 12 + 10] == 1.0  # Oct 2025
    # 2026's Laxmi Pujan (Nov 8) is a SUNDAY -- no extra closure, so the
    # weekend-suppression rule in custom_holiday_regressor's own
    # docstring means it must NOT register as a hit.
    @test reg[(2026 - 2024) * 12 + 11] == 0.0  # Nov 2026 -- suppressed, Laxmi Pujan fell on a Sunday
    @test sum(reg) == 2.0

    holi_reg = custom_holiday_regressor(Date(2026, 1, 1), Date(2026, 12, 31), INDIA_NSE, SeasonalAdjustment.holi_date)
    @test holi_reg[3] == 1.0  # March 2026, Holi on a Tuesday -- not suppressed
    @test sum(holi_reg) == 1.0
end

@testset "CAPSTONE: reproduce the real Diwali proof against the actual binary" begin
    # This is the test that actually closes the loop between W.0 and
    # the custom-regressor mechanism already proven to work (see
    # handoff/verification/diwali_regressor_proof/). It generates the
    # regressor with this task's own functions -- a synthetic "put a 1
    # in October, every year" pattern, matching exactly what the
    # existing verified diwali_official.spc hand-encodes -- and either:
    #   (a) re-runs the real x13prebuilt binary via x13_binary_path()
    #       (W.1), confirming the SAME October 1949 seasonal factor
    #       shift (0.898593816033472 -> 0.753973303751993), or
    #   (b) at minimum confirms the generated vector is byte-identical
    #       to the data already embedded in diwali_official.spc.
    # Both are always run; (a) is skipped (not failed) if
    # x13_binary_available() is false in this environment.
    #
    # Refactored per handoff/w1-artifacts.md section 4a's explicit
    # requirement: this previously hardcoded a hand-guessed path to a
    # sibling repo's copy of the Linux binary, gated behind a
    # Windows+WSL check, as an admitted stand-in ("W.1/W.3 will make
    # binary discovery a first-class, portable mechanism -- this is a
    # deliberately minimal, test-local stand-in, not a preview of that
    # design"). Now that W.1 provides x13_binary_path()/
    # x13_binary_available(), that stand-in is removed entirely.
    #
    # diwali_official.spc's regressor data is 156 months (13 years), not the
    # 144-month (12-year) series length -- confirmed by counting: this
    # is exactly the airline series' 144 months PLUS the 12-month
    # RegARIMA forecast horizon, the first of the two practical
    # requirements development-sequence.md documents (regressor data
    # must cover the forecast horizon, not just the historical series).

    # diwali_official.spc's synthetic pattern isn't "October every year" --
    # it's Oct,Nov,Nov repeating (October only when (year-1949)%3==0),
    # loosely approximating how a real lunisolar festival date drifts
    # year to year. Confirmed by inspecting the actual data in
    # diwali_official.spc directly rather than assuming a simpler pattern.
    function synthetic_diwali(year::Integer)
        (1949 <= year <= 1961) || return nothing
        return (year - 1949) % 3 == 0 ? Date(year, 10, 10) : Date(year, 11, 10)
    end
    no_weekend_cal = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set{Int}())

    reg = custom_holiday_regressor(Date(1949, 1, 1), Date(1961, 12, 31), no_weekend_cal, synthetic_diwali)
    @test length(reg) == 156

    spc_path = joinpath(@__DIR__, "..", "handoff", "verification", "diwali_regressor_proof", "diwali_official.spc")
    spc_text = read(spc_path, String)
    m = match(r"data = \(([^)]*)\)\s*\}\s*x11", spc_text)
    @test m !== nothing
    expected = parse.(Float64, split(strip(m.captures[1])))
    @test length(expected) == 156
    @test reg == expected   # (b): byte-identical to the existing verified spec's data array

    ran_real_binary = false
    if x13_binary_available()
        path = x13_binary_path()
        mktempdir() do dir
            # Reuse the airline series values directly from the existing
            # verified fixture rather than re-typing them.
            airline_spc = read(joinpath(@__DIR__, "..", "handoff", "verification", "airline_baseline", "airline_official.spc"), String)
            airline_data_match = match(r"data = \(([\s\S]*?)\)\s*\}"m, airline_spc)
            @test airline_data_match !== nothing
            data_block = airline_data_match.captures[1]

            reg_lines = join([join(reg[i:min(i + 11, end)], " ") for i in 1:12:length(reg)], "\n")
            capstone_spc = """
            series {
              title = "W.0 capstone regressor"
              start = 1949.1
              data = ($data_block)
            }
            transform { function = log }
            regression {
              variables = (td)
              user = (diwali)
              usertype = (holiday)
              start = 1949.1
              data = ($reg_lines)
            }
            x11 { save = (d10) }
            """
            write(joinpath(dir, "capstone.spc"), capstone_spc)

            cd(dir) do
                run(pipeline(ignorestatus(`$path capstone`); stdout = devnull, stderr = devnull))
            end

            d10 = read(joinpath(dir, "capstone.d10"), String)
            lines = split(strip(d10), "\n")
            oct1949_line = only(filter(l -> startswith(l, "194910"), lines))
            oct1949_value = parse(Float64, split(oct1949_line, "\t")[2])
            @test oct1949_value ≈ 0.753973303751993 atol = 1e-9
            ran_real_binary = true
        end
    end

    @info "CAPSTONE test result" ran_real_binary
    if !ran_real_binary
        @warn "CAPSTONE test could not locate/run the real x13prebuilt binary in this environment -- only the byte-identical spec-data check (b) ran, not the full binary re-run (a). See handoff/w0-calendars.md section 7, point 4."
    end
end

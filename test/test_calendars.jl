# test/test_calendars.jl -- W.0
#
# Test plan lives in handoff-w0-calendars.md; each @testset below
# corresponds to one numbered item there.

@testset "easter_date / good_friday -- cross-validated against real NSE dates" begin
    # handoff-w0-calendars.md: these 3 years were independently cross-checked
    # against real NSE Good Friday dates found via web search.
    @test SeasonalAdjustment.easter_date(2024) == Date(2024, 3, 31)
    @test SeasonalAdjustment.easter_date(2025) == Date(2025, 4, 20)
    @test SeasonalAdjustment.easter_date(2026) == Date(2026, 4, 5)

    @test SeasonalAdjustment.good_friday(2024) == Date(2024, 3, 29)
    @test SeasonalAdjustment.good_friday(2025) == Date(2025, 4, 18)
    @test SeasonalAdjustment.good_friday(2026) == Date(2026, 4, 3)
end

@testset "INDIA_NSE -- fixed-date holidays and Good Friday" begin
    for y in (2024, 2025, 2026)
        @test BusinessDays.isholiday(INDIA_NSE, Date(y, 1, 26))   # Republic Day
        @test BusinessDays.isholiday(INDIA_NSE, Date(y, 8, 15))   # Independence Day
        @test BusinessDays.isholiday(INDIA_NSE, Date(y, 10, 2))   # Gandhi Jayanti
        @test BusinessDays.isholiday(INDIA_NSE, SeasonalAdjustment.good_friday(y))
    end

    # an ordinary Tuesday, no known holiday
    @test !BusinessDays.isholiday(INDIA_NSE, Date(2025, 6, 3))
end

@testset "INDIA_NSE -- moveable-feast table (2024-2026, cross-checked dates)" begin
    @test BusinessDays.isholiday(INDIA_NSE, Date(2024, 3, 25))   # Holi
    @test BusinessDays.isholiday(INDIA_NSE, Date(2024, 11, 1))   # Diwali-Laxmi Pujan
    @test BusinessDays.isholiday(INDIA_NSE, Date(2024, 11, 2))   # Diwali-Balipratipada

    @test BusinessDays.isholiday(INDIA_NSE, Date(2025, 3, 14))   # Holi
    @test BusinessDays.isholiday(INDIA_NSE, Date(2025, 10, 21))  # Diwali-Laxmi Pujan
    @test BusinessDays.isholiday(INDIA_NSE, Date(2025, 10, 22))  # Diwali-Balipratipada

    @test BusinessDays.isholiday(INDIA_NSE, Date(2026, 3, 3))    # Holi
    @test BusinessDays.isholiday(INDIA_NSE, Date(2026, 11, 10))  # Diwali-Balipratipada
end

@testset "INDIA_NSE -- weekends are never business days regardless of holiday table" begin
    @test !BusinessDays.isbday(INDIA_NSE, Date(2025, 6, 7))    # a Saturday
    @test !BusinessDays.isbday(INDIA_NSE, Date(2025, 6, 8))    # a Sunday
    @test BusinessDays.isbday(INDIA_NSE, Date(2025, 6, 9))     # the following Monday, ordinary
end

@testset "nse_moveable_holiday_dates -- lookup and loud failure on untabulated years" begin
    dates = SeasonalAdjustment.nse_moveable_holiday_dates("diwali", [2024, 2025])
    @test dates == [Date(2024, 11, 1), Date(2024, 11, 2), Date(2025, 10, 21), Date(2025, 10, 22)]

    holi_dates = SeasonalAdjustment.nse_moveable_holiday_dates("holi", [2026])
    @test holi_dates == [Date(2026, 3, 3)]

    @test_throws ErrorException SeasonalAdjustment.nse_moveable_holiday_dates("diwali", [2030])
    @test_throws ErrorException SeasonalAdjustment.nse_moveable_holiday_dates("diwali", [2024, 2030])
end

@testset "trading_day_regressors -- hand-countable month, no-holiday calendar" begin
    # January 2024 (31 days, starting on a Monday): Mon=5, Tue=5, Wed=5,
    # Thu=4, Fri=4 as raw weekday counts. BusinessDays.jl's `isbday`
    # excludes Saturday/Sunday via its own calendar-independent
    # `isweekend` regardless of a calendar's `isholiday` override (see
    # BusinessDays.jl's bdays.jl: `isbday = !(isweekend(dt) ||
    # isholiday(hc,dt))`), so a "no holiday" calendar still counts 0
    # business days on both Sat and Sun -- confirmed directly against
    # the library's own source, not assumed.
    struct _NoHolidayCal <: BusinessDays.HolidayCalendar end
    BusinessDays.isholiday(::_NoHolidayCal, ::Date) = false
    cal = _NoHolidayCal()

    periods = [(Date(2024, 1, 1), Date(2024, 1, 31))]
    m = trading_day_regressors(cal, periods)
    @test size(m) == (1, 6)
    # business-day weekday counts: Mon 5, Tue 5, Wed 5, Thu 4, Fri 4, Sat 0, Sun 0
    @test m[1, :] == Float64[5 - 0, 5 - 0, 5 - 0, 4 - 0, 4 - 0, 0 - 0]
end

@testset "trading_day_regressors -- INDIA_NSE holiday suppresses exactly one weekday count" begin
    struct _NoHolidayCal2 <: BusinessDays.HolidayCalendar end
    BusinessDays.isholiday(::_NoHolidayCal2, ::Date) = false
    plain = _NoHolidayCal2()

    # October 2024: Gandhi Jayanti (Oct 2, a Wednesday) is an INDIA_NSE
    # holiday but not a holiday under the plain calendar.
    @test Dates.dayofweek(Date(2024, 10, 2)) == 3  # Wednesday
    periods = [(Date(2024, 10, 1), Date(2024, 10, 31))]

    m_plain = trading_day_regressors(plain, periods)
    m_nse = trading_day_regressors(INDIA_NSE, periods)

    # Every column shifts uniformly except Wednesday's, which drops by
    # exactly one relative to the holiday-free calendar (the holiday
    # falls on a Wednesday, so removing it lowers Wed's count by 1 while
    # leaving every other weekday's count -- and therefore every other
    # contrast column -- unchanged).
    @test m_nse[1, 3] == m_plain[1, 3] - 1   # Wednesday column
    for j in (1, 2, 4, 5, 6)
        @test m_nse[1, j] == m_plain[1, j]
    end
end

@testset "easter_regressor -- straddling window sums to 1, disjoint period is 0" begin
    e = SeasonalAdjustment.easter_date(2025)  # 2025-04-20
    # window=8 -> pre-Easter window is 2025-04-12 .. 2025-04-19 inclusive
    before = (Date(2025, 4, 1), Date(2025, 4, 14))    # overlaps 4/12-4/14 (3 days)
    after = (Date(2025, 4, 15), Date(2025, 4, 30))    # overlaps 4/15-4/19 (5 days)
    disjoint = (Date(2025, 5, 1), Date(2025, 5, 31))   # no overlap at all

    r = easter_regressor([before, after, disjoint]; window=8)
    @test r[1] ≈ 3 / 8
    @test r[2] ≈ 5 / 8
    @test r[1] + r[2] ≈ 1.0
    @test r[3] == 0.0
end

@testset "custom_holiday_regressor -- one holiday per period, echoing the Diwali proof's shape" begin
    holiday_dates = [Date(2024, m, 15) for m in 1:12]
    periods = [(Date(2024, m, 1), Date(2024, m, Dates.daysinmonth(2024, m))) for m in 1:12]
    r = custom_holiday_regressor(holiday_dates, periods)
    @test r == fill(1.0, 12)

    # a period containing no listed holiday date
    r2 = custom_holiday_regressor(holiday_dates, [(Date(2024, 1, 16), Date(2024, 1, 31))])
    @test r2 == [0.0]
end

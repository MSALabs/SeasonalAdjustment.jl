# test/extended/test_calendar_extreme.jl -- Stage 2
#
# Tier 1 (structural) extreme-case expansion for holidaylist,
# custom_holiday_regressor, and TableCalendar/isholiday/isweekend
# construction -- the calendar functions the existing test_calendars.jl
# (W.0) exercises only lightly, and neither test_calendar_crossval.jl
# nor test_regressor_crossval.jl reaches (both target the ENGINE
# arithmetic and trading_day_regressors/easter_regressor specifically).

@testset "extreme: holidaylist boundaries and every weekend-set shape" begin
    # A calendar with a genuinely large, multi-year table plus fixed
    # holidays, exercised across boundaries the INDIA_NSE-focused W.0
    # tests don't specifically target: single-day ranges, a range
    # entirely within one untabled year (must throw), a range spanning
    # a tabled and an untabled year (must also throw -- ANY spanned
    # year missing a table entry is an error, not just the whole range).
    fixed = Function[y -> Date(y, 1, 1)]  # New Year's Day every year
    table = Dict{Int,Vector{Tuple{Date,String}}}(
        2020 => [(Date(2020, 7, 4), "Test Holiday")],
        2021 => [(Date(2021, 7, 4), "Test Holiday")],
    )
    cal = TableCalendar(fixed, table, Set([6, 7]))

    # single-day range, on and off a holiday
    @test holidaylist(cal, Date(2020, 1, 1), Date(2020, 1, 1)) == [Date(2020, 1, 1)]
    @test holidaylist(cal, Date(2020, 1, 2), Date(2020, 1, 2)) == Date[]

    # untabled year entirely
    @test_throws ArgumentError holidaylist(cal, Date(2022, 1, 1), Date(2022, 12, 31))
    # tabled year followed immediately by an untabled one
    @test_throws ArgumentError holidaylist(cal, Date(2021, 6, 1), Date(2022, 6, 1))
    # untabled year followed by a tabled one (order of the throw check
    # doesn't matter, but both directions are worth confirming directly)
    @test_throws ArgumentError holidaylist(cal, Date(2019, 6, 1), Date(2020, 6, 1))

    # include_weekends=true vs false, on a range with both a fixed
    # holiday and several weekends
    without_weekends = holidaylist(cal, Date(2020, 1, 1), Date(2020, 1, 31); include_weekends = false)
    with_weekends = holidaylist(cal, Date(2020, 1, 1), Date(2020, 1, 31); include_weekends = true)
    @test length(without_weekends) == 1  # just Jan 1
    @test length(with_weekends) > length(without_weekends)  # Jan 1 plus every Sat/Sun in January

    # every possible weekend-set shape: no weekend at all, one day,
    # two days (the common case), all seven (a calendar with no
    # business days at all -- a genuine degenerate case).
    for weekend_days in (Set{Int}(), Set([7]), Set([6, 7]), Set([5, 6, 7]), Set(1:7))
        cal2 = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(2020 => Tuple{Date,String}[]), weekend_days)
        d0 = Date(2020, 1, 6)  # a Monday
        for offset in 0:6
            d = d0 + Dates.Day(offset)
            expected_weekend = dayofweek(d) in weekend_days
            @test isweekend(cal2, dayofweek(d)) == expected_weekend
            @test isbusinessday(cal2, d) == !expected_weekend
        end
    end
end

@testset "extreme: custom_holiday_regressor boundaries" begin
    cal = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set([6, 7]))

    # holiday_years_present returning nothing for every year -- all-zero
    # output, not an error (by design, per the function's own docstring).
    always_nothing(y) = nothing
    out = custom_holiday_regressor(Date(2020, 1, 1), Date(2020, 12, 31), cal, always_nothing)
    @test length(out) == 12
    @test all(v -> v == 0.0, out)

    # a holiday that lands on a weekday every year -- always 1.0 in its
    # own month.
    fixed_weekday_holiday(y) = Date(y, 3, 2)  # March 2, a Monday in 2020
    out2 = custom_holiday_regressor(Date(2020, 1, 1), Date(2020, 12, 31), cal, fixed_weekday_holiday)
    @test out2[3] == 1.0  # March
    @test all(i -> i == 3 || out2[i] == 0.0, 1:12)

    # a holiday that lands on a weekend -- confirmed directly (per the
    # function's own documented semantics) this contributes 0.0, not
    # 1.0, since a weekend holiday has no incremental trading-day
    # effect to explain.
    weekend_holiday(y) = Date(2021, 1, 2)  # a real Saturday
    out3 = custom_holiday_regressor(Date(2021, 1, 1), Date(2021, 12, 31), cal, weekend_holiday)
    @test all(v -> v == 0.0, out3)

    # a holiday exactly on a period boundary (last day of a month).
    boundary_holiday(y) = Date(2021, 1, 29)  # a Friday, last business day of Jan 2021
    out4 = custom_holiday_regressor(Date(2021, 1, 1), Date(2021, 12, 31), cal, boundary_holiday)
    @test out4[1] == 1.0

    # two years, holiday present in one but not the other.
    partial_years = Dict(2020 => Date(2020, 6, 15))
    partial_fn(y) = get(partial_years, y, nothing)
    out5 = custom_holiday_regressor(Date(2019, 1, 1), Date(2021, 12, 31), cal, partial_fn)
    @test length(out5) == 36
    @test count(v -> v == 1.0, out5) == 1  # exactly one month has the effect
end

@testset "extreme: TableCalendar construction and isholiday edge cases" begin
    # An empty calendar (no fixed holidays, no table, no weekend) --
    # every day is a business day.
    empty_cal = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set{Int}())
    for d in (Date(2020, 1, 1), Date(2024, 12, 25), Date(1900, 1, 1), Date(2200, 6, 15))
        @test isbusinessday(empty_cal, d)
        @test !isholiday(empty_cal, d)
    end

    # Multiple fixed holidays landing on the SAME date in different
    # years -- confirmed each year's own instance is detected
    # independently, not just the first year checked.
    multi_fixed = Function[y -> Date(y, 12, 25), y -> Date(y, 1, 1)]
    cal = TableCalendar(multi_fixed, Dict{Int,Vector{Tuple{Date,String}}}(), Set([6, 7]))
    for y in 1990:2050
        @test isholiday(cal, Date(y, 12, 25))
        @test isholiday(cal, Date(y, 1, 1))
        @test !isholiday(cal, Date(y, 6, 15))  # a plain day, no holiday
    end

    # A table_holidays entry with an EMPTY vector for a year -- must not
    # error, just report no table holidays that year (distinct from the
    # year being entirely absent from the dict, which holidaylist
    # treats as an error).
    cal_empty_year = TableCalendar(Function[], Dict(2020 => Tuple{Date,String}[]), Set([6, 7]))
    @test !isholiday(cal_empty_year, Date(2020, 7, 4))
    @test holidaylist(cal_empty_year, Date(2020, 1, 1), Date(2020, 1, 31)) == Date[]  # no error, just empty
end

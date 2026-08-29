# test/extended/test_calendar_crossval.jl -- Stage 2
#
# Cross-validates the CALENDAR ENGINE (easter_date, isbusinessday,
# adjust, businessdaysbetween) against two independent R packages --
# timeDate (a genuinely different Easter algorithm than BusinessDays.jl,
# which this package's own easter_date reuses directly) and bizdays
# (business-day arithmetic). Uses a plain weekends-only calendar on
# both sides -- this verifies the ENGINE/arithmetic, not INDIA_NSE's
# own specific holiday data, which has no independent R-side source to
# check against either (sourced from NSE circulars, same honest gap
# noted directly in calendars.jl). All checks batched into a single R
# subprocess invocation (unlike Stage 1's x13 cross-validation, a
# calendar check needs no separate binary call per case, so there's no
# reason to pay R's own startup cost hundreds of times).

const _WEEKENDS_ONLY = TableCalendar(Function[], Dict{Int,Vector{Tuple{Date,String}}}(), Set([6, 7]))

@testset "crossval: calendar engine agrees with R's timeDate/bizdays (Tier 3)" begin
    if !_r_calendar_available()
        @warn "skipping calendar cross-validation entirely: R (timeDate+bizdays+jsonlite) is not available in this environment"
    else
        # --- Easter: 300 years, both algorithms (BusinessDays.jl's,
        # reused by easter_date, vs. timeDate's own) -- confirmed
        # genuinely independent implementations, not the same code
        # imported twice.
        easter_years = collect(1850:2149)
        @test length(easter_years) == 300

        # --- isbusinessday: every day across 3 non-contiguous years,
        # spanning every weekday.
        bizday_dates = Date[]
        for y in (1999, 2024, 2087)
            for d in Date(y, 1, 1):Dates.Day(1):Date(y, 12, 31)
                push!(bizday_dates, d)
            end
        end
        @test length(bizday_dates) >= 1095  # 3 non-leap years' worth, at minimum

        # --- businessdaysbetween: a real grid of (from,to) pairs --
        # same-day, short spans crossing 0-3 weekends, long spans
        # crossing year boundaries and leap days.
        between_cases = Tuple{Date,Date}[]
        for start_month in 1:12
            d0 = Date(2024, start_month, 1)
            push!(between_cases, (d0, d0))                        # single day
            push!(between_cases, (d0, d0 + Dates.Day(6)))                # one week
            push!(between_cases, (d0, d0 + Dates.Day(13)))               # two weeks
        end
        push!(between_cases, (Date(2023, 12, 15), Date(2024, 1, 15)))  # crosses year boundary
        push!(between_cases, (Date(2000, 2, 20), Date(2000, 3, 5)))    # crosses a leap day
        push!(between_cases, (Date(2024, 1, 31), Date(2024, 1, 1)))    # reversed order (from > to)
        @test length(between_cases) == 39  # 12*3 loop-generated + 3 explicit

        # --- adjust: every day-of-week x every convention, several
        # independent weeks, plus explicit month-boundary edge cases
        # (the exact scenario modified_following/modified_preceding
        # exist for).
        adjust_cases = Tuple{Date,Symbol}[]
        conventions = (:following, :preceding, :modified_following, :modified_preceding, :unadjusted)
        for base in (Date(2024, 1, 1), Date(2024, 6, 3), Date(2025, 3, 10))
            for offset in 0:6
                for conv in conventions
                    push!(adjust_cases, (base + Dates.Day(offset), conv))
                end
            end
        end
        # explicit month-boundary cases: last day of a month landing on
        # a weekend, both directions.
        for d in (Date(2023, 12, 31), Date(2024, 3, 31), Date(2024, 6, 30), Date(2025, 2, 28))
            for conv in conventions
                push!(adjust_cases, (d, conv))
            end
        end
        @test length(adjust_cases) == 105 + 20

        input = Dict(
            "easter_years" => easter_years,
            "bizday_dates" => string.(bizday_dates),
            "between_cases" => [Dict("from" => string(f), "to" => string(t)) for (f, t) in between_cases],
            "adjust_cases" => [Dict("date" => string(d), "convention" => string(c)) for (d, c) in adjust_cases],
        )
        r = _run_r_calendar(input)

        # Easter
        @test length(r["easter_dates"]) == length(easter_years)
        for (i, y) in enumerate(easter_years)
            @test easter_date(y) == Date(r["easter_dates"][i])
        end

        # isbusinessday
        @test length(r["bizday_results"]) == length(bizday_dates)
        for (i, d) in enumerate(bizday_dates)
            @test isbusinessday(_WEEKENDS_ONLY, d) == r["bizday_results"][i]
        end

        # businessdaysbetween
        @test length(r["between_results"]) == length(between_cases)
        for (i, (f, t)) in enumerate(between_cases)
            @test businessdaysbetween(_WEEKENDS_ONLY, f, t) == r["between_results"][i]
        end

        # adjust
        @test length(r["adjust_results"]) == length(adjust_cases)
        for (i, (d, conv)) in enumerate(adjust_cases)
            @test adjust(_WEEKENDS_ONLY, d, conv) == Date(r["adjust_results"][i])
        end
    end
end

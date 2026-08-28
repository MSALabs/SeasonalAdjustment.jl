# src/calendars.jl
#
# W.0 -- business-day/holiday calendars (India + major markets) and the
# regressor-generation functions that turn a calendar into plain
# Date/Float64 data. W.2 (not yet built) is responsible for serializing
# this data into a .spc file's `regression { user = (...) data = (...) }`
# block; W.0 stops at producing the data itself.
#
# See handoff-w0-calendars.md for verified references, the honest gaps
# in the moveable-holiday table below, and the test plan this file's
# tests implement.

# ------------------------------------------------------------------
# Easter Sunday / Good Friday -- the one moveable Christian holiday
# with a closed-form date formula (Anonymous Gregorian algorithm).
# Cross-validated in handoff-w0-calendars.md against 3 real NSE Good
# Friday dates (2024, 2025, 2026) -- all matched exactly.
# ------------------------------------------------------------------

"""
    easter_date(year) -> Date

Easter Sunday for the Gregorian calendar `year`, via the Anonymous
Gregorian (Meeus/Jones/Butcher) algorithm.
"""
function easter_date(year::Integer)
    a = year % 19
    b = year ÷ 100
    c = year % 100
    d = b ÷ 4
    e = b % 4
    f = (b + 8) ÷ 25
    g = (b - f + 1) ÷ 3
    h = (19a + b - d - g + 15) % 30
    i = c ÷ 4
    k = c % 4
    l = (32 + 2e + 2i - h - k) % 7
    m = (a + 11h + 22l) ÷ 451
    month = (h + l - 7m + 114) ÷ 31
    day = ((h + l - 7m + 114) % 31) + 1
    return Date(year, month, day)
end

"""
    good_friday(year) -> Date

Good Friday (Easter Sunday minus two days) for `year`.
"""
good_friday(year::Integer) = easter_date(year) - Day(2)

# ------------------------------------------------------------------
# INDIA_NSE -- the National Stock Exchange trading calendar
# ------------------------------------------------------------------

"""
    NSEHolidayCalendar <: BusinessDays.HolidayCalendar

India's National Stock Exchange (equity segment) trading calendar:
weekends, three fixed-date national holidays, Good Friday, and a
year-keyed table of moveable Hindu-calendar feasts (Holi, Diwali).

The moveable-feast table (`NSE_MOVEABLE_HOLIDAYS`) currently covers
2024-2026 only and was cross-checked across multiple independent
aggregator sites, NOT read directly from NSE's own circular PDF (see
handoff-w0-calendars.md for why, and the specific sources used). Treat
it as a reasonable-confidence starting point that should be reconciled
against NSE's own circular before production use, and extended for
any year beyond 2026 before relying on it for that year.
"""
struct NSEHolidayCalendar <: BusinessDays.HolidayCalendar end

const NSE_FIXED_HOLIDAYS = (
    (month = 1, day = 26, name = "Republic Day"),
    (month = 8, day = 15, name = "Independence Day"),
    (month = 10, day = 2, name = "Mahatma Gandhi Jayanti"),
)

# Moveable-feast holidays -- NO closed-form date formula exists for these
# (they follow lunar/lunisolar calendars). GAP, flagged honestly (see
# handoff-w0-calendars.md): sourced from cross-checked third-party
# aggregators this session, not NSE's own circular directly (its PDF
# could not be machine-read). Eid is deliberately omitted -- sources
# disagreed on whether it's a full or partial NSE closure in a given
# year, and guessing would be worse than leaving the gap visible.
const NSE_MOVEABLE_HOLIDAYS = Dict(
    2024 => [
        (Date(2024, 3, 25), "Holi"),
        (Date(2024, 11, 1), "Diwali-Laxmi Pujan"),
        (Date(2024, 11, 2), "Diwali-Balipratipada"),
    ],
    2025 => [
        (Date(2025, 3, 14), "Holi"),
        (Date(2025, 10, 21), "Diwali-Laxmi Pujan"),
        (Date(2025, 10, 22), "Diwali-Balipratipada"),
    ],
    2026 => [
        (Date(2026, 3, 3), "Holi"),
        (Date(2026, 11, 8), "Diwali-Laxmi Pujan"),   # Sunday; Muhurat trading only
        (Date(2026, 11, 10), "Diwali-Balipratipada"),
    ],
)

function BusinessDays.isholiday(::NSEHolidayCalendar, dt::Date)
    m, d, y = month(dt), day(dt), year(dt)
    any(h -> h.month == m && h.day == d, NSE_FIXED_HOLIDAYS) && return true
    dt == good_friday(y) && return true
    if haskey(NSE_MOVEABLE_HOLIDAYS, y)
        any(entry -> entry[1] == dt, NSE_MOVEABLE_HOLIDAYS[y]) && return true
    end
    return false
end

"""
    INDIA_NSE::NSEHolidayCalendar

The India NSE trading calendar singleton. Use with `BusinessDays.isbday`
/ `isholiday`, or pass directly to [`trading_day_regressors`](@ref) /
[`easter_regressor`](@ref).

Any of BusinessDays.jl's own built-in calendars (e.g.
`BusinessDays.USSettlement()`) work with those same functions too --
India needed a calendar defined from scratch because BusinessDays.jl
doesn't ship one, "major markets" don't.
"""
const INDIA_NSE = NSEHolidayCalendar()

"""
    nse_moveable_holiday_dates(name, years) -> Vector{Date}

Look up [`NSE_MOVEABLE_HOLIDAYS`](@ref) entries whose name contains
`name` (case-insensitive; e.g. `"diwali"` matches both Laxmi Pujan and
Balipratipada) across `years`, in date order.

Errors loudly, naming the missing year, if any requested year isn't in
the table -- silently returning fewer holidays than actually exist
would corrupt a RegARIMA fit that assumed complete coverage rather than
fail visibly, and regressor data is specifically required to cover the
full forecast horizon (see development-sequence.md's W.2 notes), so a
quietly-missing year is exactly the failure mode to avoid here.
"""
function nse_moveable_holiday_dates(name::AbstractString, years::AbstractVector{<:Integer})
    dates = Date[]
    lname = lowercase(name)
    for y in years
        haskey(NSE_MOVEABLE_HOLIDAYS, y) || error(
            "no NSE moveable-holiday data for year $y -- extend " *
            "NSE_MOVEABLE_HOLIDAYS (src/calendars.jl) from NSE's own " *
            "official circular before generating regressor data that " *
            "covers this year (currently tabulated years: " *
            "$(sort(collect(keys(NSE_MOVEABLE_HOLIDAYS)))))",
        )
        for (d, hname) in NSE_MOVEABLE_HOLIDAYS[y]
            occursin(lname, lowercase(hname)) && push!(dates, d)
        end
    end
    return sort(dates)
end

# ------------------------------------------------------------------
# Regressor generation -- turns a calendar/holiday set into the plain
# Date/Float64 data W.2 will serialize into a .spc user-regressor block.
#
# `periods` is always an explicit AbstractVector{<:Tuple{Date,Date}} of
# inclusive (from, to) ranges, supplied by the caller. W.0 does not
# infer period boundaries or date ranges itself -- the two confirmed
# practical requirements around forecast-horizon coverage (see
# development-sequence.md) are W.2's responsibility to act on, not
# W.0's to guess at.
# ------------------------------------------------------------------

"""
    trading_day_regressors(cal, periods) -> Matrix{Float64}

For each `(from, to)` period, count actual business days (per `cal`) on
each weekday, returned as a `(length(periods), 6)` matrix using X-13's
own `usertype=td` contrast convention: column `j` (Monday=1..Saturday=6)
is `(# business days on weekday j in that period) - (# business days on
Sunday in that period)`.

`cal` can be [`INDIA_NSE`](@ref) or any `BusinessDays.HolidayCalendar`
(e.g. one of BusinessDays.jl's own built-in major-market calendars).
"""
function trading_day_regressors(cal::BusinessDays.HolidayCalendar,
                                 periods::AbstractVector{<:Tuple{Date,Date}})
    out = Matrix{Float64}(undef, length(periods), 6)
    for (i, (from, to)) in enumerate(periods)
        counts = zeros(Int, 7)  # index 1=Monday .. 7=Sunday, matching Dates.dayofweek
        for d in from:Day(1):to
            if BusinessDays.isbday(cal, d)
                counts[dayofweek(d)] += 1
            end
        end
        sun = counts[7]
        out[i, :] = Float64.(counts[1:6] .- sun)
    end
    return out
end

"""
    easter_regressor(periods; window::Integer=8) -> Vector{Float64}

The standard Census/X-13 Easter regressor: for each `(from, to)` period,
the fraction of the `window`-day window immediately before Easter Sunday
(of whichever year `to` falls in) that overlaps that period. `window`
defaults to 8, matching X-13's own default `easter[8]`.
"""
function easter_regressor(periods::AbstractVector{<:Tuple{Date,Date}}; window::Integer=8)
    out = Vector{Float64}(undef, length(periods))
    for (i, (from, to)) in enumerate(periods)
        e = easter_date(year(to))
        window_start = e - Day(window)
        window_end = e - Day(1)
        overlap_start = max(from, window_start)
        overlap_end = min(to, window_end)
        days_in = overlap_end >= overlap_start ? (Dates.value(overlap_end - overlap_start) + 1) : 0
        out[i] = days_in / window
    end
    return out
end

"""
    custom_holiday_regressor(holiday_dates, periods) -> Vector{Float64}

For each `(from, to)` period, count how many `holiday_dates` fall within
it. This is the exact mechanism verified end-to-end against the real
`x13prebuilt` binary in `verification/diwali_regressor_proof` (via
`regression { user = (...) usertype = (holiday) }`) -- W.0 produces the
`data` vector that block needs; W.2 is responsible for writing the block
itself.
"""
function custom_holiday_regressor(holiday_dates::AbstractVector{Date},
                                   periods::AbstractVector{<:Tuple{Date,Date}})
    return [count(d -> from <= d <= to, holiday_dates) |> Float64 for (from, to) in periods]
end

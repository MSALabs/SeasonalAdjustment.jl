# src/calendars.jl
#
# W.0 -- see handoff/w0-calendars.md for the full design rationale,
# verified references, and test plan this file's tests implement.

# ------------------------------------------------------------------
# Easter -- reuses BusinessDays.jl's own computation directly (handoff
# section 2: "BusinessDays.jl already computes Easter internally...
# reuse this directly rather than re-deriving Gauss's algorithm").
# ------------------------------------------------------------------

"""
    easter_date(year) -> Date

Easter Sunday for `year`, computed by BusinessDays.jl's own
`easter_date`/`easter_rata` (not re-derived here).
"""
easter_date(year::Integer) = BusinessDays.easter_date(Dates.Year(year))

"""
    good_friday(year) -> Date

Good Friday (Easter Sunday minus two days) for `year`.
"""
good_friday(year::Integer) = easter_date(year) - Day(2)

# ------------------------------------------------------------------
# Calendar / TableCalendar -- a QuantLib-style calendar abstraction
# (handoff section 1; `TableCalendar` is this task's `BespokeCalendar`
# analogue), deliberately its OWN hierarchy rather than a
# `BusinessDays.HolidayCalendar` subtype: BusinessDays.jl's
# `isweekend`/`isbday` hardcode Saturday/Sunday as the weekend for
# every calendar (confirmed directly from its source, bdays.jl:
# `isweekend(dt::Date) = signbit(5 - dayofweek(dt))`, dispatched only
# on the date, not the calendar) -- there is no way to express a
# different weekend (e.g. Friday/Saturday) through it. Easter is still
# reused from BusinessDays.jl (above); only the part it genuinely can't
# express -- a per-calendar weekend set -- is new here.
# ------------------------------------------------------------------

abstract type Calendar end

"""
    TableCalendar <: Calendar

A calendar defined by (1) algorithmically-computable fixed holidays
(functions `year::Int -> Date`), (2) a year-keyed table of moveable
holidays with no closed-form date, and (3) a per-calendar set of
weekend weekdays (`Dates.dayofweek` values, Monday=1..Sunday=7).
"""
struct TableCalendar <: Calendar
    fixed_holidays::Vector{Function}                      # year::Int -> Date
    table_holidays::Dict{Int,Vector{Tuple{Date,String}}}   # year => [(date, name), ...]
    weekend::Set{Int}                                       # dayofweek values counted as weekend
end

BusinessDays.isweekend(cal::Calendar, wd::Integer) = wd in cal.weekend

function BusinessDays.isholiday(cal::TableCalendar, d::Date)
    y = year(d)
    any(f -> f(y) == d, cal.fixed_holidays) && return true
    if haskey(cal.table_holidays, y)
        any(e -> e[1] == d, cal.table_holidays[y]) && return true
    end
    return false
end

"""
    isbusinessday(cal, d) -> Bool

`true` unless `d` is a weekend (per `cal`'s own weekend set) or a
holiday (per `cal`'s own fixed + table holidays).
"""
isbusinessday(cal::Calendar, d::Date) = !isweekend(cal, dayofweek(d)) && !isholiday(cal, d)

function _seek(cal::Calendar, d::Date, step::Int)
    d2 = d + Day(step)
    while !isbusinessday(cal, d2)
        d2 += Day(step)
    end
    return d2
end

"""
    adjust(cal, d, convention=:following) -> Date

Standard business-day conventions (`:following`, `:preceding`,
`:modified_following`, `:modified_preceding`, `:unadjusted`), applied
to `d` under `cal`. Returns `d` unchanged if it's already a business
day (or if `convention == :unadjusted`).
"""
function adjust(cal::Calendar, d::Date, convention::Symbol = :following)
    convention === :unadjusted && return d
    isbusinessday(cal, d) && return d
    if convention === :following
        return _seek(cal, d, +1)
    elseif convention === :preceding
        return _seek(cal, d, -1)
    elseif convention === :modified_following
        adj = _seek(cal, d, +1)
        return month(adj) == month(d) ? adj : _seek(cal, d, -1)
    elseif convention === :modified_preceding
        adj = _seek(cal, d, -1)
        return month(adj) == month(d) ? adj : _seek(cal, d, +1)
    else
        throw(ArgumentError("adjust: unknown business day convention $convention"))
    end
end

"""
    advance(cal, d, period, convention=:following) -> Date

Shifts `d` by the calendar `period` (e.g. `Dates.Month(1)`), then
applies `adjust` with `convention` to the result.
"""
advance(cal::Calendar, d::Date, period::Dates.Period, convention::Symbol = :following) =
    adjust(cal, d + period, convention)

"""
    businessdaysbetween(cal, from, to) -> Int

Count of business days in the closed interval `[min(from,to), max(from,to)]`.
"""
function businessdaysbetween(cal::Calendar, from::Date, to::Date)
    lo, hi = min(from, to), max(from, to)
    return count(d -> isbusinessday(cal, d), lo:Day(1):hi)
end

"""
    holidaylist(cal, from, to; include_weekends=false) -> Vector{Date}

Holiday dates in `[min(from,to), max(from,to)]`. `include_weekends`
additionally includes every weekend date in range (per `cal`'s own
weekend set), not just named holidays.

Errors loudly (`ArgumentError`) if any year spanned by the range has no
`table_holidays` entry in `cal` -- silently falling back to fixed
holidays only would look complete while quietly missing most of a
real moveable-feast calendar. See handoff/w0-calendars.md section 5.
"""
function holidaylist(cal::TableCalendar, from::Date, to::Date; include_weekends::Bool = false)
    lo, hi = min(from, to), max(from, to)
    for y in year(lo):year(hi)
        haskey(cal.table_holidays, y) || throw(ArgumentError(
            "No holiday table entry for year $y -- add it from the official NSE " *
            "circular before using this calendar for that year",
        ))
    end
    out = Date[]
    for d in lo:Day(1):hi
        if isholiday(cal, d) || (include_weekends && isweekend(cal, dayofweek(d)))
            push!(out, d)
        end
    end
    return out
end

# ------------------------------------------------------------------
# INDIA_NSE -- the National Stock Exchange trading calendar
# ------------------------------------------------------------------

# Fixed-date NSE holidays -- always the same Gregorian date every year,
# confirmed consistent across 3 independent years (2024-2026) of
# cross-checked aggregator data. Ambedkar Jayanti (Apr 14) is also a
# fixed date but deliberately excluded here -- see the gap note below.
const NSE_FIXED_HOLIDAYS = Function[
    y -> Date(y, 1, 26),   # Republic Day
    y -> Date(y, 5, 1),    # Maharashtra Day
    y -> Date(y, 8, 15),   # Independence Day
    y -> Date(y, 10, 2),   # Mahatma Gandhi Jayanti
    y -> Date(y, 12, 25),  # Christmas
    good_friday,
]

# Moveable-feast holidays (Hindu lunisolar calendar) -- NO closed-form
# date formula exists for these. GAP, flagged honestly (see
# handoff/w0-calendars.md): sourced from cross-checked third-party
# aggregators this session (2-3 independent sources per date), NOT read
# directly from NSE's own circular PDF (WebFetch could not extract text
# from it, and nseindia.com's own holiday page timed out). Reconcile
# against NSE's own circular before production use.
#
# DELIBERATELY OMITTED, as further unresolved gaps rather than guesses:
# Eid-ul-Fitr, Bakri Id, Muharram, Mahashivratri, Ram Navami, Mahavir
# Jayanti, Ganesh Chaturthi, and Dussehra (as distinct from Gandhi
# Jayanti) -- sources disagreed on whether NSE's equity segment treats
# these as full-day closures or partial ("morning off") closures in a
# given year, and that inconsistency looked like it might be conflating
# the equity and commodity (MCX) segment calendars. Guru Nanak Jayanti
# is ALSO omitted for 2026 specifically because of a genuine, unresolved
# source conflict: this task's own handoff (handoff/w0-calendars.md)
# states Nov 5, 2026, sourced from a single aggregator; independently
# re-checking this session found 3 different aggregators (Groww, Angel
# One, Zerodha) agreeing on Nov 24, 2026 instead. Rather than silently
# pick one, it's left out until reconciled against NSE's own circular.
const NSE_MOVEABLE_HOLIDAYS = Dict{Int,Vector{Tuple{Date,String}}}(
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
        (Date(2026, 11, 8), "Diwali-Laxmi Pujan"),   # Sunday; Muhurat trading only, no extra weekday closure
        (Date(2026, 11, 10), "Diwali-Balipratipada"),
    ],
)

"""
    INDIA_NSE::TableCalendar

The India NSE trading calendar. Weekend = Saturday/Sunday (`Set([6,7])`
in `Dates.dayofweek` terms). See [`NSE_MOVEABLE_HOLIDAYS`](@ref)'s own
docstring-adjacent comment for the honest gaps in the moveable-feast
table.
"""
const INDIA_NSE = TableCalendar(NSE_FIXED_HOLIDAYS, NSE_MOVEABLE_HOLIDAYS, Set([6, 7]))

_find_holiday(year::Integer, needle::AbstractString) = begin
    haskey(NSE_MOVEABLE_HOLIDAYS, year) || return nothing
    idx = findfirst(e -> occursin(needle, lowercase(e[2])), NSE_MOVEABLE_HOLIDAYS[year])
    idx === nothing ? nothing : NSE_MOVEABLE_HOLIDAYS[year][idx][1]
end

"""
    diwali_date(year) -> Union{Date,Nothing}

The Diwali Laxmi Pujan date for `year`, or `nothing` if `year` isn't in
[`NSE_MOVEABLE_HOLIDAYS`](@ref). A `holiday_years_present`-shaped
callback for [`custom_holiday_regressor`](@ref).
"""
diwali_date(year::Integer) = _find_holiday(year, "laxmi pujan")

"""
    holi_date(year) -> Union{Date,Nothing}

The Holi date for `year`, or `nothing` if `year` isn't in
[`NSE_MOVEABLE_HOLIDAYS`](@ref). A `holiday_years_present`-shaped
callback for [`custom_holiday_regressor`](@ref).
"""
holi_date(year::Integer) = _find_holiday(year, "holi")

# ------------------------------------------------------------------
# Regressor generation -- turns a calendar/holiday set into the plain
# Date/Float64 data W.2 will serialize into a .spc user-regressor
# block. `from`/`to` are supplied by the caller (eventually W.2, which
# knows the series' actual period boundaries and the forecast horizon
# it needs covered); W.0 does not infer date ranges itself.
# ------------------------------------------------------------------

function _monthly_periods(from::Date, to::Date)
    periods = Tuple{Date,Date}[]
    d = Dates.firstdayofmonth(from)
    stop = Dates.firstdayofmonth(to)
    while d <= stop
        push!(periods, (d, Dates.lastdayofmonth(d)))
        d += Dates.Month(1)
    end
    return periods
end

"""
    trading_day_regressors(from, to, cal; freq=:month) -> Matrix{Float64}

For each period between `from` and `to` (currently only `freq=:month`
is supported), count actual business days (per `cal`) on each weekday,
returned as a `(nperiods, 6)` matrix using X-13's own `usertype=td`
contrast convention: column `j` (Monday=1..Saturday=6) is `(# business
days on weekday j in that period) - (# business days on Sunday in that
period)`.
"""
function trading_day_regressors(from::Date, to::Date, cal::Calendar; freq::Symbol = :month)
    freq === :month || throw(ArgumentError(
        "trading_day_regressors: freq=$freq isn't supported yet (only :month) -- " *
        "extend _monthly_periods-style tiling before using another frequency",
    ))
    periods = _monthly_periods(from, to)
    out = Matrix{Float64}(undef, length(periods), 6)
    for (i, (p_from, p_to)) in enumerate(periods)
        counts = zeros(Int, 7)  # index 1=Monday .. 7=Sunday, matching Dates.dayofweek
        for d in p_from:Day(1):p_to
            if isbusinessday(cal, d)
                counts[dayofweek(d)] += 1
            end
        end
        sun = counts[7]
        out[i, :] = Float64.(counts[1:6] .- sun)
    end
    return out
end

"""
    easter_regressor(from, to; window=0) -> Vector{Float64}

The standard Census/X-13 Easter regressor: for each monthly period
between `from` and `to`, the fraction of the `window`-day window
immediately before Easter Sunday (of whichever year that period falls
in) that overlaps the period. `window=0` (the default) produces an
all-zero vector -- X-13 itself has no universal default `w`, the user
always specifies it explicitly in the `.spc` file, so no particular
value is assumed here either; pass an explicit `window` (commonly 1, 8,
or 15 in practice).
"""
function easter_regressor(from::Date, to::Date; window::Integer = 0)
    periods = _monthly_periods(from, to)
    out = Vector{Float64}(undef, length(periods))
    for (i, (p_from, p_to)) in enumerate(periods)
        if window <= 0
            out[i] = 0.0
            continue
        end
        e = easter_date(year(p_to))
        window_start = e - Day(window)
        window_end = e - Day(1)
        overlap_start = max(p_from, window_start)
        overlap_end = min(p_to, window_end)
        days_in = overlap_end >= overlap_start ? (Dates.value(overlap_end - overlap_start) + 1) : 0
        out[i] = days_in / window
    end
    return out
end

"""
    custom_holiday_regressor(from, to, cal, holiday_years_present) -> Vector{Float64}

For each monthly period between `from` and `to`, `1.0` if
`holiday_years_present(year)` (a function `year::Int ->
Union{Date,Nothing}`) returns a date that both falls in that period AND
is not already a weekend under `cal` (a holiday that lands on a weekend
has no incremental trading-day effect to explain -- matches the "no
extra closure" annotation real NSE holiday listings use for exactly
this case), `0.0` otherwise. A year for which `holiday_years_present`
returns `nothing` contributes `0.0`, silently -- by design, this
function treats "not applicable this year" and "not in the table" the
same way; callers who need to distinguish a genuine gap from a holiday
that simply didn't occur should audit coverage with `holidaylist`
first, which errors loudly on an untabulated year.

This is the exact mechanism verified end-to-end against the real
`x13prebuilt` binary in `handoff/verification/diwali_regressor_proof`
(via `regression { user = (...) usertype = (holiday) }`) -- this
function produces the `data` vector that block needs; W.2 is
responsible for writing the block itself.
"""
function custom_holiday_regressor(from::Date, to::Date, cal::Calendar, holiday_years_present::Function)
    periods = _monthly_periods(from, to)
    out = Vector{Float64}(undef, length(periods))
    for (i, (p_from, p_to)) in enumerate(periods)
        hit = 0.0
        for y in year(p_from):year(p_to)
            d = holiday_years_present(y)
            if d !== nothing && p_from <= d <= p_to && !isweekend(cal, dayofweek(d))
                hit = 1.0
            end
        end
        out[i] = hit
    end
    return out
end

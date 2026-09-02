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
`easter_date`/`easter_rata` (not re-derived here) via the standard
(Gauss/anonymous) Computus algorithm for the date of the first Sunday
following the first ecclesiastical full moon on or after 21 March.

# Examples
```jldoctest
julia> easter_date(2025)
2025-04-20

julia> easter_date(2026)
2026-04-05
```
"""
easter_date(year::Integer) = BusinessDays.easter_date(Dates.Year(year))

"""
    good_friday(year) -> Date

Good Friday (Easter Sunday minus two days) for `year`.

# Examples
```jldoctest
julia> SeasonalAdjustment.good_friday(2025)  # not exported -- qualify, or `using SeasonalAdjustment: good_friday`
2025-04-18
```
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

"""
    Calendar

Root abstract type for every calendar in this package -- a QuantLib-
style abstraction (`isbusinessday`/`isholiday`/`isweekend`/`adjust`/
`advance`/`businessdaysbetween`/`holidaylist`), deliberately its own
hierarchy rather than a `BusinessDays.HolidayCalendar` subtype (see the
comment above this type for why). [`TableCalendar`](@ref) is currently
the only concrete subtype.
"""
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

"""
    isweekend(cal::Calendar, wd::Integer) -> Bool

`true` if weekday `wd` (a `Dates.dayofweek` value, Monday=1..Sunday=7)
is in `cal`'s own weekend set. Extends `BusinessDays.isweekend`, whose
own single-argument `isweekend(dt::Date)` method hardcodes Saturday/
Sunday for every calendar -- this per-calendar method is exactly the
capability [`Calendar`](@ref)'s own docstring explains BusinessDays.jl
can't express.

# Examples
```jldoctest
julia> isweekend(INDIA_NSE, 6)  # Saturday
true

julia> isweekend(INDIA_NSE, 1)  # Monday
false
```
"""
BusinessDays.isweekend(cal::Calendar, wd::Integer) = wd in cal.weekend

"""
    isholiday(cal::TableCalendar, d::Date) -> Bool

`true` if `d` matches one of `cal`'s fixed-date holiday rules or its
year-keyed moveable-holiday table. Extends `BusinessDays.isholiday`.

# Examples
```jldoctest
julia> using Dates

julia> isholiday(INDIA_NSE, Date(2025, 8, 15))  # Independence Day, a fixed holiday
true

julia> isholiday(INDIA_NSE, Date(2025, 10, 21))  # Diwali-Laxmi Pujan, a moveable holiday
true

julia> isholiday(INDIA_NSE, Date(2025, 8, 14))
false
```
"""
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

# Examples
```jldoctest
julia> using Dates

julia> isbusinessday(INDIA_NSE, Date(2025, 10, 21))  # Diwali-Laxmi Pujan
false

julia> isbusinessday(INDIA_NSE, Date(2025, 10, 20))
true
```
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

# Examples
```jldoctest
julia> using Dates

julia> adjust(INDIA_NSE, Date(2025, 10, 21))  # Diwali-Laxmi Pujan, followed by Diwali-Balipratipada on the 22nd -- rolls to the 23rd
2025-10-23

julia> adjust(INDIA_NSE, Date(2025, 10, 21), :preceding)
2025-10-20

julia> adjust(INDIA_NSE, Date(2025, 10, 20))  # already a business day
2025-10-20
```
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

# Examples
```jldoctest
julia> using Dates

julia> advance(INDIA_NSE, Date(2025, 10, 20), Day(1))  # one calendar day forward, then adjusted
2025-10-23

julia> advance(INDIA_NSE, Date(2025, 9, 1), Month(1))
2025-10-01
```
"""
advance(cal::Calendar, d::Date, period::Dates.Period, convention::Symbol = :following) =
    adjust(cal, d + period, convention)

"""
    businessdaysbetween(cal, from, to) -> Int

Count of business days in the closed interval `[min(from,to), max(from,to)]`.

# Examples
```jldoctest
julia> using Dates

julia> businessdaysbetween(INDIA_NSE, Date(2025, 10, 1), Date(2025, 10, 31))
20
```
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
real moveable-feast calendar.

# Examples
```jldoctest
julia> using Dates

julia> holidaylist(INDIA_NSE, Date(2025, 10, 1), Date(2025, 10, 31))
3-element Vector{Date}:
 2025-10-02
 2025-10-21
 2025-10-22

julia> holidaylist(INDIA_NSE, Date(2030, 1, 1), Date(2030, 1, 31))
ERROR: ArgumentError: No holiday table entry for year 2030 -- add it from the official NSE circular before using this calendar for that year
```
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
in `Dates.dayofweek` terms). See `NSE_MOVEABLE_HOLIDAYS`'s own
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
`NSE_MOVEABLE_HOLIDAYS`. A `holiday_years_present`-shaped
callback for [`custom_holiday_regressor`](@ref).

# Examples
```jldoctest
julia> SeasonalAdjustment.diwali_date(2025)  # not exported -- qualify, or `using SeasonalAdjustment: diwali_date`
2025-10-21

julia> SeasonalAdjustment.diwali_date(2030) === nothing
true
```
"""
diwali_date(year::Integer) = _find_holiday(year, "laxmi pujan")

"""
    holi_date(year) -> Union{Date,Nothing}

The Holi date for `year`, or `nothing` if `year` isn't in
`NSE_MOVEABLE_HOLIDAYS`. A `holiday_years_present`-shaped
callback for [`custom_holiday_regressor`](@ref).

# Examples
```jldoctest
julia> SeasonalAdjustment.holi_date(2025)  # not exported -- qualify, or `using SeasonalAdjustment: holi_date`
2025-03-14
```
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

# Quarterly tiling, added alongside `_monthly_periods` to support
# `freq=:quarter` below -- 3-month blocks anchored at the calendar
# quarter (Jan/Apr/Jul/Oct) containing `from`/`to`, mirroring
# `_monthly_periods`'s own "always tile whole periods, even if `from`/
# `to` land mid-period" behavior.
function _quarterly_periods(from::Date, to::Date)
    periods = Tuple{Date,Date}[]
    fm = Dates.firstdayofmonth(from)
    d = Date(year(fm), ((month(fm) - 1) ÷ 3) * 3 + 1, 1)
    tm = Dates.firstdayofmonth(to)
    stop = Date(year(tm), ((month(tm) - 1) ÷ 3) * 3 + 1, 1)
    while d <= stop
        push!(periods, (d, Dates.lastdayofmonth(d + Dates.Month(2))))
        d += Dates.Month(3)
    end
    return periods
end

_periods_for(freq::Symbol, from::Date, to::Date) =
    freq === :month ? _monthly_periods(from, to) :
    freq === :quarter ? _quarterly_periods(from, to) :
    throw(ArgumentError(
        "freq=$freq isn't supported -- only :month or :quarter, matching X-13's own " *
        "period=12/period=4 -- see X13Spec's `period` field",
    ))

"""
    trading_day_regressors(from, to, cal; freq=:month) -> Matrix{Float64}

For each period between `from` and `to` (`freq=:month` or `freq=:quarter`,
matching X-13's own period=12/period=4), count actual business days (per
`cal`) on each weekday, returned as a `(nperiods, 6)` matrix using X-13's
own `usertype=td` contrast convention: column `j` (Monday=1..Saturday=6)
is `(# business days on weekday j in that period) - (# business days on
Sunday in that period)`.

**Known gap, `freq=:quarter`**: confirmed directly against the real
binary that quarterly's own `.rmx` export for `td` has a 7th column
("Leap Year") that monthly's does not -- this function always returns 6
columns for either `freq`, so it does not reproduce that extra column.
Fine for feeding a *user*-defined regressor (X-13 doesn't require the
extra column there), not a byte-for-byte replica of X-13's own internal
quarterly `td` regressor.

For weekday ``j`` (Monday=1..Saturday=6) in a given period,

```math
X_j = n_j - n_{\\text{Sun}}
```

where ``n_j`` is the count of business days falling on weekday ``j``
within that period -- the standard trading-day contrast X-13 itself
uses internally, with Sunday as the omitted reference category.

# Examples
```jldoctest
julia> using Dates

julia> trading_day_regressors(Date(2025, 10, 1), Date(2025, 10, 31), INDIA_NSE)
1×6 Matrix{Float64}:
 4.0  3.0  4.0  4.0  5.0  0.0
```
"""
function trading_day_regressors(from::Date, to::Date, cal::Calendar; freq::Symbol = :month)
    periods = _periods_for(freq, from, to)
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
    easter_regressor(from, to; window=0, freq=:month) -> Vector{Float64}

The standard Census/X-13 Easter regressor: for each period (`freq=:month`
or `freq=:quarter`) between `from` and `to`, the fraction of the
`window`-day window immediately before Easter Sunday (of whichever year
that period falls in) that overlaps the period. `window=0` (the default)
produces an all-zero vector -- X-13 itself has no universal default `w`,
the user always specifies it explicitly in the `.spc` file, so no
particular value is assumed here either; pass an explicit `window`
(commonly 1, 8, or 15 in practice). `freq=:quarter` confirmed directly
against the real binary to work the same way as monthly (Easter always
falls within Q1 or Q2, so at most one quarter per year is affected).

For a period ``[p_1, p_2]`` and a ``w``-day window ending the day
before Easter Sunday ``E``,

```math
\\text{value} = \\frac{\\left|[p_1, p_2] \\cap [E-w, E-1]\\right|}{w}
```

-- the fraction of the pre-Easter window that overlaps the period, so
a period entirely inside the window scores `1.0`, one entirely outside
it scores `0.0`, and a period the window only partly overlaps scores
somewhere in between.

# Examples
```jldoctest
julia> using Dates

julia> easter_regressor(Date(2025, 3, 1), Date(2025, 4, 30); window = 8)
2-element Vector{Float64}:
 0.0
 1.0

julia> easter_regressor(Date(2025, 1, 1), Date(2025, 1, 31); window = 8)  # January -- nowhere near Easter
1-element Vector{Float64}:
 0.0

julia> easter_regressor(Date(2025, 1, 1), Date(2025, 1, 31))  # window omitted -- always all-zero
1-element Vector{Float64}:
 0.0
```
"""
function easter_regressor(from::Date, to::Date; window::Integer = 0, freq::Symbol = :month)
    periods = _periods_for(freq, from, to)
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
    custom_holiday_regressor(from, to, cal, holiday_years_present; freq=:month) -> Vector{Float64}

For each period (`freq=:month` or `freq=:quarter`) between `from` and
`to`, `1.0` if `holiday_years_present(year)` (a function `year::Int ->
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
`x13prebuilt` binary (via `regression { user = (...) usertype = (holiday) }`,
a synthetic Diwali-effect test that genuinely shifted the fitted
seasonal factors) -- this function produces the `data` vector that
block needs; the spec-rendering layer is responsible for writing the
block itself.

# Examples
```jldoctest
julia> using Dates

julia> custom_holiday_regressor(Date(2025, 9, 1), Date(2025, 12, 31), INDIA_NSE,
                                 year -> year == 2025 ? Date(2025, 10, 21) : nothing)
4-element Vector{Float64}:
 0.0
 1.0
 0.0
 0.0
```
"""
function custom_holiday_regressor(from::Date, to::Date, cal::Calendar, holiday_years_present::Function; freq::Symbol = :month)
    periods = _periods_for(freq, from, to)
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

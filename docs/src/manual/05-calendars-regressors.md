```@meta
CurrentModule = SeasonalAdjustment
```

# Calendars and Regressors

One paragraph: X-13's built-in calendar effects are Easter, Labor Day
and Thanksgiving — three holidays specific to the United States. This
package adds a general calendar layer underneath these, so that a
holiday which is none of the three, or an entirely different market's
calendar altogether, remains reachable.

## How do I check whether a date is a trading day?

```julia
using Dates
isbusinessday(INDIA_NSE, Date(2025, 10, 21))   # false -- Diwali-Laxmi Pujan
isholiday(INDIA_NSE, Date(2025, 10, 21))       # true
isweekend(INDIA_NSE, Date(2025, 10, 25))       # true -- Saturday
advance(INDIA_NSE, Date(2025, 10, 21), Day(1)) # advance one calendar day, then roll to a business day
businessdaysbetween(INDIA_NSE, Date(2025, 10, 1), Date(2025, 10, 31))
```

This is a `BusinessDays.jl`-style API — [`Calendar`](@ref) is the
abstract type, [`isbusinessday`](@ref)/[`isholiday`](@ref)/
[`isweekend`](@ref)/[`adjust`](@ref)/[`advance`](@ref)/
[`businessdaysbetween`](@ref) all dispatch upon it. [`INDIA_NSE`](@ref)
ships as a concrete calendar built from real NSE circular data.

## How do I build a calendar the package does not ship?

```julia
holidays = Dict(
    2025 => [(Date(2025, 1, 1), "New Year"), (Date(2025, 12, 25), "Christmas")],
)
my_calendar = TableCalendar(holidays)
```

[`TableCalendar`](@ref) builds a calendar directly from a per-year
list of `(Date, name)` pairs — this is the very mechanism behind
`INDIA_NSE` itself, so a calendar for any other market is the same
construction with different dates. [`holidaylist`](@ref) errors
loudly (`ArgumentError`) rather than silently returning an empty range
where any year spanned by a query has no table entry — a real,
deliberate design choice, since silently falling back to "no holidays
that year" would look complete while quietly missing data.

## How do I build a holiday regressor from dates?

```julia
function diwali_date(year::Int)
    year == 2025 ? Date(2025, 10, 21) : nothing
end

reg = custom_holiday_regressor(Date(2025, 1, 1), Date(2025, 12, 31),
                                INDIA_NSE, diwali_date; freq = :month)
```

[`custom_holiday_regressor`](@ref) takes a function `year ->
Union{Date, Nothing}` rather than a fixed date list, so that a moving
holiday's date may be computed or looked up per year. It returns `1.0`
in whichever period the holiday falls in **unless that date is
already a non-trading day under the given calendar**, in which case it
contributes `0.0` instead — the weekend-drop rule, covered in full in
the [Moving Holidays](../introduction/11-moving-holidays.md) chapter.

The result is fed into `x13()` as a `regression_user`:

```julia
res = x13(y; transform = :log, regression_user = reg,
          regression_usertype = :holiday, regression_user_name = :diwali)
```

!!! warning "Gotcha — do not also list the regressor's name in `regression_variables`"
    `regression_user_name = :diwali` plus `user = (diwali)` in the
    rendered spec is sufficient on its own to include the regressor in
    the model. Adding `"diwali"` to `regression_variables` as well
    makes the real binary reject the spec outright
    (`Regression variable name "diwali" not found`) — confirmed
    directly by rendering the exact `.spc` text and testing
    incrementally. `user = (name)` alone is what includes a
    user-defined regressor; the name ought not be duplicated.

## How do I add trading-day or Easter regressors?

```julia
res = x13(y; trading = true, transform = :log)
res = x13(y; aictest = [:td, :easter], transform = :auto)
```

Both are built in. `trading = true` adds the day-of-week regressors
directly; `aictest` fits with and without each one, retaining it only
where it earns its place by information criterion. For the raw
regressor data itself, without a full adjustment being run:

```julia
trading_day_regressors(Date(1949, 1, 1), Date(1960, 12, 1))
easter_regressor(Date(1949, 1, 1), Date(1960, 12, 1); window = 8)
```

## How do I do any of this for quarterly data?

```julia
custom_holiday_regressor(from, to, cal, year_fn; freq = :quarter)
```

Every calendar and regressor function taking `freq` accepts `:month`
or `:quarter` — the same convention `x13(y; period = 4)` uses for the
adjustment itself.

---

**See also:** the [Moving Holidays](../introduction/11-moving-holidays.md)
chapter of the *Introduction* for why the weekend-drop rule is a
methodological choice, and not merely an implementation detail, with a
real worked example against `iip_india`. [`Calendar`](@ref)/
[`TableCalendar`](@ref)/[`INDIA_NSE`](@ref) and the rest in the
[API Reference](../api.md).

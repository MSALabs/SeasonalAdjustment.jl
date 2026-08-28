# Handoff: Task W.0 — Business-Day Calendars & Holiday Regressor Generation

For a fresh Claude Code session picking this up with no prior context.
Read `CLAUDE.md` and `development-sequence.md` in full first — this
handoff assumes both. This is the first task in the sequence; nothing
in this package depends on anything not already in the repo scaffold.

## Where this fits

- **Depends on:** nothing internal — `BusinessDays.jl` only (external
  package).
- **Consumed by:** W.2 (spec-file generation) directly — this task's
  whole purpose is producing numeric regressor vectors in the exact
  format W.2 will embed into `.spc` files. Build toward that output
  shape specifically, not a general-purpose calendar library that
  happens to be useful later.
- **This is the task the whole custom-regressor mechanism already
  proved works.** The verification bundle already in this repo
  (`handoff/verification/diwali_regressor_proof/`) is real output from feeding
  a synthetic Diwali-effect regressor into the actual `x13prebuilt`
  binary — this task's job is generating that regressor *for real*,
  not re-proving the mechanism (already done).

---

## 1. Verified reference: QuantLib's `Calendar` interface

Confirmed directly (QuantLib's own documentation, RQuantLib, and
QuantLib-Python) during this project's design phase:
```
isBusinessDay(date) -> Bool
isHoliday(date) -> Bool
isWeekend(weekday) -> Bool
isEndOfMonth(date) -> Bool
adjust(date, convention) -> Date
advance(date, period, convention) -> Date
businessDaysBetween(from, to, includeFirst, includeLast) -> Int
holidayList(from, to, includeWeekends) -> Vector{Date}
```
Business day conventions: `Following`, `Preceding`, `ModifiedFollowing`,
`ModifiedPreceding`, `Unadjusted`.

**`BespokeCalendar`** — QuantLib's own escape hatch for a fully
user-defined calendar — is the direct precedent for this task's
`TableCalendar` design below.

## 2. Verified foundation: `BusinessDays.jl`, not reimplemented

Confirmed: `QuantLib.jl` itself builds its calendar module on top of
`BusinessDays.jl` rather than reimplementing calendar data — this
project follows the same precedent. `BusinessDays.jl` already computes
Easter internally (`easter_rata`, used for its own Western-calendar
holiday support) — reuse this directly rather than re-deriving Gauss's
algorithm from scratch.

## 3. India — what's computable, and what needs a maintained table

**Algorithmically computable, no table needed:**
```julia
Republic Day       = January 26
Independence Day   = August 15
Gandhi Jayanti      = October 2
Good Friday         = via BusinessDays.jl's existing Easter computation
```

**Needs a maintained, year-keyed table — no closed-form formula exists**:
Diwali, Holi, Eid al-Fitr, Eid al-Adha, and most of NSE's actual
holiday list follow the Hindu lunisolar or Islamic lunar calendar.
QuantLib's own India calendar handles this the same way — a maintained
list of announced dates, not a formula.

**A real data-sourcing caution, already hit once during this project's
design phase**: secondary financial-news aggregators disagreed on one
2026 NSE holiday date by more than two weeks (Diwali Laxmi Pujan —
most sources said November 8, one said October 21). **Source the
production table from NSE's own official circular directly, not
aggregator sites.** The starter table below is majority-sourced from
aggregators and explicitly NOT to be trusted as production data without
that direct confirmation.

### Starter table (2026 — confirm against NSE's official circular before treating as production)

```julia
const INDIA_NSE_HOLIDAYS_2026 = [
    Date(2026,1,26),   # Republic Day
    Date(2026,2,15),   # Mahashivratri (Sunday -- no extra closure)
    Date(2026,3,3),    # Holi
    Date(2026,3,21),   # Id-Ul-Fitr (Sunday -- no extra closure)
    Date(2026,4,3),    # Good Friday
    Date(2026,5,1),    # Maharashtra Day
    Date(2026,8,15),   # Independence Day (Sunday -- no extra closure)
    Date(2026,10,2),   # Gandhi Jayanti / Dussehra
    Date(2026,11,8),   # Diwali Laxmi Pujan -- SOURCE-VERIFY, see caution above
    Date(2026,11,5),   # Guru Nanak Jayanti
    Date(2026,12,25),  # Christmas
]
```

## 4. The actual downstream target: exact numeric format already tested against the real binary

**Confirmed working** (this repo's `handoff/verification/diwali_regressor_proof/diwali_official.spc`):
```
regression {
  variables = (td)
  user = (diwali)
  usertype = (holiday)
  start = 1949.1
  data = (0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0
          0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0
          ...)
}
```
One value per period (month, for monthly series), space-separated,
12 per line by convention (not required, just what the working example
used). **This task's functions must produce exactly this shape** — a
flat `Vector{Float64}`, one entry per period across the requested date
range — so W.2 can format it directly with no reshaping logic of its
own.

**Two real, hard requirements, already discovered by hitting them**:
1. **The regressor vector must cover the RegARIMA forecast horizon**
   (a year ahead by default), not just the historical series length —
   confirmed via a real error (`"forecasts end date ... must end on or
   before user-defined regression variables end date"`) when this
   wasn't done. This task's functions must accept an explicit `to::Date`
   that the caller sets *past* the series' own end, not silently stop
   at the last historical observation.
2. **(Not this task's concern directly, but downstream-relevant)**:
   W.2 must pair any regressor-driven RegARIMA spec with
   `transform { function = log }`. Note it in this task's docstrings so
   it isn't lost by the time W.2 is written.

---

## 5. Proposed API

```julia
abstract type Calendar end

struct TableCalendar <: Calendar
    fixed_holidays::Vector{Function}        # year::Int -> Date
    table_holidays::Dict{Int,Vector{Date}}  # year => specific dates
    weekend::Set{Int}                        # weekday numbers counted as weekend
end

const INDIA_NSE = TableCalendar(
    [y -> Date(y,1,26), y -> Date(y,8,15), y -> Date(y,10,2)],
    Dict(2026 => INDIA_NSE_HOLIDAYS_2026),
    Set([6,7]),
)

isbusinessday(cal::Calendar, d::Date) -> Bool
isholiday(cal::Calendar, d::Date) -> Bool
isweekend(cal::Calendar, wd::Int) -> Bool
adjust(cal::Calendar, d::Date, convention::Symbol=:following) -> Date
advance(cal::Calendar, d::Date, period, convention::Symbol=:following) -> Date
businessdaysbetween(cal::Calendar, from::Date, to::Date) -> Int
holidaylist(cal::Calendar, from::Date, to::Date; include_weekends::Bool=false) -> Vector{Date}

trading_day_regressors(from::Date, to::Date, cal::Calendar; freq::Symbol=:month) -> Matrix{Float64}
easter_regressor(from::Date, to::Date; window::Int=0) -> Vector{Float64}
custom_holiday_regressor(from::Date, to::Date, cal::Calendar, holiday_years_present::Function) -> Vector{Float64}
```

Design notes:
- **`custom_holiday_regressor`** is the new, general function this task
  actually needs to add beyond what was sketched during design —
  `holiday_years_present` is a function `year::Int -> Union{Nothing,Date}`
  returning that year's occurrence of the target holiday (or `nothing`
  if it doesn't apply that year), so the same function drives Diwali,
  Holi, or any other table-based holiday without duplicating logic per
  holiday name.
- **`holidaylist`/regressor functions on a year not in `table_holidays`
  must throw a clear, named `ArgumentError`** (`"No holiday table entry
  for year 2030 -- add it from the official NSE circular before using
  this calendar for that year"`) — never silently fall back to fixed
  holidays only, since that would look complete while quietly missing
  the majority of India's actual trading calendar.
- **`Symbol`-based conventions** (`:following`, `:modified_following`,
  `:preceding`, `:modified_preceding`, `:unadjusted`) — matches this
  project's established naming style.

---

## 6. Comprehensive test matrix

```julia
using Test, Dates

@testset "India fixed holidays" begin
    @test isholiday(INDIA_NSE, Date(2026,1,26))
    @test isholiday(INDIA_NSE, Date(2026,8,15))
    @test isholiday(INDIA_NSE, Date(2026,10,2))
    @test !isholiday(INDIA_NSE, Date(2026,1,27))
end

@testset "Easter -- reuses BusinessDays.jl, spot-checked against known dates" begin
    @test easter_date(2024) == Date(2024,3,31)
    @test easter_date(2025) == Date(2025,4,20)
    @test easter_date(2026) == Date(2026,4,5)
end

@testset "table calendar -- year not in table errors clearly" begin
    @test_throws ArgumentError holidaylist(INDIA_NSE, Date(2030,1,1), Date(2030,12,31))
    @test_throws ArgumentError custom_holiday_regressor(Date(2030,1,1), Date(2030,12,31), INDIA_NSE, diwali_date)
end

@testset "weekend detection" begin
    @test isweekend(INDIA_NSE, 6)
    @test isweekend(INDIA_NSE, 7)
    @test !isweekend(INDIA_NSE, 1)
end

@testset "business day conventions" begin
    sat = Date(2026,1,31)
    @test dayofweek(adjust(INDIA_NSE, sat, :following)) != 6
    @test adjust(INDIA_NSE, sat, :following) > sat
    @test adjust(INDIA_NSE, sat, :preceding) < sat
end

@testset "regressor vectors -- correct shape for W.2" begin
    reg = custom_holiday_regressor(Date(2026,1,1), Date(2027,12,31), INDIA_NSE, diwali_date)
    @test length(reg) == 24  # 2 full years, monthly
    @test all(x -> x == 0.0 || x == 1.0, reg)
    @test sum(reg) == 2  # one Diwali-month hit per year present in the table
end

@testset "CAPSTONE: reproduce the real Diwali proof against the actual binary" begin
    # Regenerate the exact regressor this repo's handoff/verification/diwali_regressor_proof/
    # was built from, using this task's own functions instead of the
    # hand-written synthetic values -- then either (a) re-run x13prebuilt
    # directly if it's available in this environment, confirming the
    # SAME October seasonal-factor shift (0.8986 -> 0.7540, per the
    # corrected "official" fixture data -- see handoff/verification/README.md), or (b) at
    # minimum confirm the generated vector byte-matches the values
    # already in handoff/verification/diwali_regressor_proof/diwali_official.spc.
    # This is the test that actually closes the loop between W.0 and
    # the mechanism already proven to work.
end
```

---

## 7. What to do with this

1. Implement `Calendar`/`TableCalendar` and all functions in section 5,
   in `src/calendars.jl` (already stubbed).
2. Run the tests in section 6 — **the capstone test is the one that
   actually matters most**; don't consider this task done until a
   generated regressor either reproduces the existing verified binary
   output or is confirmed byte-identical to the spec file already in
   `handoff/verification/diwali_regressor_proof/`.
3. Do not treat the starter 2026 India holiday table as production data
   — flag this explicitly in code comments at `INDIA_NSE_HOLIDAYS_2026`'s
   definition, pointing back to this handoff's data-sourcing caution.
4. Update `development-sequence.md`'s W.0 row to mark this complete,
   and note explicitly whether the capstone test re-ran the real binary
   or only confirmed byte-identical spec output (an honest distinction
   worth recording, not collapsing into a single "done").
5. Move to W.1 (`Artifacts.toml` finalization via `tools/generate_artifacts.jl`)
   next, per `development-sequence.md`'s critical path.

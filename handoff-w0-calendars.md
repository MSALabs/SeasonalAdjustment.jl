# Handoff — W.0: Business-day/holiday calendars

## Scope

Per `development-sequence.md`, W.0 delivers the calendar machinery that
generates the *data* for user-defined regressors — the mechanism W.2
(spec-file generation, not yet built) will later serialize into a
`.spc` file's `regression { user = (...) data = (...) }` block. W.0
does **not** generate spec-file text itself (that's W.2), and does not
invoke the binary (that's W.3) — it produces plain Julia `Date`s and
`Float64` arrays.

`src/SeasonalAdjustment.jl` already commits to this export surface
(written at scaffold time, honored here rather than redesigned):
```julia
export INDIA_NSE
export trading_day_regressors, easter_regressor, custom_holiday_regressor
```

## Verified references

- **Good Friday**: computed as `Easter Sunday - 2 days`, via the
  standard Anonymous Gregorian algorithm (Meeus/Jones/Butcher). Cross-
  validated directly against 3 independent years of real NSE Good
  Friday dates found via web search (not just the algorithm's own
  reputation):
  - 2024: algorithm gives Mar 29 → matches CalendarLabs' NSE 2024 list
  - 2025: algorithm gives Apr 18 → matches Jainam's NSE 2025 list
  - 2026: algorithm gives Apr 3 → matches Groww's and Angel One's NSE
    2026 lists
  All three matched exactly. This is real, if informal, verification —
  not just "the formula is well-known."
- **Fixed-date NSE holidays**: Republic Day (Jan 26), Independence Day
  (Aug 15), Mahatma Gandhi Jayanti (Oct 2) — confirmed algorithmically
  computable per `development-sequence.md`, cross-checked against the
  same 2024-2026 aggregator pages above.
- **Moveable-feast NSE holidays** (Holi, Diwali Laxmi Pujan, Diwali
  Balipratipada): **no closed-form formula** (lunar/lunisolar), per
  `development-sequence.md`'s own explicit caution. Sourced via
  WebSearch/WebFetch this session, cross-checking multiple independent
  aggregators against each other for 2024-2026:
  - 2024: Holi Mar 25; Laxmi Pujan Nov 1; Balipratipada Nov 2
  - 2025: Holi Mar 14; Laxmi Pujan Oct 21; Balipratipada Oct 22
  - 2026: Holi Mar 3; Laxmi Pujan Nov 8 (Sunday — Muhurat trading only,
    not itself a weekday closure); Balipratipada Nov 10
  Two to three independent sources agreed for each year above (Groww,
  Angel One, Zerodha, CalendarLabs, Jainam).

## Honest gap — not silently resolved

**The official NSE circular PDFs could not be machine-read this
session.** `WebFetch` on both
`archives.nseindia.com/content/circulars/CMTR54757.pdf` and the linked
2024 circular (`CMTR59722.pdf`) returned binary/compressed content it
could not extract text from, and the live
`nseindia.com/resources/exchange-communication-holidays` page timed
out (likely bot-blocked). The table in `NSE_MOVEABLE_HOLIDAYS` is
therefore built from cross-checked third-party aggregators, not NSE's
own circular directly — exactly the class of source
`development-sequence.md` warns disagreed on a 2026 Diwali date by two
weeks elsewhere. The dates above are corroborated by 2-3 independent
aggregators each and cross-validate against the Easter/Good-Friday
figures where relevant, so confidence is reasonable, but **this should
be reconciled against NSE's own circular before being relied on for
actual official-statistics work.** The code:
- errors loudly (rather than silently zero-filling) if a moveable-
  holiday lookup is requested for a year outside 2024-2026
- documents this gap inline, at the table definition, not just here

**Eid dates are deliberately omitted from the table.** Sources
disagreed on whether Eid-ul-Fitr/Bakri Id are full NSE trading closures
or partial ("morning off") closures in a given year, and this looked
like it might be conflating the equity segment calendar with the
commodity (MCX) segment calendar. Rather than guess, Eid is left out of
`NSE_MOVEABLE_HOLIDAYS` entirely — a real gap, flagged, not a silent
omission.

## "India + major markets" — how the scope is actually split

`BusinessDays.jl` (the declared W.0 dependency) already ships built-in
calendars for major markets (US, UK, Brazil, TARGET/EU, Japan, etc. —
confirmed by inspecting the installed package, see below). It does
**not** ship an India/NSE calendar. So W.0's actual new work is just
`INDIA_NSE`; "major markets" support is satisfied because
`trading_day_regressors` and `easter_regressor` are written generically
against `BusinessDays.HolidayCalendar`, not hardcoded to India — any of
BusinessDays.jl's built-in calendars (e.g. `BusinessDays.USSettlement`)
work with them automatically. This is an interpretation, stated
plainly rather than assumed silently: the alternative reading (W.0
must define its *own* US/UK/etc. calendars from scratch, duplicating
BusinessDays.jl) was rejected as needless duplication of a dependency
already pulled in for exactly this purpose.

## API design

```julia
easter_date(year::Integer) -> Date                    # not exported; internal helper
good_friday(year::Integer) -> Date                     # not exported; internal helper

INDIA_NSE::NSEHolidayCalendar                           # exported singleton, isa BusinessDays.HolidayCalendar

trading_day_regressors(cal, periods) -> Matrix{Float64}  # (nperiods, 6): Mon..Sat business-day counts, each minus that period's Sunday count (X-13's usertype=td contrast convention)
easter_regressor(periods; window=8) -> Vector{Float64}   # standard X-13 Easter[w] regressor: fraction of the w-day pre-Easter window falling in each period
custom_holiday_regressor(holiday_dates, periods) -> Vector{Float64}  # count of holiday_dates falling in each period -- the exact mechanism proven by the Diwali test

nse_moveable_holiday_dates(name, years) -> Vector{Date}   # not exported; lookup helper for INDIA_NSE's own table, errors on untabulated years
```

`periods` throughout is `AbstractVector{<:Tuple{Date,Date}}` — explicit
`(from, to)` inclusive ranges, supplied by the caller (eventually W.2,
which knows the series' actual period boundaries and the forecast
horizon it needs covered — W.0 does not infer date ranges itself,
consistent with the two practical requirements already confirmed
against the real binary: regressor data must be supplied for the full
forecast horizon, and that's a W.2-level responsibility, not W.0's).

## Test plan (`test/test_calendars.jl`)

1. `easter_date`/`good_friday` reproduce the 3 cross-checked real years
   above exactly (2024, 2025, 2026).
2. `INDIA_NSE` flags each fixed-date holiday (Republic Day,
   Independence Day, Gandhi Jayanti) and Good Friday as a holiday, for
   at least 2 different years, and does NOT flag an arbitrary ordinary
   business day.
3. `INDIA_NSE` flags each real 2024-2026 moveable-feast date sourced
   above as a holiday.
4. `BusinessDays.isbday(INDIA_NSE, ::Date)` is `false` on weekends
   regardless of the holiday table (sanity check on the
   HolidayCalendar/isbday contract, not just `isholiday` in isolation).
5. `nse_moveable_holiday_dates` errors clearly for a year outside
   2024-2026 (the loud-failure-over-silent-gap requirement), and
   returns the right dates, in order, for a name/year combination that
   is tabulated.
6. `trading_day_regressors` on a hand-countable single-month period
   against a trivial "every weekday is a business day, no holidays"
   calendar reproduces the exact weekday-count arithmetic by hand.
7. `trading_day_regressors` against `INDIA_NSE` over a period
   containing a known NSE holiday shows that weekday's count reduced by
   exactly one relative to the holiday-free calculation — proving the
   holiday table actually suppresses a business day, not just that the
   function runs.
8. `easter_regressor` on a period wholly before the pre-Easter window,
   wholly after it, and exactly straddling it (split across two
   periods) sums to 1.0 across the two straddling periods and is 0.0
   for the disjoint period — the defining property of the regressor,
   not just a spot value.
9. `custom_holiday_regressor` reproduces the Diwali proof's *shape*
   (one holiday per period, all periods) against a small synthetic
   date set — a structural echo of `verification/diwali_regressor_proof`
   without re-invoking the real binary (that remains W.3's own
   integration-level test, out of scope here).

## Known follow-on for W.2 (not this task, noted for continuity)

- Combining a RegARIMA model with multiplicative X-11 needs an explicit
  `transform { function = log }` spec (already confirmed against the
  real binary) — W.2's concern, not W.0's; noted here only so it isn't
  lost between handoffs.
- User-defined regressor data must cover the RegARIMA forecast horizon
  (default 1 year past the series end) — W.0's `periods` argument
  already supports this (the caller just needs to pass periods that
  extend that far); W.2 is responsible for actually doing so.

```@meta
CurrentModule = SeasonalAdjustment
```

# API Reference

## The idiomatic entry point

```@docs
x13
X13Result
static
```

## Spec generation

```@docs
X13Spec
render
validate!
write_spec
generate_specs
```

## Subprocess invocation

```@docs
X13RunResult
run_x13
run_x13_batch
```

## Output-table parsing

```@docs
parse_table
parse_output
parse_udg
```

## Binary artifact management

```@docs
x13_binary_path
x13_binary_available
```

## Calendars

```@docs
Calendar
TableCalendar
INDIA_NSE
isbusinessday
isholiday
isweekend
adjust
advance
businessdaysbetween
holidaylist
easter_date
```

## Regressor generation

```@docs
trading_day_regressors
easter_regressor
custom_holiday_regressor
```

```@meta
CurrentModule = SeasonalAdjustment
```

# Output and Tables

One paragraph: [`X13Result`](@ref) carries the four core series
directly as fields. This page is for everything else X-13 can write.

## Where is the adjusted series?

Four fields, mapped to X-11/SEATS table names once:

| Field | X-11 | SEATS | What it is |
|---|---|---|---|
| `seasonally_adjusted` | D11 | S11 | the series with the seasonal pattern removed |
| `trend` | D12 | S12 | the smooth underlying trend-cycle |
| `seasonal_factors` | D10 | S10 | the estimated seasonal pattern itself |
| `irregular` | D13 | S13 | what's left over |

`x13()` always fetches all four (plus `residuals` from the regARIMA
model), whether you asked for them or not — that quartet is the
contract an `X13Result` promises.

## How do I get a table that was not saved?

```julia
res = x13(dataset("airline"))
d8 = series(res, [:d8])[:d8]
```

[`series`](@ref) re-runs automatically if the requested table wasn't in
the original `save` list, and logs an `@info` when it does so you know
a second subprocess call happened:

```
[ Info: series(): re-running to save additional table(s)
│   missing_tables = [:d8]
```

## How do I get several extra tables at once?

```julia
tables = series(res, [:d8, :hol, :rsd])
```

Pass a vector. `series` unions everything missing into **one** re-run,
not one re-run per table — asking for three unsaved tables costs the
same single subprocess call as asking for one.

## How do I find the right table name?

`_KNOWN_TABLES` (checked internally by [`validate!`](@ref)) covers the
full 281-entry saveable-table catalogue. `series(r, [:bad])` fails
immediately, before any subprocess runs, naming which symbols it
doesn't recognise.

## How do I read a table file directly?

```julia
parse_table("myrun.d11"; period = 12)
parse_output(result, [:d10, :d11]; period = 12)
```

[`parse_table`](@ref) reads one file into `[(date, value), ...]` pairs.
[`parse_output`](@ref) does several at once against an
[`X13RunResult`](@ref) — this is what `series` calls internally once it
knows every requested table is already saved.

!!! warning "Gotcha — the save keyword is not the table number"
    The holiday-factor series is X-11 table **A7**, but you request it
    as `regression.holiday`, not `a7`, and it lands on disk as `.hol`.
    `save = (a7)` silently does nothing useful — `a7` isn't a
    recognised save keyword at all, and [`validate!`](@ref) rejects it
    before a subprocess is even spawned. Only `a10` and `a13` happen to
    be spelled as their own table numbers; treat that as the exception,
    not the pattern.

---

**See also:** [Specifications](01-specifications.md) for building the
spec that determines what gets saved in the first place.
[`series`](@ref)/[`parse_table`](@ref)/[`parse_output`](@ref) in the
[API Reference](../api.md) for full signatures.

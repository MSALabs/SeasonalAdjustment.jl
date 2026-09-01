```@meta
CurrentModule = SeasonalAdjustment
```

# Specifications

One paragraph: [`x13`](@ref) covers most work. This page is for the rest
— when you need to see, check, or hand-build the specification `x13()`
builds for you internally.

## When do I need more than `x13()`?

Three tiers, in the order to reach for them:

1. **`x13()`'s own keywords** — `automdl`, `outlier`, `transform`,
   `seasonal_order`, and the rest. Covers most cases; see
   [Getting Started](../getting-started/04-beyond-defaults.md).
2. **`spec_args`** — any spec block with no dedicated keyword
   (`forecast`, `slidingspans`, `history`, `pickmdl`, ...), passed as raw
   `"block.argument" => "value"` pairs.
3. **Building an [`X13Spec`](@ref) directly** — when you want to inspect
   or modify the spec before running it, rather than let `x13()` build
   and run it in one step.

## How do I set a spec argument with no keyword?

```julia
res = x13(dataset("airline");
          spec_args = Dict("forecast.maxlead" => "12"))
```

`spec_args` renders each entry verbatim into the named block, splitting
on the first `.` for the block name. A key naming a block the struct
*already* renders through a typed field (`transform`, `x11`, `automdl`,
`regression`, `estimate`, `series`, `arima`, `seats`, `outlier`) throws
rather than creating two sources of truth for one block — set the typed
field instead.

## How do I see what specification was generated?

```julia
spec = X13Spec(dataset("airline").value;
               start = (1949, 1), automdl = true, transform = :auto)
print(render(spec))
```

[`render`](@ref) returns the `.spc` text `x13()` would send to the
binary, without running anything.

## How do I check a specification before running it?

```julia
spec = X13Spec(y; automdl = true, seasonal_order = (0, 1, 1, 12))
validate!(spec)
```

```
ERROR: ArgumentError: an explicit ARIMA model (arima_model/seasonal_order)
and automdl (automdl/maxorder/maxdiff) can't both be given -- confirmed
directly against the real binary's own error: "Cannot specify arima and
automdl spec in the same input file."
```

[`validate!`](@ref) checks every real requirement confirmed directly
against the binary — minimum series length, the ARIMA-vs-`automdl`
conflict shown above, the `transform=:log`/multiplicative-mode
interaction, regressor forecast-horizon coverage — natively, in
microseconds, before a subprocess is ever spawned. `x13()` calls it for
you; call it yourself when building a spec by hand, so a bad
specification fails immediately rather than after a real binary
round-trip.

**What it cannot check:** the *content* of `spec_args` or
`regression_variables` passthrough. Those are rendered verbatim; a typo
in `"td"` spelled `"tdd"` is caught by the binary, not by `validate!`.

## How do I write a `.spc` file?

```julia
path = write_spec(spec, "myspec.spc")
```

[`write_spec`](@ref) validates, renders, and writes in one call — the
file `run_x13`(@ref) then runs directly.

## How do I change one setting on an existing spec?

```julia
spec2 = X13Spec(spec; outlier = true)
```

`X13Spec`'s copy constructor takes an existing spec plus keyword
overrides, leaving everything else unchanged. This is what
[`static`](@ref) (see [Reproducibility](08-reproducibility.md)) and
[`update`](@ref) both build on internally.

!!! warning "Gotcha — a named field wins over `spec_args` silently for the same setting spelled two ways"
    If a setting is reachable both through a typed field and through
    `spec_args` under a different block name that happens to render the
    same underlying X-13 argument, the typed field's own render call
    runs and `spec_args` cannot un-set it. Prefer the typed field
    whenever one exists; reach for `spec_args` only for what has none.

---

**See also:** [Output and Tables](02-output-tables.md) for what comes
back once a spec has run. [`X13Spec`](@ref)/[`render`](@ref)/
[`validate!`](@ref) in the [API Reference](../api.md) for the full
keyword list.

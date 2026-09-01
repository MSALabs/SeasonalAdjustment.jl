```@meta
CurrentModule = SeasonalAdjustment
```

# Many Series at Once

One paragraph: [`generate_specs`](@ref) and [`run_x13_batch`](@ref)
turn a loop over series into two calls, one for building specs and one
for running them, both parallel by default.

## How do I build specifications for a panel?

```julia
names = ["airline", "appliance"]
series_list = [dataset(n).value for n in names]
options_list = [(; automdl = true, outlier = true, transform = :auto) for _ in names]
specs = generate_specs(series_list, options_list)
```

`series_list` and `options_list` must be the same length — one
`NamedTuple` of `x13()`-style keywords per series. `generate_specs`
builds every [`X13Spec`](@ref) (using threads when there are enough
series to make it worthwhile), but does not run anything yet.

## How do I run them?

```julia
paths = [write_spec(specs[i], joinpath(mktempdir(), "run_$i.spc")) for i in eachindex(specs)]
results = run_x13_batch(paths)
```

[`run_x13_batch`](@ref) runs every path concurrently by default — one
`@async` task per subprocess, joined with `@sync`, not a worker-pool.
That design was benchmarked directly against the alternative and found
faster for X-13's own real ~10ms-per-run cost, where worker-pool
coordination overhead would exceed the work being parallelised.

!!! warning "Gotcha — `run_x13_batch` never produces `.udg`"
    `run_x13_batch` has no `udg` keyword, so it never passes the `-S`
    flag — meaning none of the diagnostics functions in
    [Accessing Diagnostics](10-diagnostics-access.md) have anything to
    read after a batch run through this function alone. For a panel
    where you also want diagnostics, call [`run_x13`](@ref) directly
    per spec with `udg = true`, as the next section does — the same
    `@sync`/`@async` pattern works identically.

## How do I handle one series failing?

```julia
results = run_x13_batch(paths)
for (name, r) in zip(names, results)
    r.success || @warn "adjustment failed" series=name errors=r.errors
end
```

A failure in one run does not raise or stop the others — `run_x13_batch`
always returns a full-length `Vector{X13RunResult}`, one entry per
input path, each with its own `success`/`errors`. Check individually
rather than wrapping the whole call in a `try`.

## How do I collect diagnostics across a panel?

This is the section with no single function behind it — the worked
loop, using `run_x13` directly (with `udg = true`) so every diagnostics
accessor below has something to read:

```julia
results = Vector{X13RunResult}(undef, length(specs))
@sync for i in eachindex(specs)
    @async results[i] = run_x13(paths[i]; udg = true)
end

rows = map(zip(names, results)) do (name, result)
    udgd = parse_udg(joinpath(result.dir, "$(result.basename).udg"))
    m = mstats(udgd)
    q = qs(udgd)
    (series = name,
     transform = transformfunction(udgd),
     model = arima_model(udgd),
     q = m === nothing ? missing : m.q,
     m7 = m === nothing ? missing : m.m7,
     qs_p_adjusted = q.sa.pvalue,
     n_outliers = outlier_counts(udgd).total,
     converged = result.success)
end
```

Real output, on `airline` and `appliance`:

```
(series = "airline", transform = :log, model = "(0 1 1)(0 1 1)", q = 0.26, m7 = 0.202, qs_p_adjusted = 1.0, n_outliers = 0, converged = true)
(series = "appliance", transform = :log, model = "(3 0 1)(0 1 1)", q = 0.28, m7 = 0.176, qs_p_adjusted = 1.0, n_outliers = 0, converged = true)
```

Collect `rows` into a `DataFrame` (`DataFrame(rows)`) or leave it as
the `Vector{NamedTuple}` above — both are Tables.jl-compatible. This is
the shape a production run at any real scale actually wants: one row
per series, the headline diagnostics as columns, nothing that needs a
plot to read.

---

**See also:** [Accessing Diagnostics](10-diagnostics-access.md) for
what each column in the worked loop above means and how to read it for
one series at a time. [`generate_specs`](@ref)/[`run_x13_batch`](@ref)
in the [API Reference](../api.md).

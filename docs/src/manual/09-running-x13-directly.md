```@meta
CurrentModule = SeasonalAdjustment
```

# Running X-13 Directly

One paragraph: `x13()` builds a spec, runs it, and parses the result in
one call. This page is for the layer underneath, when you've already
built an [`X13Spec`](@ref) by hand (see [Specifications](01-specifications.md))
and want to run it yourself.

## How do I run a spec I built by hand?

```julia
path = write_spec(spec, "myrun.spc")
result = run_x13(path)
```

[`run_x13`](@ref) copies the spec into a fresh scratch directory, runs
the binary against it, and returns a typed [`X13RunResult`](@ref) —
`success`, `warnings`, and `errors` already extracted from the
binary's own stdout, not left for you to grep. Confirmed directly that
the process exit code alone cannot tell success from failure — always
check `result.success`.

## Where do the output files go?

A fresh temporary directory per call, by default — `result.dir`. The
binary's own basename (derived from the spec filename) is
`result.basename`; every output file is
`joinpath(result.dir, "$(result.basename).<ext>")`.

## How do I keep the directory for inspection?

```julia
mydir = mktempdir(; cleanup = false)
path = write_spec(spec, joinpath(mydir, "myrun.spc"))
result = run_x13(path)
```

`run_x13` itself does not delete anything — Julia's own `mktempdir`
cleanup (if you used the default, cleaned-up form) is what would remove
it. Pass `cleanup = false` explicitly, as above, to keep the directory
around after the process ends.

## How do I see the binary's warnings?

```julia
result = run_x13(path)
result.warnings   # Vector{String}, extracted from stdout
result.errors     # Vector{String}, empty when result.success
```

A run can succeed (`result.success == true`) and still carry warnings —
check both, not just `success`, when a result looks unexpected.

## How do I open the full HTML report?

```julia
open_output(result)
```

[`open_output`](@ref) opens the binary's own HTML output in your
default browser — the exhaustive detail X-13 itself produces, useful
when something needs investigating beyond what any typed accessor
surfaces.

## How do I check the binary is working?

```julia
x13_binary_available()   # -> Bool, never throws
x13_binary_path()        # -> String, the resolved executable path
```

[`x13_binary_available`](@ref) resolves the artifact for your platform
and actually invokes it, returning `false` rather than throwing — safe
to use as a guard in scripts and test suites. See
[Getting Started chapter 1](../getting-started/01-installation.md) for
what a `false` result means and how to fix it.

---

**See also:** [Specifications](01-specifications.md) for building the
spec this page runs. [`run_x13`](@ref)/[`X13RunResult`](@ref)/
[`open_output`](@ref) in the [API Reference](../api.md).

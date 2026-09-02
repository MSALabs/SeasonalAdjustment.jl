```@meta
CurrentModule = SeasonalAdjustment
```

# Running X-13 Directly

One paragraph: `x13()` builds a spec, runs it, and parses the result
in one call. This page is for the layer underneath, for occasions when
an [`X13Spec`](@ref) has already been built by hand (see
[Specifications](01-specifications.md)) and one wishes to run it
oneself.

## How do I run a spec I built by hand?

```julia
path = write_spec(spec, "myrun.spc")
result = run_x13(path)
```

[`run_x13`](@ref) copies the spec into a fresh scratch directory, runs
the binary against it, and returns a typed [`X13RunResult`](@ref) —
`success`, `warnings`, and `errors` already extracted from the
binary's own stdout, rather than left for one to grep out oneself.
Confirmed directly that the process exit code alone cannot tell
success from failure — `result.success` ought always be checked.

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
cleanup (where the default, cleaned-up form was used) is what would
remove it. Pass `cleanup = false` explicitly, as shown above, to keep
the directory around once the process has ended.

## How do I see the binary's warnings?

```julia
result = run_x13(path)
result.warnings   # Vector{String}, extracted from stdout
result.errors     # Vector{String}, empty when result.success
```

A run may succeed (`result.success == true`) and still carry
warnings — both are worth checking, not `success` alone, whenever a
result looks other than expected.

## How do I open the full HTML report?

```julia
open_output(result)
```

[`open_output`](@ref) opens the binary's own HTML output in the
default browser — the exhaustive detail X-13 itself produces, useful
where something needs investigating beyond what any typed accessor
surfaces.

## How do I check the binary is working?

```julia
x13_binary_available()   # -> Bool, never throws
x13_binary_path()        # -> String, the resolved executable path
```

[`x13_binary_available`](@ref) resolves the artifact for the current
platform and thereafter actually invokes it, returning `false` rather
than throwing — safe to use as a guard in scripts and test suites. See
[Getting Started chapter 1](../getting-started/01-installation.md) for
what a `false` result means, and how it may be fixed.

---

**See also:** [Specifications](01-specifications.md) for building the
spec this page runs. [`run_x13`](@ref)/[`X13RunResult`](@ref)/
[`open_output`](@ref) in the [API Reference](../api.md).

```@meta
CurrentModule = SeasonalAdjustment
```

# 1. Installation and First Check

!!! note "About the examples in this guide"
    Every example in this guide was actually run, not just written and
    assumed correct — the pure-Julia ones (calendars, spec construction,
    bundled datasets) are live `jldoctest` blocks Documenter re-verifies
    on every docs build; the ones that call the real binary were
    confirmed directly against it during development but are shown as
    plain code blocks rather than live doctests, since running the
    actual `x13prebuilt` binary isn't something every environment that
    might build these docs can do. Every concrete number quoted in this
    guide was independently re-verified against a real run, not copied
    from a draft without checking.

## Installing

!!! warning "Alpha release"
    Neither this package nor `TSAnalytics.jl` is in Julia's General
    registry yet, so both must be installed together in a **single**
    call:

    ```julia
    using Pkg
    Pkg.add([
        PackageSpec(url = "https://github.com/MSALabs/TSAnalytics.jl",
                    rev = "v0.1.0-alpha.1"),
        PackageSpec(url = "https://github.com/MSALabs/SeasonalAdjustment.jl",
                    rev = "v0.1.0-alpha.1"),
    ])
    ```

    Two separate `Pkg.add` calls **fail in either order** — whichever
    runs first triggers a dependency-resolution pass that needs the
    other package already present. Both must go in one call, exactly as
    shown.

    After registration this becomes the ordinary single-package
    `Pkg.add("SeasonalAdjustment")`.

## Nothing else to install

Whichever way you installed it, **X-13 itself came with the package.**
There is no second download, no `PATH` entry, no system-wide install.

This is worth pausing on, because it differs from every other way of
reaching X-13ARIMA-SEATS. In R you install the `seasonal` package and
then separately obtain the X-13 binary, historically through the
companion `x13binary` package. In Python, `statsmodels.tsa.x13` expects
you to download the binary from the Census Bureau yourself and either
put it on your `PATH` or pass its location to every call.

SeasonalAdjustment.jl ships the binary as a Julia artifact, resolved for
your platform when the package is installed. Linux, macOS and Windows
are all covered. Nothing is placed on your `PATH`, nothing is installed
system-wide, and different Julia environments can hold different
versions without interfering.

## Checking it works

```julia
using SeasonalAdjustment

x13_binary_available()
```

```
true
```

[`x13_binary_available`](@ref) resolves the binary for your platform and
then actually invokes it. It returns `false` rather than throwing, so
it's safe to use as a guard in scripts and test suites.

If you want the path itself, [`x13_binary_path`](@ref) resolves it (the
exact value is platform-dependent, so not reproduced here) — the path
differs by platform in a way that's worth knowing about only if
something goes wrong. On Linux the executable sits at the artifact root.
On Windows it's inside an `x13ashtml/` subdirectory. On macOS it's at
`x13ashtml/bin/x13ashtml` and is dynamically linked against three
libraries in a sibling `lib/` directory, which [`x13_binary_path`](@ref)
checks for and reports clearly if they're missing.

## If the check fails

`x13_binary_available()` returning `false` means one of two things.

The artifact didn't resolve for your platform. This happens on
platforms outside the prebuilt set, most often unusual Linux
architectures. There is no workaround inside the package; you'd need to
build X-13 from the Census Bureau's Fortran source and point the
package at it through [`run_x13`](@ref)'s `binary_path` keyword.

Or the artifact resolved but the binary wouldn't run. On macOS this is
usually the missing-library case above, and the error message names the
specific file. Clearing the artifact cache and reinstalling fixes most
instances.

## What you have just installed

The binary is `x13ashtml`, built from the U.S. Census Bureau's own
source, taken from the same prebuilt distribution R's `seasonal`
package uses. It's the program national statistical offices run in
production.

This matters for a reason that will come up repeatedly.
SeasonalAdjustment.jl does not reimplement seasonal adjustment. It
builds a specification file, runs the Census binary, and parses what
comes back into Julia types. When you compare results against a
statistical office's published figures, you're comparing against the
same computation, not an independent one that happens to agree.

## What comes next

Chapter 2 adjusts a series. Chapter 3 is about deciding whether the
result was any good, which is the part most tutorials skip. Chapter 4
covers the three settings you'll actually reach for. Chapter 5 points
onward.

If you want the concepts behind any of it, the *Introduction to
Seasonal Adjustment* section is written to be read on its own. If you
want a function's full signature, keywords and defaults, go straight to
the API Reference; this guide deliberately does not repeat them.

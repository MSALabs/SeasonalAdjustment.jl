```@meta
CurrentModule = SeasonalAdjustment
```

# 1. Installation and First Check

!!! note "About the examples in this guide"
    Every example in this guide was actually run, not merely written and
    assumed correct — the pure-Julia ones (calendars, spec construction,
    bundled datasets) are live `jldoctest` blocks Documenter re-verifies
    on every docs build; those that call the real binary were confirmed
    directly against it during development but are shown as plain code
    blocks rather than live doctests, since running the actual
    `x13prebuilt` binary is not something every environment building
    these docs can do. Every concrete number quoted in this guide was
    independently re-verified against a real run, kindly note, not
    carried over from a draft without checking.

## Installing

!!! warning "Alpha release"
    Neither this package nor `TSAnalytics.jl` is on Julia's General
    registry as yet, so both must be installed together, in a
    **single** call:

    ```julia
    using Pkg
    Pkg.add([
        PackageSpec(url = "https://github.com/MSALabs/TSAnalytics.jl",
                    rev = "v0.1.0-alpha.1"),
        PackageSpec(url = "https://github.com/MSALabs/SeasonalAdjustment.jl",
                    rev = "v0.1.0-alpha.1"),
    ])
    ```

    Two separate `Pkg.add` calls will **fail in either order** —
    whichever runs first triggers a dependency-resolution pass that
    needs the other package already present. Both must go in one call,
    exactly as shown above.

    Once registration is complete, this reduces to the ordinary
    single-package `Pkg.add("SeasonalAdjustment")`.

## Nothing else to install

Whichever way it was installed, **X-13 itself came along with the
package.** There is no second download, no `PATH` entry to set, no
system-wide install required.

This is worth pausing on, since it differs from most other ways of
reaching X-13ARIMA-SEATS, which typically expect the binary to be
obtained and placed separately — put on the `PATH`, or its location
passed to every call by hand.

SeasonalAdjustment.jl ships the binary as a Julia artifact, resolved
for the platform in use at the time of install. Linux, macOS and
Windows are all covered. Nothing is placed on the `PATH`, nothing is
installed system-wide, and different Julia environments may hold
different versions without interfering with one another.

## Checking it works

```julia
using SeasonalAdjustment

x13_binary_available()
```

```
true
```

[`x13_binary_available`](@ref) resolves the binary for the current
platform and thereafter actually invokes it. It returns `false` rather
than throwing, so it may safely be used as a guard in scripts and test
suites.

Should the path itself be wanted, [`x13_binary_path`](@ref) resolves it
(the exact value is platform-dependent, so is not reproduced here) —
the path differs by platform in a way worth knowing only should
something go wrong. On Linux the executable sits at the artifact root.
On Windows it is inside an `x13ashtml/` subdirectory. On macOS it is at
`x13ashtml/bin/x13ashtml` and is dynamically linked against three
libraries in a sibling `lib/` directory, which
[`x13_binary_path`](@ref) checks for and reports clearly should any be
missing.

## If the check fails

`x13_binary_available()` returning `false` means one of two things.

Either the artifact did not resolve for the platform in question. This
happens on platforms outside the prebuilt set, most often unusual
Linux architectures. There is no workaround within the package for
this; X-13 would need to be built from the Census Bureau's own Fortran
source, and the package pointed at it through [`run_x13`](@ref)'s
`binary_path` keyword.

Or the artifact resolved but the binary would not run. On macOS this is
usually the missing-library case noted above, and the error message
names the specific file concerned. Clearing the artifact cache and
reinstalling resolves most such instances.

## What has just been installed

The binary is `x13ashtml`, built from the U.S. Census Bureau's own
source. It is the very program national statistical offices run in
production.

This matters for a reason that will recur throughout. SeasonalAdjustment.jl
does not reimplement seasonal adjustment. It builds a specification
file, runs the Census binary, and parses what comes back into Julia
types. When results are compared against a statistical office's own
published figures, one is comparing against the same computation, not
an independent one that merely happens to agree.

## What comes next

Chapter 2 adjusts a series. Chapter 3 concerns deciding whether the
result was any good, which is the part most tutorials skip over.
Chapter 4 covers the three settings one will actually reach for.
Chapter 5 points onward.

For the concepts behind any of this, the *Introduction to Seasonal
Adjustment* section is written to be read on its own. For a function's
full signature, keywords and defaults, go straight to the API
Reference; this guide deliberately does not repeat them.

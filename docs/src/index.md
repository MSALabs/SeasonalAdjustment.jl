```@meta
CurrentModule = SeasonalAdjustment
```

# SeasonalAdjustment.jl

## What is SeasonalAdjustment.jl?

[SeasonalAdjustment.jl](https://github.com/MSALabs/SeasonalAdjustment.jl)
is a Julia interface to
[X-13ARIMA-SEATS](https://www.census.gov/data/software/x13as.html), the
seasonal adjustment program developed and maintained by the U.S. Census
Bureau.

Monthly and quarterly economic data carry a repeating calendar pattern.
Retail sales rise every December; industrial output falls around
Diwali. Seasonal adjustment removes that pattern so that adjacent
periods may be compared meaningfully, which is what makes "output rose
this month" a genuine statement rather than a mere restatement of the
calendar.

```julia
julia> using SeasonalAdjustment, Plots

julia> res = x13(dataset("airline"))
X13Result
  ARIMA model:  (0 0 0)
  Transform:    none
  N:            144
  AIC:          0.205784733802868E+04
  BIC:          0.206081715132825E+04
  Q:            0.27
  Outliers:     0

julia> plot(res)
```

![Original and seasonally adjusted](assets/gs02-original-vs-adjusted.png)

The package builds X-13's specification file, runs the Census binary,
and parses what comes back into Julia types. **It does not reimplement
seasonal adjustment.** Results obtained through this package are the
same computation a statistical office's own published figures rest on,
not an independent one that merely happens to agree with it.

!!! tip "No separate X-13 download required"
    The binary ships with this package itself, as a Julia artifact,
    resolved automatically for Linux, macOS and Windows on install.
    There is nothing to download separately from the Census Bureau and
    nothing to place on your `PATH`. This may be checked directly with
    [`x13_binary_available`](@ref).

**Status:** the `x13prebuilt` wrapper (X-11, RegARIMA, SEATS,
diagnostics, plotting, bundled datasets) is complete, including a full
twenty-chapter *Introduction to Seasonal Adjustment*. A from-scratch
native Julia engine is planned but has not yet been started.

!!! warning "Alpha release"
    Neither this package nor `TSAnalytics.jl` is on the General
    registry as yet, so both must kindly be installed together, in a
    single call:

    ```julia
    using Pkg
    Pkg.add([
        PackageSpec(url = "https://github.com/MSALabs/TSAnalytics.jl",
                    rev = "v0.1.0-alpha.1"),
        PackageSpec(url = "https://github.com/MSALabs/SeasonalAdjustment.jl",
                    rev = "v0.1.0-alpha.1"),
    ])
    ```

    Two separate `Pkg.add` calls will fail, in either order. Once
    registration is complete, this reduces to the usual
    `Pkg.add("SeasonalAdjustment")`.

## Resources for getting started

A few paths are available, depending on where one is starting from:

- Read the
  [Installation and First Check](getting-started/01-installation.md)
  chapter, and thereafter work through
  [Your First Adjustment](getting-started/02-first-adjustment.md). This
  takes about an hour in all, and ends with a properly checked
  adjustment.
- Those new to seasonal adjustment as a subject are advised to read
  [Why Adjust?](introduction/01-why-adjust.md) first. The *Introduction*
  has been written to be readable without Julia in front of one at all.
- Coming from another seasonal-adjustment tool? The Manual's own
  [translation page](manual/04-coming-from-r-python.md) maps the
  common workflows across directly.
- Already know precisely what is wanted, and need only the one worked
  call for it? The [Manual](manual/01-specifications.md) is organised
  around "how do I ..." tasks, and is not a walkthrough.

!!! tip "Help us improve"
    Should an unclear error message, confusing behaviour, or a gap in
    the documentation be encountered — even where the problem has
    already been solved on one's own — kindly do open an issue on the
    [issue tracker](https://github.com/MSALabs/SeasonalAdjustment.jl/issues).
    Feedback of this kind is the most useful signal we receive.

## How the documentation is structured

A high-level view of the layout should help in knowing where to look.

- **[Getting Started](getting-started/01-installation.md)** is a guided
  path from installation through to a checked adjustment, using one
  dataset and one thread throughout. Begin here if the aim is simply to
  use the package.

- **[Manual](manual/01-specifications.md)** answers "how do I ...?" for
  a specific task at hand -- specs, output tables, batch runs,
  calendars, plotting, migrating from another tool -- one worked call
  per page, not a walkthrough. Begin here once the task itself is
  already known.

- **[Introduction to Seasonal Adjustment](introduction/01-why-adjust.md)**
  explains the subject proper: what X-11 does across its three passes,
  why a forecasting model sits ahead of a smoothing procedure, what
  SEATS does differently, and how each diagnostic is to be read. Begin
  here if the aim is to understand what is actually being run.

- **[API Reference](api.md)** is the complete listing of functions,
  keywords, defaults and known gaps, together with the underlying
  mathematics where this helps. Consult this when precisely what a
  given argument accepts needs to be known. The other two sections
  deliberately do not repeat it.

## Citing

Where this package is used in published work, kindly cite **both** the
package and X-13ARIMA-SEATS itself. The statistical results are, after
all, the Census Bureau's own program at work; this package is merely an
interface to it.

```bibtex
@software{SeasonalAdjustmentJL,
    author  = {{XKDR Forum}},
    title   = {{SeasonalAdjustment.jl}: Seasonal adjustment in Julia with X-13ARIMA-SEATS},
    year    = {2026},
    url     = {https://github.com/MSALabs/SeasonalAdjustment.jl}
}

@manual{X13ARIMASEATS,
    author       = {{U.S. Census Bureau}},
    title        = {X-13ARIMA-SEATS Reference Manual},
    organization = {U.S. Census Bureau},
    address      = {Washington, DC},
    url          = {https://www.census.gov/data/software/x13as.html}
}
```

!!! note
    The repository is to move to the [xKDR](https://github.com/xKDR)
    organisation in due course. The URL above is current as of this
    release; the citation author is unaffected by the move.

Work that leans on the methodology rather than on the software as such
should also cite Findley, Monsell, Bell, Otto and Chen (1998), for the
regARIMA and diagnostic apparatus. The
[Further Reading](introduction/B-further-reading.md) appendix carries
the full list.

## About XKDR Forum

SeasonalAdjustment.jl is developed at [XKDR Forum](https://xkdr.org) —
Cross Disciplinary Knowledge Data Research — a non-profit research
organisation based in Mumbai, India, whose work spans economics, law,
public administration, engineering and statistics. Building open tools
for working with Indian data forms part of its applied statistics
programme, and this package is one such tool.

That origin shapes the package in a manner worth stating plainly.
X-13's built-in moving-holiday regressors are Easter, Labor Day and
Thanksgiving — three holidays specific to the United States — and the
wider literature has largely followed suit. Holidays that move between
months on a lunar or luni-solar calendar, Diwali very much among them,
present a structurally different problem, and one poorly served thus
far. The calendar layer in this package, together with the
[Moving Holidays](introduction/11-moving-holidays.md) chapter of the
*Introduction*, exists precisely on account of this gap.

XKDR's other open-source work may be found at
[github.com/xKDR](https://github.com/xKDR).

## License

SeasonalAdjustment.jl is licensed under the
[MIT licence](https://github.com/MSALabs/SeasonalAdjustment.jl/blob/main/LICENSE).

The bundled X-13ARIMA-SEATS binary is **not** covered under that
licence. It is distributed under the U.S. Census Bureau's own
public-domain and royalty-free terms; kindly consult the
[`x13prebuilt`](https://github.com/x13org/x13prebuilt) repository for
the exact wording thereof.

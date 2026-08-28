# SeasonalAdjustment.jl

[![docs latest](https://img.shields.io/badge/docs-dev-blue.svg)](https://msalabs.github.io/SeasonalAdjustment.jl/dev/)
[![CI](https://github.com/MSALabs/SeasonalAdjustment.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/MSALabs/SeasonalAdjustment.jl/actions/workflows/CI.yml)

Official-statistics-grade seasonal adjustment for Julia — X-11,
RegARIMA, and SEATS — built on the same trusted, freely-redistributable
Census Bureau binary ([`x13prebuilt`](https://github.com/x13org/x13prebuilt))
that R's `seasonal` and Python's `statsmodels.tsa.x13` both wrap
internally, with **India- and other-market-aware calendar effects**
(Diwali, Holi, and beyond) fed into RegARIMA via `x13prebuilt`'s own
user-defined-regressor mechanism — something neither R's nor Python's
default setup provides out of the box.

Part of the [TSAnalytics.jl](https://github.com/MSALabs/TSAnalytics.jl)
project.

## Status

Part 1 (the `x13prebuilt` wrapper, W.0-W.4) is complete. Part 2 (a
from-scratch native Julia engine) hasn't started yet. See
`development-sequence.md` for the full roadmap and current
task-by-task status.

## Design

This package deliberately departs from TSAnalytics.jl's own
"reference, never port" principle for its core functionality — it wraps
the actual Census Bureau X-13ARIMA-SEATS binary directly, rather than
reimplementing X-11/RegARIMA/SEATS from scratch, since both R and
Python already trust this exact binary for the hardest parts of this
problem (SEATS's spectral factorization especially). A from-scratch
native Julia engine remains a planned future track (`development-sequence.md`,
Part 2), not abandoned, just deliberately sequenced behind a working
wrapper.

## Installation

```julia
] add https://github.com/MSALabs/SeasonalAdjustment.jl
```

## Quick example

```julia
using SeasonalAdjustment

result = x13(airline_passengers; seasonal_order=(0,1,1,12))
result.seasonally_adjusted
result.trend
result.seasonal_factors
```

## License

MIT for this package's own code. The bundled `x13prebuilt` binary is
distributed under the U.S. Census Bureau's own public-domain /
royalty-free license (see `x13prebuilt`'s own repository for the exact
terms) — not this package's MIT license.

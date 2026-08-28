```@meta
CurrentModule = SeasonalAdjustment
```

# SeasonalAdjustment.jl

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

**Status:** Part 1 (the `x13prebuilt` wrapper, tasks W.0-W.4) is
complete. See
[`development-sequence.md`](https://github.com/MSALabs/SeasonalAdjustment.jl/blob/main/development-sequence.md)
in the repository root for the full staged roadmap, including Part 2
(a from-scratch native Julia engine, not yet started).

- New to the package? Start with [Getting Started](getting_started.md).
- Looking for a specific function? See the [API Reference](api.md).

## Design principles

0. **Wrap the real binary, don't reimplement it — the one deliberate
   exception to the TSAnalytics.jl family's usual "reference, never
   port" rule.** Rather than reimplementing X-11/RegARIMA/SEATS from
   scratch, this package's core (Part 1) wraps `x13prebuilt` directly —
   the exact same binary R's and Python's own wrapper packages call
   internally. Both ecosystems already trust this binary for the
   hardest part of the whole problem (SEATS's spectral factorization
   especially); wrapping it directly gets correct, production-grade
   output immediately rather than spending months re-deriving the
   hardest mathematics in the field before shipping anything. A
   from-scratch native Julia engine remains a real, planned track
   (Part 2), deliberately sequenced behind a working wrapper, not
   abandoned.
1. **A genuine superset of R's `seas()` and Python's
   `x13_arima_analysis()`, not just a naming exercise.** R exposes the
   entire X-13 spec grammar dynamically via `...`; Python exposes only
   a curated, typed subset. [`x13`](@ref)'s own keyword arguments
   combine both: R-style raw passthrough (`regression_variables`,
   `arima_model`) for anything the curated fields don't cover, layered
   with Python-style curated ergonomics (`maxorder`, `maxdiff`,
   `trading`, `outlier`, `seasonal_order`, ... — matching
   `statsmodels.tsa.x13.x13_arima_analysis`'s own real parameter
   names) for discoverability.
2. **Validated before a subprocess round-trip is ever spent.**
   [`validate!`](@ref) checks every real requirement this project
   confirmed directly against the actual binary (minimum series
   length, regressor forecast-horizon coverage, the
   `transform=:log`/multiplicative-mode interaction, the
   ARIMA-vs-`automdl` conflict) natively, in microseconds, before
   [`X13Spec`](@ref) is ever rendered and run — neither R's nor
   Python's wrapper does this validation at all.
3. **Typed results, not raw files or bare text.** [`run_x13`](@ref)
   returns a real [`X13RunResult`](@ref) (`success`, `warnings`,
   `errors` already extracted from the binary's own stdout — confirmed
   directly that the process exit code alone can't tell success from
   failure), and [`x13`](@ref) returns a typed [`X13Result`](@ref), not
   a directory of output tables the caller has to go find and parse
   themselves.
4. **Verified against the real binary directly, not a third-party
   reimplementation.** Since R's and Python's own wrapper packages call
   the identical binary this package wraps, "matches R" and "matches
   Python" both reduce to "matches `x13prebuilt`'s own real output" —
   there is no independent second computation to cross-check against
   for Part 1. Every stage's committed verification fixtures
   (`handoff/verification/`) are real, generated output from actually
   running the pinned binary, reused as regression fixtures rather than
   hand-written.

Full detail on all of these — including which findings were confirmed
directly against the binary during development, and exactly how each
platform (Linux/Windows/macOS) was verified — lives in the repository
README and `development-sequence.md`.

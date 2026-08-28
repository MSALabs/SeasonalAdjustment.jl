# Handoff: Task W.4 — Idiomatic Julia API

For a fresh Claude Code session picking this up with no prior context.
Read `CLAUDE.md` and `development-sequence.md` in full first. Depends
on W.0-W.3, all complete. This closes out Part 1.

## The one flagged question CLAUDE.md requires resolving first

CLAUDE.md: "check directly whether TSAnalytics.jl's
`classical_decompose`/`stl_decompose` share a common abstract result
type -- if so, `X13Result` should subtype it; if not, the light
dependency stands as-is."

**Checked directly against the actual TSAnalytics.jl source** (not
assumed): `ClassicalDecomposition` (`src/decompose.jl`) and
`STLDecomposition` (`src/stl.jl`) are both plain `struct`s with no
supertype at all. A full `grep "abstract type"` across TSAnalytics.jl's
entire `src/` finds exactly four abstract types --
`TimeSeriesModel`/`StateSpaceModel`/`UnivariateModel`/`HypothesisTest`
-- none related to decomposition results. **Answer: no shared abstract
type exists.** Per CLAUDE.md's own instruction, `X13Result` stays a
plain struct; the light dependency (`using TSAnalytics: tsvalues,
tsindex`) already in `Project.toml` is sufficient. For family
consistency (not correctness -- there's no shared type to satisfy)
`X13Result`'s field naming still echoes `ClassicalDecomposition`/
`STLDecomposition`'s `observed`/`trend`/... convention where it doesn't
conflict with README.md's own already-published field names (see
below).

## The API design requirement, restated precisely

CLAUDE.md's own target signature:
```julia
x13(y; maxorder=(2,1), outlier=true, trading=false,   # Python-style curated ergonomics
       regression_variables=[...], arima_model="...", # R-style direct spec passthrough
       kwargs...)                                      # anything else, forwarded straight into spec generation
```
`maxorder`, `trading` are *not* currently `X13Spec` fields -- they're
`statsmodels.tsa.x13.x13_arima_analysis`'s own real parameter names
(confirmed against its actual signature: `maxorder=(2,1),
maxdiff=(2,1), ..., outlier=True, trading=False, ...`). Genuinely
supporting them (not just accepting and ignoring the kwarg) needed a
small, real extension to W.2's `X13Spec` -- done as part of this task,
not a separate one, since W.4 is what actually needs them:

- **`maxorder`/`maxdiff`**: `automdl`'s own max-order/max-differencing
  bounds. Verified directly against the real binary: `automdl {
  maxorder = (2 1) maxdiff = (2 1) }` is valid X-13 grammar, matching
  Python's `(nonseasonal, seasonal)` tuple shape exactly.
- **`trading`**: a `Bool` shorthand for adding `"td"` to
  `regression_variables` (deduplicated against an explicit `"td"`
  already there).
- **A fourth `validate!` rule, found while testing this** (not in W.2's
  original three): an explicit ARIMA model (`arima_model`/
  `seasonal_order`) and `automdl`/`maxorder`/`maxdiff` can't both be
  given -- confirmed directly: `"ERROR: Cannot specify arima and
  automdl spec in the same input file."` `validate!` now checks this
  before either renders, the same fast-native-check-before-subprocess
  pattern as the original three.

README.md's own already-published quick example is the other concrete
constraint on `X13Result`'s shape:
```julia
result = x13(airline_passengers; seasonal_order=(0,1,1,12))
result.seasonally_adjusted
result.trend
result.seasonal_factors
```
These exact field names (`seasonally_adjusted`, `trend`,
`seasonal_factors`, not TSAnalytics' `resid`-style `seasonal`) are
already a committed public surface -- honor them precisely rather than
rename to match TSAnalytics' own decomposition-struct convention, which
would break this already-published example for no correctness benefit
(there is no shared abstract type to satisfy, per the question above).

## Proposed `X13Result` and `x13()`

```julia
struct X13Result
    observed::Vector{Float64}
    seasonally_adjusted::Vector{Float64}   # D11 / S11
    trend::Vector{Float64}                  # D12 / S12
    seasonal_factors::Vector{Float64}       # D10 / S10
    irregular::Vector{Float64}              # D13 / S13
    dates::Vector{Date}
    spec::X13Spec        # what was actually sent to the binary -- introspectable, not a black box
    run_result::X13RunResult   # raw stdout/warnings, even on success
end

x13(y; index=tsindex(y), start=nothing,
       maxorder=nothing, maxdiff=nothing, outlier=false, trading=false,
       kwargs...) -> X13Result
```

Design notes:
- **Dated-series bridging** (the concrete job CLAUDE.md/W.2's own
  docstring assigned to W.4): `index` defaults to `tsindex(y)`, which is
  `nothing` for a plain `Vector` and most sliced-column containers (per
  TSAnalytics.jl's own `interface.jl` docstring: date info usually lives
  on the parent container, not the column, so callers pass `index=`
  explicitly the same way they already do for `acf(tsf[:,:Close];
  index=TSFrames.index(tsf))` etc. -- mirrored here for family
  consistency, not invented). If `index` resolves to something
  (explicitly passed, or a container that does define `tsindex`),
  `start` is inferred from `index[1]`'s year/month. Explicit `start=`
  overrides either way. Neither given falls back to `X13Spec`'s own
  default `(1980,1)` -- the underlying D10-D13 numbers are unaffected by
  this label either way, only the returned `dates` field is.
- **`save` is deliberately not an `x13()` kwarg.** `x13()`'s contract is
  a fully-populated `X13Result`, which needs all four tables; exposing
  `save` would let a caller request a subset and get a broken result.
  Named explicitly in the signature (not left to fall through `kwargs`)
  specifically so passing it produces a clear `ArgumentError` pointing
  at the lower-level `X13Spec`/`run_x13`/`parse_output` API instead of a
  confusing "keyword argument repeated" `MethodError` from colliding
  with `x13()`'s own internal `save=`.
- **A failed run throws**, with the real binary's own error text, not a
  half-populated `X13Result` -- matches this project's "typed result,
  not silent partial success" ethos from W.3, applied one level up.
- **SEATS is reached the ordinary way**: `x13(y; seats=true)` --
  `seats` isn't named in `x13()`'s own signature, it just flows through
  `kwargs...` straight to `X13Spec` (genuine R-style passthrough, not
  special-cased). `x13()` picks `:s10.../:d10...` internally based on
  `spec.seats` when choosing which tables to fetch.

## Test plan

1. `x13(y; seasonal_order=(0,1,1,12))` on `airline_official`'s real
   144-month series reproduces the already-committed D10/D11/D12/D13
   fixture values exactly (reuses W.3's own committed fixture, no new
   ground truth needed).
2. `x13(y; seats=true)` reproduces `seats_baseline`'s committed S-table
   values.
3. `maxorder`/`maxdiff`/`trading` each render correctly and run cleanly
   against the real binary (extends W.2's own render-level tests one
   layer up, with a real subprocess this time).
4. The arima+automdl conflict throws before any subprocess, mirroring
   W.2's own `validate!` test pattern for the other three rules.
5. A short (24-month) series throws via the same `validate!` path W.2
   already covers -- confirms `x13()` doesn't bypass it.
6. `index=`/dated-series bridging: build a plain vector plus an
   explicit `Vector{Date}` index, confirm `result.dates` matches.
7. A failing run (the real minimum-length case, or a deliberately
   malformed spec) throws with the binary's real error text surfaced,
   not swallowed.

Same platform-verification split as W.1-W.3: every test that actually
invokes the binary is gated on `x13_binary_available()`, confirmed for
real via WSL/Linux, expected to fail its precondition (not the test
itself) in this specific sandboxed session on native Windows.

## What to do with this

1. Extend `X13Spec` (`src/spec.jl`) with `maxorder`/`maxdiff`/`trading`
   and the fourth `validate!` rule.
2. Implement `X13Result`/`x13` in `src/api.jl` (already stubbed).
3. Run the test plan above; update `development-sequence.md`'s W.4 row,
   including the resolved TSAnalytics abstract-type question and the
   W.2 extension, and mark Part 1 complete now that W.0-W.4 are all
   done.

# CLAUDE.md — SeasonalAdjustment.jl project context

Read `development-sequence.md` in full before starting any task — it
has the complete roadmap, task-by-task dependencies, and the
verification standard for each task. This file is background context,
not a substitute for it.

## What this package is

Official-statistics-grade seasonal adjustment for Julia (X-11,
RegARIMA, SEATS), part of the TSAnalytics.jl project family
(`https://github.com/MSALabs/TSAnalytics.jl`). Depends on `TSAnalytics.jl`
for `tsvalues`/`tsindex` at minimum. **Before implementing W.4**: check
directly whether TSAnalytics.jl's `classical_decompose`/`stl_decompose`
share a common abstract result type — if so, `X13Result` should subtype
it; if not, the light dependency stands as-is. This was flagged, not
resolved, when the project was scaffolded — don't assume either answer.

## API design requirement — verified, not aspirational

`x13(...)`'s signature must be a genuine superset of both R's `seas()`
and Python's `x13_arima_analysis()` — confirmed these are differently
*shaped*, not just differently named: R's `...` mechanism passes any
X-13 spec-argument combination through dynamically (the full grammar);
Python exposes only a fixed, curated subset. The Julia design needs
R's full-passthrough mechanism as its foundation (via `kwargs...`),
with Python's curated common options layered on top for discoverability
-- not just Python's subset alone. See `development-sequence.md`'s API
design section for the exact signature shape this implies.


## The one thing to understand before touching any code

**This package deliberately breaks from TSAnalytics.jl's own
"reference, never port" principle, for its core (Part 1) functionality.**
Rather than reimplement X-11/RegARIMA/SEATS from scratch, Part 1 wraps
the actual Census Bureau X-13ARIMA-SEATS binary directly — the exact
same binary R's `seasonal`/`x13binary` packages and Python's
`statsmodels.tsa.x13` both already call internally, via
`https://github.com/x13org/x13prebuilt` (confirmed in-session: this is
literally the repository R's own packages depend on, not a third-party
reimplementation). This is a real, deliberate exception, not an
oversight -- state it plainly if it comes up, don't treat it as
something to quietly work around.

A from-scratch native engine remains planned (`development-sequence.md`,
Part 2) but is explicitly sequenced *behind* a working wrapper, not
abandoned.

## Verification philosophy — genuinely different between Part 1 and Part 2, don't blur them

**Part 1 (W.0-W.4, the wrapper)**: "matches R" and "matches Python" both
reduce to "matches `x13prebuilt`'s own real output directly" -- R and
Python don't independently compute anything here, they call the same
binary. Primary verification is direct binary invocation (already
proven working in development, including a real user-defined
Diwali-effect regressor test -- see below). R's/Python's wrappers are a
secondary check on *API-level* parsing behavior, not a second
independent computation.

**Part 2 (S.0-S.5, the native engine, once started)**: genuine
independent reimplementation -- the full TSAnalytics.jl dual-verification
standard applies exactly as it did throughout that project (real R and
Python execution where possible, `x13prebuilt`'s own output as an
additional, even stronger ground truth per Stage S.1's own finding).

## Facts already established, don't re-derive these

- **Pinned `x13prebuilt` commit**: `61c4043949f43c1ea5ad0fbbc7b6c11fc5073d19`.
  Real, computed SHA256 hashes for all platform binaries at this commit
  are already in `Artifacts.toml`. The `git-tree-sha1` values in that
  file are placeholders -- run `tools/generate_artifacts.jl` in a real
  Julia environment (network access required) to fill them in properly
  before trusting `Pkg.instantiate()` on this package. Do not hand-write
  a `git-tree-sha1` value.
- **The macOS x86_64 and arm64 binaries have identical SHA256 hashes**
  in the source repo at the pinned commit -- confirm this is a genuine
  universal binary (plausible, not yet independently confirmed) rather
  than a repo issue, before treating both platform entries as correct.
- **User-defined regressors are confirmed working end-to-end**, tested
  directly against the real binary: `regression { variables = (td)
  user = (diwali) usertype = (holiday) data = (...) }` genuinely changes
  the RegARIMA fit (a synthetic Diwali-effect test shifted October's
  seasonal factor from 0.8986 to 0.7268 on identical underlying data --
  not silently ignored). Two real practical requirements surfaced:
  (1) user-defined regressor data must cover the RegARIMA forecast
  horizon (default: 1 year ahead), not just the historical series
  length, or the binary errors clearly; (2) combining a RegARIMA model
  with multiplicative X-11 mode needs an explicit
  `transform { function = log }` spec.
- **Real ground truth already generated**: the Box-Jenkins airline
  passengers series (1949-1960), both without and with a custom
  holiday regressor -- see the verification bundles already produced
  during development for the exact spec files and output tables.

## Working style

- One task from `development-sequence.md` at a time, in order. Each
  task gets its own handoff document (verified references, API design,
  test cases, honest gaps flagged) before implementation starts --
  same standard as TSAnalytics.jl's own development throughout.
- Fully autonomous by default (`bypassPermissions`, set automatically
  by this devcontainer) -- work through a task's checklist without
  pausing for confirmation unless something in the task's own handoff
  flags a genuine decision point.
- When a task's handoff flags something as unverified or a real gap,
  say so in code comments and commit messages -- don't silently resolve
  ambiguity by picking whichever interpretation is easiest to implement.
- Update `development-sequence.md`'s own status markers as each task
  completes, the same way TSAnalytics.jl's roadmap was kept current
  throughout its own development.

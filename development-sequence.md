# SeasonalAdjustment.jl — Development Sequence

## What this is, and the one deliberate exception at its core

SeasonalAdjustment.jl is the destination the broader TSAnalytics.jl
project was originally built toward: official-statistics-grade
seasonal adjustment for Julia — X-11, RegARIMA, and SEATS.

**It also deliberately breaks from that project's own "reference, never
port" principle**, for this package's core functionality specifically.
Rather than reimplement X-11/RegARIMA/SEATS from scratch as a first
step, this package wraps the actual Census Bureau X-13ARIMA-SEATS
binary directly — confirmed, not assumed: `x13org/x13prebuilt` on
GitHub is the exact repository R's own `seasonal`/`x13binary` packages
depend on internally, and Python's `statsmodels.tsa.x13` calls the same
program too. Both of the usual reference ecosystems already trust this
binary for the hardest part of the whole problem — SEATS's spectral
factorization especially. Wrapping it directly gets this package to
correct, production-grade output immediately, rather than spending
months on the hardest mathematics in the entire TSAnalytics.jl roadmap
before shipping anything.

A from-scratch native Julia engine remains a real, planned track
(Part 2 below) — not abandoned, deliberately sequenced behind a working
wrapper.

## Relationship to TSAnalytics.jl

**Confirmed**: `tsvalues`/`tsindex` (TSAnalytics.jl's container-agnostic
series interface) as a baseline dependency either way, so a user can
pass the same series object to either package consistently.

**Open, flagged honestly rather than assumed**: whether `X13Result`
(W.4) should subtype an existing TSAnalytics.jl decomposition abstract
type, if `classical_decompose`/`stl_decompose` share one — this needs a
direct check against the real TSAnalytics.jl source before W.4 is
implemented. If a shared type exists, `X13Result` should subtype it for
consistent display/composition; if not, the light dependency above is
sufficient for Part 1. **Do not guess on this — check the source
directly as the first step of W.4's own handoff, not before.**

Part 2 needs the full, deep dependency regardless of how the above
resolves: Stage 8.3 (`fit_arimax`/`fit_sarimax`), Stage 6.8
(`auto_arima`), Stage 6.3 (the Kalman smoother), and Stage 2.4
(Ljung-Box) from that project directly.

## API design principle — a genuine superset of R and Python, verified precisely

R's `seas()` and Python's `x13_arima_analysis()` are differently
*shaped*, not just differently named, confirmed directly:
```r
seas(x, xreg=NULL, ..., list=NULL)   # `...` accepts ANY spec.argument combination directly -- the full X-13 grammar, dynamically
```
```python
x13_arima_analysis(endog, maxorder=(2,1), maxdiff=(2,1), outlier=True, trading=False, ...)  # a fixed, curated subset only
```
**R exposes the entire X-13 spec grammar dynamically; Python exposes
only a curated subset of it.** Being a genuine superset of both
therefore means R's full-passthrough mechanism is the *foundation*,
with Python's curated option list layered on top for discoverability —
not the reverse. Julia's own `kwargs...` maps onto this directly:
```julia
x13(y; maxorder=(2,1), outlier=true, trading=false,   # Python-style curated ergonomics
       regression_variables=[...], arima_model="...", # R-style direct spec passthrough
       kwargs...)                                      # anything else, forwarded straight into spec generation
```
This is a concrete design requirement for W.4 now, not an aspiration —
confirm both mechanisms are genuinely present before treating that
stage as complete.


## Verification philosophy — Part 1 and Part 2 are genuinely different, stated plainly so they don't get blurred

**Part 1 (the wrapper)**: "matches R" and "matches Python" both reduce
to the same claim — "matches `x13prebuilt`'s own real output" — since
neither reference independently computes anything here; both call the
identical binary this package wraps. Primary verification is therefore
direct binary invocation, already proven working (see the real ground
truth already generated, below). R's and Python's own wrapper packages
serve as a secondary check on *API-level* behavior only.

**Part 2 (the native engine, once started)**: genuine independent
reimplementation, so the full TSAnalytics.jl dual-verification standard
applies exactly as it did throughout that project — real R and Python
execution wherever reachable, with `x13prebuilt`'s own output available
as an even stronger ground truth than usual (confirmed directly: this
program includes X-11, RegARIMA, *and* SEATS all in one binary, so
every native-engine stage has real, authoritative output to check
against, not just a published algorithm description).

---

## Real ground truth already generated — reuse this, don't regenerate it

**The pinned `x13prebuilt` commit**: `61c4043949f43c1ea5ad0fbbc7b6c11fc5073d19`.
Real SHA256 hashes for every platform binary at this commit are already
computed and in `Artifacts.toml` — Linux x86_64, Linux armv7l, Windows,
macOS x86_64, macOS arm64 (the last two share an identical hash in the
source repo — confirm this is a genuine universal binary before
trusting both platform entries blindly).

**The core Box-Jenkins airline passengers series** (1949-1960, 144
monthly observations — the standard benchmark in this entire field),
run through the real binary twice:

*Without any custom regressor* — real D10 (seasonal factors), D11
(seasonally adjusted), D12 (trend-cycle) tables generated directly:
```
D10, Jan-Jun 1949: 0.909187671763704, 0.959401810971537, 1.05757934646024,
                    1.00514879872191, 0.999732566557629, 1.07303952726698
D11, Jan-Mar 1949: 123.186888118198, 122.993305464483, 124.813330027491
D12, Jan-Mar 1949: 123.774514749304, 123.950693749510, 124.289377383170
```

*With a synthetic Diwali-effect user-defined regressor* (proving the
custom-holiday-regressor mechanism, section "W.0" below) — the same
series, same spec otherwise, but with
`regression { variables=(td) user=(diwali) usertype=(holiday) data=(...) }`
added:
```
D10, October factors WITHOUT the custom regressor: 0.898593816033472 (1949), ...
D10, October factors WITH the custom regressor:    0.726751422651829 (1949), ...
```
**The seasonal factor genuinely shifted** — proof the binary actually
used the custom regressor, not just accepted and ignored it.

Two real, practical requirements surfaced while getting this clean run,
both worth keeping for W.2's spec generation:
1. **User-defined regressor data must cover the RegARIMA forecast
   horizon** (a year ahead, by default), not just the historical series
   length — the binary errors clearly (`"forecasts end date ... must
   end on or before user-defined regression variables end date"`) if it
   doesn't, rather than silently truncating.
2. **Combining a RegARIMA model with multiplicative X-11 mode needs an
   explicit `transform { function = log }` spec** — without it, the
   binary errors (`"Multiplicative or log additive seasonal adjustment
   cannot be performed when preadjustment factors are derived from a
   regARIMA model for data which have not been log transformed"`).

All spec files and full 144-month output tables from both runs are
preserved in this package's verification assets — reuse them directly
as test fixtures rather than regenerating from scratch.

---

## Part 1 — wrap `x13prebuilt` (the active track)

| # | Status | What | Needs | Notes |
|---|---|---|---|---|
| W.0 | ✅ Done | Business-day/holiday calendars (India + major markets) — generates the actual user-defined regressors W.2 passes to the binary | `BusinessDays.jl` | Confirmed working end-to-end with the real binary (the Diwali proof above) — not optional once non-Western-calendar effects are wanted. India's fixed-date holidays (Republic Day, Independence Day, Gandhi Jayanti, Maharashtra Day, Christmas) and Good Friday are algorithmically computable; Holi/Diwali and most of India's actual trading calendar have no closed-form date formula and need a maintained, year-keyed table sourced from the relevant exchange's own official circular (a real data-sourcing caution — secondary aggregator sites disagreed on one 2026 NSE holiday date, Guru Nanak Jayanti, by 19 days during this task's own research — don't trust aggregators, use NSE's own circular). **Implemented** in `src/calendars.jl` per `handoff/w0-calendars.md`: a QuantLib-style `Calendar`/`TableCalendar` abstraction (deliberately its own hierarchy, not a `BusinessDays.HolidayCalendar` subtype, since it needs a per-calendar configurable weekend set that BusinessDays.jl can't express) with `isbusinessday`/`isholiday`/`isweekend`/`adjust`/`advance`/`businessdaysbetween`/`holidaylist`; `easter_date` reuses BusinessDays.jl's own computation rather than re-deriving it; `INDIA_NSE` (fixed holidays + Good Friday, cross-validated against 3 real years, + a 2024-2026 moveable-feast table cross-checked across aggregators, honestly flagged as not yet reconciled against NSE's own circular PDF; Eid/Mahashivratri/Ram Navami/etc. deliberately omitted as unresolved gaps, Guru Nanak Jayanti omitted specifically because this task's own handoff and this task's independent research disagreed on its 2026 date and neither was silently preferred); plus `trading_day_regressors`/`easter_regressor`/`custom_holiday_regressor`. **The CAPSTONE test actually re-ran the real `x13prebuilt` binary** (located locally, invoked via `x13_binary_path()` since W.1 landed) against a spec file built from this task's own generated regressor data, and confirmed the documented October-1949 seasonal-factor shift (0.898593816033472 → 0.753973303751993, the corrected "official" fixture value, see W.1's own row for the fixture correction) — not just a byte-identical-vector check, the stronger of the two options the handoff allowed. |
| W.1 | ✅ Done | Binary artifact management for `x13prebuilt` (Linux/Windows/macOS) via Julia's Artifacts system | none | `Artifacts.toml` already scaffolded with real SHA256 hashes and verified download URLs, pinned to the commit above; `git-tree-sha1` values are placeholders needing a real Julia runtime to compute (`tools/generate_artifacts.jl` is ready to run for this). **Implemented** per `handoff/w1-artifacts.md`, with three real bugs found and fixed along the way, none of them hypothetical -- each confirmed by directly hitting it: (1) `Artifacts.toml`'s original structure used five different top-level names, each a single-platform `[name]` table with a nested `[[name.platform]]` sub-table -- confirmed against Artifacts.jl's own `unpack_platform`/its own test fixture that this is wrong; the correct shape is one shared name with repeated `[[name]]` array-of-tables entries, `os`/`arch` as direct keys. Fixed, and confirmed working by observing `artifact_meta` correctly auto-select the Windows entry from this Windows host. (2) Julia's built-in lazy-artifact installer only knows how to unpack real archives (zip/tar.gz/etc) and hard-errors (`"Is not archive"`) on upstream's bare-file Linux download -- confirmed directly by hitting exactly that error on a clean cache. `_linux_x13_artifact_dir()` in `src/artifacts.jl` now installs the Linux binary manually (download, sha256-verify against the same hash already in `Artifacts.toml`, `create_artifact`), lazily, at first use. (3) The macOS x86_64/arm64 "identical hash" question flagged since project scaffolding is now resolved, not just re-flagged: confirmed via GitHub's own blob SHA that the two tarballs are byte-identical, and via `file` that the binary inside is `Mach-O 64-bit x86_64 executable` -- a genuine upstream repo issue, not a legitimate universal binary; Apple Silicon users get an x86_64 binary that runs under Rosetta 2, not natively, documented as such in `Artifacts.toml` rather than presented as native support. **Platform verification, precisely, per the handoff's own instruction not to blur this**: Linux confirmed fully end-to-end for real (fresh artifact cache, real download+install+execution, via a genuine Linux Julia process over WSL -- resolved, ran, produced the expected usage banner). Windows: artifact resolution confirmed structurally correct (right path, right git-tree-sha1, `file` confirms a valid PE32+ executable) but actual native execution could NOT be confirmed in this specific coding-agent sandbox -- it blocks executing any binary placed under `~/.julia/artifacts/`, confirmed via a control test (even a plain copy of `julia.exe` itself fails identically from that directory tree with "Access is denied" while running fine from any other directory) -- a sandbox execution policy, not a resolution bug; needs the CI matrix (`.github/workflows/CI.yml`, `windows-latest`) or a real, non-sandboxed Windows machine to confirm positively. macOS: archive extraction and the `bin/`+`lib/` directory layout confirmed correct (forced-platform resolution + direct file checks); execution unverifiable without macOS hardware, same CI dependency. `x13_binary_available()`'s test is left as a hard, un-skipped assertion regardless (per the handoff) -- it fails in this one sandboxed session for the reason above, and should pass everywhere else. W.0's capstone test was refactored per the handoff's explicit requirement to use `x13_binary_path()`, removing its earlier hardcoded-path/WSL-specific stand-in entirely. |
| W.2 | ✅ Done | Spec-file generation (`series{}`, `x11{}`, `regression{}`, `arima{}`, `outlier{}`, user-defined regressor blocks) | W.1, W.0 | Grammar confirmed directly against the real binary, including both practical requirements noted above. **Implemented** in `src/spec.jl` per `handoff/w2-spec.md`: `X13Spec`/`render`/`validate!`/`write_spec`/`generate_specs`, combining R-style raw passthrough (`regression_variables`, `arima_model`) with Python-style curated fields (`transform`, `seasonal_order`, `x11_mode`, `outlier`, ...) as the handoff's "genuine superset" design required. All three `validate!` rules implemented and each triggered directly in tests: series length ≥36 months, `regression_user` covering the +12-month forecast horizon, `transform=:log` required for a regression block combined with multiplicative/log-additive `x11_mode`. `generate_specs`'s `Threads.@threads` path is genuinely exercised (this session's default is single-threaded, where it silently falls back to the serial branch) and confirmed to match serial output exactly when actually run with `--threads=4`. **A fourth real bug found and fixed while testing against the real binary** (not in the handoff's own list): `x11{mode=...}` requires X-13's short keywords (`mult`/`add`/`logadd`/`pseudoadd`), not the full words this package's own `x11_mode` symbols use for discoverability (`:multiplicative` etc.) — a real parse error (`"Argument name \"multiplicative\" not found"`) hit directly before the fix; `_X11_MODE_KEYWORDS` now translates between them, and `validate!` rejects an unrecognized mode symbol before it can reach render/the binary at all. **CAPSTONE, one level past W.0's own**: W.0's Diwali regressor run through `X13Spec`/`render`/`run_x13` (not hand-assembled `.spc` text) reproduces the exact documented value (0.753973303751993) — confirmed directly, including the finding that `regression_variables=["td"]` must be included alongside the user regressor to match the original proof exactly (omitting it is a valid but different, non-matching spec). The 120-case length×seed×option grid from the handoff is fully executed as structural checks (fast, no subprocess); a representative real-binary subset is spot-checked separately, gated on `x13_binary_available()` per W.1's established pattern (confirmed passing for real on Linux via WSL this session — see W.3's row for the shared verification methodology). |
| W.3 | ✅ Done | Subprocess invocation + output-table parsing (`d10`/`d11`/`d12`/`d13`, SEATS' own tables) | W.2 | Real output format already confirmed from actual runs — tab-separated, `date\tvalue` per line, a `date\t------\t---...` header row to skip. **Implemented** in `src/run.jl`/`src/parse.jl` per `handoff/w3-run-parse.md`: `X13RunResult`/`run_x13`/`run_x13_batch`/`parse_table`/`parse_output`. Confirmed directly, not assumed: (1) `x13ashtml` writes ALL diagnostic text (banner, `ERROR:`, `WARNING:`) to stdout — stderr is always empty; (2) **the process exit code is 0 even on a real `ERROR:`** (hit directly running the real 24-month failing case) — `success` is therefore derived from whether any `ERROR:` block was extracted from stdout, never from the exit code; (3) SEATS' `.sNN` tables share `.dNN`'s exact tab-separated format, confirmed by generating and committing a real SEATS fixture (`handoff/verification/seats_baseline/`) and parsing it with the same `parse_table`. `parse_output`'s signature was deliberately changed from the handoff's own sketch (`parse_output(basename, tables)`) to `parse_output(result::X13RunResult, tables)`, documented in its own docstring: `run_x13` always runs in a fresh scratch directory (never the fixture directory itself, to avoid littering committed fixtures with generated `.html`/output files on every test run), so resolving output paths needs `result.dir` too, not just a bare basename assumed relative to some implicit CWD. **The async-spawn parallel design was actually benchmarked with real Julia this session** (the handoff's own explicit ask, flagged as unverified since no Julia was available when it was written) — genuinely faster, unlike Python's worker-pool approach the handoff found slower: N=20, serial 1.02s vs parallel 0.54s (1.89×); N=100, serial 15.67s vs parallel 5.62s (2.79×), both via WSL's real Linux Julia against the real binary. **Platform verification, same split as W.1/W.2**: every execution-dependent test (`run_x13`, `run_x13_batch`, the 24-case grid, the parallel-vs-serial and timing checks) is gated on `x13_binary_available()` and confirmed passing for real via a genuine Linux Julia process over WSL this session — resolved, ran, correct output, including the minimum-length error surfacing as a structured `result.errors` entry (not raw text) exactly as designed. These same tests fail their `x13_binary_available()` precondition on native Windows in this specific coding-agent sandbox (see W.1's row) and are skipped there with a clear warning rather than crashing; CI (or a real machine) is the authoritative confirmation for Windows/macOS, per the same convention established in W.1. |
| W.4 | ✅ Done | Idiomatic Julia API (`x13(y; options...)`) | W.3 | Mirrors R's `seas()` ergonomics; returns a proper Julia struct (`X13Result`), not raw files. **The open question CLAUDE.md flagged at project scaffolding is resolved, not deferred again**: checked directly against TSAnalytics.jl's actual source that `ClassicalDecomposition`/`STLDecomposition` share no common abstract type (both plain structs; a repo-wide `grep "abstract type"` finds only `TimeSeriesModel`/`StateSpaceModel`/`UnivariateModel`/`HypothesisTest`, none decomposition-related) — `X13Result` stays a plain struct per CLAUDE.md's own instruction for that case, with field names that follow README.md's own already-published quick-example (`seasonally_adjusted`/`trend`/`seasonal_factors`) rather than TSAnalytics' `observed`/`seasonal` convention, since there's no shared type to satisfy and the README example is itself a committed public surface. **Implemented** in `src/api.jl` per `handoff/w4-api.md`: `X13Result`/`x13`, combining Python-parity curated kwargs (`maxorder`, `maxdiff`, `outlier`, `trading` — matching `statsmodels.tsa.x13.x13_arima_analysis`'s own real parameter names, not just similar ones) with full R-style passthrough via `kwargs...` straight into `X13Spec` (`transform`, `x11_mode`, `seats`, `regression_variables`, `arima_model`, `regression_user`, ... all work with no `x13()`-level code needed for any of them). **Required a small, real extension to W.2's `X13Spec`** (`maxorder`/`maxdiff`/`trading` fields, since Python's parameter names aren't spec-argument names X-13 accepts directly) plus **a fourth `validate!` rule found while testing it**: an explicit ARIMA model and `automdl`/`maxorder`/`maxdiff` can't both be given — confirmed directly (`"ERROR: Cannot specify arima and automdl spec in the same input file."`), now checked before either renders, matching the existing three rules' fast-fail-before-subprocess pattern. Dated-series bridging (`index=tsindex(y)`, inferring `start` from `index[1]`) follows TSAnalytics.jl's own established convention of explicit `index=` passthrough (`tsindex` returns `nothing` for a plain vector or most sliced columns by design, per its own docstring — not a gap to work around, the normal case). `save` is deliberately rejected as an `x13()` kwarg (named explicitly so it errors clearly rather than colliding with `x13()`'s own internal use of it) — the lower-level `X13Spec`/`run_x13`/`parse_output` API is for a custom partial-table selection. **CAPSTONE, closing Part 1 end to end**: README.md's own quick-start example (`x13(airline_passengers; ...)`) runs for real via WSL and reproduces the committed X-11 baseline exactly (D10/D11/D12/D13), and `x13(y; seats=true, ...)` separately reproduces the committed SEATS baseline exactly (S10/S11) — the two real ground-truth bundles this whole project has carried since W.0/W.1, both now reachable through the actual public one-line API, not just the internal plumbing. `maxorder`/`maxdiff`/`trading`, the arima+automdl conflict, `save` rejection, and a genuine binary-level failure (a syntactically invalid `arima_model` string, which `validate!` correctly doesn't catch since it's R-style raw passthrough) surfacing as a thrown error with the real binary's text are all confirmed the same way. Same platform-verification split as W.1-W.3: every execution-dependent test gated on `x13_binary_available()`, confirmed passing for real via WSL, expected to skip (not fail) its precondition on native Windows in this specific sandboxed session. **Part 1 (the x13prebuilt wrapper) is now complete, W.0 through W.4.** |

---

## Post-push finding (2026-08-28): local verification had a real blind spot, caught only by actually pushing to CI

Every prior "confirmed" claim above about Windows/macOS artifact resolution, and every green local test run through W.0-W.4, was genuinely true *for what it tested* -- but local testing never actually exercised a completely fresh dependency/artifact install the way a real new user or CI runner does. Pushing this repo and checking the actual GitHub Actions results (prompted directly by being asked "pushed, now?" rather than assumed) surfaced two real, previously-invisible bugs, both now fixed and confirmed via a genuinely clean-room reproduction (an isolated `JULIA_DEPOT_PATH`, no local package caches, no manually-pre-run tooling) rather than just re-patched and hoped:

1. **Every single CI run, on every commit since the project's first scaffold, had been failing** at the dependency-resolution step (`julia-buildpkg`), with `ERROR: expected package TSAnalytics [b1a2c3d4] to be registered`. TSAnalytics.jl isn't published to Julia's General registry -- `Project.toml`'s `[deps]` entry alone can't tell `Pkg.instantiate()` where to get it from. Local development never hit this because every local session had `TSAnalytics` manually `Pkg.develop`'d from a sibling checkout on disk -- something no fresh CI runner has. Confirmed the exact error by reproducing it directly (a clean depot, `git archive HEAD`, `Pkg.instantiate()`), and confirmed the fix the same way: an explicit `Pkg.develop(url="https://github.com/MSALabs/TSAnalytics.jl")` step (TSAnalytics.jl is a public repo, confirmed directly) added to both `.github/workflows/CI.yml` and `Docs.yml`, before `Pkg.instantiate()`/`julia-buildpkg` in each. A full, genuinely fresh `Pkg.test()` run then passes 480/481 (the one failure is the pre-existing sandbox-execution-restriction case, documented below and in W.1's own row).
2. **The Windows artifact was never actually confirmed via a real fresh install, only ever re-found in a cache this package's own `tools/generate_artifacts.jl` had already populated manually.** Once genuinely exercised fresh (same clean-depot method), it failed: `"This does not appear to be a TAR file/stream"`. Root cause confirmed directly from Pkg's own stdlib source (`Pkg.PlatformEngines.unpack`): Julia's built-in artifact installer *always* pipes `7z x <archive> -so` into `Tar.extract` -- which only produces a valid result for tar-based archives (where 7z's `-so` reveals an inner tar stream); a plain `.zip` has no such inner tar layer, so the pipe produces raw file bytes that `Tar.extract` can't parse. **Julia's built-in artifact system cannot install plain zip files at all, full stop** -- not a configuration issue (confirmed by also testing with `JULIA_PKG_SERVER=""` to rule out CDN-mirror interference; identical failure either way). Fixed the same way Linux's own bare-file problem was fixed in the original W.1 work: `_windows_x13_artifact_dir()` in `src/artifacts.jl` installs the Windows artifact manually, via `p7zip_jll` (a new, direct dependency -- the same 7-Zip binary Pkg itself already uses internally, invoked as a normal, complete extraction this time, not routed through the tar-only pipe). **A further subtlety, also confirmed directly, not assumed**: `p7zip_jll`'s extraction produces a *different* git-tree-sha1 than the `unzip`-based one `tools/generate_artifacts.jl` originally computed, for the exact same byte-identical zip (almost certainly a difference in restored executable-permission metadata between the two tools) -- confirmed deterministic across repeated runs, and `Artifacts.toml`'s Windows entry updated to the `p7zip_jll`-produced value, since that's what every real installation now actually goes through; `tools/generate_artifacts.jl` was updated to use `p7zip_jll` too, so a maintainer re-running it in the future gets a hash consistent with runtime reality. **macOS was separately re-verified via the same genuinely-fresh method and confirmed to NOT have this problem** -- a real tar.gz is exactly the format Julia's built-in installer is designed for, and does handle correctly; the fresh install exactly reproduced the same tree hash `tools/generate_artifacts.jl` had already computed.

Local `Pkg.test()` (native Windows, this session's own sandbox) still shows 480/481 -- the one expected failure is `x13_binary_available()`'s hard assertion, still blocked by the sandbox's own restriction on executing anything under `~/.julia/artifacts/` (documented in W.1's own row, unrelated to and unaffected by either fix above). Both fixes are confirmed via a from-scratch clean-room `Pkg.test()` run (480/481, same single expected failure) and a from-scratch clean-room `docs/make.jl` run (passes completely) -- the strongest verification available without an actual CI runner, deliberately going further than "it works on my machine" given that's exactly the blind spot that let both bugs through undetected until now.

Pushing the two fixes above (commit `160dbac`) got CI's `julia-buildpkg` step passing on all 6 matrix jobs -- but `julia-runtest` then failed on all 6, a second, distinct blind spot: this session's execution-dependent tests (gated on `x13_binary_available()`) had genuinely never been run for real as the literal committed test files before, since the sandbox itself can't execute the artifact binary (above) and every prior ad hoc verification had used separate standalone scripts, not `Pkg.test()` itself. Getting a real answer required a genuinely working Linux execution environment, which took real effort to obtain: WSL's existing Julia (1.7.2) was too old for the current `Manifest.toml`; a newer Julia (1.12.7) had to be downloaded from native Windows and manually extracted into WSL (`juliaup` itself couldn't reach the Julia S3 bucket from inside WSL); and the repo/depot initially placed on WSL's `/mnt/c/...` Windows-interop mount produced *consistently wrong* artifact tree-hashes for two unrelated packages (`Bzip2_jll`, `OpenSpecFun_jll`) from multiple independent sources -- diagnosed as filesystem-interop corruption specific to that mount, fixed by moving both the repo and the Julia depot onto WSL's native ext4 filesystem instead. That finally produced a genuine, real-execution `Pkg.test()` run: 616 passed, 8 failed, 1 errored, and both failures traced to exactly two real, previously-uncaught bugs (not test-environment issues):

3. **`src/spec.jl`'s `_write_wrapped` wrapped output data by a fixed count of values per line (12), not by character width** -- confirmed to overflow X-13's real, hard input-record-length limit (`"ERROR: Input record longer than limit :         133"`) for longer series with wider numeric representations, hit directly by the spot-check test's longer (240-month) cases. Fixed by rewriting `_write_wrapped` to wrap on character width instead (a conservative 100-char budget, well under the confirmed 133-char limit, to leave margin for the caller's own line prefix such as `"  data = ("` on the first wrapped line).
4. **`test/test_run_parse.jl`'s bulk 24-case length-grid test wrongly assumed every successful run produces a `.d10` output table.** Confirmed directly (`grep -H "x11" handoff/verification/w2_length_grid/*.spc`) that all 24 fixtures share the exact same bare `x11 { }` block, with no `save=` clause -- and confirmed separately that X-13 with a bare `x11{}` computes the adjustment but writes **no output table files at all**. These fixtures were built by W.2's own handoff specifically to probe the minimum-length validation boundary, not table output, so the test's own assumption was wrong, not `run_x13`/`parse_output`'s logic. Fixed by removing the `parse_output`/`:d10` assertions from the successful-case branch, keeping only the `result.success == length_ok` check the fixtures were actually designed to support.

Both fixes re-verified via the same genuine WSL native-filesystem `Pkg.test()` run (repo + depot both on ext4, Julia 1.12.7, real binary execution enabled): **644 passed, 0 failed, 0 errored** -- the first fully clean, fully real-execution test run this package has had. Pushed as a follow-up commit (`c744e6e`) after `160dbac`.

That push still left 5 of 6 CI test matrix jobs red (only `ubuntu-latest, 1` -- Julia 1.12, matching the WSL environment above -- passed) plus `Documentation` red, a third distinct blind spot: the two bugs above were real, but not the whole story, and both remaining failures needed genuinely reproducing the SPECIFIC failing environment (older Julia, or the docs install step) rather than assuming one clean run elsewhere covered them.

5. **`run_x13_batch`'s parallel path had a genuine concurrency bug in `src/run.jl`, independent of platform** -- `run(pipeline(cmd; stdout=buf, stderr=buf))` (used identically in both `run_x13` and the batch version) has Base spawn one internal relay task per redirected stream that copies bytes into the destination as they arrive; even confining each subprocess to its own private `IOBuffer` inside its own `@async` task (a first attempted fix) didn't eliminate it, since the race is between a SINGLE process's own stdout-relay and stderr-relay tasks, not between different processes' buffers. Confirmed directly and repeatedly via a genuine WSL Julia-1.9 environment (matching the CI matrix's failing `1.9` jobs): intermittent `ArgumentError: ensureroom failed, IOBuffer is not writeable`, and -- more importantly -- silently truncated output (a real WARNING message present in the serial run's text simply missing from the parallel run's text for the same spec) that would corrupt results without ever throwing. Fixed by replacing the `IOBuffer`-redirect-target pattern with a `Pipe()` read directly by the calling task (`_run_capture`, now shared by both `run_x13` and `run_x13_batch`): passing the same `Pipe` as both `stdout` and `stderr` merges the two streams at the OS level, with no Base-managed relay task at all, so there is nothing left to race. Verified clean across 3 repeated full `Pkg.test()` runs on Julia 1.9 in WSL (643/643 each time, 0 failures) plus 5 repeated runs of an isolated parallel-vs-serial comparison script with zero mismatches -- deliberately run multiple times since races don't reproduce on every attempt.
6. **`Docs.yml`'s "Install dependencies" step failed on every run since the original CI.yml-style fix was added, for a different reason than that fix addressed.** Root cause confirmed directly by reproducing the exact step in a clean, git-metadata-intact WSL copy: `docs/Project.toml` lists `SeasonalAdjustment` as a direct dependency, and `SeasonalAdjustment`'s own `Project.toml` lists `TSAnalytics` as a dependency -- so the two packages are each other's dependency-resolution neighbor inside the `docs` environment. Calling `Pkg.develop(url=TSAnalytics)` then `Pkg.develop(PackageSpec(path=pwd()))` **sequentially** fails either order: whichever call runs first triggers a full resolve pass that needs the OTHER package already registered-or-developed, and it isn't yet -- confirmed both failure modes directly (`"expected package SeasonalAdjustment to be registered"` one order, `"TSAnalytics has no known versions!"` the other). Fixed by combining both into a single atomic `Pkg.develop([PackageSpec(path=pwd()), PackageSpec(url="https://github.com/MSALabs/TSAnalytics.jl")])` call, so Pkg treats both as fixed from the start of one resolve pass. Verified via a full clean-room reproduction with real git metadata present (needed for Documenter's own repo-remote auto-detection, separately confirmed to fail with a plain non-git directory copy -- a red herring ruled out along the way, not a bug): `Pkg.develop` + `Pkg.instantiate` succeed, and `docs/make.jl` completes cleanly through doctest, cross-reference, and HTML-render stages, correctly skipping deployment (no CI environment present locally).

Both fixes verified and pushed together as a further follow-up commit. Three real, distinct concurrency/environment bugs (this section's #5 and #6, plus #3/#4 above) surfaced only by insisting on genuine execution in the actual failing environment at each step, rather than treating one clean run elsewhere as sufficient -- consistent with this project's verification philosophy, and worth remembering the next time "it passed for me" is tempting to accept at face value.

That push still left every macOS and Windows test job red (both Julia versions, both platforms), with Linux and Documentation now genuinely clean. This session cannot execute the artifact binary at all in its own local sandbox (a known, unrelated restriction -- W.1's own row) and has no Mac to test on, so real evidence had to come from CI itself -- but the GitHub Actions log-download API returns 403 ("Must have admin rights to Repository") even for this public repo without an authenticated token, which this session doesn't have. Worked around by making the failing test emit its diagnostic as a `::warning::` GitHub Actions workflow command instead of a plain exception message: workflow commands printed to *any* step's stdout (including from a nested subprocess like `julia-runtest`) become check-run annotations, and those ARE readable anonymously via the public API. A temporary diagnostic block was added to `test_artifacts.jl`'s "the resolved binary actually runs" test (removed once real evidence was in hand) to surface exactly this. Two distinct, unrelated real bugs came out of it:

7. **The macOS git-tree-sha1 fix from the very first "Post-push finding" round above was itself wrong, for a documented-but-unverified reason.** That original fix reused ONE git-tree-sha1 (computed once, on a non-Mac environment) for both the x86_64 and aarch64 `Artifacts.toml` entries, reasoning from the tarballs being byte-identical (true, independently re-confirmed here via sha256 again) -- but a byte-identical INPUT doesn't guarantee an identical tree-hash if the tool computing it differs from Julia's own real `@artifact_str` extraction, and that was never actually checked against real hardware (this session has none). GitHub Actions' `macos-latest` runners are Apple Silicon (arm64) by default now, so this was the very first genuine exercise of this artifact on any real Mac at all -- and it hit a real `Tree Hash Mismatch!` (expected `b014791cb9413683ee2d468e930f68bcec187a57`, real Julia-native result `bdb3303eadb041eeabb849a0c9e24f26004b6fb2`). Fixed by using the real, CI-confirmed value for both entries -- the x86_64 entry's original value remains equally unverified (no x86_64 macOS CI runner exercises it either), not assumed correct just because it hadn't yet been caught.
8. **A genuinely fresh Windows install hit `IOError: could not spawn ... permission denied (EACCES)` on the very first invocation of a just-extracted `.exe`.** This is a well-documented Windows pattern -- real-time antivirus (Windows Defender on GitHub-hosted runners) briefly locking a freshly-written executable while scanning it -- not a code bug, and confirmed transient in practice: the same commit's diagnostic captured the exact error text once, then a subsequent CI run (same commit, same code) passed cleanly with no changes at all, showing the condition doesn't persist. Fixed by adding `_spawn_retrying_eacces` (`src/artifacts.jl`): a small bounded retry (6 attempts, exponential backoff from 0.25s) applied to both `x13_binary_available()`'s trial invocation and `_run_capture`'s real spawn (`src/run.jl`) -- retries only on a permission-denied `IOError`, anything else propagates immediately. An extended diagnostic round (raw Windows error code, a `chmod(path, 0o755)` mitigation attempt) was prepared to go further if the plain retry hadn't been enough, but the retry alone was sufficient once actually exercised on real CI -- both Windows jobs passed cleanly with it in place.

All 6 test matrix jobs plus `Documentation` are confirmed green on real CI as of this section -- the first time this package has had a fully clean CI run across every platform and Julia version it targets.

---

## Part 2 — native Julia engine (deferred, not abandoned)

| # | Status | What | Needs | Reference points |
|---|---|---|---|---|
| S.1 | Not started | X-11 filters (Henderson moving averages, iterative seasonal factors) | Julia's standard convolution/filtering primitives only — this is the one native-engine stage genuinely independent of everything else in this chapter | Census Bureau X-11 method documentation; Ladiray & Quenneville, *Seasonal Adjustment with the X-11 Method* (2001); real D10/D11/D12 ground truth now available from `x13prebuilt` directly (above), a categorically stronger verification target than most native-engine work gets |
| S.2 | Not started | RegARIMA — calendar regressors (trading-day effects, Easter) | TSAnalytics.jl Stage 8.3, W.0 | X-13ARIMA-SEATS Reference Manual (US Census Bureau, 2009) |
| S.3 | Not started | Automatic outlier detection (additive, level-shift, transitory), TRAMO-style | S.2, TSAnalytics.jl Stage 2.4 | Gómez & Maravall's TRAMO/SEATS papers |
| S.4 | Not started | The full X-13 pipeline, orchestrating S.1–S.3 | S.1, S.2, S.3 | Census Bureau Reference Manual |
| S.5 | Not started | SEATS canonical decomposition, Wiener-Kolmogorov filters | TSAnalytics.jl Stage 6.8, Stage 6.3, S.2 | Gómez & Maravall (1996) — still the hardest single piece across both this package and the broader TSAnalytics.jl roadmap, even with real binary output now available to check against |

### S.1's own verified starting point — the Henderson filter formula

Already confirmed from two independent sources (a working reference
implementation and a US patent document, cross-checked against each
other):
```
For a symmetric Henderson filter of length n = 2m+1:
  m1 = (m+1)^2,  m2 = (m+2)^2,  m3 = (m+3)^2
  d  = 8*(m+2)*(m2-1)*(4*m2-1)*(4*m2-9)*(4*m2-25)
  w[j] = 315 * (m1-j^2) * (m2-j^2) * (m3-j^2) * (3*m2-11*j^2-16) / d
```
Real, hand-checkable target: the 5-term filter's published weights are
`(-0.073, 0.294, 0.558, 0.294, -0.073)`. The defining mathematical
property (exact reproduction of any cubic polynomial) is itself a real,
reference-free test — verify this before anything else once S.1 starts.

---

## The critical path

```
W.0 ──► W.2 ──► W.3 ──► W.4
W.1 (independent, needed by W.2 but can build in parallel)

S.1 (fully independent of the rest of Part 2 — can start any time)
S.2 needs W.0 + TSAnalytics.jl 8.3, then unblocks S.3 and S.5 both
```

**W.0 and S.2 are the two real bottlenecks of this whole package** —
nearly everything downstream, in both parts, eventually depends on one
or the other.

---

## How this gets built

One task at a time, strictly in the order above — each task gets its
own handoff document (verified references, API design, test cases,
honest gaps flagged explicitly) before implementation starts, matching
TSAnalytics.jl's own development standard throughout. Given Part 1's
different verification philosophy (above), each Part 1 handoff should
say plainly that its "R and Python" check is really "matches the
binary directly," rather than imply the traditional dual-independent-
reimplementation standard applies where it doesn't.

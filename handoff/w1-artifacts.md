# Handoff: Task W.1 — Binary Artifact Management for `x13prebuilt`

For a fresh Claude Code session picking this up with no prior context.
Read `CLAUDE.md` and `development-sequence.md` in full first. **This
task is independent of W.0** — the roadmap's own dependency diagram
shows them as parallel tracks, both feeding into W.2. If W.0 isn't
finished yet, that's not a blocker for starting this.

## Where this fits

- **Depends on:** nothing internal.
- **Already partially done, not starting from scratch**: `Artifacts.toml`
  exists in the repo root with real, computed SHA256 hashes and
  verified download URLs for all five platform binaries, pinned to
  commit `61c4043949f43c1ea5ad0fbbc7b6c11fc5073d19`. `tools/generate_artifacts.jl`
  exists and is ready to run. **What's not done**: actually running that
  script (needs a real Julia runtime with network access — this was
  written in an environment without one), and — found only while
  preparing this handoff, not yet designed around — **macOS needs
  materially different handling than Linux or Windows.**

---

## 1. New finding: the three platforms are not structurally equivalent

Checked directly, not assumed, by extracting each archive:

**Linux** (already confirmed working in this project): a single,
statically-linked ELF executable, no dependencies. `x13ashtml`, run
directly.

**Windows**: a zip extracting to `x13ashtml/x13ashtml.exe` — a plain
subfolder-then-executable structure. Also contains a bonus:
`x13ashtml/Testairline.spc`, an **official Census Bureau test spec
file** bundled directly in the distribution — worth using as an
additional verification fixture in section 4, not just this project's
own airline-series test.

**macOS**: a tar.gz extracting to:
```
x13ashtml/
  bin/x13ashtml
  lib/libgfortran.5.dylib
  lib/libquadmath.0.dylib
  lib/libgcc_s.1.dylib
```
**This is not a single-file binary** — `bin/x13ashtml` is
dynamically linked against the three `.dylib` files in the sibling
`lib/` directory. Extracting just the executable and discarding the
rest will produce a binary that "installs" successfully but fails to
run. **The artifact resolution must preserve this directory structure
intact** and either rely on the binary's own relative
`@executable_path/../lib` linking (common convention for exactly this
layout, but needs confirming on macOS specifically once that platform
is actually testable) or set `DYLD_LIBRARY_PATH` explicitly when
invoking it.

## 2. What's already real and computed — reuse, don't regenerate

From `Artifacts.toml`, already verified in a prior session (confirmed
against the actual files, not transcribed from anywhere):
```
Linux x86_64:    c4496c94985984ae9acdcf7fa164197a91fa52c2690b1e1a456312b96920f652
Linux armv7l:    c0fa23a2ee4683d1c370c1b7916fbcf7d22b631135ecfc350b40b5ae12762864
Windows (zip):   360def33266deea0640b75b998ae62da5aaeb174b1b284da94dcfe1f1fb0bb83
macOS x86_64:    99feaaab6c0ccbbc47b736310c69ff88127b1d99b4b2ce851db5aee844fe9b2c
macOS arm64:     99feaaab6c0ccbbc47b736310c69ff88127b1d99b4b2ce851db5aee844fe9b2c
```
The two macOS hashes being identical was already flagged as needing a
human glance (plausibly a genuine universal binary, not independently
confirmed) — still open, worth resolving as part of this task since
it directly affects whether one artifact entry or two is correct.

---

## 3. Proposed API

```julia
x13_binary_path() -> String   # resolves to the correct executable for the running platform
x13_binary_available() -> Bool  # true if resolution + a trivial invocation both succeed
```

Design notes:
- **`x13_binary_path()` must return the actual invokable path, not just
  the artifact directory** — for Linux this is trivial
  (`artifact"x13ashtml"`), for Windows it's `.../x13ashtml/x13ashtml.exe`,
  for macOS it's `.../x13ashtml/bin/x13ashtml` **with the sibling `lib/`
  directory confirmed present** (assert this explicitly and throw a
  clear error if it's missing, rather than let a broken extraction fail
  silently at first actual use in W.3).
- **`x13_binary_available()`** exists specifically so W.3 and W.4 can
  give a clear, actionable error ("the x13prebuilt binary could not be
  resolved for this platform — run `Pkg.instantiate()`" or similar)
  instead of a cryptic subprocess failure three layers deep.

---

## 4. Comprehensive test matrix

```julia
using Test

@testset "artifact resolution -- path exists and is executable" begin
    path = x13_binary_path()
    @test isfile(path)
    @test Sys.isexecutable(path)
end

@testset "macOS specifically -- lib/ directory present alongside bin/" begin
    if Sys.isapple()
        binpath = x13_binary_path()
        libdir = joinpath(dirname(dirname(binpath)), "lib")
        @test isdir(libdir)
        @test isfile(joinpath(libdir, "libgfortran.5.dylib"))
        @test isfile(joinpath(libdir, "libquadmath.0.dylib"))
        @test isfile(joinpath(libdir, "libgcc_s.1.dylib"))
    end
end

@testset "the resolved binary actually runs" begin
    @test x13_binary_available()
    # a bare invocation with no args should produce the expected
    # "Must specify either an input specification file" message and
    # exit cleanly, matching the behavior already confirmed manually
    # for the Linux binary during this project's design phase
end

@testset "end-to-end: resolved binary reproduces already-verified output" begin
    # run handoff/verification/airline_baseline/airline_official.spc through the
    # artifact-resolved binary (not a manually-placed copy) and confirm
    # the resulting D10/D11/D12 tables match the values already
    # committed in that same directory -- this is the test that
    # actually confirms artifact resolution works, not just that a
    # file exists at some path
end

@testset "bonus: official Census Bureau test spec runs cleanly" begin
    # x13ashtml/Testairline.spc, bundled in the Windows distribution --
    # a genuine Census Bureau test fixture, worth running once
    # regardless of platform if extractable, as an independent sanity
    # check beyond this project's own test cases
end
```

---

## 4a. A real connection to W.0, found by reviewing its actual implementation

W.0's capstone test needed to run the real binary to prove its
custom-regressor mechanism, but no proper binary resolution existed
yet — so it improvised: a hardcoded path guess, gated behind a
Windows+WSL check, invoking the Linux binary through WSL rather than
the native Windows executable. Its own comments say plainly: *"W.1/W.3
will make binary discovery a first-class, portable mechanism — this is
a deliberately minimal, test-local stand-in, not a preview of that
design."* Take that as a direct requirement, not just context:

**Once `x13_binary_path()` exists, go back and refactor W.0's capstone
test to call it, removing the hardcoded path guess and the
WSL-specific branch entirely.** That stand-in should not persist once
this task provides the real mechanism — leaving it in place would mean
two different, inconsistent binary-resolution strategies coexisting in
the same codebase.

**Also worth stating plainly, confirmed by this same review**: the
devcontainer is a Linux environment, even when the host machine is
Windows. Locally, inside it, only the Linux artifact path can actually
be exercised directly — Windows and macOS genuinely need the CI matrix
to confirm (already required in section 5 below, now grounded in a
concrete reason rather than general caution). If cross-platform testing
is ever wanted from a real Windows host directly (outside the
devcontainer), the WSL-invocation pattern W.0's capstone test already
worked out is a reasonable, reusable technique for that specific
case — worth keeping in mind as a documented option, not something to
throw away just because the hardcoded path around it gets removed.

---

## 5. What to do with this

1. **Run `tools/generate_artifacts.jl` for real** — this needs an
   actual Julia runtime with network access, which is now available
   given development has moved into the real devcontainer. This fills
   in the `git-tree-sha1` placeholders currently in `Artifacts.toml`.
   **Verify the SHA256 check inside that script actually matches before
   proceeding** — it's designed to error loudly on a mismatch rather
   than continue silently.
2. Resolve the macOS identical-hash question (section 2) — confirm via
   the source repo directly whether this is a genuine universal binary
   or a repo issue, before trusting both platform entries.
3. Implement `x13_binary_path()`/`x13_binary_available()` in
   `src/artifacts.jl` (already stubbed), handling all three platform
   layouts from section 1 — **not just Linux**, since that's the one
   layout already implicitly assumed correct from prior manual testing.
4. Run the test matrix in section 4. The devcontainer is Linux-based —
   Windows/macOS-specific tests will need the CI matrix (already
   configured in `.github/workflows/CI.yml` across all three OSes) to
   actually confirm, not this local environment alone. Don't mark this
   task complete based on Linux passing only.
5. **Refactor W.0's capstone test** (section 4a) to use `x13_binary_path()`
   once it exists, removing its hardcoded path guess and WSL-specific
   branch — this is a required follow-up, not optional cleanup.
6. Update `development-sequence.md`'s W.1 row, noting explicitly which
   platforms were actually confirmed (local Linux vs. CI-confirmed
   Windows/macOS) rather than a single blanket "done."

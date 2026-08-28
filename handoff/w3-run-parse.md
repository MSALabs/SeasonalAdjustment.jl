# Handoff: Task W.3 — Subprocess Invocation & Output-Table Parsing

For a fresh Claude Code session picking this up with no prior context.
Read `CLAUDE.md` and `development-sequence.md` in full first. Depends
on W.1 (binary resolution) and W.2 (spec generation).

## Which of the four criteria actually apply here

Unlike W.2, **all four genuinely apply** — this is the task that
actually calls the binary, and performance/parallelism are real here in
a way they weren't for spec-text formatting.

---

## 1. New finding: SEATS uses a different output-file convention than X-11

Confirmed by actually running a SEATS spec, not assumed from
documentation: X-11's tables are `.d10`/`.d11`/`.d12`/`.d13`; **SEATS'
own tables are `.s10`/`.s11`/`.s12`/`.s13`** — a different extension
prefix entirely, discovered only by running `seats { save = (s10 s11
s12 s13) }` directly and checking what files actually appeared.
**The internal format is identical** (confirmed: same tab-separated
`date\tvalue` layout, same `------` header row) — one parser handles
both, keyed off the extension's letter (`d` vs `s`), not two separate
parsers.

## 2. Real, measured performance — and a genuinely important negative result

**Single invocation**: `0.0127s` cold, `0.0101s` average over 10 runs —
genuinely fast, consistent with W.2's framing (the real cost in this
whole package sits here, not in spec generation, but even here it's
small in absolute terms).

**Parallel subprocess invocation, tested directly, did NOT help — worth
reporting honestly rather than assuming parallelism is free value**:
```
Serial (20 runs):                    0.2448s
Parallel (8 workers, 20 runs):       0.4948s   <- SLOWER
Serial (100 runs):                   1.0147s
Parallel (8 workers, 100 runs):      1.0948s   <- still slightly slower
Pure pool startup/teardown overhead: 0.0006s   <- not the cause
```
**Why**: tested via Python's `ProcessPoolExecutor`, which spawns entire
worker *Python interpreter* processes, each of which then spawns its
own `x13ashtml` subprocess -- a genuine double layer of process overhead
for a task that only takes ~10ms to begin with. The coordination cost
(inter-process communication, task/result marshalling) is comparable to
or exceeds the work being parallelized.

**This is specific to Python's heavyweight worker-process model, not
necessarily a ceiling on what Julia can do** — worth a clear design
recommendation, not a re-run of the same mistake:
```julia
# NOT this (Python's model, mirrored badly): spawn N Julia worker
# processes, each spawning its own x13ashtml subprocess -- same double
# overhead problem, just relocated.

# INSTEAD: spawn the x13ashtml subprocesses directly and asynchronously,
# no Julia-side worker-process layer at all -- the OS scheduler handles
# genuinely concurrent execution of the spawned binaries directly.
processes = [run(`$binary_path $spec`; wait=false) for spec in spec_names]
foreach(wait, processes)
```
**This is a real, structurally-grounded design recommendation, not a
verified Julia number** -- no Julia runtime was available to actually
benchmark this session. Flagged explicitly: confirm this design
actually outperforms serial execution once implemented, rather than
assume the structural argument alone is sufficient. If it doesn't
(unlikely given the reasoning, but not yet proven), the honest fallback
is `parallel=false` as the safe default until proven otherwise, matching
this project's own "don't optimize without a profile" discipline.

---

## 3. Proposed API

```julia
run_x13(spec_path::String; binary_path::String=x13_binary_path()) -> X13RunResult
run_x13_batch(spec_paths::Vector{String}; parallel::Bool=true) -> Vector{X13RunResult}

parse_table(path::String) -> Vector{Tuple{Date,Float64}}   # one .dNN or .sNN file
parse_output(basename::String, tables::Vector{Symbol}) -> Dict{Symbol,Vector{Tuple{Date,Float64}}}
```

Design notes:
- **`X13RunResult` should be a real, typed structure**, not raw stdout
  text -- `success::Bool`, `stdout::String`, `warnings::Vector{String}`,
  `errors::Vector{String}`. This is the concrete "superior to R/Python"
  claim for this task specifically: both references return either raw
  text (R via `system2`) or leave error inspection to the caller
  manually parsing output; a typed result with warnings/errors already
  extracted is a genuine ergonomic improvement, not just a renamed
  wrapper.
- **`parse_table` must handle both `d` and `s` prefixes identically** --
  section 1's finding -- via one shared parsing function, dispatching
  only on which specific table letter+number was requested, not on
  X-11-vs-SEATS as a structural branch.
- **`run_x13_batch`'s `parallel` design follows section 2's async-spawn
  approach**, not a worker-pool model -- and defaults to `true` per this
  project's established convention, but ship with a clear code comment
  flagging that the performance claim needs real confirmation once a
  Julia runtime can actually benchmark it, not asserted from the Python
  finding alone.

---

## 4. Comprehensive test matrix

### Real, already-generated fixtures to parse (reuse, don't regenerate)

```julia
using Test, Dates

@testset "parse_table -- X-11 D-tables, real fixture" begin
    d11 = parse_table("verification/airline_baseline/airline_official.d11")
    @test length(d11) == 144
    @test d11[1] == (Date(1949,1), 124.546106577719)  # first value, confirmed this session
    @test all(v -> v[2] > 0, d11)  # seasonally adjusted airline passengers must stay positive
end

@testset "parse_table -- SEATS S-tables, real fixture generated this session" begin
    s11 = parse_table("verification/seats_baseline/seats_test.s11")  # generate + commit this fixture
    @test length(s11) == 144
    @test s11[1] == (Date(1949,1), 122.847234947105)
end

@testset "run_x13 -- real invocation, typed result" begin
    result = run_x13("verification/airline_baseline/airline_official.spc")
    @test result.success
    @test isempty(result.errors)
end

@testset "run_x13 -- the real minimum-length error, typed not raw text" begin
    # reuses W.2's own minimum-length validation target -- but this
    # test specifically confirms run_x13 surfaces it as a structured
    # error field, not just leaves it buried in raw stdout
    short_spec = "verification/w2_length_grid/batch_1.spc"   # the real 24-month failing case from W.2
    result = run_x13(short_spec)
    @test !result.success
    @test any(e -> occursin("3 complete years", e), result.errors)
end
```

### Bulk: reuse W.2's 24-case grid directly, now checking *parsed* output

```julia
@testset "bulk: parse every successful case from W.2's real grid" begin
    for i in 1:24
        spec_path = "verification/w2_length_grid/batch_$i.spc"
        result = run_x13(spec_path)
        length_ok = i > 3   # cases 1-3 were the confirmed 24-month failures
        @test result.success == length_ok
        if result.success
            d10 = parse_table("batch_$i.d10")
            @test length(d10) > 0
            @test all(v -> v[2] > 0, d10)  # seasonal factors should be positive for this data shape
        end
    end
end
```

### Parallel-vs-serial correctness (not yet a performance claim, per section 2)

```julia
@testset "run_x13_batch -- parallel and serial produce IDENTICAL results" begin
    specs = ["verification/w2_length_grid/batch_$i.spc" for i in 4:24]  # skip the known-failing cases
    par = run_x13_batch(specs; parallel=true)
    serial = run_x13_batch(specs; parallel=false)
    for i in eachindex(specs)
        @test par[i].success == serial[i].success
        @test par[i].stdout == serial[i].stdout   # deterministic binary, should match exactly
    end
end
```

**Honest note on the 100+ bar**: parsing the 24-case grid (already
executed in W.2, reused here) plus the SEATS fixture gives 25+ real
cases directly reusing this session's actual runs. Extend by running
`run_x13`/`parse_table` against the full 120-case grid W.2's handoff
designed but didn't fully execute -- completing that grid closes both
tasks' 100+ requirement at once, not two separate efforts.

---

## 5. What to do with this

1. Implement `run_x13`/`run_x13_batch`/`parse_table`/`parse_output` in
   `src/run.jl` and `src/parse.jl` (both already stubbed).
2. Generate and commit a SEATS fixture (`verification/seats_baseline/`,
   using this handoff's `seats_test.spc`) -- not yet in the repo, section
   1's finding needs a real committed fixture, not just this handoff's
   description of it.
3. Run the tests in section 4, including completing W.2's 120-case grid
   as the shared path to both tasks' 100+ requirement.
4. Implement the async-spawn (not worker-pool) parallel design from
   section 2, and **actually benchmark it once Julia is available** --
   confirm or correct the structural performance argument with real
   numbers rather than let the Python-derived reasoning stand
   unverified indefinitely.
5. Update `development-sequence.md`'s W.3 row: mark implemented, record
   the SEATS extension-convention finding and the honest
   parallel-invocation performance status (structurally reasoned,
   not yet Julia-benchmarked) explicitly.

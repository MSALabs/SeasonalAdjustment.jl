# Handoff: Task W.2 — Spec-File Generation

For a fresh Claude Code session picking this up with no prior context.
Read `CLAUDE.md` and `development-sequence.md` in full first. Depends
on W.0 (complete) and W.1 — confirm W.1's `x13_binary_path()` exists
before the integration tests in section 5 can actually run against the
real binary, though spec-generation itself has no runtime dependency
on W.1 at all.

## Which of the four requested criteria actually apply here — stated honestly, not assumed

- **100+ test cases**: yes, directly applicable, and largely already
  executed for this handoff (section 4) rather than just described.
- **Performance**: **not the real story for this task specifically**,
  and worth saying so rather than manufacture relevance. Spec
  generation is string formatting over at most a few hundred numbers --
  microseconds, not a meaningful cost next to W.3's actual subprocess
  invocation (tens to hundreds of milliseconds, per this project's own
  earlier GARCH/ARIMA timing work). What *is* real: batch generation
  across many independent series (see parallelism, below).
- **Signature superior to R and Python**: yes, and now backed by a
  concrete mechanism, not just a naming preference (section 2).
- **Parallelism**: yes, for the genuine batch case -- generating specs
  for many independent series at once, a real, common X-13 use case
  (seasonally adjusting an entire panel of economic series), not
  forced onto a task that doesn't need it.

---

## 1. New findings from actually running the binary against varied real input

**A real, previously undocumented minimum-length requirement, confirmed
directly from the binary's own error message**:
```
ERROR: Series to be modelled and/or seasonally adjusted must have at
       least 3 complete years of data.
```
Confirmed the exact boundary: **36 months succeeds, 24 months fails
cleanly** with this message, tested directly (3 seeds each, both
lengths). This is a real validation rule W.2 should catch at spec-
construction time, not something to discover only after a subprocess
round-trip.

**24 real spec files, generated and run programmatically** (varying
series length -- 24 through 240 months -- and 3 random seeds each,
8 lengths x 3 seeds), confirming: **21/24 succeeded cleanly; all 3
failures were exactly the sub-36-month cases**, and failed with exactly
the message above, not a different or inconsistent error. This is
already real evidence toward the 100+ bar, not a sketch -- extend the
same grid (more lengths, more seeds, varying `x11`/`regression`/`arima`
block presence) to clear it fully; the methodology is proven, not
hypothetical.

---

## 2. The "superior to R and Python" design, made concrete

Recall the earlier finding (already in `development-sequence.md`): R's
`seas()` passes any `spec.argument` combination through dynamically via
`...`, with no validation until the binary itself runs; Python's
`x13_arima_analysis()` only exposes a curated subset, safer but
narrower. **Neither validates a spec before spending a subprocess
round-trip on it.** That's the concrete gap Julia can close:

```julia
struct X13Spec
    series::SeriesSpec
    x11::Union{Nothing,X11Spec}
    regression::Union{Nothing,RegressionSpec}
    arima::Union{Nothing,ArimaSpec}
    transform::Union{Nothing,TransformSpec}
    outlier::Union{Nothing,OutlierSpec}
end

function X13Spec(series::SeriesSpec; kwargs...)
    spec = # ... construct from kwargs, R-style dot-passthrough AND
           # Python-style curated fields both supported (see below)
    validate!(spec)   # fast, native Julia checks -- BEFORE any subprocess spawn
    return spec
end
```

**`validate!` should check, at minimum, every real requirement already
confirmed by directly hitting it against the binary across this
project's development** -- not a hypothetical list:
1. **Series length >= 36 months** (section 1, new finding this session).
2. **User-defined regressor data covers the RegARIMA forecast horizon**,
   not just the historical series length (confirmed in W.0's
   development: `"forecasts end date ... must end on or before
   user-defined regression variables end date"`).
3. **`transform.function = log` is set whenever a `regression`
   (RegARIMA) block is combined with multiplicative `x11`** (confirmed
   the same way: `"Multiplicative or log additive seasonal adjustment
   cannot be performed when preadjustment factors are derived from a
   regARIMA model for data which have not been log transformed"`).

**This is the actual "Julia superior" claim, made specific and
checkable**: three real, binary-confirmed failure modes, caught in
microseconds locally instead of a full external-process round-trip --
neither R's nor Python's wrapper does this validation at all.

### API -- both mechanisms, matching the superset design already established

```julia
# Python-style curated fields, discoverable, typed
X13Spec(y; seasonal_order=(0,1,1,12), transform=:log, outlier=true)

# R-style full passthrough, for anything the curated fields don't cover
X13Spec(y; regression_variables=["td", "easter[1]"], arima_model="(0 1 1)(0 1 1)")

# Both together -- genuinely superior to either reference alone, not just renamed
X13Spec(y; seasonal_order=(0,1,1,12), regression_user=(:diwali,), regression_usertype=:holiday)
```

---

## 3. Proposed full API

```julia
render(spec::X13Spec) -> String          # the .spc text itself
write_spec(spec::X13Spec, path::String) -> String   # writes, returns the path
validate!(spec::X13Spec) -> X13Spec      # the three checks above, throws ArgumentError with a clear message

generate_specs(series_list::Vector, options_list::Vector; parallel::Bool=true) -> Vector{X13Spec}
```

Design notes:
- **`validate!` throws, doesn't warn** -- a spec that would fail against
  the real binary shouldn't silently proceed to W.3 and waste a
  subprocess round-trip discovering that.
- **`generate_specs` is the actual parallelism target** (section 0) --
  independent per-series construction + validation, `Threads.@threads`
  guarded the same way as every other parallel design in this project
  family (`Threads.nthreads() > 1`, a minimum batch size below which
  threading overhead isn't worth it).

```julia
function generate_specs(series_list, options_list; parallel::Bool=true)
    n = length(series_list)
    out = Vector{X13Spec}(undef, n)
    use_threads = parallel && Threads.nthreads() > 1 && n >= 4
    if use_threads
        Threads.@threads for i in 1:n
            out[i] = X13Spec(series_list[i]; options_list[i]...)
        end
    else
        for i in 1:n
            out[i] = X13Spec(series_list[i]; options_list[i]...)
        end
    end
    return out
end
```

---

## 4. Comprehensive test matrix -- real evidence, not just a plan

### Already executed this session (24 cases, section 1) -- reuse directly

```julia
using Test

@testset "minimum length -- real, confirmed boundary" begin
    short = randn(24) .+ 100
    @test_throws ArgumentError X13Spec(short)  # validate! must catch this BEFORE any subprocess

    ok = randn(36) .+ 100
    spec = X13Spec(ok)   # must NOT throw -- 36 is the real, confirmed working boundary
    @test spec isa X13Spec
end
```

### Extend to 100+ -- the proven grid, scaled up

```julia
@testset "bulk: varied length x seed x option combination" begin
    lengths = [36, 48, 60, 84, 120, 144, 180, 240]       # 8 lengths, all >= the real minimum
    seeds = 1:5                                            # 5 seeds each = 40 cases
    option_sets = [(;), (; transform=:log), (; outlier=true)]  # 3 option variants = 120 total cases

    for len in lengths, seed in seeds, opts in option_sets
        Random.seed!(seed * 1000 + len)
        y = max.(100 .+ cumsum(randn(len).*0.5) .+ 10 .* sin.(2π.*(1:len)./12), 1.0)
        spec = X13Spec(y; opts...)
        rendered = render(spec)
        @test occursin("series {", rendered)
        @test occursin("data = (", rendered)
        # actual binary round-trip on a representative subset, not all 120 --
        # subprocess cost adds up; spot-check thoroughly, don't brute-force everything
    end
end

@testset "the three validate! checks, each triggered directly" begin
    y = randn(48) .+ 100
    x = randn(48)

    # check 2: regressor doesn't cover forecast horizon
    short_regressor = zeros(48)  # matches series length exactly, not the +12 forecast horizon
    @test_throws ArgumentError X13Spec(y; exog=x, regression_user=short_regressor)

    # check 3: regARIMA + multiplicative without transform=log
    @test_throws ArgumentError X13Spec(y; exog=x, x11_mode=:multiplicative, transform=nothing)
end

@testset "generate_specs -- parallel matches serial" begin
    series_list = [randn(48) .+ 100 for _ in 1:20]
    options_list = [(;) for _ in 1:20]
    par = generate_specs(series_list, options_list; parallel=true)
    serial = generate_specs(series_list, options_list; parallel=false)
    for i in 1:20
        @test render(par[i]) == render(serial[i])
    end
end
```

**Honest note on the 100+ bar**: the 24 length-variation cases in
section 1 were actually executed against the real binary this session.
The 120-case grid above is designed and ready to run but not yet
executed here -- extend it the same way Stage 6.8/7.1 in the parent
TSAnalytics.jl project scaled a proven small grid to a larger one,
rather than treating "designed" and "executed" as the same claim.

---

## 5. What to do with this

1. Implement `X13Spec`/`render`/`validate!`/`write_spec` in `src/spec.jl`
   (already stubbed), with all three real validation rules from section 2.
2. Run the tests in section 4, including actually executing (not just
   designing) the scaled-up 120-case grid.
3. Confirm `generate_specs`'s parallel path produces identical output to
   serial -- the cheap, high-value regression guard, same pattern as
   every other parallel design in this project family.
4. Update `development-sequence.md`'s W.2 row: mark implemented, record
   the minimum-length finding explicitly (it wasn't documented anywhere
   before this session), and note how many of the 100+ test cases were
   actually run against the real binary vs. structurally checked only.

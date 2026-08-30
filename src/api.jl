# src/api.jl
#
# W.4 -- the idiomatic Julia x13(...) entry point, closing out Part 1.
# See handoff/w4-api.md for the verified references (in particular: the
# TSAnalytics.jl abstract-decomposition-type question CLAUDE.md flagged,
# checked directly and resolved -- no shared type exists, so X13Result
# stays a plain struct) and the test plan this file's tests implement.

"""
    X13Result

The result of [`x13`](@ref) -- `seasonally_adjusted`/`trend`/
`seasonal_factors`/`irregular` are the parsed D11/D12/D10/D13 (or, for a
SEATS spec, S11/S12/S10/S13) tables, matching README.md's own
already-published field names exactly. `residuals` (the D13-adjacent
regARIMA residuals, from `estimate { save = (rsd) }` -- a distinct spec
block from the decomposition tables, since residuals are a property of
the underlying model fit) and `udg` (the binary's own "user diagnostics"
key-value dump, requires the `-S` invocation flag -- see [`parse_udg`](@ref))
are always populated too, matching R's `seas()` always making this
information available rather than requiring an opt-in. `spec`/
`run_result` are the actual [`X13Spec`](@ref)/[`X13RunResult`](@ref) the
run used -- `x13` returns a typed, introspectable result, not a black
box (`run_result` carries the binary's real stdout/warnings even on
success).

Deliberately a plain `struct`: checked directly against TSAnalytics.jl's
actual source (see handoff/w4-api.md) that `ClassicalDecomposition` and
`STLDecomposition` share no common abstract type to subtype -- the
open question CLAUDE.md flagged at project scaffolding, resolved here,
not re-deferred.
"""
struct X13Result
    observed::Vector{Float64}
    seasonally_adjusted::Vector{Float64}
    trend::Vector{Float64}
    seasonal_factors::Vector{Float64}
    irregular::Vector{Float64}
    residuals::Vector{Float64}
    udg::Dict{String,String}
    dates::Vector{Date}
    spec::X13Spec
    run_result::X13RunResult
end

"""
    x13(y; index=tsindex(y), start=nothing, maxorder=nothing, maxdiff=nothing,
           outlier=false, trading=false, kwargs...) -> X13Result

The idiomatic entry point: builds an [`X13Spec`](@ref), runs it via
[`run_x13`](@ref), and returns a parsed, typed [`X13Result`](@ref).
`maxorder`/`maxdiff`/`trading`/`outlier` are named explicitly for
discoverability, matching `statsmodels.tsa.x13.x13_arima_analysis`'s own
parameter names (Python-style curated ergonomics); anything else --
`transform`, `x11_mode`, `seats`, `regression_variables`, `arima_model`,
`regression_user`, ... -- flows straight through `kwargs...` into
`X13Spec` unchanged (R-style full passthrough). Together this is the
concrete "genuine superset of R's `seas()` and Python's
`x13_arima_analysis()`" signature CLAUDE.md requires, not just a naming
exercise -- see handoff/w4-api.md section "The API design requirement."

`y` accepts anything `tsvalues` does. `index` (defaulting to
`tsindex(y)`, which is `nothing` for a plain vector and most sliced
containers -- pass it explicitly the same way other TSAnalytics.jl
functions ask for `index=`) is used to infer `start` when neither it
nor an explicit `start=(year, period)` is given; falls back to
`X13Spec`'s own `(1980, 1)` default otherwise (only `result.dates`'
labeling is affected either way, not the computed values).

`period` (`12` monthly / `4` quarterly, matching [`X13Spec`](@ref)'s own
default and validation -- see [`validate!`](@ref)) controls both how
`start` is inferred from `index` (a quarter number 1-4, derived from the
inferred date's month, when `period=4`) and how output tables/residuals
are parsed back (`YYYYQQ` vs `YYYYMM`, see [`parse_table`](@ref)).

Throws `ArgumentError` immediately if the spec is invalid (see
[`validate!`](@ref)) -- before any subprocess is spawned -- and throws
an `ErrorException` carrying the binary's own error text if the run
itself fails, rather than returning a half-populated result.

`save` is deliberately not accepted here (see handoff/w4-api.md) --
`x13`'s contract is a fully-populated `X13Result`, which needs all four
tables; use [`X13Spec`](@ref)/[`run_x13`](@ref)/[`parse_output`](@ref)
directly for a custom, partial table selection. `residuals` is rejected
the same way and for the same reason -- `x13()` always requests it (see
[`X13Result`](@ref)). For a non-SEATS spec, `:d8` (final unmodified SI
ratios) is ALSO always saved alongside D10-D13 (W.6) -- not one of
`X13Result`'s own fields, but present on disk so [`monthplot`](@ref)'s
SI-ratio overlay never needs to re-run for an `x13()`-produced result.
"""
function x13(
    y;
    index = tsindex(y),
    start::Union{Nothing,Tuple{Int,Int}} = nothing,
    period::Int = 12,
    maxorder::Union{Nothing,Tuple{Int,Int}} = nothing,
    maxdiff::Union{Nothing,Tuple{Int,Int}} = nothing,
    outlier::Bool = false,
    trading::Bool = false,
    save = nothing,
    residuals = nothing,
    kwargs...,
)
    save === nothing || throw(ArgumentError(
        "x13() doesn't accept `save` -- it always needs the full D10-D13/S10-S13 " *
        "quartet to populate an X13Result. For a custom, partial table selection, use " *
        "X13Spec/run_x13/parse_output directly instead.",
    ))
    residuals === nothing || throw(ArgumentError(
        "x13() doesn't accept `residuals` -- it always requests them to populate " *
        "X13Result.residuals. For a custom spec, use X13Spec/run_x13/parse_output " *
        "directly instead.",
    ))

    yv = Float64.(collect(tsvalues(y)))
    resolved_start = if start !== nothing
        start
    elseif index !== nothing
        period == 12 ? (Dates.year(index[1]), Dates.month(index[1])) :
            (Dates.year(index[1]), (Dates.month(index[1]) - 1) ÷ 3 + 1)
    else
        nothing
    end

    # W.6: :d8 (final unmodified SI ratios) is always saved alongside the
    # D10-D13 quartet for a non-SEATS spec -- SEATS has no D8-equivalent
    # table at all, confirmed by X-11's own SI-ratio concept simply not
    # applying to SEATS' ARIMA-model-based decomposition. This is what lets
    # `monthplot`'s SI-ratio overlay avoid a re-run for any `x13()`-produced
    # result; a hand-built `X13Spec`/`run_x13` run still needs `series(r,
    # :d8)`'s own automatic re-run (or an explicit `save=` including `:d8`).
    is_seats = get(kwargs, :seats, false)
    default_save = is_seats ? nothing : [:d10, :d11, :d12, :d13, :d8]

    spec = resolved_start === nothing ?
        X13Spec(yv; period = period, maxorder = maxorder, maxdiff = maxdiff, outlier = outlier, trading = trading, residuals = true, save = default_save, kwargs...) :
        X13Spec(yv; start = resolved_start, period = period, maxorder = maxorder, maxdiff = maxdiff, outlier = outlier, trading = trading, residuals = true, save = default_save, kwargs...)

    spec_path = write_spec(spec, joinpath(mktempdir(), "series.spc"))
    run_result = run_x13(spec_path; udg = true)
    run_result.success || throw(ErrorException(
        "x13() run failed: " * join(run_result.errors, "; "),
    ))

    tables = spec.seats ? (:s10, :s11, :s12, :s13) : (:d10, :d11, :d12, :d13)
    parsed = parse_output(run_result, collect(tables); period = spec.period)
    seasonal_factors = last.(parsed[tables[1]])
    seasonally_adjusted = last.(parsed[tables[2]])
    trend = last.(parsed[tables[3]])
    irregular = last.(parsed[tables[4]])
    dates = first.(parsed[tables[1]])
    residuals_vec = last.(parse_table(joinpath(run_result.dir, "$(run_result.basename).rsd"); period = spec.period))
    udg = parse_udg(joinpath(run_result.dir, "$(run_result.basename).udg"))

    return X13Result(
        yv, seasonally_adjusted, trend, seasonal_factors, irregular, residuals_vec, udg,
        dates, spec, run_result,
    )
end

"""
    static(result::X13Result) -> X13Spec

Resolves an "automatic" spec's `:auto`/`automdl`/`outlier` choices into
an explicit, reproducible [`X13Spec`](@ref) -- matching R's `seasonal`
package's own `static()`. Reads exclusively from `result.udg`, never
stdout/HTML. Resolves three things, each confirmed directly against the
real binary this session (`handoff/w4-addendum-udg-residuals-static.md`
plus this session's own follow-up verification, which corrected one gap
in that handoff -- see point 3):

1. **ARIMA order**: `.udg`'s `arimamdl` field (e.g. `"(0 1 1)(0 1 1)"`)
   is the model actually used, whether from `automdl` or already
   explicit; used verbatim as `arima_model`, with `automdl`/`maxorder`/
   `maxdiff` cleared.
2. **Automatically detected outliers**: `.udg` keys of the form
   `AutoOutlier\$AO1951.May` name each one. Confirmed directly that the
   key with the `AutoOutlier\$` prefix stripped (`AO1951.May`) is itself
   a valid `regression_variables` entry -- fed back in, it reproduces
   the identical estimated coefficient as two other equivalent formats
   (`AO1951.5`, `AO1951.05`), so no month-name-to-number conversion is
   needed. Appended to `regression_variables`; `outlier` (automatic
   detection) is turned off, since these are now pinned explicitly.
3. **Transform** (`transform=:auto`): the original handoff found no
   clean `.udg` field for this and planned to regex the HTML output for
   `"prefers <strong>log transformation</strong>"` -- a real gap, but
   not the one this session found. Direct testing here found `.udg`
   DOES resolve this cleanly, just inconsistently between outcomes: when
   log wins, a separate `aictrans: Log(y)` field appears (the top-level
   `transform` field itself stays a generic `"Automatic selection"`);
   when log does NOT win (confirmed with a series containing negative
   values, where log is mathematically inapplicable), `aictrans` is
   simply absent and `transform` itself directly reads
   `"No transformation"` instead. Only these two exact, independently
   confirmed strings are recognized -- anything else leaves the spec's
   existing `transform` unchanged rather than guessing past what this
   session actually verified.

Any of the three pieces `.udg` doesn't resolve (including when the
original spec was never automatic in that respect to begin with) is
left as-is from `result.spec` -- `static()` never invents a value it
can't trace back to a real `.udg` field.

**Not bit-identical**: confirmed directly that re-running the resolved
spec reproduces the original automatic run's tables only to within
~1e-6 relative precision, not exactly -- the same caveat R's own
`seasonal::static()` documents (RegARIMA's iterative estimation doesn't
necessarily converge to bit-identical coefficients when a model is
pre-specified vs. discovered through `automdl`'s own search). Compare
results with `isapprox`, not `==`.
"""
function static(result::X13Result)
    udg = result.udg
    spec = result.spec
    overrides = Dict{Symbol,Any}()

    if haskey(udg, "arimamdl")
        overrides[:arima_model] = udg["arimamdl"]
        overrides[:automdl] = false
        overrides[:maxorder] = nothing
        overrides[:maxdiff] = nothing
    end

    outlier_keys = [k for k in keys(udg) if startswith(k, "AutoOutlier\$")]
    if !isempty(outlier_keys)
        resolved_vars = [replace(k, "AutoOutlier\$" => "") for k in outlier_keys]
        overrides[:regression_variables] = vcat(spec.regression_variables, resolved_vars)
        overrides[:outlier] = false
    end

    tf = transformfunction(udg)
    tf !== nothing && (overrides[:transform] = tf)

    return X13Spec(spec; overrides...)
end

# ---------------------------------------------------------------------
# W.5 -- diagnostics accessor dispatch, StatsAPI contract, series(),
# show(). See handoff/w5-diagnostics-api-handoff.md and
# src/diagnostics.jl's own module comment for the design and the real
# .udg keys each of these reads, verified directly against the committed
# fixture (and, for transformfunction's two non-fixture rules, against a
# real explicit-transform run this session).
# ---------------------------------------------------------------------

"""
    udg(r::X13Result) -> Dict{String,String}
    udg(r::X13Result, key::AbstractString) -> Union{String,Nothing}
    udg(r::X13Result, keys::AbstractVector) -> Dict{String,String}

The raw `.udg` dict (`r.udg` -- this first form is just a named
accessor for the existing field, for symmetry with the other two forms
and with R's `seasonal::udg(x, stats=NULL)`). The second form looks up
one key, `nothing` if absent -- never throws (mirrors this file's other
W.5 accessors, not R's own `fail=` argument, which has no Julia
analogue needed here). The third form returns the subset of `r.udg`
matching `keys`, silently omitting any key not present.
"""
udg(r::X13Result) = r.udg
udg(r::X13Result, key::AbstractString) = get(r.udg, key, nothing)
udg(r::X13Result, keys::AbstractVector) = Dict(k => r.udg[k] for k in keys if haskey(r.udg, k))

# The X13Result-dispatching overloads for every Dict-based accessor in
# diagnostics.jl -- each just forwards to `r.udg`, since `X13Result`
# already carries the full raw dict.
transformfunction(r::X13Result) = transformfunction(r.udg)
arima_model(r::X13Result) = arima_model(r.udg)
mstats(r::X13Result) = mstats(r.udg)
qs(r::X13Result; which::Symbol = :all) = qs(r.udg; which = which)
outliers(r::X13Result; full::Bool = false) = outliers(r.udg; full = full)
outlier_counts(r::X13Result) = outlier_counts(r.udg)
fivebestmdl(r::X13Result) = fivebestmdl(r.udg)
seasonality_tests(r::X13Result) = seasonality_tests(r.udg)
residual_diagnostics(r::X13Result) = residual_diagnostics(r.udg)
spectral_peaks(r::X13Result) = spectral_peaks(r.udg)
filters(r::X13Result) = filters(r.udg)
nobs_effective(r::X13Result) = nobs_effective(r.udg)
spectrum_peaks(r::X13Result; series::Symbol = :sa) = spectrum_peaks(r.udg; series = series)

"""
    _coefficient_lines(path) -> Vector{NamedTuple}

Re-reads the `.udg` file at `path` DIRECTLY (not via `parse_udg`'s
`Dict`) to recover file order for the coefficient block -- confirmed
this matters: `Dict` iteration order isn't a language guarantee, and
`coef`/`coefnames`/`stderror` need a stable, meaningful order (the order
X-13 itself estimated the coefficients in), not whatever order a `Dict`
happens to iterate in. A coefficient line is identified as the handoff
specifies -- a key containing `\$` whose value splits into exactly three
parseable floats (`estimate std-error t-statistic`) -- MINUS a real,
confirmed exception: `lbq\$NN`/`bpq\$NN`/`sigacf\$NN`/`sigpacf\$NN` (the
lag-indexed diagnostic families `residual_diagnostics` already parses)
ALSO have a `\$` in their key and a 3-float value, and are explicitly
excluded (see `_NON_COEFFICIENT_DOLLAR_PREFIXES`) -- a first version of
this function without that exclusion matched 14 lines against the real
fixture, not the true `nreg + nregderived + nmodel` = 3 + 1 + 2 = 6, a
bug caught only by actually running the real-fixture test, not by
inspecting the handoff's own single worked example.
"""
# Lag-indexed diagnostic families (lbq$03, bpq$03, sigacf$03, sigpacf$03,
# ...) ALSO have a '$' in their key and a 3-field value -- confirmed
# directly this session that a first version of _coefficient_lines
# without this exclusion matched 14 lines against the fixture, not the
# real 6 (nreg 3 + nregderived 1 + nmodel 2), because these four
# lag-table families slipped through the same "$-in-key, 3 float fields"
# heuristic. They're already handled by _udg_lag_table (see
# residual_diagnostics) and are not regression coefficients at all.
const _NON_COEFFICIENT_DOLLAR_PREFIXES = r"^(lbq|bpq|sigacf|sigpacf)\$\d+$"

function _coefficient_lines(path::AbstractString)
    out = NamedTuple[]
    for line in eachline(path)
        idx = findfirst(':', line)
        idx === nothing && continue
        key = strip(line[1:idx-1])
        occursin('$', key) || continue
        occursin(_NON_COEFFICIENT_DOLLAR_PREFIXES, key) && continue
        fields = split(strip(line[idx+1:end]))
        length(fields) == 3 || continue
        est, se, t = tryparse(Float64, fields[1]), tryparse(Float64, fields[2]), tryparse(Float64, fields[3])
        (est === nothing || se === nothing || t === nothing) && continue
        push!(out, (key = String(key), estimate = est, stderror = se, tstat = t))
    end
    return out
end

"""
    _coefficient_name(key) -> String

Reduces one raw `.udg` coefficient key to the shorter name
`coefnames`/`show` display, in three genuinely different cases
(confirmed directly against the fixture's own four distinct key shapes
-- a single "strip an N-Coefficient prefix" rule, as first sketched in
the handoff, does NOT cover all of them):

1. `"1-Coefficient Trading Day\$Weekday"` -- strips the leading
   `"<digit>-Coefficient "` prefix -> `"Trading Day\$Weekday"`.
2. `"AutoOutlier\$AO1951.May"` -- strips the `"AutoOutlier\$"` prefix
   (the SAME rule [`outliers`](@ref)'s own `label` field uses) ->
   `"AO1951.May"`.
3. `"Easter[1]\$Easter[1]"` -- an exact repeated `X\$X` segment collapses
   to one copy -> `"Easter[1]"`. Neither rule 1 nor 2 applies here at
   all (no such prefix), so this needed its own case.
4. Anything else (e.g. `"MA\$Nonseasonal\$01\$01"`, four `\$`-separated
   segments, no prefix, no repeated pair) is left UNCHANGED.
"""
function _coefficient_name(key::AbstractString)
    m = match(r"^\d+-Coefficient (.+)$", key)
    m !== nothing && return m.captures[1]
    startswith(key, "AutoOutlier\$") && return key[(ncodeunits("AutoOutlier\$")+1):end]
    parts = split(key, '$')
    length(parts) == 2 && parts[1] == parts[2] && return parts[1]
    return key
end

function _udg_path(r::X13Result)
    return joinpath(r.run_result.dir, "$(r.run_result.basename).udg")
end

# NOTE: deliberately NOT `something(_udg_float(...), throw(...))` -- a real
# bug caught this session, not a style choice: `throw(...)` is a plain
# function-call ARGUMENT there, evaluated eagerly before `something` is
# even entered, so it fires unconditionally on every call, whether or not
# the key was actually present. Plain conditional functions instead.
function _require_udg_float(d::AbstractDict, key::AbstractString, label::AbstractString = key)
    v = _udg_float(d, key)
    v === nothing && throw(ErrorException(
        "$label: \"$key\" not found in .udg -- was a regARIMA model actually fit?",
    ))
    return v
end
function _require_udg_int(d::AbstractDict, key::AbstractString, label::AbstractString = key)
    v = _udg_int(d, key)
    v === nothing && throw(ErrorException("$label: \"$key\" not found in .udg"))
    return v
end

StatsAPI.nobs(r::X13Result) = _require_udg_int(r.udg, "nobs")
StatsAPI.aic(r::X13Result) = _require_udg_float(r.udg, "aic")
StatsAPI.bic(r::X13Result) = _require_udg_float(r.udg, "bic")
StatsAPI.aicc(r::X13Result) = _require_udg_float(r.udg, "aicc")
StatsAPI.loglikelihood(r::X13Result) = _require_udg_float(r.udg, "loglikelihood")
StatsAPI.residuals(r::X13Result) = r.residuals
StatsAPI.coef(r::X13Result) = [c.estimate for c in _coefficient_lines(_udg_path(r))]
StatsAPI.coefnames(r::X13Result) = [_coefficient_name(c.key) for c in _coefficient_lines(_udg_path(r))]
StatsAPI.stderror(r::X13Result) = [c.stderror for c in _coefficient_lines(_udg_path(r))]

"""
    StatsAPI.dof(r::X13Result) -> Int

`nreg + nmodel` (regression coefficients plus ARIMA model parameters) --
`nreg=3, nmodel=2 -> dof=5` in the committed fixture, confirmed directly.
Not independently cross-checked against R's own `dof(seas_object)`
semantics; treat this definition as this package's own, not an assumed
R-identical one, until that comparison is actually run (see
handoff/w5-diagnostics-api-handoff.md section 7.6).
"""
StatsAPI.dof(r::X13Result) = something(_udg_int(r.udg, "nreg"), 0) + something(_udg_int(r.udg, "nmodel"), 0)

"""
    StatsAPI.vcov(r::X13Result)

Always throws. `.udg` carries each coefficient's own standard error
(see `StatsAPI.stderror`) but no covariance matrix between
coefficients -- there is nothing to return, so this names that plainly
rather than returning a wrong or fabricated answer, the same style
`durbin_watson_test(method=:exact)`/`fit_garch(dist=:t)`-style "not
implemented for this case" errors use elsewhere in the TSAnalytics.jl
family.
"""
StatsAPI.vcov(::X13Result) = throw(ErrorException(
    "vcov(::X13Result) is not available -- .udg carries each coefficient's own standard " *
    "error (see stderror) but no covariance matrix between coefficients; x13ashtml does " *
    "not expose one",
))

"""
    Base.show(io, ::MIME"text/plain", r::X13Result)

A compact summary in the shape of R's `summary.seas`: ARIMA model,
transform, N, AIC/BIC, overall quality (Q), outlier count, and a
`StatsBase.CoefTable` of the estimated coefficients (matching
TSAnalytics.jl's own `ARXModel` display convention).
"""
function Base.show(io::IO, ::MIME"text/plain", r::X13Result)
    println(io, "X13Result")
    am = arima_model(r)
    am !== nothing && println(io, "  ARIMA model:  ", am)
    tf = transformfunction(r)
    tf !== nothing && println(io, "  Transform:    ", tf)
    println(io, "  N:            ", length(r.observed))
    haskey(r.udg, "aic") && println(io, "  AIC:          ", r.udg["aic"])
    haskey(r.udg, "bic") && println(io, "  BIC:          ", r.udg["bic"])
    m = mstats(r)
    m !== nothing && println(io, "  Q:            ", m.q)
    oc = outlier_counts(r)
    oc.total !== nothing && println(io, "  Outliers:     ", oc.total)

    coefs = StatsAPI.coef(r)
    if !isempty(coefs)
        println(io)
        ct = StatsBase.CoefTable(
            hcat(coefs, StatsAPI.stderror(r)), ["Estimate", "Std.Error"], StatsAPI.coefnames(r),
        )
        show(io, ct)
    end
end

# Known X-11/SEATS/regARIMA table codes -- series() validates a
# requested table symbol against this BEFORE spawning any subprocess.
const _KNOWN_TABLES = Set([
    :b1, :c17, :d8, :d9, :d10, :d11, :d12, :d13,
    :s10, :s11, :s12, :s13, :s14, :s15, :s16, :s17, :s18,
    :rsd, :fct, :fvr,
])

function series(r::X13Result, tables::AbstractVector{Symbol}; reeval::Bool = true)
    unknown = filter(t -> !(t in _KNOWN_TABLES), tables)
    isempty(unknown) || throw(ArgumentError(
        "series: unrecognized table symbol(s) $unknown -- known tables are " *
        "$(sort(collect(_KNOWN_TABLES)))",
    ))

    existing = something(r.spec.save, Symbol[])
    missing_tables = filter(t -> !(t in existing), tables)
    if isempty(missing_tables)
        result, period = r.run_result, r.spec.period
    else
        reeval || throw(ArgumentError(
            "series: table(s) $missing_tables were not saved by the original run " *
            "(spec.save=$existing) -- pass reeval=true (the default) to automatically " *
            "re-run with them added, or build a spec with `save` including them yourself",
        ))
        @info "series(): re-running to save additional table(s)" missing_tables
        new_spec = X13Spec(r.spec; save = union(existing, tables))
        path = write_spec(new_spec, joinpath(mktempdir(), "series_rerun.spc"))
        result = run_x13(path)
        result.success || throw(ErrorException("series() re-run failed: " * join(result.errors, "; ")))
        period = new_spec.period
    end

    out = Dict{Symbol,Vector{Float64}}()
    for t in tables
        path = joinpath(result.dir, "$(result.basename).$t")
        isfile(path) || throw(ErrorException(
            "series(): output table $path (requested :$t) does not exist after the run",
        ))
        out[t] = last.(parse_table(path; period = period))
    end
    return out
end

series(r::X13Result, table::Symbol; reeval::Bool = true) = series(r, [table]; reeval = reeval)[table]

# Attached via explicit post-definition `@doc str name` rather than the
# usual pre-definition `"""..."""` convention -- a real, unresolved
# oddity found while verifying W.6's own doc changes with a full
# Documenter build (not just the doctest-only check W.5 was verified
# with): a pre-definition docstring for `series` specifically (moved to
# immediately precede `function series(...)` after finding and fixing
# the original bug of it being attached to `_KNOWN_TABLES` instead --
# see git history) still would not attach -- confirmed directly,
# repeatedly, that `Base.Docs.meta(SeasonalAdjustment)` had no entry for
# the `series` binding at all, even after a from-scratch recompile, with
# `plots.jl` disabled, and with the second method definition removed,
# ruling out cache staleness, RecipesBase/@recipe interference, and
# multi-method interaction as the cause. This explicit form is standard,
# always-reliable Julia syntax and sidesteps whatever the real cause is.
@doc """
    series(r::X13Result, table::Symbol; reeval=true) -> Vector{Float64}
    series(r::X13Result, tables::AbstractVector{Symbol}; reeval=true) -> Dict{Symbol,Vector{Float64}}

Mirrors R's `seasonal::series(x, "d8")`: if `table` wasn't included in
the original run's `spec.save`, re-runs with it added and returns the
freshly-parsed values, rather than forcing the caller down to
`X13Spec`/`run_x13`/`parse_output` and rebuilding the spec by hand. The
vector form re-runs ONCE for the union of every missing table requested,
not once per table.

| `reeval` | Behaviour |
|---|---|
| `true` (default) | Missing table(s) trigger one automatic re-run with `save` extended to include them (matches R's own default). An `@info` note is logged when this happens (the Julia idiom for R's `verbose=TRUE`, suppressible through the logging system). |
| `false` | A missing table throws `ArgumentError` naming it, instead of re-running (matches R's `reeval=FALSE`). |

**Not cached**: every call that needs a re-run performs a fresh
subprocess invocation, even if an identical `series()` call was already
made -- `X13Result` is an immutable `struct` (deliberately, see its own
docstring), so caching the re-run's result on it isn't possible without
either a mutable scratch field or a wrapper type, neither of which this
first pass adds. A caller looping over several tables should use the
vector form (one re-run for all of them) rather than calling the scalar
form repeatedly.

Table symbols are validated against the union of known X-11/SEATS/
regARIMA table codes before any subprocess is spawned -- an unrecognized
symbol throws `ArgumentError` immediately rather than being passed to
the binary to fail on.
""" series

# ---------------------------------------------------------------------
# W.6 -- spectrum-curve fetching for spectrumplot. Deliberately NOT
# folded into series()/_KNOWN_TABLES: the spectrum tables (.sp0/.sp1/
# .sp2/.spr) come from the `spectrum{save=(...)}` spec block, not X-11's
# `x11{save=(...)}`/SEATS' `seats{save=(...)}` -- series()'s own re-run
# logic only extends THAT `save` list, so requesting a spectrum table
# needs its own small re-run path via `spec_args` instead (confirmed
# directly: `spectrum{save=(sp0 sp1 sp2 spr)}`, in that block, not any
# existing typed field, produces the 4 files, plus a bonus `.str` Tukey-
# spectrum file that isn't currently exposed here since no accessor
# needs it yet).
# ---------------------------------------------------------------------

const _SPECTRUM_TABLE_FOR_SERIES = Dict(:original => :sp0, :sa => :sp1, :irregular => :sp2, :residual => :spr)

"""
    _parse_spectrum_table(path) -> Vector{NamedTuple}

Parses a `.sp0`/`.sp1`/`.sp2`/`.spr` file -- confirmed directly against
the real binary this is a DIFFERENT 3-column shape (`Pos\tFrequency\tValue`)
than `parse_table`'s own 2-column `date\tvalue` tables, so it needs its
own reader rather than reusing `parse_table`.
"""
function _parse_spectrum_table(path::AbstractString)
    lines = readlines(path)
    out = NamedTuple[]
    for line in @view lines[3:end]
        isempty(strip(line)) && continue
        parts = split(line, '\t')
        length(parts) >= 3 || continue
        freq = tryparse(Float64, parts[2])
        val = tryparse(Float64, parts[3])
        (freq === nothing || val === nothing) && continue
        push!(out, (freq = freq, value = val))
    end
    return out
end

"""
    _spectrum_series(r::X13Result, series::Symbol) -> Vector{NamedTuple}

`(freq=, value=)` pairs -- the actual spectrum curve `spectrumplot`
(W.6) draws, for `series` in `(:original, :sa, :irregular, :residual)`
(mapping to the real, confirmed table codes `sp0`/`sp1`/`sp2`/`spr`).
Re-runs (announced via `@info`, same convention as [`series`](@ref)) and
requests ALL FOUR tables at once if the needed one isn't already present
-- so a second `spectrumplot(r; series=...)` call for a DIFFERENT series
on the same `r` still needs its own re-run (`X13Result` isn't mutable,
see `series`'s own docstring for why this isn't cached), but at least
doesn't re-run once per series if all four happen to be requested via
one shared, pre-fetched result.
"""
function _spectrum_series(r::X13Result, series::Symbol)
    haskey(_SPECTRUM_TABLE_FOR_SERIES, series) || throw(ArgumentError(
        "spectrumplot: series=:$series isn't recognized -- must be :original, :sa, " *
        ":irregular, or :residual",
    ))
    table = _SPECTRUM_TABLE_FOR_SERIES[series]
    path = joinpath(r.run_result.dir, "$(r.run_result.basename).$table")
    if !isfile(path)
        @info "spectrumplot(): re-running to save spectrum table(s)" table
        merged_spec_args = merge(r.spec.spec_args, Dict("spectrum.save" => "(sp0 sp1 sp2 spr)"))
        new_spec = X13Spec(r.spec; spec_args = merged_spec_args)
        newpath = write_spec(new_spec, joinpath(mktempdir(), "spectrum_rerun.spc"))
        result = run_x13(newpath)
        result.success || throw(ErrorException(
            "spectrumplot() re-run failed: " * join(result.errors, "; "),
        ))
        path = joinpath(result.dir, "$(result.basename).$table")
    end
    return _parse_spectrum_table(path)
end

"""
    select_order(y; kwargs...) -> NamedTuple

`(order=(p,d,q), seasonal_order=(P,D,Q,period), transform=:log|:none)` --
matches `statsmodels.tsa.x13.x13_arima_select_order`. Thin: runs
[`x13`](@ref) with `automdl=true` (accepting the same kwargs `x13`
does), then parses the resolved `arimamdl` string and [`transformfunction`](@ref)
back out of the result.
"""
function select_order(y; kwargs...)
    r = x13(y; automdl = true, kwargs...)
    m = arima_model(r)
    m === nothing && throw(ErrorException("select_order: automdl did not resolve an ARIMA model (no arimamdl in .udg)"))
    parts = match(r"^\((\d+) (\d+) (\d+)\)\((\d+) (\d+) (\d+)\)$", m)
    parts === nothing && throw(ErrorException("select_order: could not parse arimamdl=\"$m\""))
    p, d, q, P, D, Q = parse.(Int, parts.captures)
    return (order = (p, d, q), seasonal_order = (P, D, Q, r.spec.period), transform = transformfunction(r))
end

"""
    open_output(r::X13Result)

R's `out()`: writes the HTML output and opens it with the platform
handler (`xdg-open` on Linux, `open` on macOS, `start` on Windows).
Throws `ErrorException` if the output file doesn't exist (the binary
only writes it on a successful run).
"""
function open_output(r::X13Result)
    path = joinpath(r.run_result.dir, "$(r.run_result.basename).html")
    isfile(path) || throw(ErrorException(
        "open_output: $path does not exist -- the binary only writes the HTML report on a " *
        "successful run",
    ))
    cmd = if Sys.iswindows()
        `cmd /c start "" $path`
    elseif Sys.isapple()
        `open $path`
    else
        `xdg-open $path`
    end
    run(cmd; wait = false)
    return nothing
end

# ---------------------------------------------------------------------
# import_spc -- W.5.6, sequenced last per the handoff (it needs a real
# parser, not a lookup). Scoped deliberately: parses the "block { key =
# value ... }" shape this package's own render() produces (and which
# ordinary hand-written .spc files also use), NOT a fully general X-13
# grammar -- no comment handling, no exotic multi-line quoting beyond a
# plain parenthesized data list. Real migration value for anyone
# arriving with existing .spc files stays intact for the common case;
# an unusual file is expected to need manual cleanup, not silently
# misparse.
# ---------------------------------------------------------------------

function _parse_spc_blocks(text::AbstractString)
    blocks = Pair{String,String}[]
    pos = firstindex(text)
    n = lastindex(text)
    while true
        m = match(r"([A-Za-z_][A-Za-z0-9_]*)\s*\{", text, pos)
        m === nothing && break
        name = m.captures[1]
        bstart = m.offset + ncodeunits(m.match)
        depth = 1
        i = bstart
        while i <= n && depth > 0
            c = text[i]
            c == '{' && (depth += 1)
            c == '}' && (depth -= 1)
            depth > 0 && (i = nextind(text, i))
        end
        push!(blocks, name => text[bstart:i-1])
        pos = i > n ? n + 1 : nextind(text, i)
        pos > n && break
    end
    return blocks
end

function _parse_spc_kv(body::AbstractString)
    kv = Pair{String,String}[]
    pos = firstindex(body)
    n = lastindex(body)
    while true
        m = match(r"([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*", body, pos)
        m === nothing && break
        key = m.captures[1]
        vstart = m.offset + ncodeunits(m.match)
        if vstart <= n && body[vstart] == '('
            # One or more segments butted together with NO intervening
            # whitespace: a parenthesized group, or a bare trailing
            # suffix. Needed for arima's own "(p d q)(P D Q)period"
            # value shape (TWO paren groups plus a trailing bare period
            # digit, all adjacent) -- a naive single-"(...)" capture
            # would stop at the first ")" and silently truncate it.
            i = vstart
            while i <= n && !isspace(body[i])
                if body[i] == '('
                    depth = 1
                    i = nextind(body, i)
                    while i <= n && depth > 0
                        c = body[i]
                        c == '(' && (depth += 1)
                        c == ')' && (depth -= 1)
                        i = nextind(body, i)
                    end
                else
                    i = nextind(body, i)
                end
            end
            push!(kv, key => body[vstart:i-1])
            pos = i > n ? n + 1 : i
        elseif vstart <= n && body[vstart] == '"'
            i = nextind(body, vstart)
            while i <= n && body[i] != '"'
                i = nextind(body, i)
            end
            push!(kv, key => body[vstart:i])
            pos = i > n ? n + 1 : nextind(body, i)
        else
            i = vstart
            while i <= n && !isspace(body[i])
                i = nextind(body, i)
            end
            push!(kv, key => body[vstart:i-1])
            pos = i
        end
        pos > n && break
    end
    return kv
end

_strip_parens(s::AbstractString) = strip(strip(s), ['(', ')'])
_strip_quotes(s::AbstractString) = strip(strip(s), '"')

"""
    import_spc(path) -> X13Spec

R's `import.spc()`: builds an [`X13Spec`](@ref) from an existing `.spc`
file. Real migration value for anyone arriving from R/Census tooling with
existing spec files, rather than hand-translating every block into
keyword arguments.

**Scope, stated plainly rather than implied**: parses the same
`block { key = value ... }` shape this package's own [`render`](@ref)
produces. Known blocks (`series`, `transform`, `regression`, `arima`,
`automdl`, `outlier`, `estimate`, `x11`, `seats`) map to `X13Spec`'s
typed fields; anything else becomes a [`spec_args`](@ref X13Spec) entry
(W.5.4) under `"blockname.key"`. Not a general X-13 grammar parser --
comments and unusual multi-line quoting are not handled.

**One confirmed, real information gap**: `outlier { types = (ao ls tc) }`
sets `outlier=true` but the specific `types=` list is DROPPED, not
preserved -- `X13Spec` has no typed field for outlier types yet (see
handoff/seasonaladjustment-w5-w10-pipeline-handoff.md §3), and
`spec_args` can't target `outlier` since it's already a typed-field
block (see [`validate!`](@ref)). Silently losing this would be worse
than documenting it: check the source `.spc` by hand if `outlier.types`
matters for your use case.
"""
function import_spc(path::AbstractString)
    text = read(path, String)
    blocks = _parse_spc_blocks(text)

    y = Float64[]
    start = (1980, 1)
    period = 12
    title = "SeasonalAdjustment.jl series"
    kwargs = Dict{Symbol,Any}()
    spec_args = Dict{String,String}()
    seen_series = false

    for (blockname, body) in blocks
        kv = _parse_spc_kv(body)
        d = Dict(kv)
        if blockname == "series"
            seen_series = true
            haskey(d, "title") && (title = _strip_quotes(d["title"]))
            if haskey(d, "start")
                parts = split(d["start"], '.')
                start = (parse(Int, parts[1]), parse(Int, parts[2]))
            end
            haskey(d, "period") && (period = parse(Int, d["period"]))
            haskey(d, "data") && (y = parse.(Float64, split(_strip_parens(d["data"]))))
        elseif blockname == "transform"
            haskey(d, "function") && (kwargs[:transform] = Symbol(d["function"]))
        elseif blockname == "outlier"
            kwargs[:outlier] = true
        elseif blockname == "automdl"
            kwargs[:automdl] = true
            if haskey(d, "maxorder")
                nums = parse.(Int, split(_strip_parens(d["maxorder"])))
                kwargs[:maxorder] = (nums[1], nums[2])
            end
            if haskey(d, "maxdiff")
                nums = parse.(Int, split(_strip_parens(d["maxdiff"])))
                kwargs[:maxdiff] = (nums[1], nums[2])
            end
        elseif blockname == "arima"
            haskey(d, "model") && (kwargs[:arima_model] = d["model"])
        elseif blockname == "estimate"
            haskey(d, "save") && occursin("rsd", d["save"]) && (kwargs[:residuals] = true)
        elseif blockname in ("x11", "seats")
            kwargs[:seats] = (blockname == "seats")
            haskey(d, "save") && (kwargs[:save] = Symbol.(split(_strip_parens(d["save"]))))
            if blockname == "x11" && haskey(d, "mode")
                inv = Dict(v => k for (k, v) in _X11_MODE_KEYWORDS)
                haskey(inv, d["mode"]) && (kwargs[:x11_mode] = inv[d["mode"]])
            end
        elseif blockname == "regression"
            if haskey(d, "variables")
                vars = String.(split(_strip_parens(d["variables"])))
                if "td" in vars
                    kwargs[:trading] = true
                    kwargs[:regression_variables] = filter(!=("td"), vars)
                else
                    kwargs[:regression_variables] = vars
                end
            end
            haskey(d, "aictest") && (kwargs[:aictest] = Symbol.(split(_strip_parens(d["aictest"]))))
            haskey(d, "usertype") && (kwargs[:regression_usertype] = Symbol(_strip_parens(d["usertype"])))
            haskey(d, "data") && (kwargs[:regression_user] = parse.(Float64, split(_strip_parens(d["data"]))))
            haskey(d, "user") && (kwargs[:regression_user_name] = Symbol(_strip_parens(d["user"])))
        else
            for (k, v) in kv
                spec_args["$blockname.$k"] = v
            end
        end
    end

    seen_series || throw(ErrorException("import_spc: no series{} block found in $path"))
    isempty(y) && throw(ErrorException("import_spc: series{} block in $path has no data"))

    return X13Spec(y; start = start, period = period, title = title, spec_args = spec_args, kwargs...)
end

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
[`X13Result`](@ref)).
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

    spec = resolved_start === nothing ?
        X13Spec(yv; period = period, maxorder = maxorder, maxdiff = maxdiff, outlier = outlier, trading = trading, residuals = true, kwargs...) :
        X13Spec(yv; start = resolved_start, period = period, maxorder = maxorder, maxdiff = maxdiff, outlier = outlier, trading = trading, residuals = true, kwargs...)

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

    if get(udg, "aictrans", "") == "Log(y)"
        overrides[:transform] = :log
    elseif get(udg, "transform", "") == "No transformation"
        overrides[:transform] = :none
    end

    return X13Spec(spec; overrides...)
end

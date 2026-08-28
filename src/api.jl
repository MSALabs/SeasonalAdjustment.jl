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
already-published field names exactly. `spec`/`run_result` are the
actual [`X13Spec`](@ref)/[`X13RunResult`](@ref) the run used -- `x13`
returns a typed, introspectable result, not a black box (`run_result`
carries the binary's real stdout/warnings even on success).

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

`y` accepts anything [`tsvalues`](@ref) does. `index` (defaulting to
`tsindex(y)`, which is `nothing` for a plain vector and most sliced
containers -- pass it explicitly the same way other TSAnalytics.jl
functions ask for `index=`) is used to infer `start` when neither it
nor an explicit `start=(year, period)` is given; falls back to
`X13Spec`'s own `(1980, 1)` default otherwise (only `result.dates`'
labeling is affected either way, not the computed values).

Throws `ArgumentError` immediately if the spec is invalid (see
[`validate!`](@ref)) -- before any subprocess is spawned -- and throws
an `ErrorException` carrying the binary's own error text if the run
itself fails, rather than returning a half-populated result.

`save` is deliberately not accepted here (see handoff/w4-api.md) --
`x13`'s contract is a fully-populated `X13Result`, which needs all four
tables; use [`X13Spec`](@ref)/[`run_x13`](@ref)/[`parse_output`](@ref)
directly for a custom, partial table selection.
"""
function x13(
    y;
    index = tsindex(y),
    start::Union{Nothing,Tuple{Int,Int}} = nothing,
    maxorder::Union{Nothing,Tuple{Int,Int}} = nothing,
    maxdiff::Union{Nothing,Tuple{Int,Int}} = nothing,
    outlier::Bool = false,
    trading::Bool = false,
    save = nothing,
    kwargs...,
)
    save === nothing || throw(ArgumentError(
        "x13() doesn't accept `save` -- it always needs the full D10-D13/S10-S13 " *
        "quartet to populate an X13Result. For a custom, partial table selection, use " *
        "X13Spec/run_x13/parse_output directly instead.",
    ))

    yv = Float64.(collect(tsvalues(y)))
    resolved_start = if start !== nothing
        start
    elseif index !== nothing
        (Dates.year(index[1]), Dates.month(index[1]))
    else
        nothing
    end

    spec = resolved_start === nothing ?
        X13Spec(yv; maxorder = maxorder, maxdiff = maxdiff, outlier = outlier, trading = trading, kwargs...) :
        X13Spec(yv; start = resolved_start, maxorder = maxorder, maxdiff = maxdiff, outlier = outlier, trading = trading, kwargs...)

    spec_path = write_spec(spec, joinpath(mktempdir(), "series.spc"))
    run_result = run_x13(spec_path)
    run_result.success || throw(ErrorException(
        "x13() run failed: " * join(run_result.errors, "; "),
    ))

    tables = spec.seats ? (:s10, :s11, :s12, :s13) : (:d10, :d11, :d12, :d13)
    parsed = parse_output(run_result, collect(tables))
    seasonal_factors = last.(parsed[tables[1]])
    seasonally_adjusted = last.(parsed[tables[2]])
    trend = last.(parsed[tables[3]])
    irregular = last.(parsed[tables[4]])
    dates = first.(parsed[tables[1]])

    return X13Result(yv, seasonally_adjusted, trend, seasonal_factors, irregular, dates, spec, run_result)
end

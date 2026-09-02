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
actual source that `ClassicalDecomposition` and `STLDecomposition` share
no common abstract type to subtype -- the open question CLAUDE.md
flagged at project scaffolding, resolved here, not re-deferred.

# Examples
This needs the real x13prebuilt binary, so it is shown as a plain code
block rather than a live doctest -- confirmed directly against a real
run, not invented:
```julia
julia> res = x13(dataset("airline"))
X13Result
  ARIMA model:  (0 0 0)
  Transform:    none
  N:            144
  AIC:          0.205784733802868E+04
  BIC:          0.206081715132825E+04
  Q:            0.27
  Outliers:     0

julia> res.seasonally_adjusted[1:3]
3-element Vector{Float64}:
 124.546106577719
 124.626037057387
 124.891225520544

julia> res.dates[1]
1949-01-01
```
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
exercise.

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

`save` is deliberately not accepted here --
`x13`'s contract is a fully-populated `X13Result`, which needs all four
tables; use [`X13Spec`](@ref)/[`run_x13`](@ref)/[`parse_output`](@ref)
directly for a custom, partial table selection. `residuals` is rejected
the same way and for the same reason -- `x13()` always requests it (see
[`X13Result`](@ref)). For a non-SEATS spec, `:d8` (final unmodified SI
ratios) is ALSO always saved alongside D10-D13 -- not one of
`X13Result`'s own fields, but present on disk so [`monthplot`](@ref)'s
SI-ratio overlay never needs to re-run for an `x13()`-produced result.

`missing_action=:x13` needs an explicit `transform`
(`:log`/`:none`/`:auto`) the SAME way any other regression content does
(see [`validate!`](@ref)'s own rule 5) -- confirmed directly: X-13
interpolates the `-99999` sentinel via its OWN internal AO-style
regressor, which is enough to trigger the "regression present + default
multiplicative mode + no explicit transform" error, even though this
package's own `X13Spec` never renders a `regression{}` block for it.
Not silently defaulted here -- pass `transform` explicitly.

# Examples
A bare call, with nothing turned on (see [`X13Result`](@ref) for what
this does and does not fit):
```julia
julia> res = x13(dataset("airline"));
```

Letting X-13 make its usual automatic choices -- transform selection,
ARIMA search, outlier detection, and trading-day/Easter testing --
which is the specification most real use reaches for:
```julia
julia> res = x13(dataset("airline");
                  automdl = true, outlier = true,
                  aictest = [:td, :easter], transform = :auto);

julia> arima_model(res)
"(0 1 1)(0 1 1)"

julia> transformfunction(res)
:log

julia> mstats(res).q
0.2

julia> length(outliers(res))
1
```
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
    missing_action::Symbol = :error,
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
    missing_action in (:error, :x13, :omit) || throw(ArgumentError(
        "x13(): missing_action=:$missing_action isn't recognized -- must be :error " *
        "(the default), :x13, or :omit",
    ))

    # tsvalues(y) itself errors on a Union{Missing,Float64} plain vector
    # (confirmed directly: TSAnalytics.jl's own conversion path can't
    # convert Missing to Float64 eagerly) -- for that one concrete case,
    # skip straight to _handle_missing on `y` itself, which already does
    # its own Missing-aware Float64 conversion; every other container
    # tsvalues supports goes through it as before.
    yv_raw = (y isa AbstractVector && Missing <: eltype(y)) ? y : tsvalues(y)
    yv, missing_offset = _handle_missing(yv_raw, missing_action)
    resolved_start = if start !== nothing
        start
    elseif index !== nothing
        period == 12 ? (Dates.year(index[1]), Dates.month(index[1])) :
            (Dates.year(index[1]), (Dates.month(index[1]) - 1) ÷ 3 + 1)
    else
        nothing
    end
    # missing_action=:omit may have dropped leading observations (see
    # _handle_missing) -- shift the effective start forward by however
    # many periods were trimmed, so result.dates still lines up with the
    # TRIMMED series, not the original one.
    resolved_start = resolved_start === nothing || missing_offset == 0 ?
        resolved_start : _advance_start(resolved_start, missing_offset, period)

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

    return _run_spec(spec; label = "x13()")
end

"""
    _run_spec(spec::X13Spec; label="x13()") -> X13Result

The shared "write, run, parse into X13Result" tail behind both [`x13`](@ref)
and [`update`](@ref) -- factored out so `update` doesn't need its
own second copy of this logic; the only difference between the two
callers is which `X13Spec` they hand in (a freshly built one vs.
`X13Spec(r.spec; kwargs...)`) and the error message's own label.
"""
function _run_spec(spec::X13Spec; label::AbstractString = "x13()")
    spec_path = write_spec(spec, joinpath(mktempdir(), "series.spc"))
    run_result = run_x13(spec_path; udg = true)
    run_result.success || throw(ErrorException(
        "$label run failed: " * join(run_result.errors, "; "),
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
        spec.y, seasonally_adjusted, trend, seasonal_factors, irregular, residuals_vec, udg,
        dates, spec, run_result,
    )
end

# ---------------------------------------------------------------------
# W.7.3 -- missing-value support. The 2015 Reference Manual's Chapter 1
# says missing values are not allowed; confirmed stale (handoff): R's
# `seasonal::na.x13()` is one line, substituting NA with X-13's own
# default missing code -99999, and series.seriesmvadj (.mv) returns the
# series with those replaced by regARIMA estimates. No `missingcode`
# argument is needed at the default (a non-default value was flagged as
# unconfirmed by the handoff and stays unconfirmed here -- not exposed).
# ---------------------------------------------------------------------

_is_missing_value(v) = v === missing || (v isa Real && isnan(v))

"""
    _handle_missing(yv, missing_action::Symbol) -> (Vector{Float64}, Int)

Returns `(values, leading_offset)` -- `leading_offset` is how many
leading observations `missing_action=:omit` dropped (0 for every other
case), which [`x13`](@ref) uses to shift `start` forward so
`result.dates` still lines up with the trimmed series.
"""
function _handle_missing(yv_in, missing_action::Symbol)
    has_missing = any(_is_missing_value, yv_in)
    if !has_missing
        return Float64.(collect(yv_in)), 0
    end

    if missing_action == :error
        throw(ArgumentError(
            "x13(): series contains missing/NaN values -- pass missing_action=:x13 (X-13 " *
            "interpolates via a -99999 sentinel + regARIMA, matching R's na.action=na.x13) " *
            "or missing_action=:omit (drop only LEADING/TRAILING gaps) to allow this, or " *
            "clean the series yourself first",
        ))
    elseif missing_action == :x13
        real_sentinel = any(v -> v isa Real && !isnan(v) && v == -99999.0, yv_in)
        real_sentinel && @warn "x13(): the series already contains the value -99999.0 -- " *
            "missing_action=:x13 will treat every -99999.0 as a missing-value sentinel too, " *
            "indistinguishable from a genuine -99999.0 observation"
        vals = Float64[_is_missing_value(v) ? -99999.0 : Float64(v) for v in yv_in]
        return vals, 0
    else # :omit
        first_valid = findfirst(!_is_missing_value, yv_in)
        first_valid === nothing && throw(ArgumentError("x13(): series is entirely missing"))
        last_valid = findlast(!_is_missing_value, yv_in)
        interior = yv_in[first_valid:last_valid]
        interior_gap = findfirst(_is_missing_value, interior)
        interior_gap === nothing || throw(ArgumentError(
            "x13(): missing_action=:omit only drops LEADING/TRAILING missing values -- an " *
            "interior gap was found at position $(first_valid - 1 + interior_gap) (1-based, " *
            "in the original series) -- use missing_action=:x13 to interpolate an interior gap",
        ))
        return Float64.(collect(interior)), first_valid - 1
    end
end

"""
    _advance_start(start, offset, period) -> (Int, Int)

Shifts `start` forward by `offset` periods (used when
`missing_action=:omit` trims leading observations).
"""
function _advance_start(start::Tuple{Int,Int}, offset::Int, period::Int)
    offset == 0 && return start
    linear = start[1] * period + (start[2] - 1) + offset
    y, p = divrem(linear, period)
    return (y, p + 1)
end

"""
    interpolated(r::X13Result) -> Vector{Float64}

`series.seriesmvadj` (`.mv`) -- the original series with missing values
(inserted via `x13(y; missing_action=:x13)`'s `-99999` sentinel)
replaced by regARIMA's own estimates. Re-runs via [`series`](@ref) if
`.mv` wasn't already saved.

The interpolated value's quality depends entirely on the model doing
the interpolating -- a real difference, confirmed directly: with no
`automdl`/`seasonal_order` (so no real ARIMA model fit at all, see
[`X13Spec`](@ref)'s own docstring), the interpolated value is close to
meaningless (`0.0`/`1.0` for a series around 120); with `automdl = true`
fitting a genuine model, it lands close to the true value.

# Examples
```julia
julia> y = copy(dataset("airline").value); y[5] = NaN;  # May 1949, true value 121.0

julia> res = x13(y; start = (1949, 1), missing_action = :x13, transform = :log, automdl = true);

julia> interpolated(res)[5]
121.55895357992
```
"""
interpolated(r::X13Result) = series(r, :mv)

"""
    static(result::X13Result) -> X13Spec

Resolves an "automatic" spec's `:auto`/`automdl`/`outlier` choices into
an explicit, reproducible [`X13Spec`](@ref) -- matching R's `seasonal`
package's own `static()`. Reads exclusively from `result.udg`, never
stdout/HTML. Resolves three things, each confirmed directly against the
real binary (see point 3 for a real gap found and closed during
verification):

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
3. **Transform** (`transform=:auto`): regexing the HTML output for
   `"prefers <strong>log transformation</strong>"` was the fallback
   plan when no clean `.udg` field seemed available for this. Direct
   testing found `.udg`
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

# Examples
```julia
julia> res = x13(dataset("airline"); automdl = true, outlier = true, transform = :auto);

julia> frozen = static(res);

julia> frozen.arima_model
"(0 1 1)(0 1 1)"

julia> frozen.automdl
false

julia> res2 = x13(frozen);

julia> res.seasonally_adjusted ≈ res2.seasonally_adjusted
true
```
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
diagnostics accessors, not R's own `fail=` argument, which has no Julia
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
happens to iterate in. A coefficient line is identified as
a key containing `\$` whose value splits into exactly three
parseable floats (`estimate std-error t-statistic`) -- MINUS a real,
confirmed exception: `lbq\$NN`/`bpq\$NN`/`sigacf\$NN`/`sigpacf\$NN` (the
lag-indexed diagnostic families `residual_diagnostics` already parses)
ALSO have a `\$` in their key and a 3-float value, and are explicitly
excluded (see `_NON_COEFFICIENT_DOLLAR_PREFIXES`) -- a first version of
this function without that exclusion matched 14 lines against the real
fixture, not the true `nreg + nregderived + nmodel` = 3 + 1 + 2 = 6, a
bug caught only by actually running the real-fixture test against a
single worked example.

A second, distinct exception found the same way,
against a `trading=true` regression run: `chi\$<group name>` (e.g.
`"chi\$Trading Day"`) is the joint significance CHI-SQUARED TEST for a
whole regressor group, not a coefficient -- it ALSO has a `\$` in its
key and happens to have a 3-field value, so it slipped through the same
heuristic the lag-diagnostic families did. Excluded the same way.
"""
# Lag-indexed diagnostic families (lbq$03, bpq$03, sigacf$03, sigpacf$03,
# ...) ALSO have a '$' in their key and a 3-field value -- confirmed
# directly this session that a first version of _coefficient_lines
# without this exclusion matched 14 lines against the fixture, not the
# real 6 (nreg 3 + nregderived 1 + nmodel 2), because these four
# lag-table families slipped through the same "$-in-key, 3 float fields"
# heuristic. They're already handled by _udg_lag_table (see
# residual_diagnostics) and are not regression coefficients at all.
# `chi$<group>` (e.g. "chi$Trading Day") is the same trap found again
# later, against a real trading=true run -- a joint chi-squared test for
# a regressor GROUP, not a coefficient.
const _NON_COEFFICIENT_DOLLAR_PREFIXES = r"^(lbq|bpq|sigacf|sigpacf)\$\d+$|^chi\$.+$"

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
-- a single "strip an N-Coefficient prefix" rule does NOT cover all of
them):

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
R-identical one, until that comparison is actually run.

# Examples
```julia
julia> res = x13(dataset("airline"); automdl = true, outlier = true, transform = :auto);

julia> StatsAPI.dof(res)  # nreg=0 (no regression variables), nmodel=2 (two MA terms)
2
```
"""
StatsAPI.dof(r::X13Result) = something(_udg_int(r.udg, "nreg"), 0) + something(_udg_int(r.udg, "nmodel"), 0)

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

# W.7.1: _KNOWN_TABLES/_TABLE_BLOCK now come from src/known_tables.jl
# (generated from handoff/x13-saveable-tables.md's 281-entry catalogue --
# see tools/generate_known_tables.jl) instead of a 20-symbol hand-written
# list. render()'s per-block save routing (spec.jl) is what makes most of
# these actually reachable; series() below just needed its whitelist
# widened to match.

# Confirmed directly against the real binary: .sp0/.sp1/.sp2/.spr share a
# 3-column Pos/Frequency/Value format (_parse_spectrum_table), NOT
# parse_table's 2-column date/value shape. The rest of the "spectrum"
# block (.is0/.it0/.st0/.ser/... -- Tukey and indirect/SEATS spectrum
# variants) are presumed to share it but were never independently run and
# checked -- series() refuses them explicitly below rather than silently
# mis-parsing a 3-column file with a 2-column reader.
const _SPECTRUM_FORMAT_TABLES = Set([:sp0, :sp1, :sp2, :spr])

"""
    _ensure_saved(r::X13Result, tables; reeval=true, label="series()") -> (X13RunResult, Int)

The shared re-run machinery behind both [`series`](@ref) and
[`_spectrum_series`](@ref) (the latter folds into the former's own
save-extension path rather than keeping two separate re-run
implementations). Returns `r.run_result` /
`r.spec.period` unchanged if every table in `tables` was already saved by
the original run; otherwise re-runs once with `save` extended to the
union of the existing tables and `tables`.
"""
function _ensure_saved(r::X13Result, tables::AbstractVector{Symbol}; reeval::Bool = true, label::AbstractString = "series()")
    existing = something(r.spec.save, Symbol[])
    missing_tables = filter(t -> !(t in existing), tables)
    isempty(missing_tables) && return r.run_result, r.spec.period

    reeval || throw(ArgumentError(
        "$label: table(s) $missing_tables were not saved by the original run " *
        "(spec.save=$existing) -- pass reeval=true (the default) to automatically " *
        "re-run with them added, or build a spec with `save` including them yourself",
    ))
    @info "$label: re-running to save additional table(s)" missing_tables
    new_spec = X13Spec(r.spec; save = union(existing, tables))
    path = write_spec(new_spec, joinpath(mktempdir(), "series_rerun.spc"))
    result = run_x13(path)
    result.success || throw(ErrorException("$label re-run failed: " * join(result.errors, "; ")))
    return result, new_spec.period
end

function series(r::X13Result, tables::AbstractVector{Symbol}; reeval::Bool = true)
    unknown = filter(t -> !(t in _KNOWN_TABLES), tables)
    isempty(unknown) || throw(ArgumentError(
        "series: unrecognized table symbol(s) $unknown -- known tables are the " *
        "$(length(_KNOWN_TABLES))-entry X-13 saveable-table catalogue",
    ))

    result, period = _ensure_saved(r, tables; reeval = reeval, label = "series()")

    out = Dict{Symbol,Vector{Float64}}()
    for t in tables
        path = joinpath(result.dir, "$(result.basename).$t")
        isfile(path) || throw(ErrorException(
            "series(): output table $path (requested :$t) does not exist after the run",
        ))
        if t in _SPECTRUM_FORMAT_TABLES
            out[t] = [e.value for e in _parse_spectrum_table(path)]
        elseif _TABLE_BLOCK[t] == _SPECTRUM_FORMAT_BLOCK
            throw(ErrorException(
                "series(): :$t is a spectrum-block table whose column format hasn't been " *
                "independently confirmed against the real binary -- only :sp0/:sp1/:sp2/:spr " *
                "are supported here; use a hand-built X13Spec/run_x13/parse_output if you " *
                "need :$t's raw file directly",
            ))
        else
            out[t] = last.(parse_table(path; period = period))
        end
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

# Examples
```julia
julia> res = x13(dataset("airline"); automdl = true, outlier = true, aictest = [:td, :easter], transform = :auto);

julia> d8 = series(res, :d8);  # final unmodified SI ratios -- not one of X13Result's own fields

julia> d8[1:2]
2-element Vector{Float64}:
 0.90954413431534
 0.958134917539742

julia> tables = series(res, [:d8, :hol]);  # one re-run for both, not two

julia> sort(collect(keys(tables)))
2-element Vector{Symbol}:
 :d8
 :hol
```
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
 draws, for `series` in `(:original, :sa, :irregular, :residual)`
(mapping to the real, confirmed table codes `sp0`/`sp1`/`sp2`/`spr`).

Shares [`_ensure_saved`](@ref)'s re-run machinery with
[`series`](@ref) rather than a second, bespoke re-run implementation --
the two used to diverge (this function extended `spectrum.save` via
`spec_args` directly; `series()` extended the typed `save` field), which
was exactly the "two mechanisms for one job" this consolidation fixes.
Now both funnel through the same `X13Spec(r.spec; save=...)` path, with
`render()`'s own per-block routing (spec.jl) sending `:sp0`/`:sp1`/`:sp2`/
`:spr` to the `spectrum{}` block automatically. Still requests all four
spectrum tables at once when a re-run is needed (not just the one
`series` symbol asked for), so a second `spectrumplot(r; series=...)`
call for a DIFFERENT series on the same `r` doesn't need its own re-run.
"""
function _spectrum_series(r::X13Result, series::Symbol)
    haskey(_SPECTRUM_TABLE_FOR_SERIES, series) || throw(ArgumentError(
        "spectrumplot: series=:$series isn't recognized -- must be :original, :sa, " *
        ":irregular, or :residual",
    ))
    table = _SPECTRUM_TABLE_FOR_SERIES[series]
    all_spectrum_tables = collect(values(_SPECTRUM_TABLE_FOR_SERIES))
    result, _ = _ensure_saved(r, all_spectrum_tables; label = "spectrumplot()")
    path = joinpath(result.dir, "$(result.basename).$table")
    isfile(path) || throw(ErrorException(
        "_spectrum_series(): output table $path (requested :$table) does not exist after the run",
    ))
    return _parse_spectrum_table(path)
end

# ---------------------------------------------------------------------
# W.7.2 -- forecast/backcast. .fct/.bct are a 4-column format (date,
# point, lowerci, upperci -- confirmed directly against the real binary,
# a distinct shape from BOTH parse_table's 2-column and the spectrum
# tables' 3-column format), so they need their own reader.
# ---------------------------------------------------------------------

"""
    _parse_forecast_table(path) -> Vector{NamedTuple}

Parses a `.fct`/`.bct` file (`date\tpoint\tlowerci\tupperci`, confirmed
directly against the real binary -- header + dashed separator row, then
one data row per forecast/backcast period, with BOTH the point value and
its prediction interval already on the original scale).
"""
function _parse_forecast_table(path::AbstractString)
    lines = readlines(path)
    out = NamedTuple[]
    for line in @view lines[3:end]
        isempty(strip(line)) && continue
        parts = split(line, '\t')
        length(parts) >= 4 || continue
        point = tryparse(Float64, parts[2])
        lo = tryparse(Float64, parts[3])
        hi = tryparse(Float64, parts[4])
        (point === nothing || lo === nothing || hi === nothing) && continue
        push!(out, (point = point, lower = lo, upper = hi))
    end
    return out
end

_extend_dates_forward(last::Date, n::Int, period::Int) =
    [last + (period == 12 ? Dates.Month(i) : Dates.Month(3i)) for i in 1:n]
_extend_dates_backward(first::Date, n::Int, period::Int) =
    [first - (period == 12 ? Dates.Month(n - i + 1) : Dates.Month(3 * (n - i + 1))) for i in 1:n]

_effective_forecast_probability(spec::X13Spec) =
    something(tryparse(Float64, get(spec.spec_args, "forecast.probability", "")), 0.95)

function _forecast_rerun(r::X13Result, table::Symbol, level::Real; label::AbstractString)
    0.0 < level < 1.0 || throw(ArgumentError("$label: level=$level must be in (0,1)"))
    existing = something(r.spec.save, Symbol[])
    needs_rerun = !(table in existing) || _effective_forecast_probability(r.spec) != level
    needs_rerun || return r.run_result, r.spec.period
    @info "$label: re-running" level table
    merged_args = merge(r.spec.spec_args, Dict("forecast.probability" => string(level)))
    new_spec = X13Spec(r.spec; save = union(existing, [table]), spec_args = merged_args)
    path = write_spec(new_spec, joinpath(mktempdir(), "forecast_rerun.spc"))
    result = run_x13(path)
    result.success || throw(ErrorException("$label re-run failed: " * join(result.errors, "; ")))
    return result, new_spec.period
end

"""
    forecast(r::X13Result; level=0.95) -> (dates=, point=, lower=, upper=)

Point forecasts plus their `level`-width prediction interval, extending
`r.dates` forward -- `.fct` (`forecast.forecasts`) already carries all
three on the original scale (confirmed directly), so
nothing needs back-transforming here. Re-runs (via [`X13Spec`](@ref)'s
`forecast.probability`) whenever `:fct` wasn't already saved OR the
requested `level` differs from whatever probability the original run
used -- changing `level` genuinely forces a re-run, since the interval
width is computed by the binary itself, not derived after the fact.

Program limit: `maxlead` (X-13 default 12) is capped at 120
(`pfcst`, [`validate!`](@ref)) -- pass `maxlead` to [`x13`](@ref)/
[`X13Spec`](@ref), not here, to control the horizon itself.

# Examples
```julia
julia> res = x13(dataset("airline"); automdl = true, outlier = true, aictest = [:td, :easter], transform = :auto);

julia> f = forecast(res; level = 0.95);

julia> f.point[1:3]
3-element Vector{Float64}:
 444.296392254728
 413.509289596684
 465.549800699388

julia> f.dates[1]
1961-01-01
```
"""
function forecast(r::X13Result; level::Real = 0.95)
    result, period = _forecast_rerun(r, :fct, level; label = "forecast()")
    path = joinpath(result.dir, "$(result.basename).fct")
    isfile(path) || throw(ErrorException("forecast(): $path does not exist after the run"))
    rows = _parse_forecast_table(path)
    dates = _extend_dates_forward(r.dates[end], length(rows), period)
    return (
        dates = dates, point = [x.point for x in rows],
        lower = [x.lower for x in rows], upper = [x.upper for x in rows],
    )
end

"""
    backcast(r::X13Result; level=0.95) -> (dates=, point=, lower=, upper=)

Same as [`forecast`](@ref), extending `r.dates` BACKWARD instead --
`.bct` (`forecast.backcasts`). The horizon is controlled by
`spec_args["forecast.maxback"]` (no typed field -- see [`X13Spec`](@ref)'s
own docstring for why only `maxlead` got one).

# Examples
The default `X13Spec` requests no backcasts at all -- `maxback` must be
set explicitly through `spec_args`, or `.bct` comes back empty:
```julia
julia> res = x13(dataset("airline");
                  automdl = true, outlier = true, aictest = [:td, :easter], transform = :auto,
                  spec_args = Dict("forecast.maxback" => "12"));

julia> b = backcast(res; level = 0.95);

julia> b.point[1:2]
2-element Vector{Float64}:
  99.1566037656758
 109.414698194457

julia> b.dates[1]
1948-01-01
```
"""
function backcast(r::X13Result; level::Real = 0.95)
    result, period = _forecast_rerun(r, :bct, level; label = "backcast()")
    path = joinpath(result.dir, "$(result.basename).bct")
    isfile(path) || throw(ErrorException("backcast(): $path does not exist after the run"))
    rows = _parse_forecast_table(path)
    dates = _extend_dates_backward(r.dates[1], length(rows), period)
    return (
        dates = dates, point = [x.point for x in rows],
        lower = [x.lower for x in rows], upper = [x.upper for x in rows],
    )
end

# ---------------------------------------------------------------------
# W.7.4 -- component-factor accessors. Each is a `regression{}` table,
# NOT an `x11{}` one (the W.7.1 naming trap this whole handoff pair is
# built around) -- series()'s per-block save routing (spec.jl) is what
# makes fetching these actually work.
# ---------------------------------------------------------------------

const _COMPONENT_TABLE = Dict(
    :trading_day => :td, :holiday => :hol, :user => :usr, :outlier => :otl,
    :ao => :ao, :ls => :ls, :tc => :tc, :so => :so,
)

# Cheap, exact pre-checks for the two component kinds this package can
# tell are present or absent from the SPEC alone, with no subprocess --
# avoids handing the binary a save request for a regression effect that
# was never configured (e.g. `regression.holiday` when there's no
# holiday-typed user regressor and no easter/holiday regression
# variable at all). :holiday/:outlier/:ao/:ls/:tc/:so have no equally
# clean spec-level signal (a holiday effect can come from a typed user
# regressor OR a raw `regression_variables` entry; automdl's own outlier
# detection isn't knowable before a run) -- those fall through to
# `_ensure_saved` and, in a genuine "not part of this model" case, may
# surface the binary's own error rather than a guaranteed clean
# `nothing`. Documented as a real, honest gap, not silently papered over.
function _component_precheck(spec::X13Spec, which::Symbol)
    which == :trading_day && return spec.trading || "td" in spec.regression_variables
    which == :user && return spec.regression_user !== nothing
    return true # :holiday/:outlier/:ao/:ls/:tc/:so -- no cheap pre-check, try the run
end

"""
    components(r::X13Result; which=:all) -> NamedTuple or Union{Nothing,Vector{Float64}}

The estimated TIME PATH of each regression effect (`which=:all` ->
`(trading_day=, holiday=, user=, outlier=, ao=, ls=, tc=, so=)`, each
`nothing` when that effect isn't part of the model; a single `which`
returns just that vector, or `nothing`). Given the India-calendar layer,
`which=:holiday`/`:user` are the point of this: `coef(r)` gives the
Diwali coefficient itself, `components(r; which=:user)` gives its
month-by-month factor -- closing the loop `componentplot` draws.

Fetched via [`series`](@ref)'s own re-run machinery (`_ensure_saved`),
so results are announced with the same `@info` convention. `which=:all`
throws `ArgumentError` if the model has NO regression effects at all
(nothing to return); a single `which` returns `nothing` instead in that
case -- see this function's own source comment on `_component_precheck`
for the one real, flagged gap (a handful of component kinds can't be
cheaply distinguished from "not part of the model" before a subprocess).

# Examples
```julia
julia> res = x13(dataset("airline"); automdl = true, outlier = true, aictest = [:td, :easter], transform = :auto);

julia> comp = components(res; which = :all);

julia> comp.trading_day[1:3]
3-element Vector{Float64}:
 1.01186867692772
 0.991150442477876
 0.991189940604853

julia> comp.user === nothing  # no user-defined regressor in this spec
true

julia> components(res; which = :outlier)[1:3] == comp.outlier[1:3]
true
```
"""
function components(r::X13Result; which::Symbol = :all)
    if which == :all
        _has_regression(r.spec) || throw(ArgumentError(
            "components(): which=:all requires the model to have at least one regression " *
            "effect -- this spec has none (no trading day, holiday, user regressor, or " *
            "outlier regression variables)",
        ))
        tables = collect(values(_COMPONENT_TABLE))
        result, period = _ensure_saved(r, tables; label = "components()")
        out = Dict{Symbol,Any}()
        for (name, table) in _COMPONENT_TABLE
            path = joinpath(result.dir, "$(result.basename).$table")
            out[name] = isfile(path) ? last.(parse_table(path; period = period)) : nothing
        end
        return NamedTuple((:trading_day, :holiday, :user, :outlier, :ao, :ls, :tc, :so) .=>
            getindex.(Ref(out), (:trading_day, :holiday, :user, :outlier, :ao, :ls, :tc, :so)))
    end

    haskey(_COMPONENT_TABLE, which) || throw(ArgumentError(
        "components: which=:$which isn't recognized -- must be :all, :trading_day, " *
        ":holiday, :user, :outlier, :ao, :ls, :tc, or :so",
    ))
    _component_precheck(r.spec, which) || return nothing
    table = _COMPONENT_TABLE[which]
    result, period = _ensure_saved(r, [table]; label = "components()")
    path = joinpath(result.dir, "$(result.basename).$table")
    isfile(path) || return nothing
    return last.(parse_table(path; period = period))
end

# ---------------------------------------------------------------------
# W.7.5 -- vcov, via estimate.regcmatrix (.rcm)/estimate.armacmatrix
# (.acm) requested with `save` (the COVARIANCE matrix; the same table
# code under `print` is the CORRELATION matrix instead -- W.7 handoff).
# Scope: matches _coefficient_lines' own two coefficient FAMILIES
# (regression vs. ARIMA/ARMA) -- .rcm covers the regression family,
# .acm the ARIMA family; cross-covariance between the two families isn't
# reported by X-13 at all, so those entries are left `NaN` ("unknown",
# not silently asserted independent/zero).
# ---------------------------------------------------------------------

_is_arma_coefficient_key(key::AbstractString) = occursin(r"^(AR|MA)\$", key)

"""
    _parse_matrix_table(path) -> (names::Vector{String}, M::Matrix{Float64})

Parses a `.rcm`/`.acm` square-matrix table (header row naming the
columns, dashed separator, then one row per parameter: a row LABEL
followed by exactly as many numeric fields as there are columns --
confirmed directly against the real binary that `.acm`'s row label
carries one extra non-numeric field vs. `.rcm`'s own, single-field row
label; handled generically here by taking the trailing N fields as data
and joining everything before them as the label, rather than assuming
either shape specifically).
"""
function _parse_matrix_table(path::AbstractString)
    lines = readlines(path)
    ncols = length(split(lines[1], '\t')) - 1
    names = String[]
    rows = Vector{Float64}[]
    for line in @view lines[3:end]
        isempty(strip(line)) && continue
        parts = split(line, '\t')
        length(parts) >= ncols + 1 || continue
        vals = tryparse.(Float64, parts[(end - ncols + 1):end])
        any(isnothing, vals) && continue
        push!(names, join(parts[1:(end - ncols)], " "))
        push!(rows, Float64.(vals))
    end
    M = Matrix{Float64}(undef, length(rows), ncols)
    for (i, row) in enumerate(rows)
        M[i, :] = row
    end
    return names, M
end

"""
    StatsAPI.vcov(r::X13Result) -> Matrix{Float64}

Sized `length(coef(r)) x length(coef(r))`, aligned to
`StatsAPI.coefnames`'s own order. The regression-coefficient
block comes from `.rcm`, the ARIMA/ARMA-coefficient block from `.acm`
(re-run via `save` if not already present, same convention as
[`series`](@ref)); cross-covariance between the two families is `NaN`
(genuinely not reported by X-13, not assumed zero). Throws
`ErrorException` if the model has no coefficients at all (nothing to
return -- the same reasoning that applies to the pure-`.udg`
case).

**Verified, not assumed**: `.rcm`/`.acm`'s row order is checked against
`.udg`'s own coefficient count before use (`sqrt.(diag(V))` should
reproduce `StatsAPI.stderror` -- asserted directly in this
package's own test suite, not just hoped for).

**A real, honest scope limitation, found directly**: a `trading=true`
regression reports a 7th, DERIVED coefficient (`"Trading Day\$Sun"`,
Sunday's effect implied by the other six, not independently estimated)
that `.udg`'s own coefficient block includes but `.rcm`'s covariance
matrix does NOT (6 rows, not 7) -- `nregderived` in [`StatsAPI.dof`](@ref)'s
own docstring is exactly this. Rather than guess which coefficient(s) a
count mismatch corresponds to, this throws a clear `ErrorException`
naming the row-count mismatch instead of silently misaligning the
matrix. Models whose regression coefficients are all independently
estimated (holiday/user/easter-style single regressors, or trading-day
WITHOUT the derived 7th term) are unaffected -- this is specifically a
trading-day-regression gap, not a general one.

**A second, separate finding**: X-13 does not write `.rcm` AT ALL for
exactly ONE regression coefficient (confirmed directly -- a run with
only `easter[1]` produces no `.rcm` file at all, even on success with no
error; the same spec with a second, independent regression variable
added DOES produce it). Presumably a 1x1 "covariance matrix" is
considered redundant with `stderror` alone. `vcov` still throws its
regular `ErrorException` in that case (via the same "output table does
not exist" path [`series`](@ref) already uses), not a silent empty
matrix.

# Examples
```julia
julia> res = x13(dataset("airline").value; start = (1949, 1),
                  regression_variables = ["easter[1]", "labor[1]"], automdl = true, transform = :log);

julia> V = StatsAPI.vcov(res);

julia> size(V)
(4, 4)

julia> sqrt.(diag(V)) ≈ StatsAPI.stderror(res)
true
```

The `trading=true` derived-coefficient gap noted above, reproduced
directly:
```julia
julia> res_td = x13(dataset("airline").value; start = (1949, 1), trading = true, automdl = true, transform = :log);

julia> StatsAPI.vcov(res_td)
ERROR: vcov(): .rcm has 6 rows but 7 regression coefficients were found in .udg -- refusing to guess at the alignment
```
"""
function StatsAPI.vcov(r::X13Result)
    coefs = _coefficient_lines(_udg_path(r))
    isempty(coefs) && throw(ErrorException(
        "vcov(::X13Result) is not available -- no regression or ARIMA coefficients were " *
        "estimated",
    ))
    reg_idx = findall(c -> !_is_arma_coefficient_key(c.key), coefs)
    arma_idx = findall(c -> _is_arma_coefficient_key(c.key), coefs)
    needed = Symbol[]
    isempty(reg_idx) || push!(needed, :rcm)
    isempty(arma_idx) || push!(needed, :acm)
    result, _ = _ensure_saved(r, needed; label = "vcov()")

    n = length(coefs)
    V = fill(NaN, n, n)
    if !isempty(reg_idx)
        _, rcm = _parse_matrix_table(joinpath(result.dir, "$(result.basename).rcm"))
        size(rcm, 1) == length(reg_idx) || throw(ErrorException(
            "vcov(): .rcm has $(size(rcm,1)) rows but $(length(reg_idx)) regression " *
            "coefficients were found in .udg -- refusing to guess at the alignment",
        ))
        V[reg_idx, reg_idx] = rcm
    end
    if !isempty(arma_idx)
        _, acm = _parse_matrix_table(joinpath(result.dir, "$(result.basename).acm"))
        size(acm, 1) == length(arma_idx) || throw(ErrorException(
            "vcov(): .acm has $(size(acm,1)) rows but $(length(arma_idx)) ARIMA " *
            "coefficients were found in .udg -- refusing to guess at the alignment",
        ))
        V[arma_idx, arma_idx] = acm
    end
    return V
end

"""
    StatsBase.coeftable(r::X13Result) -> StatsBase.CoefTable

Estimate/Std.Error/t value for every coefficient `StatsAPI.coef`
reports, straight from `.udg`'s own three-field coefficient lines (no
[`StatsAPI.vcov`](@ref) needed for this much -- `_coefficient_lines`
already carries the t-statistic X-13 itself computed). Extends
`StatsBase.coeftable` (used fully-qualified, matching this file's own
`StatsAPI.aic`-style convention -- not re-exported under the bare name,
since `StatsBase` already defines and exports one). **p-values are
deliberately NOT included**: computing one needs a t-distribution CDF,
which would mean either a new dependency (`Distributions.jl`, for one
column) or leaning on TSAnalytics.jl exposing one, neither confirmed
worth it yet -- the same open question applies to a possible future
Q-Q plot panel. Flagged here rather than silently guessed at.

# Examples
```julia
julia> res = x13(dataset("airline").value; start = (1949, 1),
                  regression_variables = ["easter[1]", "labor[1]"], automdl = true, transform = :log);

julia> StatsBase.coeftable(res)
────────────────────────────────────────────────────
                       Estimate   Std.Error  t value
────────────────────────────────────────────────────
Easter[1]             0.0201786  0.00952065  2.11946
Labor[1]              0.0287849  0.0112048   2.56898
MA\$Nonseasonal\$01\$01  0.344444   0.0808494   4.26032
MA\$Seasonal\$12\$12     0.548218   0.0775167   7.07226
────────────────────────────────────────────────────
```
"""
function StatsBase.coeftable(r::X13Result)
    lines = _coefficient_lines(_udg_path(r))
    names = [_coefficient_name(c.key) for c in lines]
    est = [c.estimate for c in lines]
    se = [c.stderror for c in lines]
    t = [c.tstat for c in lines]
    return StatsBase.CoefTable(isempty(lines) ? zeros(0, 3) : hcat(est, se, t),
        ["Estimate", "Std.Error", "t value"], names)
end

# ---------------------------------------------------------------------
# W.7.6 -- summary()/update(). Both compose existing accessors; no new
# binary-facing capability.
# ---------------------------------------------------------------------

"""
    X13Summary

[`summary`](@ref)'s return type -- a compact report (ARIMA model,
transform, N/effective N, AIC/BIC, M7 quality statistic, QS on the
seasonally adjusted series, outlier count, and a full `StatsBase.coeftable`)
with its own `show`, matching R's `summary.seas` in spirit.

# Examples
```julia
julia> res = x13(dataset("airline"); automdl = true, outlier = true, transform = :auto);

julia> SeasonalAdjustment.summary(res)
X13Summary
  ARIMA model:  (0 1 1)(0 1 1)
  Transform:    log
  N:            144  (effective: 131)
  AIC:          987.195554981389
  BIC:          995.821146950993
  Q (M7):       0.26
  QS (SA):      statistic=0.0  pvalue=1.0
  Outliers:     0

────────────────────────────────────────────────────
                       Estimate  Std.Error  t value
────────────────────────────────────────────────────
MA\$Nonseasonal\$01\$01  0.401808  0.0788697  5.09458
MA\$Seasonal\$12\$12     0.556946  0.0762554  7.30368
────────────────────────────────────────────────────
```
"""
struct X13Summary
    arima_model::Union{Nothing,String}
    transform::Union{Nothing,Symbol}
    n::Int
    n_effective::Union{Nothing,Int}
    aic::Union{Nothing,Float64}
    bic::Union{Nothing,Float64}
    q::Union{Nothing,Float64}
    qs_sa::Union{Nothing,NamedTuple}
    outlier_total::Union{Nothing,Int}
    coeftable::StatsBase.CoefTable
end

# ---------------------------------------------------------------------
# W.8.3 -- check.acf/check.pacf/check.acfsquared (.acf/.pcf/.ac2), for
# residdiagplot. Confirmed directly against the real binary: yet ANOTHER
# distinct column format -- `Lag\tSample_ACF\tSE_of_ACF\tLjung-Box_Q\t
# df_of_Q\tP-value` for .acf/.ac2 (6 columns), `Lag\tSample_PACF\t
# S.E._of_PACF` for .pcf (3 columns) -- neither parse_table's 2-column
# nor _parse_matrix_table's square-matrix shape, so series() correctly
# refuses these (they're in the "spectrum" block's sibling "check"
# block, not covered by _SPECTRUM_FORMAT_TABLES at all -- a check-block
# table was never going to reach that code path regardless). Only the
# PRIMARY statistic column (the 2nd tab-separated field) is fetched --
# the one residdiagplot's ACF/PACF panels actually draw; the standard
# error / Ljung-Box columns are not currently exposed anywhere.
# ---------------------------------------------------------------------

function _parse_check_table(path::AbstractString)
    lines = readlines(path)
    out = Float64[]
    for line in @view lines[3:end]
        isempty(strip(line)) && continue
        parts = split(line, '\t')
        length(parts) >= 2 || continue
        v = tryparse(Float64, parts[2])
        v === nothing && continue
        push!(out, v)
    end
    return out
end

"""
    _check_series(r::X13Result, table::Symbol) -> Vector{Float64}

The primary statistic column of a `check{}`-block table (`:acf`, `:pcf`,
or `:ac2`) -- re-runs via `save` (same convention as [`series`](@ref))
if not already present.
"""
function _check_series(r::X13Result, table::Symbol)
    table in (:acf, :pcf, :ac2) || throw(ArgumentError(
        "_check_series: :$table isn't a check{}-block table -- must be :acf, :pcf, or :ac2",
    ))
    result, _ = _ensure_saved(r, [table]; label = "residdiagplot()")
    path = joinpath(result.dir, "$(result.basename).$table")
    isfile(path) || throw(ErrorException(
        "residdiagplot(): output table $path (requested :$table) does not exist after the run",
    ))
    return _parse_check_table(path)
end

"""
    SeasonalAdjustment.summary(r::X13Result) -> X13Summary

Composes [`arima_model`](@ref)/[`transformfunction`](@ref)/
[`mstats`](@ref)/[`qs`](@ref)/[`outlier_counts`](@ref)/`StatsBase.coeftable`
into one report -- no new capability, just a single convenient bundle.
**Not exported** (confirmed directly: `Base` already
has its own `summary`, a different one-line-descriptive-string contract
-- `using SeasonalAdjustment` would collide with it) -- call this
fully-qualified, `SeasonalAdjustment.summary(r)`.
"""
function summary(r::X13Result)
    m = mstats(r)
    oc = outlier_counts(r)
    return X13Summary(
        arima_model(r), transformfunction(r), length(r.observed), nobs_effective(r),
        _udg_float(r.udg, "aic"), _udg_float(r.udg, "bic"),
        m === nothing ? nothing : m.q,
        qs(r).sa, oc.total, StatsBase.coeftable(r),
    )
end

function Base.show(io::IO, ::MIME"text/plain", s::X13Summary)
    println(io, "X13Summary")
    s.arima_model !== nothing && println(io, "  ARIMA model:  ", s.arima_model)
    s.transform !== nothing && println(io, "  Transform:    ", s.transform)
    print(io, "  N:            ", s.n)
    s.n_effective !== nothing && print(io, "  (effective: ", s.n_effective, ")")
    println(io)
    s.aic !== nothing && println(io, "  AIC:          ", s.aic)
    s.bic !== nothing && println(io, "  BIC:          ", s.bic)
    s.q !== nothing && println(io, "  Q (M7):       ", s.q)
    s.qs_sa !== nothing && println(io, "  QS (SA):      statistic=", s.qs_sa.statistic, "  pvalue=", s.qs_sa.pvalue)
    s.outlier_total !== nothing && println(io, "  Outliers:     ", s.outlier_total)
    println(io)
    show(io, s.coeftable)
end

"""
    update(r::X13Result; kwargs...) -> X13Result

`X13Spec(r.spec; kwargs...)` then re-runs (via the same `_run_spec`
tail [`x13`](@ref) itself uses) -- R's `seasonal::update.seas`. `r`
itself is untouched (`X13Result`/`X13Spec` are both immutable).

# Examples
```julia
julia> res = x13(dataset("airline"); automdl = true, outlier = true, transform = :auto);

julia> res2 = update(res; outlier = false);

julia> res2.spec.outlier
false

julia> res.spec.outlier  # the original is untouched
true
```
"""
function update(r::X13Result; kwargs...)
    new_spec = X13Spec(r.spec; kwargs...)
    return _run_spec(new_spec; label = "update()")
end

# ---------------------------------------------------------------------
# W.7.8 -- sliding spans / revision history. W.5's open question 3,
# settled directly this session: BOTH land rich summary statistics in
# `.udg` itself (confirmed: `ss*`/`s2.*`/`s3.*` for sliding spans,
# `r0N.lag00.*`/`revspan` for history) -- no separate table parsing
# needed for the summaries themselves. Given the sheer number of fields
# X-13 produces here (dozens, spanning per-period/per-year/hinge/
# breakdown-by-threshold detail), these accessors surface the headline
# numbers as typed fields plus a `raw` escape hatch (every matching
# `.udg` key, for anything not promoted to its own field) rather than
# modeling every single one -- consistent with not gold-plating a
# feature nobody has asked for the full depth of yet.
# ---------------------------------------------------------------------

# The last whitespace-separated token of a .udg value, as Float64 -- .udg
# lines under slidingspans/history mix plain single-float values
# ("0.21") with "label value" pairs ("Jan   91.12"); this handles both.
function _udg_last_float(d::AbstractDict, key::AbstractString)
    haskey(d, key) || return nothing
    toks = split(strip(d[key]))
    isempty(toks) && return nothing
    return tryparse(Float64, toks[end])
end

"""
    slidingspans(r::X13Result) -> Union{Nothing,NamedTuple}

`nothing` if `slidingspans{}` wasn't requested (`udg(r, "sspans") !=
"yes"`); otherwise `(seasonal_pct=, sachange_pct=, trend_pct=, td_pct=,
raw=)` -- the headline "percentage of months flagged unstable" figures
(`ssm7`'s own 4 values: seasonal/SA-percent-change/trend/TD, confirmed
directly against `.udg`) plus `raw`, every `ss*`/`s2.*`/`s3.*` key
verbatim, for anything not promoted to a typed field.

# Examples
`slidingspans{}` (or any spec_args entry naming it) must be requested
explicitly -- it is not on by default:
```julia
julia> res = x13(dataset("airline"); start = (1949, 1), spec_args = Dict("slidingspans" => ""));

julia> ss = slidingspans(res);

julia> propertynames(ss)
(:seasonal_pct, :sachange_pct, :trend_pct, :td_pct, :raw)

julia> res_bare = x13(dataset("airline"));

julia> slidingspans(res_bare) === nothing
true
```
"""
function slidingspans(r::X13Result)
    udg(r, "sspans") == "yes" || return nothing
    d = r.udg
    m7 = get(d, "ssm7", nothing)
    m7_vals = m7 === nothing ? nothing : tryparse.(Float64, split(m7))
    raw = Dict(k => v for (k, v) in d if startswith(k, "ss") || startswith(k, "s2.") || startswith(k, "s3."))
    return (
        seasonal_pct = m7_vals === nothing || length(m7_vals) < 1 ? nothing : m7_vals[1],
        sachange_pct = m7_vals === nothing || length(m7_vals) < 2 ? nothing : m7_vals[2],
        trend_pct = m7_vals === nothing || length(m7_vals) < 3 ? nothing : m7_vals[3],
        td_pct = m7_vals === nothing || length(m7_vals) < 4 ? nothing : m7_vals[4],
        raw = raw,
    )
end

"""
    revision_history(r::X13Result) -> Union{Nothing,NamedTuple}

`nothing` if `history{}` wasn't requested (`udg(r, "history") !=
"yes"`); otherwise `(sa_estimates=, raw=)` -- `sa_estimates` collects
every `r0N.lag00.aar.*` (average absolute revision) value found (the
concurrent-vs-most-recent seasonally adjusted revision history), `raw`
every `r0*`/`revspan` key verbatim.

# Examples
`history{}` must be requested explicitly, naming which estimates to
track:
```julia
julia> res = x13(dataset("airline"); start = (1949, 1),
                  spec_args = Dict("history.estimates" => "(sadj sadjchng)"));

julia> h = revision_history(res);

julia> length(h.sa_estimates)
38

julia> h.sa_estimates[1]
0.9915460157

julia> revision_history(x13(dataset("airline"))) === nothing
true
```
"""
function revision_history(r::X13Result)
    udg(r, "history") == "yes" || return nothing
    d = r.udg
    aar_keys = sort([k for k in keys(d) if occursin(r"^r\d+\.lag00\.aar\.", k)])
    sa_estimates = filter(!isnothing, [_udg_last_float(d, k) for k in aar_keys])
    raw = Dict(k => v for (k, v) in d if startswith(k, "r0") || k == "revspan")
    return (sa_estimates = sa_estimates, raw = raw)
end

"""
    select_order(y; kwargs...) -> NamedTuple

`(order=(p,d,q), seasonal_order=(P,D,Q,period), transform=:log|:none)` --
matches `statsmodels.tsa.x13.x13_arima_select_order`. Thin: runs
[`x13`](@ref) with `automdl=true` (accepting the same kwargs `x13`
does), then parses the resolved `arimamdl` string and [`transformfunction`](@ref)
back out of the result.

# Examples
```julia
julia> select_order(dataset("airline"))
(order = (3, 1, 1), seasonal_order = (0, 1, 1, 12), transform = :none)
```

Note this searches under whatever kwargs are passed -- with no
`aictest`/`transform` requested here, it is a different search (and a
different result) than the fuller `automdl=true, aictest=[:td,:easter],
transform=:auto` specification used elsewhere in this documentation.
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

# Examples
```julia
julia> res = x13(dataset("airline"); automdl = true, outlier = true, transform = :auto);

julia> open_output(res)  # opens the binary's own HTML report in the default browser
```
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
 under `"blockname.key"`. Not a general X-13 grammar parser --
comments and unusual multi-line quoting are not handled.

**One confirmed, real information gap**: `outlier { types = (ao ls tc) }`
sets `outlier=true` but the specific `types=` list is DROPPED, not
preserved -- `X13Spec` has no typed field for outlier types yet, and
`spec_args` can't target `outlier` since it's already a typed-field
block (see [`validate!`](@ref)). Silently losing this would be worse
than documenting it: check the source `.spc` by hand if `outlier.types`
matters for your use case.

# Examples
This needs no real X-13 run -- it is pure text parsing, so it is a
genuine jldoctest:
```jldoctest
julia> spc_text = \"\"\"
       series {
         title = "demo"
         start = 1949.1
         data = (112 118 132 129 121 135 148 148 136 119 104 118
       115 126 141 135 125 149 170 170 158 133 114 140
       145 150 178 163 172 178 199 199 184 162 146 166
       171 180 193 181 183 218 230 242 209 191 172 194
       196 196 236 235 229 243 264 272 237 211 180 201
       204 188 235 227 234 264 302 293 259 229 203 229
       242 233 267 269 270 315 364 347 312 274 237 278
       284 277 317 313 318 374 413 405 355 306 271 306
       315 301 356 348 355 422 465 467 404 347 305 336
       340 318 362 348 363 435 491 505 404 359 310 337
       360 342 406 396 420 472 548 559 463 407 362 405
       417 391 419 461 472 535 622 606 508 461 390 432)
       }
       transform { function = log }
       automdl { }
       \"\"\";

julia> path = joinpath(mktempdir(), "demo.spc");

julia> write(path, spc_text);

julia> spec = import_spc(path);

julia> spec.transform
:log

julia> spec.automdl
true

julia> spec.start
(1949, 1)
```
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

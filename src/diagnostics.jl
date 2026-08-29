# src/diagnostics.jl
#
# W.5 -- a typed accessor layer over the .udg diagnostics dict `parse_udg`
# already returns. See handoff/w5-diagnostics-api-handoff.md for the
# verified references (every value quoted there, and every value asserted
# in this file's own tests, was checked directly against the real
# committed fixture `handoff/udg_and_residuals/auto_test.udg` -- not
# assumed from the handoff's prose).
#
# Design principle (per the handoff): `parse_udg` stays exactly as it is
# -- raw `Dict{String,String}`, no numeric coercion. This layer sits on
# top and NEVER throws for a missing key; it returns `nothing` (or an
# empty collection where a collection is the natural "absent" value).
# A `.udg` from a SEATS run, a quarterly run, or a run without `automdl`
# legitimately lacks whole families of keys -- an accessor that threw
# would make every caller wrap in `haskey`.
#
# Every function here is defined on a plain `AbstractDict` first (so it's
# testable against the fixture with zero subprocess calls), with a
# matching `X13Result`-dispatching method added in api.jl once
# `X13Result` itself is defined (this file is included BEFORE api.jl,
# so it cannot reference that type).

# ---------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------

"""
    _udg_float(d, key) -> Union{Float64,Nothing}

Parses `d[key]` as a `Float64` (handles Fortran E-notation, e.g.
`"0.946662093458382E+03"`, directly -- confirmed `parse(Float64, ...)`
needs no preprocessing for this format). `nothing` if the key is absent
or doesn't parse.
"""
function _udg_float(d::AbstractDict, key::AbstractString)
    haskey(d, key) || return nothing
    return tryparse(Float64, strip(d[key]))
end

"""
    _udg_int(d, key) -> Union{Int,Nothing}

As `_udg_float`, but for plain integer fields (e.g. `nobs`, `nreg`).
"""
function _udg_int(d::AbstractDict, key::AbstractString)
    haskey(d, key) || return nothing
    return tryparse(Int, strip(d[key]))
end

"""
    _udg_fields(d, key) -> Union{Vector{String},Nothing}

Whitespace-splits `d[key]` -- several `.udg` values are multi-field
(`qsori` is `"statistic p-value"`, coefficient lines are
`"estimate std-error t-statistic"`). `nothing` if the key is absent.
"""
function _udg_fields(d::AbstractDict, key::AbstractString)
    haskey(d, key) || return nothing
    return split(strip(d[key]))
end

"""
    _udg_pair(d, key) -> Union{Tuple{Float64,Float64},Nothing}

As `_udg_fields`, but parses exactly the first two whitespace-separated
fields as `Float64` and returns a plain 2-tuple `(a, b)`. `nothing` if
the key is absent or doesn't have at least 2 parseable fields.
"""
function _udg_pair(d::AbstractDict, key::AbstractString)
    fields = _udg_fields(d, key)
    fields === nothing && return nothing
    length(fields) >= 2 || return nothing
    a = tryparse(Float64, fields[1])
    b = tryparse(Float64, fields[2])
    (a === nothing || b === nothing) && return nothing
    return (a, b)
end

"""
    _udg_qs_pair(d, key) -> Union{NamedTuple,Nothing}

As `_udg_pair`, but returns `(statistic=, pvalue=)` -- the shape [`qs`](@ref)
uses for each of its four component series.
"""
function _udg_qs_pair(d::AbstractDict, key::AbstractString)
    p = _udg_pair(d, key)
    p === nothing && return nothing
    return (statistic = p[1], pvalue = p[2])
end

"""
    _udg_indexed(d, prefix, n) -> Vector{Union{Float64,Nothing}}

Reads the zero-padded family `\$(prefix)01`, `\$(prefix)02`, ... up to
`\$(prefix)\$n` (e.g. `prefix="f3.m"`, `n=11` reads `f3.m01`..`f3.m11`) --
`.udg` zero-pads to 2 digits (`f3.m01`, not `f3.m1`), a formatting detail
that silently produces all-`nothing`s if missed.
"""
_udg_indexed(d::AbstractDict, prefix::AbstractString, n::Integer) =
    [_udg_float(d, prefix * lpad(i, 2, '0')) for i in 1:n]

"""
    _udg_lag_table(d, value_prefix, lags_key) -> Vector{NamedTuple}

Reads a lag-indexed family (`lbq\$03`, `lbq\$04`, ... for
`value_prefix="lbq"`) using the companion `lags_key` field to know which
lag numbers exist. `lags_key` is NOT a mechanical `value_prefix * "lags"`
-- confirmed directly against the fixture this is a real, irregular
naming split: `lbq`'s own lags field is `lblags` (the trailing `q`
dropped), same for `bpq`/`bplags`, while `sigacf`/`sigpacf` instead use
their own FULL name plus `lags` (`sigacflags`/`sigpacflags`). Callers
must pass the correct `lags_key` explicitly rather than have it guessed
-- a first version of this function guessed `value_prefix * "lags"`
uniformly and silently returned an empty table for `lbq` as a result
(`"lbqlags"` is not a real key). Each value line is `statistic df
pvalue`. Returns `NamedTuple[]` (not `nothing`) if the lags list itself
is absent -- an empty table, not a missing one.
"""
function _udg_lag_table(d::AbstractDict, value_prefix::AbstractString, lags_key::AbstractString)
    lagstr = get(d, lags_key, nothing)
    lagstr === nothing && return NamedTuple[]
    lags = tryparse.(Int, split(strip(lagstr)))
    any(isnothing, lags) && return NamedTuple[]
    out = NamedTuple[]
    for lag in lags
        fields = _udg_fields(d, "$value_prefix\$" * lpad(lag, 2, '0'))
        fields === nothing && continue
        length(fields) == 3 || continue
        stat = tryparse(Float64, fields[1])
        dfv = tryparse(Float64, fields[2])
        pv = tryparse(Float64, fields[3])
        (stat === nothing || dfv === nothing || pv === nothing) && continue
        push!(out, (lag = lag, statistic = stat, df = dfv, pvalue = pv))
    end
    return out
end

# ---------------------------------------------------------------------
# Public accessors -- all take a plain `Dict`-like object here; the
# X13Result-dispatching overloads (`f(r::X13Result) = f(r.udg)`) are
# added in api.jl.
# ---------------------------------------------------------------------

"""
    transformfunction(d) -> Union{Symbol,Nothing}

Resolves the transform actually used, normalized to `:log`/`:none`.
Mirrors R's `seasonal::transformfunction()`.

Two of these four rules were CONFIRMED DIRECTLY this session (not
assumed from the committed fixture, which only has an automatic-selection
run) by running explicit `transform=:log` and `transform=:none` specs
through the real binary with `udg=true` and inspecting the result:

| Condition | Returns | Confirmed how |
|---|---|---|
| `aictrans == "Log(y)"` | `:log` | automatic selection, log wins -- the committed fixture |
| `transform == "No transformation"` | `:none` | automatic selection, log doesn't win (fixture) **and** an explicit `transform=:none` spec (confirmed directly this session -- same exact string both ways, a real finding: an earlier draft of this accessor's design assumed a separate literal `"None"` string for the explicit case, which does NOT occur in practice) |
| `transform == "Log(y)"` | `:log` | an explicit `transform=:log` spec (confirmed directly this session) |
| `transform == "None"` | `:none` | NOT confirmed against any real fixture -- kept only as a defensive alias in case another `x13ashtml` build/version emits it; do not rely on this case being real |
| anything else | `nothing` | never guess |

Reused by [`static`](@ref) rather than duplicated.
"""
function transformfunction(d::AbstractDict)
    get(d, "aictrans", "") == "Log(y)" && return :log
    t = get(d, "transform", "")
    t in ("No transformation", "None") && return :none
    t == "Log(y)" && return :log
    return nothing
end

"""
    arima_model(d) -> Union{String,Nothing}

The ARIMA model actually used (e.g. `"(0 1 1)(0 1 1)"`), from `arimamdl`
-- whether it came from `automdl` or was already explicit.
"""
arima_model(d::AbstractDict) = get(d, "arimamdl", nothing)

"""
    mstats(d) -> Union{NamedTuple,Nothing}

`(m1=…, m2=…, …, m11=…, q=…, qm2=…, fail=…)` -- the M1-M11 statistics,
overall quality `Q`, `Q-M2`, and the `f3.fail` count. `nothing` only if
`f3.q` itself is absent -- CONFIRMED directly this session (not just
inferred) by running a real SEATS spec with `-S`: a SEATS run's `.udg`
genuinely has no `f3.*` family at all (M-statistics are an X-11-specific
diagnostic, with no SEATS equivalent). Also confirmed directly for a
quarterly spec: `f3.m01`-`f3.m11` still has all 11 entries regardless of
`period` -- only [`filters`](@ref)'s `seasonal_ma` scales with `period`
(4 entries for quarterly, 12 for monthly), M-statistics do not.
"""
function mstats(d::AbstractDict)
    haskey(d, "f3.q") || return nothing
    m = _udg_indexed(d, "f3.m", 11)
    return (
        m1 = m[1], m2 = m[2], m3 = m[3], m4 = m[4], m5 = m[5], m6 = m[6],
        m7 = m[7], m8 = m[8], m9 = m[9], m10 = m[10], m11 = m[11],
        q = _udg_float(d, "f3.q"), qm2 = _udg_float(d, "f3.qm2"),
        fail = _udg_int(d, "f3.fail"),
    )
end

"""
    qs(d; which=:all) -> NamedTuple

QS test for seasonality, before and after adjustment. Mirrors R's
`seasonal::qs()`, which returns all rows as a matrix -- `which=:all`
(the default) is the closer analogue here.

| `which` | Returns | `.udg` key |
|---|---|---|
| `:all` | `(original=, sa=, residual=, irregular=)`, each `(statistic=, pvalue=)` or `nothing` | -- |
| `:original` | `(statistic=, pvalue=)` or `nothing` | `qsori` |
| `:sa` | as above | `qssadj` |
| `:residual` | as above | `qsrsd` |
| `:irregular` | as above | `qsirr` |

Deliberately does NOT expose the `qss*` (extreme-value-adjusted) and
`*evadj` variants at this level -- still reachable via `udg(r, "qssori")`
etc.
"""
function qs(d::AbstractDict; which::Symbol = :all)
    if which === :all
        return (
            original = _udg_qs_pair(d, "qsori"), sa = _udg_qs_pair(d, "qssadj"),
            residual = _udg_qs_pair(d, "qsrsd"), irregular = _udg_qs_pair(d, "qsirr"),
        )
    elseif which === :original
        return _udg_qs_pair(d, "qsori")
    elseif which === :sa
        return _udg_qs_pair(d, "qssadj")
    elseif which === :residual
        return _udg_qs_pair(d, "qsrsd")
    elseif which === :irregular
        return _udg_qs_pair(d, "qsirr")
    else
        throw(ArgumentError(
            "qs: which=:$which isn't recognized -- must be :all, :original, :sa, :residual, or :irregular",
        ))
    end
end

const _OUTLIER_TYPE_PREFIXES = ("AO", "LS", "TC", "RP", "SO", "TLS")
const _MONTH_ABBREV = Dict(
    "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4, "May" => 5, "Jun" => 6,
    "Jul" => 7, "Aug" => 8, "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12,
)

"""
    outliers(d; full=false) -> Vector{NamedTuple}

Parses `AutoOutlier\$<TYPE><YEAR>.<PERIOD>` keys (e.g. `AutoOutlier\$AO1951.May`
in the committed fixture). Mirrors R's `seasonal::outlier(x, full=FALSE)`.

`label` (e.g. `"AO1951.May"`) is the `AutoOutlier\$` prefix stripped and
NOTHING ELSE -- confirmed directly (W.4a) that this exact string is
itself a valid `regression_variables` entry the binary re-accepts
verbatim, reproducing the identical estimated coefficient; **do not**
convert the month name to a number for `label`. `period`, by contrast, IS
converted to an integer (`5` for `"May"`) purely for display/analysis --
that field is never fed back into a spec, so the conversion doesn't
contradict the `label` rule above. `period` is `nothing` if the trailing
token isn't a recognized 3-letter month abbreviation (e.g. an unconfirmed
quarterly-labeling scheme) -- left unresolved rather than guessed.

| `full` | Element shape |
|---|---|
| `false` (default) | `(label=, type=, year=, period=)` |
| `true` | above plus `estimate=`, `stderror=`, `tstat=` |

Type symbols: `:ao`, `:ls`, `:tc`, `:rp`, `:so`, `:tls`.
"""
function outliers(d::AbstractDict; full::Bool = false)
    out = NamedTuple[]
    for (k, v) in d
        startswith(k, "AutoOutlier\$") || continue
        label = k[(ncodeunits("AutoOutlier\$") + 1):end]
        m = match(r"^(AO|LS|TC|RP|SO|TLS)(\d{4})\.(.+)$", label)
        m === nothing && continue
        typesym = Symbol(lowercase(m.captures[1]))
        year = parse(Int, m.captures[2])
        period_token = m.captures[3]
        period = get(_MONTH_ABBREV, period_token, tryparse(Int, period_token))
        base = (label = label, type = typesym, year = year, period = period)
        if full
            fields = split(strip(v))
            if length(fields) == 3
                est, se, t = tryparse(Float64, fields[1]), tryparse(Float64, fields[2]), tryparse(Float64, fields[3])
                push!(out, merge(base, (estimate = est, stderror = se, tstat = t)))
            else
                push!(out, merge(base, (estimate = nothing, stderror = nothing, tstat = nothing)))
            end
        else
            push!(out, base)
        end
    end
    return out
end

"""
    outlier_counts(d) -> NamedTuple

`(ao=, ls=, tc=, rp=, so=, tls=, total=)` from `outlier.ao`/`.ls`/`.tc`/
`.rp`/`.so`/`.tls`/`.total`. Each field is `nothing` if that key is
absent (e.g. `outlier=false` was passed, so no outlier detection ran at
all).
"""
outlier_counts(d::AbstractDict) = (
    ao = _udg_int(d, "outlier.ao"), ls = _udg_int(d, "outlier.ls"),
    tc = _udg_int(d, "outlier.tc"), rp = _udg_int(d, "outlier.rp"),
    so = _udg_int(d, "outlier.so"), tls = _udg_int(d, "outlier.tls"),
    total = _udg_int(d, "outlier.total"),
)

"""
    fivebestmdl(d) -> Union{Vector{NamedTuple},Nothing}

`[(model=, bic=), …]`, up to 5, in rank order, from
`automdl.best5.mdl01`-`05`/`automdl.best5.bic01`-`05`. `nothing` when
`automdl` didn't run (no `automdl.best5.mdl01` key at all). Stops at the
first missing index rather than assuming five are always present.
"""
function fivebestmdl(d::AbstractDict)
    haskey(d, "automdl.best5.mdl01") || return nothing
    out = NamedTuple[]
    i = 1
    while true
        mdl_key = "automdl.best5.mdl" * lpad(i, 2, '0')
        haskey(d, mdl_key) || break
        bic_key = "automdl.best5.bic" * lpad(i, 2, '0')
        push!(out, (model = d[mdl_key], bic = _udg_float(d, bic_key)))
        i += 1
    end
    return out
end

"""
    seasonality_tests(d) -> Union{NamedTuple,Nothing}

`(stable_f=, stable_d8_f=, kruskal_wallis=, moving_seasonality=,
identifiable=)`, each a plain `(F_or_stat, pvalue)` tuple except
`identifiable::Bool` (from `f2.idseasonal`, `"yes"`/`"no"`). `nothing` if
`f2.fsb1` itself is absent. Nothing in R's `seasonal` exposes these as a
function -- a genuine addition, not just parity.
"""
function seasonality_tests(d::AbstractDict)
    haskey(d, "f2.fsb1") || return nothing
    return (
        stable_f = _udg_pair(d, "f2.fsb1"), stable_d8_f = _udg_pair(d, "f2.fsd8"),
        kruskal_wallis = _udg_pair(d, "f2.kw"), moving_seasonality = _udg_pair(d, "f2.msf"),
        identifiable = get(d, "f2.idseasonal", "") == "yes",
    )
end

"""
    residual_diagnostics(d) -> NamedTuple

`(durbin_watson=, skewness=, kurtosis=, ljung_box=, n_ljung_box=,
n_sig_acf=, n_sig_pacf=)`. `ljung_box` is the full lag-indexed table
(`[(lag=, statistic=, df=, pvalue=), …]`, from `lbq\$NN`/`lblags`), not a
single value -- the raw `.udg` data itself is lag-indexed, not scalar.
"""
residual_diagnostics(d::AbstractDict) = (
    durbin_watson = _udg_float(d, "durbinwatson"), skewness = _udg_float(d, "skewness"),
    kurtosis = _udg_float(d, "kurtosis"), ljung_box = _udg_lag_table(d, "lbq", "lblags"),
    n_ljung_box = _udg_int(d, "nlbq"), n_sig_acf = _udg_int(d, "nsigacf"),
    n_sig_pacf = _udg_int(d, "nsigpacf"),
)

"""
    spectral_peaks(d) -> NamedTuple

`(seasonal=, trading_day=)`, each a `Vector{Symbol}` naming which
series (`:ori`/`:sa`/`:rsd`/`:irr`) show a visually significant peak, from
`peaks.seas`/`peaks.td`. Empty vector when the key is absent or reads
`"none"`. This is what R's own summary output (and what the Python
reference pipeline scraped out of the HTML report as
`trading_day_peak_warning`) reduces to.
"""
function spectral_peaks(d::AbstractDict)
    parse_list(key) = begin
        v = get(d, key, nothing)
        (v === nothing || strip(v) == "none") ? Symbol[] : Symbol.(split(strip(v)))
    end
    return (seasonal = parse_list("peaks.seas"), trading_day = parse_list("peaks.td"))
end

"""
    filters(d) -> NamedTuple

`(seasonal_ma=, trend_ma=, mode=, sa_mode=, unit_root=)` -- the moving-
average filters and mode X-11 actually chose. `seasonal_ma` is a
`Vector{String}` with one entry per calendar period -- confirmed
directly, not assumed, that this genuinely scales with `period` (12
`"MSR"` entries for a monthly spec, 4 for quarterly, checked against a
real run of each); `trend_ma` an `Int` (falls back to the raw string if
it isn't purely numeric); `mode` a `Symbol` (`:multiplicative` etc.,
from `finmode`). Empty for a SEATS spec (confirmed directly: SEATS uses
no X-11-style seasonal-MA filter at all, so `finaltrendma`/`seasonalma`
are simply absent from a SEATS `.udg`).
"""
function filters(d::AbstractDict)
    sma = get(d, "seasonalma", nothing)
    seasonal_ma = sma === nothing ? String[] : split(strip(sma))
    tma_raw = get(d, "finaltrendma", nothing)
    trend_ma = tma_raw === nothing ? nothing : something(tryparse(Int, strip(tma_raw)), strip(tma_raw))
    mode_raw = get(d, "finmode", nothing)
    mode = mode_raw === nothing ? nothing : Symbol(strip(mode_raw))
    return (
        seasonal_ma = seasonal_ma, trend_ma = trend_ma, mode = mode,
        sa_mode = get(d, "samode", nothing), unit_root = get(d, "finalur", nothing),
    )
end

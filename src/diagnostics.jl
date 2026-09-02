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

# Examples
```jldoctest
julia> transformfunction(Dict("aictrans" => "Log(y)", "transform" => "Automatic selection"))
:log

julia> transformfunction(Dict("transform" => "No transformation"))
:none

julia> transformfunction(Dict("nreg" => "3")) === nothing
true
```
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

# Examples
```jldoctest
julia> arima_model(Dict("arimamdl" => "(0 1 1)(0 1 1)"))
"(0 1 1)(0 1 1)"
```
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

Each ``M_i`` is scaled to the range ``[0, 3]``, and the overall quality
statistic ``Q`` is a weighted combination of all eleven. The Census
Bureau's own published convention (X-11-ARIMA/2000 documentation) is
that ``Q < 1.0`` indicates an acceptable adjustment; this package does
not itself apply that threshold anywhere -- it is stated here purely
for interpreting the returned value, not enforced as a pass/fail rule.

# Examples
```jldoctest
julia> d = Dict("f3.m01" => "0.041", "f3.m02" => "0.042", "f3.m03" => "0.000",
                 "f3.m04" => "0.283", "f3.m05" => "0.190", "f3.m06" => "0.703",
                 "f3.m07" => "0.203", "f3.m08" => "0.418", "f3.m09" => "0.368",
                 "f3.m10" => "0.431", "f3.m11" => "0.418", "f3.q" => "0.20",
                 "f3.qm2" => "0.22", "f3.fail" => "0");

julia> mstats(d).q
0.2

julia> mstats(d).fail
0

julia> mstats(Dict("nreg" => "3")) === nothing
true
```
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

The QS statistic is a Ljung-Box-style portmanteau test restricted to
the autocorrelations at the seasonal lag and its first harmonic (lag
``s`` and ``2s``, e.g. 12 and 24 for a monthly series), rather than a
whole run of consecutive lags:

```math
QS = n(n+2)\\left(\\frac{\\hat{\\rho}_s^2}{n-s} + \\frac{\\hat{\\rho}_{2s}^2}{n-2s}\\right)
```

Under the null of no residual seasonality, ``QS`` is asymptotically
``\\chi^2_2``-distributed; a small `pvalue` is evidence that seasonality
remains in that series.

# Examples
```jldoctest
julia> d = Dict("qsori" => "167.64858    0.00000", "qssadj" => "0.00000    1.00000");

julia> qs(d; which=:original)
(statistic = 167.64858, pvalue = 0.0)

julia> qs(d; which=:sa)
(statistic = 0.0, pvalue = 1.0)

julia> qs(d; which=:residual) === nothing
true
```
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
NOTHING ELSE -- confirmed directly that this exact string is
itself a valid `regression_variables` entry the binary re-accepts
verbatim, reproducing the identical estimated coefficient; **do not**
convert the month name to a number for `label`. `period`, by contrast, IS
converted to an integer (`5` for `"May"`) purely for display/analysis --
that field is never fed back into a spec, so the conversion doesn't
contradict the `label` rule above. For a **quarterly** spec, confirmed
directly this session (a real level-shift run, `period=4`): the trailing
token is already a plain quarter-number integer (e.g. `"LS2010.1"`, not
a month abbreviation) -- the existing `tryparse(Int, ...)` fallback below
handles this correctly with no special-casing needed, and `period` here
means "quarter number" for a quarterly spec the same way it means "month
number" for a monthly one (see [`X13Spec`](@ref)'s own `start` field
convention). `period` is `nothing` only for a genuinely unrecognized
trailing token (neither a 3-letter month abbreviation nor a bare
integer) -- left unresolved rather than guessed.

| `full` | Element shape |
|---|---|
| `false` (default) | `(label=, type=, year=, period=)` |
| `true` | above plus `estimate=`, `stderror=`, `tstat=` |

Type symbols: `:ao`, `:ls`, `:tc`, `:rp`, `:so`, `:tls`.

# Examples
```jldoctest
julia> d = Dict(raw"AutoOutlier\$AO1951.May" => "+0.100155824411322E+00 +0.204386646810968E-01 +0.490031154060440E+01");

julia> outliers(d)
1-element Vector{NamedTuple}:
 (label = "AO1951.May", type = :ao, year = 1951, period = 5)

julia> outliers(d; full=true)[1].estimate
0.100155824411322
```
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

# Examples
```jldoctest
julia> d = Dict("outlier.ao" => "1", "outlier.ls" => "0", "outlier.tc" => "0",
                 "outlier.rp" => "0", "outlier.so" => "0", "outlier.tls" => "0",
                 "outlier.total" => "1");

julia> outlier_counts(d)
(ao = 1, ls = 0, tc = 0, rp = 0, so = 0, tls = 0, total = 1)
```
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

`bic` is Schwarz's Bayesian Information Criterion,
``\\mathrm{BIC} = -2\\ell + k\\log n`` for log-likelihood ``\\ell``,
``k`` estimated parameters and ``n`` effective observations -- the
lowest `bic` in the list is the model `automdl` actually selected
(rank 1, first in the vector).

# Examples
```jldoctest
julia> d = Dict("automdl.best5.mdl01" => "(0 1 0)(0 1 1)", "automdl.best5.bic01" => "-4.007",
                 "automdl.best5.mdl02" => "(1 1 1)(0 1 1)", "automdl.best5.bic02" => "-3.986");

julia> fivebestmdl(d)
2-element Vector{NamedTuple}:
 (model = "(0 1 0)(0 1 1)", bic = -4.007)
 (model = "(1 1 1)(0 1 1)", bic = -3.986)

julia> fivebestmdl(Dict("nreg" => "3")) === nothing
true
```
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

# Examples
```jldoctest
julia> d = Dict("f2.fsb1" => "164.889    0.00", "f2.fsd8" => "215.358    0.00",
                 "f2.kw" => "132.948    0.00", "f2.msf" => "3.557    0.02",
                 "f2.idseasonal" => "yes");

julia> seasonality_tests(d).stable_f
(164.889, 0.0)

julia> seasonality_tests(d).identifiable
true
```
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

`durbin_watson` tests for first-order residual autocorrelation,

```math
DW = \\frac{\\sum_{t=2}^{n}(e_t - e_{t-1})^2}{\\sum_{t=1}^{n} e_t^2}
```

with ``DW \\approx 2`` indicating no autocorrelation, ``DW < 2``
positive autocorrelation and ``DW > 2`` negative autocorrelation.
`ljung_box`'s own statistic at each lag ``m`` is

```math
Q(m) = n(n+2)\\sum_{k=1}^{m}\\frac{\\hat{\\rho}_k^2}{n-k}
```

asymptotically ``\\chi^2`` under the null of no autocorrelation up to
lag ``m``.

# Examples
```jldoctest
julia> d = Dict("durbinwatson" => "0.19503780E+01", "skewness" => "0.0900", "kurtosis" => "3.0698",
                 "nlbq" => "2", "nsigacf" => "2", "nsigpacf" => "2", "lblags" => "3 4",
                 raw"lbq\$03" => "6.813       1      0.009", raw"lbq\$04" => "7.089       2      0.029");

julia> residual_diagnostics(d).durbin_watson
1.950378

julia> residual_diagnostics(d).ljung_box
2-element Vector{NamedTuple}:
 (lag = 3, statistic = 6.813, df = 1.0, pvalue = 0.009)
 (lag = 4, statistic = 7.089, df = 2.0, pvalue = 0.029)
```
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

# Examples
```jldoctest
julia> d = Dict("peaks.seas" => "rsd sa", "peaks.td" => "sa irr");

julia> spectral_peaks(d)
(seasonal = [:rsd, :sa], trading_day = [:sa, :irr])

julia> spectral_peaks(Dict("peaks.seas" => "none"))
(seasonal = Symbol[], trading_day = Symbol[])
```
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

# Examples
```jldoctest
julia> d = Dict("seasonalma" => "MSR MSR MSR MSR MSR MSR MSR MSR MSR MSR MSR MSR",
                 "finaltrendma" => "9", "finmode" => "multiplicative",
                 "samode" => "auto-mode seasonal adjustment", "finalur" => "none");

julia> filters(d).trend_ma
9

julia> filters(d).mode
:multiplicative

julia> length(filters(d).seasonal_ma)
12
```
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

"""
    nobs_effective(d) -> Union{Int,Nothing}

`nefobs` -- the effective observation count AFTER differencing (131 in
the committed fixture, vs. `StatsAPI.nobs`'s 144) -- distinct from plain
`nobs` because ARIMA differencing costs observations. Needed by
`residplot`: regARIMA residuals run to `nefobs`, not `nobs`, so the
residual series is shorter than `r.observed`/`r.dates` by exactly that
difference, confirmed directly against the fixture (144-131=13 fewer
residual observations than the original series).

# Examples
```jldoctest
julia> nobs_effective(Dict("nefobs" => "131"))
131

julia> nobs_effective(Dict("nreg" => "3")) === nothing
true
```
"""
nobs_effective(d::AbstractDict) = _udg_int(d, "nefobs")

# W.6's own frequency grid -- the SAME five seasonal + two trading-day
# frequencies are shared across all four spectra (original/SA/irregular/
# residual); only the peak/nopeak VALUE differs per spectrum, confirmed
# directly against the fixture (a single top-level "s1.freq"/"t1.freq"
# family, not one per spcori/spcsa/spcirr/spcrsd prefix).
const _SPECTRUM_LABELS = (:s1, :s2, :s3, :s4, :s5, :t1, :t2)
const _SPECTRUM_UDG_PREFIX = Dict(:original => "spcori", :sa => "spcsa", :irregular => "spcirr", :residual => "spcrsd")

"""
    spectrum_peaks(d; series=:sa) -> Vector{NamedTuple}

`(label=, freq=, significant=)` for each of the five seasonal (`:s1`-`:s5`)
and two trading-day (`:t1`,`:t2`) frequencies X-13's own spectral
analysis reports, for the given `series` (`:original`, `:sa`,
`:irregular`, or `:residual`, mapping to the `.udg` prefixes `spcori`/
`spcsa`/`spcirr`/`spcrsd`). `freq` is read from the SHARED top-level
`s1.freq`..`t2.freq` family (confirmed directly: one frequency grid
serves all four spectra, not one per series). `significant` is `true`
only when the raw value has a trailing `"+"` flag (confirmed format:
`"15.2 +"`; `"nopeak"` and a bare value with no flag both read `false`
-- X-13's documentation describes a wider `+`/`-`/blank vocabulary than
this fixture happens to exercise, so a `"-"` or blank flag is treated
the same conservative way as no flag at all, not guessed to mean
something more specific).

Distinct from [`spectral_peaks`](@ref), which only reports WHICH
series has any significant peak at all, not which frequency -- this is
the finer-grained data `spectrumplot` needs for its frequency
markers, deferred out of the plain diagnostics-accessor scope for
exactly this.

# Examples
```jldoctest
julia> d = Dict("s1.freq" => "0.08333333", "t1.freq" => "0.34820000",
                 "spcsa.s1" => "8.5 +", "spcori.s1" => "21.0 +");

julia> spectrum_peaks(d; series=:sa)
1-element Vector{NamedTuple}:
 (label = :s1, freq = 0.08333333, significant = true)

julia> spectrum_peaks(d; series=:original)
1-element Vector{NamedTuple}:
 (label = :s1, freq = 0.08333333, significant = true)
```
"""
function spectrum_peaks(d::AbstractDict; series::Symbol = :sa)
    haskey(_SPECTRUM_UDG_PREFIX, series) || throw(ArgumentError(
        "spectrum_peaks: series=:$series isn't recognized -- must be :original, :sa, " *
        ":irregular, or :residual",
    ))
    prefix = _SPECTRUM_UDG_PREFIX[series]
    out = NamedTuple[]
    for label in _SPECTRUM_LABELS
        freq = _udg_float(d, "$label.freq")
        freq === nothing && continue
        raw = get(d, "$prefix.$label", nothing)
        raw === nothing && continue
        significant = endswith(strip(raw), "+")
        push!(out, (label = label, freq = freq, significant = significant))
    end
    return out
end

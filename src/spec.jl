# src/spec.jl
#
# W.2 -- .spc spec-file generation. See handoff/w2-spec.md for the
# verified references (the real minimum-length finding, the three
# validate! rules, each confirmed directly against the real binary) and
# the test plan this file's tests implement.

"""
    X13Spec

A validated, renderable X-13ARIMA-SEATS spec. Combines R's full
spec-argument passthrough (`regression_variables`, `arima_model` as raw
strings) with Python's curated, typed fields (`transform`, `outlier`,
`seasonal_order`, ...) -- see [`X13Spec(::AbstractVector)`](@ref) for
the actual keyword constructor; this struct itself is just the plain
field container.
"""
struct X13Spec
    y::Vector{Float64}
    start::Tuple{Int,Int}                          # (year, subperiod); subperiod is 1-12 for monthly (period=12) or 1-4 for quarterly (period=4)
    period::Int                                     # 4 (quarterly) or 12 (monthly) -- confirmed directly against the real binary that X-13 supports no other value for seasonal adjustment ("Seasonal period must be 4 or 12"); see validate!'s own new rule
    title::String
    order::NTuple{3,Int}                            # non-seasonal (p,d,q), Python-style default (0,1,1)
    seasonal_order::Union{Nothing,NTuple{4,Int}}     # seasonal (P,D,Q,period), Python-style
    arima_model::Union{Nothing,String}               # R-style raw passthrough, overrides order/seasonal_order if given
    transform::Union{Nothing,Symbol}                 # :log, :auto, :none, or nothing (no transform block)
    outlier::Bool
    automdl::Bool
    maxorder::Union{Nothing,Tuple{Int,Int}}          # automdl's (nonseasonal, seasonal) max order -- Python's maxorder; implies automdl
    maxdiff::Union{Nothing,Tuple{Int,Int}}           # automdl's (nonseasonal, seasonal) max differencing -- Python's maxdiff; implies automdl
    x11_mode::Union{Nothing,Symbol}                  # :multiplicative, :additive, :logadditive, :pseudoadditive
    seats::Bool                                       # seats{} instead of x11{}
    save::Union{Nothing,Vector{Symbol}}               # tables to save; defaults to the standard d10-d13/s10-s13 set
    trading::Bool                                      # Python's `trading` -- shorthand for adding "td" to regression_variables
    regression_variables::Vector{String}              # R-style passthrough (e.g. ["td", "easter[1]"])
    regression_user::Union{Nothing,Vector{Float64}}   # user-defined regressor DATA (W.0 generates this)
    regression_usertype::Union{Nothing,Symbol}        # e.g. :holiday, :td
    regression_user_name::Symbol                      # the regressor's name in the spec, default :user1
    exog::Union{Nothing,Vector{Float64}}              # a generic companion regressor (also triggers a regression block)
    aictest::Vector{Symbol}                            # e.g. [:td, :easter]
    residuals::Bool                                     # estimate { save = (rsd) } -- regARIMA residuals, W.4 addendum
    maxlead::Union{Nothing,Int}                         # W.7.2: forecast { maxlead = ... }; X-13 default is 12 when unset
    force::Union{Nothing,Symbol}                        # W.7.7: force { type = ... } -- :none, :denton, or :regress
    force_target::Symbol                                # W.7.7: force { target = ... } -- confirmed values only (see _FORCE_TARGET_KEYWORDS)
    seasonalma::Union{Nothing,Symbol,AbstractVector{Symbol}} # W.7.7: x11 { seasonalma = ... } -- one filter for all periods, or one per period
    spec_args::Dict{String,String}                      # W.5.4: raw "block.setting"=>"value" passthrough for any
                                                          # spec block with no typed field (slidingspans, history,
                                                          # check, pickmdl, forecast's other settings, ...); see
                                                          # render/validate!
end

"""
    X13Spec(y; start=(1980,1), period=12, title=..., order=(0,1,1), seasonal_order=nothing,
            arima_model=nothing, transform=nothing, outlier=false, automdl=false,
            maxorder=nothing, maxdiff=nothing, x11_mode=nothing, seats=false,
            save=nothing, trading=false, regression_variables=String[],
            regression_user=nothing, regression_usertype=nothing, regression_user_name=:user1,
            exog=nothing, aictest=Symbol[], residuals=false,
            maxlead=nothing, force=nothing, force_target=:original, seasonalma=nothing,
            spec_args=Dict{String,String}()) -> X13Spec

    X13Spec(base::X13Spec; kwargs...) -> X13Spec

The second form copies `base`, overriding only the fields named in
`kwargs` (e.g. `X13Spec(base; arima_model="(0 1 1)(0 1 1)", automdl=false)`)
-- re-[`validate!`](@ref)s the result like any other construction, since
an override can just as easily produce an invalid combination (e.g.
setting both `arima_model` and leaving `automdl=true`) as a fresh spec
can. Used by [`static`](@ref) to resolve an automatic spec's `:auto`
choices into an explicit, reproducible one.

Builds and [`validate!`](@ref)s a spec from `y` (a plain numeric
series -- [`x13`](@ref) (W.4) is responsible for bridging
TSAnalytics.jl-style dated series into this) and keyword arguments,
mixing Python-style curated options (`transform`, `outlier`,
`seasonal_order`, `maxorder`, `maxdiff`, `trading` -- matching
`statsmodels.tsa.x13.x13_arima_analysis`'s own parameter names, per
CLAUDE.md's genuine-superset requirement) with R-style raw passthrough
(`regression_variables`, `arima_model`) -- see handoff/w2-spec.md
section 2 for the design rationale. Throws `ArgumentError` immediately
(before any subprocess is ever spawned) if the spec violates one of the
rules `validate!` checks, each confirmed directly against the real
binary, not hypothetical.

`period=12` (monthly, `start[2]` in `1:12`) or `period=4` (quarterly,
`start[2]` in `1:4`) -- confirmed directly against the real binary that
these are the ONLY two values X-13ARIMA-SEATS accepts for seasonal
adjustment at all (`"ERROR: Seasonal period must be 4 or 12 if a
seasonal adjustment is done"`, hit directly testing every other
plausible value: 1, 2, 3, 6, 24, 52). This is a genuine, hard limit of
the underlying methodology (X-11's filters are specifically designed
for these two), not a wrapper-imposed restriction -- there is no
broader "arbitrary frequency" support to add here or anywhere upstream
of it.

`residuals=true` adds an `estimate { save = (rsd) }` block -- confirmed
directly against the real binary (`handoff/udg_and_residuals/`) that
regARIMA residuals are saved from `estimate{}`, a distinct spec block
from `x11{}`/`seats{}`, since they're a property of the underlying
model fit rather than the decomposition step.

`spec_args` (W.5.4) is a raw `"block.setting" => "value"` passthrough
for any spec block with no typed field of its own (`forecast`,
`slidingspans`, `history`, `check`, `pickmdl`, `force`, ...) -- see
[`render`](@ref)'s own docstring for the exact rendering rules and
[`validate!`](@ref) for why a key naming a block this struct ALREADY
renders via a typed field (`transform`, `x11`, `automdl`, `regression`,
`estimate`, `series`, `arima`, `seats`, `outlier`) throws rather than
silently creating two sources of truth for one block. Values are
rendered verbatim, exactly like `arima_model`'s own raw passthrough --
`validate!` does not parse or catch a syntax error inside a `spec_args`
value, the binary will.

**The `forecast.maxlead` default is deliberately NOT forced to `0`.**
Both R's `seasonal` and the Python `statsmodels` reference pipeline force
`forecast.maxlead = 0` whenever a user regressor is present, because R's
`seasonal` cannot extend a user regressor past the sample end. This
package embeds regressor data inline and `validate!`'s own rule 4
already requires `regression_user` to cover the series plus one forecast
horizon -- so this package genuinely CAN extend and forecast properly,
and changing nothing by default preserves that. Callers wanting R/Python
parity write `spec_args = Dict("forecast.maxlead" => "0")` explicitly.

**(W.7.2)** `maxlead` is a typed field (rather than only reachable via
`spec_args`) specifically so [`validate!`](@ref) can enforce X-13's own
`pfcst=120` program limit before any subprocess is spawned. `maxback`
(the backcast horizon) has no equivalent typed field -- reach it via
`spec_args["forecast.maxback"]` -- since nothing needs to validate it
independently of `maxlead`'s own limit.

**(W.7.7)** `force`/`force_target` (forcing seasonally adjusted annual
totals to match the original series -- `force.type`/`force.target`) and
`seasonalma` (the seasonal moving-average filter choice --
`x11.seasonalma`) are typed fields with every accepted keyword
CONFIRMED directly against the real binary (not transcribed from the
Reference Manual alone) -- see `_FORCE_TYPE_KEYWORDS`/
`_FORCE_TARGET_KEYWORDS`/`_SEASONALMA_KEYWORDS`. `force_target`'s real
spelling is `:calendaradj`, not `:caladjust` as an earlier draft of the
W.7 handoff guessed -- the binary's own error message settled it.
"""
function X13Spec(
    y::AbstractVector{<:Real};
    start::Tuple{Int,Int} = (1980, 1),
    period::Int = 12,
    title::AbstractString = "SeasonalAdjustment.jl series",
    order::NTuple{3,Int} = (0, 1, 1),
    seasonal_order::Union{Nothing,NTuple{4,Int}} = nothing,
    arima_model::Union{Nothing,AbstractString} = nothing,
    transform::Union{Nothing,Symbol} = nothing,
    outlier::Bool = false,
    automdl::Bool = false,
    maxorder::Union{Nothing,Tuple{Int,Int}} = nothing,
    maxdiff::Union{Nothing,Tuple{Int,Int}} = nothing,
    x11_mode::Union{Nothing,Symbol} = nothing,
    seats::Bool = false,
    save::Union{Nothing,Vector{Symbol}} = nothing,
    trading::Bool = false,
    regression_variables::AbstractVector{<:AbstractString} = String[],
    regression_user::Union{Nothing,AbstractVector{<:Real}} = nothing,
    regression_usertype::Union{Nothing,Symbol} = nothing,
    regression_user_name::Symbol = :user1,
    exog::Union{Nothing,AbstractVector{<:Real}} = nothing,
    aictest::AbstractVector{Symbol} = Symbol[],
    residuals::Bool = false,
    maxlead::Union{Nothing,Int} = nothing,
    force::Union{Nothing,Symbol} = nothing,
    force_target::Symbol = :original,
    seasonalma::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing,
    spec_args::AbstractDict{<:AbstractString,<:AbstractString} = Dict{String,String}(),
)
    spec = X13Spec(
        Float64.(collect(y)),
        start,
        period,
        String(title),
        order,
        seasonal_order,
        arima_model === nothing ? nothing : String(arima_model),
        transform,
        outlier,
        automdl,
        maxorder,
        maxdiff,
        x11_mode,
        seats,
        save,
        trading,
        String.(collect(regression_variables)),
        regression_user === nothing ? nothing : Float64.(collect(regression_user)),
        regression_usertype,
        regression_user_name,
        exog === nothing ? nothing : Float64.(collect(exog)),
        collect(aictest),
        residuals,
        maxlead,
        force,
        force_target,
        seasonalma isa AbstractVector ? collect(seasonalma) : seasonalma,
        Dict{String,String}(spec_args),
    )
    validate!(spec)
    return spec
end

function X13Spec(base::X13Spec; kwargs...)
    fields = Dict{Symbol,Any}(fn => getfield(base, fn) for fn in fieldnames(X13Spec) if fn != :y)
    for (k, v) in kwargs
        haskey(fields, k) || throw(ArgumentError("X13Spec has no field :$k to override"))
        fields[k] = v
    end
    return X13Spec(base.y; fields...)
end

"""
    validate!(spec::X13Spec) -> X13Spec

Checks real requirements confirmed directly against the real
`x13prebuilt` binary during this project's development (see
handoff/w2-spec.md section 2 and development-sequence.md), throwing
`ArgumentError` with a message that names the actual binary error it's
preventing -- fast, native, BEFORE any subprocess round-trip:

1. An explicit ARIMA model (`arima_model`/`seasonal_order`) and
   `automdl`/`maxorder`/`maxdiff` can't both be given (found while
   implementing W.4's `maxorder`/`maxdiff` passthrough).
2. `period` must be 4 (quarterly) or 12 (monthly) -- confirmed directly
   against the real binary, the ONLY two values it accepts for seasonal
   adjustment at all.
3. Series length >= 3 complete years, i.e. `3 * period` observations
   (36 for monthly, 12 for quarterly -- confirmed directly for both:
   the real binary's own minimum-length error is identical in wording
   for either period, just scaled).
4. `regression_user` data must cover the series length plus the
   RegARIMA forecast horizon (1 year = `period` observations), not just
   the historical length.
5. `transform = :log` is required whenever a regression block is
   combined with `x11_mode` in `(:multiplicative, :logadditive)` --
   **or `x11_mode === nothing`**, since X-13's own implicit default mode
   IS multiplicative (confirmed directly: a plain `trading=true` spec
   with no explicit `x11_mode` hits the real binary's own log-transform
   error, the same as setting `x11_mode=:multiplicative` by hand would).
   Only `:additive`/`:pseudoadditive` are exempt.
6. `spec_args` (W.5.4) can't name a block (`transform`, `x11`, `automdl`,
   `regression`, `estimate`, `series`, `arima`, `seats`, `outlier`) this
   struct already renders via a typed field -- two sources of truth for
   one block is a silent-misconfiguration risk worth failing loudly on,
   not a real binary error to reproduce. A dotless `spec_args` key (no
   `block.setting` shape) must have an empty value -- it renders an
   empty block (`"slidingspans" => ""` -> `slidingspans { }`); a
   non-empty value on a dotless key has no defined shape and is rejected
   rather than guessed at.
7. **(W.7.1)** Every symbol in `save` must be a real X-13 save keyword --
   checked against `_KNOWN_TABLES` (generated from the full 281-entry
   catalogue in `handoff/x13-saveable-tables.md`, see
   `tools/generate_known_tables.jl`). `print`-only keywords (`none`,
   `all`, `alltables`, `default`, `brief` -- valid for `print`, invalid
   for `save`, confirmed directly, Manual §3.2) get their own, more
   specific error rather than falling into the generic "not a recognized
   table" message. This closes a real gap: before W.7.1, an unrecognized
   or print-only symbol in `save` was accepted silently here and either
   produced a confusing binary-side error (the old code rendered
   `save=` verbatim into `x11{}`/`seats{}` regardless of which block the
   table actually belonged to) or, under W.7.1's own per-block routing,
   would have been silently dropped instead -- worse. Reject it up
   front, the same fast-fail convention every other rule here uses.
"""
function validate!(spec::X13Spec)
    spec.x11_mode === nothing || haskey(_X11_MODE_KEYWORDS, spec.x11_mode) || throw(ArgumentError(
        "x11_mode=:$(spec.x11_mode) isn't recognized -- must be one of " *
        "$(join(sort(string.(keys(_X11_MODE_KEYWORDS))), ", ")), or `nothing`",
    ))

    has_arima = spec.arima_model !== nothing || spec.seasonal_order !== nothing
    has_automdl = spec.automdl || spec.maxorder !== nothing || spec.maxdiff !== nothing
    has_arima && has_automdl && throw(ArgumentError(
        "an explicit ARIMA model (arima_model/seasonal_order) and automdl " *
        "(automdl/maxorder/maxdiff) can't both be given -- confirmed directly against " *
        "the real binary's own error: \"Cannot specify arima and automdl spec in the " *
        "same input file.\"",
    ))

    spec.period in (4, 12) || throw(ArgumentError(
        "period=$(spec.period) isn't valid -- X-13ARIMA-SEATS accepts only 4 (quarterly) " *
        "or 12 (monthly) for seasonal adjustment, confirmed directly against the real " *
        "binary's own error: \"Seasonal period must be 4 or 12 if a seasonal adjustment " *
        "is done.\" (tested directly against periods 1, 2, 3, 6, 24, 52 -- all rejected " *
        "the same way)",
    ))
    spec.start[2] in 1:spec.period || throw(ArgumentError(
        "start=$(spec.start) has a subperiod (start[2]=$(spec.start[2])) outside the " *
        "valid range 1:$(spec.period) for period=$(spec.period)",
    ))

    n = length(spec.y)
    min_n = 3 * spec.period
    n >= min_n || throw(ArgumentError(
        "series has $n observations, but x13prebuilt requires at least $min_n " *
        "$(spec.period == 12 ? "months" : "quarters") (3 complete years) of data -- " *
        "confirmed directly against the real binary's own error (identical wording for " *
        "both period=12 and period=4, just scaled): \"Series to be modelled and/or " *
        "seasonally adjusted must have at least 3 complete years of data.\"",
    ))

    # W.7.2: forecast/backcast program limits (Reference Manual Table 2.2,
    # confirmed directly: pfcst=120 caps maxlead/maxback, pobs=780 caps
    # series length). pureg=52 (max user regressors) and pb=80 (max total
    # regression variables, including auto-detected outliers) are NOT
    # enforced here -- this package supports exactly one named user
    # regressor at a time (structurally impossible to exceed 52) and pb's
    # true count isn't knowable before a run (automdl-detected outliers
    # aren't known until the binary finds them), so a pre-run check would
    # either be vacuous or wrong; left to the binary's own error.
    spec.maxlead === nothing || spec.maxlead >= 0 || throw(ArgumentError(
        "maxlead=$(spec.maxlead) must be >= 0",
    ))
    spec.maxlead === nothing || spec.maxlead <= 120 || throw(ArgumentError(
        "maxlead=$(spec.maxlead) exceeds X-13's own program limit pfcst=120 (Reference " *
        "Manual Table 2.2) -- forecasts are capped at 120 periods",
    ))
    n > 780 && throw(ArgumentError(
        "series has $n observations, exceeding X-13's own program limit pobs=780 " *
        "(Reference Manual Table 2.2)",
    ))

    spec.force === nothing || haskey(_FORCE_TYPE_KEYWORDS, spec.force) || throw(ArgumentError(
        "force=:$(spec.force) isn't recognized -- must be one of " *
        "$(join(sort(string.(keys(_FORCE_TYPE_KEYWORDS))), ", ")), or `nothing`, confirmed " *
        "directly against the real binary",
    ))
    haskey(_FORCE_TARGET_KEYWORDS, spec.force_target) || throw(ArgumentError(
        "force_target=:$(spec.force_target) isn't recognized -- confirmed directly against " *
        "the real binary's own error, the only accepted values are " *
        "$(join(sort(string.(keys(_FORCE_TARGET_KEYWORDS))), ", "))",
    ))

    if spec.seasonalma !== nothing
        sma_list = spec.seasonalma isa Symbol ? [spec.seasonalma] : spec.seasonalma
        for f in sma_list
            haskey(_SEASONALMA_KEYWORDS, f) || throw(ArgumentError(
                "seasonalma=:$f isn't recognized -- confirmed directly against the real " *
                "binary, the only accepted values are " *
                "$(join(sort(string.(keys(_SEASONALMA_KEYWORDS))), ", "))",
            ))
        end
    end

    if spec.regression_user !== nothing
        min_len = n + spec.period
        length(spec.regression_user) >= min_len || throw(ArgumentError(
            "regression_user has $(length(spec.regression_user)) data points, but must " *
            "cover the series length ($n) plus the RegARIMA forecast horizon " *
            "($(spec.period) $(spec.period == 12 ? "months" : "quarters")) = $min_len -- " *
            "confirmed directly against the real binary's own error: \"forecasts end " *
            "date ... must end on or before user-defined regression variables end date\"",
        ))
    end

    # (W.7 follow-up) The real, more precise rule, confirmed directly
    # against the binary across FOUR combinations (not assumed from one
    # worked example): the failure is triggered by a MISSING transform
    # block (`transform === nothing`, so no `transform { ... }` at all),
    # not specifically by "not :log". `transform = :none` -- an EXPLICIT
    # no-op transform -- runs successfully in the exact same
    # `trading=true`, x11_mode-unset combination that fails with no
    # transform block at all; so does the original :log finding. X-13's
    # own IMPLICIT default x11 mode (when x11_mode is left `nothing`) is
    # multiplicative -- confirmed separately -- which is why this also
    # fires for an unset x11_mode, not just an explicit multiplicative/
    # logadditive one (the ORIGINAL, narrower version of this rule
    # missed that far more common case). `transform = :auto` was not
    # independently tested here; treated as "explicit enough" by analogy
    # with :none/:log rather than assumed to fail.
    if _has_regression(spec) && !spec.seats && spec.x11_mode ∉ (:additive, :pseudoadditive)
        spec.transform === nothing && throw(ArgumentError(
            "combining a RegARIMA model (a regression block is present) with " *
            "x11_mode=$(spec.x11_mode === nothing ? "the default (multiplicative)" : ":$(spec.x11_mode)") " *
            "requires an EXPLICIT transform (:log, :none, or :auto -- :none and :log both " *
            "confirmed directly; a completely absent transform block is what actually " *
            "fails) -- confirmed directly against the real binary's own error: " *
            "\"Multiplicative or log additive seasonal adjustment cannot be performed when " *
            "preadjustment factors are derived from a regARIMA model for data which have " *
            "not been log transformed.\"",
        ))
    end

    for (k, v) in spec.spec_args
        dot = findfirst('.', k)
        blockname = dot === nothing ? k : k[1:prevind(k, dot)]
        blockname in _TYPED_SPEC_BLOCKS && throw(ArgumentError(
            "spec_args key \"$k\" targets the \"$blockname\" block, which X13Spec already " *
            "renders via a typed field ($(join(sort(collect(_TYPED_SPEC_BLOCKS)), ", "))) -- " *
            "use that field instead of spec_args for this block, to avoid two sources of " *
            "truth for the same spec block",
        ))
        dot === nothing && !isempty(v) && throw(ArgumentError(
            "spec_args key \"$k\" has no '.' (no block.setting shape) but a non-empty value " *
            "\"$v\" -- a dotless key is only defined for an EMPTY block (spec_args[\"$k\"] = " *
            "\"\" renders \"$k { }\"); give it a \"$k.setting\" shape instead if you meant a " *
            "real setting",
        ))
    end

    if spec.save !== nothing
        for s in spec.save
            s in _PRINT_ONLY_SAVE_KEYWORDS && throw(ArgumentError(
                "save=[...] contains :$s, which is a print-only keyword -- \"none\"/\"all\"/" *
                "\"alltables\"/\"default\"/\"brief\" are valid for X-13's `print` argument, " *
                "never for `save` (confirmed directly, Reference Manual §3.2)",
            ))
            s in _KNOWN_TABLES || throw(ArgumentError(
                "save=[...] contains :$s, which isn't a recognized X-13 save table -- see " *
                "handoff/x13-saveable-tables.md's catalogue ($(length(_KNOWN_TABLES)) valid " *
                "entries); the file extension is often NOT the X-11 table number (e.g. " *
                "holiday factors, table A7, save as :hol, not :a7)",
            ))
        end
    end

    return spec
end

# print-only `print`/`save` keywords -- valid for X-13's `print` argument,
# invalid for `save` (Reference Manual §3.2, confirmed directly against
# handoff/x13-saveable-tables.md's own "How save works" section).
const _PRINT_ONLY_SAVE_KEYWORDS = Set([:none, :all, :alltables, :default, :brief])

# Blocks X13Spec already renders via a dedicated typed field -- a
# spec_args key targeting one of these throws in validate! above rather
# than silently creating a second, conflicting source of truth for it.
const _TYPED_SPEC_BLOCKS = Set([
    "transform", "x11", "automdl", "regression", "estimate", "series",
    "arima", "seats", "outlier", "force",
])

# W.7.7 -- confirmed directly against the real binary (not transcribed
# from the Reference Manual table alone, which the handoff flagged as
# past its fetch limit). force.target's real accepted spelling is
# "calendaradj", NOT "caladjust" as an earlier draft of the handoff
# guessed -- the binary's own error message settled it:
# "Entry for forcetarget argument must be original, calendaradj,
# permprioradj, or both."
const _FORCE_TYPE_KEYWORDS = Dict(:none => "none", :denton => "denton", :regress => "regress")
const _FORCE_TARGET_KEYWORDS = Dict(
    :original => "original", :calendaradj => "calendaradj",
    :permprioradj => "permprioradj", :both => "both",
)

# W.7.7 -- all 8 confirmed directly against the real binary (each run
# individually via a hand-rendered x11{seasonalma=...} spec); every
# spelling is identical to its Julia Symbol name, no translation needed.
const _SEASONALMA_KEYWORDS = Dict(
    :s3x1 => "s3x1", :s3x3 => "s3x3", :s3x5 => "s3x5", :s3x9 => "s3x9",
    :s3x15 => "s3x15", :stable => "stable", :x11default => "x11default", :msr => "msr",
)

# X-13's x11{mode=...} keyword is the SHORT form -- confirmed directly
# by hitting a real parse error using the full word ("Argument name
# \"multiplicative\" not found"). X13Spec's own x11_mode field uses the
# more discoverable full-word Symbol (matching this project's Python-
# style ergonomics elsewhere); this maps it to what the binary actually
# accepts.
const _X11_MODE_KEYWORDS = Dict(
    :multiplicative => "mult",
    :additive => "add",
    :logadditive => "logadd",
    :pseudoadditive => "pseudoadd",
)

_has_regression(spec::X13Spec) = !isempty(spec.regression_variables) || spec.trading ||
                                  spec.regression_user !== nothing || spec.exog !== nothing ||
                                  !isempty(spec.aictest)

# X-13 has a hard Fortran-heritage input record length limit -- confirmed
# directly by hitting a real parse error on a wide/long series ("ERROR:
# Input record longer than limit :         133"). Wrapping by a *fixed
# count* of values per line (the original approach) doesn't respect this:
# wider numeric representations (larger magnitudes, more decimal digits)
# can push a fixed-count line past 133 characters even though a shorter
# series with narrower values never would. Wrap by character width
# instead. `max_width` is kept well under the confirmed 133-char limit to
# leave margin for the caller's own line prefix (e.g. "  data = (", not
# accounted for here since only the first wrapped line sits behind it).
function _write_wrapped(io::IO, vec::AbstractVector{<:Real}; max_width::Int = 100)
    isempty(vec) && return
    line_len = 0
    for (i, v) in enumerate(vec)
        s = string(v)
        sep_len = i == 1 ? 0 : 1
        if line_len > 0 && line_len + sep_len + length(s) > max_width
            println(io)
            line_len = 0
            sep_len = 0
        end
        sep_len > 0 && print(io, " ")
        print(io, s)
        line_len += sep_len + length(s)
    end
end

"""
    render(spec::X13Spec) -> String

Renders `spec` to `.spc` text, in the same format already confirmed
working against the real binary throughout this project's development
(`series { ... }`, `transform { function = ... }`, `regression { ... }`,
`arima { model = ... }`, `automdl { }`, `outlier { }`,
`estimate { save = (rsd) }`, `x11 { ... }` / `seats { ... }`, each block
only emitted if relevant, followed by any `spec_args` (W.5.4) blocks).

**(W.7.1) `save` is routed per-table to the spec block that actually owns
it**, not dumped unconditionally into `x11{}`/`seats{}`. Before W.7.1
this was a real, confirmed bug: `save=[:hol]` (the regression-block
holiday-factor table) rendered `x11 { save = (hol) }`, which the real
binary rejects, since `.hol` is a `regression{}` table, not an `x11{}`
one -- see `handoff/x13-saveable-tables.md`'s own "critical naming trap"
section and `src/known_tables.jl`'s generated `_TABLE_BLOCK`, which this
now keys off. Practically: `series(r, :hol)`'s automatic re-run (and any
hand-built `X13Spec(y; save=[:hol, :rsd, :fct])` mixing tables from
different blocks) now lands each table in the right block --
`regression{save=(hol)}`, `estimate{save=(rsd)}`, `forecast{save=(fct)}`
-- in one render, one run.

Per-block routing rules:

- `series`/`regression`/`estimate`/`outlier`/`x11`/`seats` already have a
  typed rendering path (`_TYPED_SPEC_BLOCKS`) -- a `save` table destined
  for one of these is appended to that block's own `save = (...)` line
  (creating the block, e.g. an otherwise-empty `regression{}` or
  `estimate{}`, if nothing else would have rendered it). `x11`/`seats`
  keep their historical default (`d10 d11 d12 d13` / `s10 s11 s12 s13`)
  whenever `save` is `nothing` OR contains no table from that block, so
  a `save` request naming only e.g. a regression table doesn't silently
  turn off the decomposition step itself.
- Every other block (`forecast`, `check`, `force`, `slidingspans`,
  `history`, `identify`, `x11regression`, `spectrum`) has no typed field
  at all -- a `save` table destined for one of these is merged into
  `spec_args` as a synthetic `"blockname.save"` entry (unioned with any
  `save` the caller already put there directly via `spec_args`) and
  rendered through the ordinary `spec_args` path below. `composite`-only
  tables have no rendering path at all (this package has no multi-series
  aggregation support) and are silently not renderable, though still
  valid entries in `_KNOWN_TABLES` for cataloguing purposes.

`spec_args` rendering rules (validated against a block collision at
`validate!` time, not here -- see [`validate!`](@ref)):

1. Keys are grouped by the part before the first `.` -- that's the block
   name (`"forecast.maxlead"` -> block `forecast`, setting `maxlead`).
2. A key with NO dot and an EMPTY value renders as an empty block:
   `spec_args["slidingspans"] = ""` -> `slidingspans { }`. A dotless key
   with a NON-empty value is rejected (ambiguous -- there's no defined
   shape for it) rather than guessed at.
3. Values are emitted VERBATIM, no quoting or escaping -- a raw
   passthrough exactly like `arima_model`'s own.
4. Blocks and, within a block, settings are emitted in sorted-key order
   -- `spec_args` is a plain `Dict`, whose iteration order Julia does not
   guarantee, so sorting is what makes `render`'s output reproducible
   across runs.
"""
function render(spec::X13Spec)
    save_by_block = _save_by_block(spec)

    io = IOBuffer()
    series_saves = get(save_by_block, "series", Symbol[])
    println(io, "series {")
    println(io, "  title = \"$(spec.title)\"")
    println(io, "  start = $(spec.start[1]).$(spec.start[2])")
    println(io, "  period = $(spec.period)")
    print(io, "  data = (")
    _write_wrapped(io, spec.y)
    println(io, ")")
    !isempty(series_saves) && println(io, "  save = ($(join(sort(string.(series_saves)), " ")))")
    println(io, "}")

    spec.transform !== nothing && println(io, "transform { function = $(spec.transform) }")

    regression_saves = get(save_by_block, "regression", Symbol[])
    if _has_regression(spec) || !isempty(regression_saves)
        println(io, "regression {")
        # `trading` is Python's own shorthand for adding "td" to the
        # regression variables list; deduplicated against an explicit
        # "td" already present in regression_variables.
        variables = spec.trading && !("td" in spec.regression_variables) ?
            vcat(spec.regression_variables, "td") : spec.regression_variables
        !isempty(variables) && println(io, "  variables = ($(join(variables, " ")))")
        !isempty(spec.aictest) && println(io, "  aictest = ($(join(spec.aictest, " ")))")
        if spec.regression_user !== nothing
            println(io, "  user = ($(spec.regression_user_name))")
            spec.regression_usertype !== nothing &&
                println(io, "  usertype = ($(spec.regression_usertype))")
            println(io, "  start = $(spec.start[1]).$(spec.start[2])")
            print(io, "  data = (")
            _write_wrapped(io, spec.regression_user)
            println(io, ")")
        elseif spec.exog !== nothing
            println(io, "  user = (exog1)")
            println(io, "  start = $(spec.start[1]).$(spec.start[2])")
            print(io, "  data = (")
            _write_wrapped(io, spec.exog)
            println(io, ")")
        end
        !isempty(regression_saves) && println(io, "  save = ($(join(sort(string.(regression_saves)), " ")))")
        println(io, "}")
    end

    if spec.arima_model !== nothing
        println(io, "arima { model = $(spec.arima_model) }")
    elseif spec.seasonal_order !== nothing
        p, d, q = spec.order
        P, D, Q, s = spec.seasonal_order
        println(io, "arima { model = ($p $d $q)($P $D $Q)$s }")
    end

    if spec.automdl || spec.maxorder !== nothing || spec.maxdiff !== nothing
        parts = String[]
        spec.maxorder !== nothing && push!(parts, "maxorder = ($(spec.maxorder[1]) $(spec.maxorder[2]))")
        spec.maxdiff !== nothing && push!(parts, "maxdiff = ($(spec.maxdiff[1]) $(spec.maxdiff[2]))")
        println(io, "automdl { $(join(parts, "  ")) }")
    end

    outlier_saves = get(save_by_block, "outlier", Symbol[])
    if spec.outlier || !isempty(outlier_saves)
        if isempty(outlier_saves)
            println(io, "outlier { }")
        else
            println(io, "outlier { save = ($(join(sort(string.(outlier_saves)), " "))) }")
        end
    end

    estimate_saves = copy(get(save_by_block, "estimate", Symbol[]))
    spec.residuals && !(:rsd in estimate_saves) && push!(estimate_saves, :rsd)
    !isempty(estimate_saves) &&
        println(io, "estimate { save = ($(join(sort(string.(estimate_saves)), " "))) }")

    x11_or_seats_block = spec.seats ? "seats" : "x11"
    x11_or_seats_saves = get(save_by_block, x11_or_seats_block, Symbol[])
    if spec.seats
        savepart = isempty(x11_or_seats_saves) ? "s10 s11 s12 s13" : join(sort(string.(x11_or_seats_saves)), " ")
        println(io, "seats { save = ($savepart) }")
    else
        savepart = isempty(x11_or_seats_saves) ? "d10 d11 d12 d13" : join(sort(string.(x11_or_seats_saves)), " ")
        x11_parts = String[]
        spec.x11_mode !== nothing && push!(x11_parts, "mode = $(_X11_MODE_KEYWORDS[spec.x11_mode])")
        if spec.seasonalma !== nothing
            sma_str = spec.seasonalma isa Symbol ? _SEASONALMA_KEYWORDS[spec.seasonalma] :
                "($(join([_SEASONALMA_KEYWORDS[f] for f in spec.seasonalma], " ")))"
            push!(x11_parts, "seasonalma = $sma_str")
        end
        push!(x11_parts, "save = ($savepart)")
        println(io, "x11 { $(join(x11_parts, "  ")) }")
    end

    merged_args = _merge_generic_saves(spec.spec_args, save_by_block)
    if spec.maxlead !== nothing && !haskey(merged_args, "forecast.maxlead")
        merged_args = merge(merged_args, Dict("forecast.maxlead" => string(spec.maxlead)))
    end
    if spec.force !== nothing
        merged_args = merge(merged_args, Dict(
            "force.type" => _FORCE_TYPE_KEYWORDS[spec.force],
            "force.target" => _FORCE_TARGET_KEYWORDS[spec.force_target],
        ))
    end
    _render_spec_args(io, merged_args)

    return String(take!(io))
end

# Blocks with their own typed rendering path above -- a `save` table
# destined for one of these is handled inline where that block is
# rendered, not merged into spec_args. `composite` is deliberately
# excluded from this set (see render()'s own docstring): it has NO
# rendering path, typed or generic, so any save request landing there is
# silently unroutable -- consistent with this package having no
# multi-series aggregation support at all.
const _SAVE_TYPED_BLOCKS = Set(["series", "regression", "estimate", "outlier", "x11", "seats"])

# Groups spec.save by the spec block each table belongs to (W.7.1),
# using the generated _TABLE_BLOCK catalogue (src/known_tables.jl).
# validate! already rejects any symbol not in _KNOWN_TABLES before a
# spec can reach render(), so every symbol here resolves to a real block.
function _save_by_block(spec::X13Spec)
    by_block = Dict{String,Vector{Symbol}}()
    spec.save === nothing && return by_block
    for s in spec.save
        blockname = _TABLE_BLOCK[s]
        push!(get!(by_block, blockname, Symbol[]), s)
    end
    return by_block
end

# Merges the generic (non-typed-block) portion of save_by_block into
# spec_args as synthetic "blockname.save" entries, unioned with any
# save list the caller already wrote into spec_args directly for that
# same block (e.g. spec_args["forecast.save"]).
function _merge_generic_saves(spec_args::AbstractDict{String,String}, save_by_block::AbstractDict{String,Vector{Symbol}})
    isempty(save_by_block) && return spec_args
    merged = copy(spec_args)
    for (blockname, syms) in save_by_block
        blockname in _SAVE_TYPED_BLOCKS && continue
        blockname == "composite" && continue
        key = "$blockname.save"
        if haskey(merged, key)
            existing = Symbol.(split(_strip_parens(merged[key])))
            merged[key] = "($(join(sort(unique(vcat(existing, syms))), " ")))"
        else
            merged[key] = "($(join(sort(syms), " ")))"
        end
    end
    return merged
end

function _render_spec_args(io::IO, spec_args::AbstractDict{String,String})
    isempty(spec_args) && return
    blocks = Dict{String,Vector{Tuple{String,String}}}()
    empty_blocks = String[]
    for (k, v) in spec_args
        dot = findfirst('.', k)
        if dot === nothing
            isempty(v) || throw(ArgumentError(
                "spec_args key \"$k\" has no '.' (no block.setting shape) but a non-empty " *
                "value \"$v\" -- a dotless key is only defined for an EMPTY block " *
                "(spec_args[\"$k\"] = \"\" renders \"$k { }\"); give it a \"$k.setting\" " *
                "shape instead if you meant a real setting",
            ))
            push!(empty_blocks, k)
        else
            blockname = k[1:prevind(k, dot)]
            subkey = k[nextind(k, dot):end]
            push!(get!(blocks, blockname, Tuple{String,String}[]), (subkey, v))
        end
    end
    for blockname in sort(collect(keys(blocks)))
        println(io, "$blockname {")
        for (subkey, v) in sort(blocks[blockname]; by = first)
            println(io, "  $subkey = $v")
        end
        println(io, "}")
    end
    for blockname in sort(empty_blocks)
        println(io, "$blockname { }")
    end
end

"""
    write_spec(spec::X13Spec, path::AbstractString) -> String

Renders and writes `spec` to `path`, returning `path`.
"""
function write_spec(spec::X13Spec, path::AbstractString)
    write(path, render(spec))
    return path
end

"""
    generate_specs(series_list, options_list; parallel::Bool=true) -> Vector{X13Spec}

Builds one [`X13Spec`](@ref) per `(series, options)` pair. Each spec's
construction (including `validate!`) is independent of every other, so
this is genuinely parallelizable for the real batch use case (seasonally
adjusting a whole panel of series) -- `Threads.@threads`, guarded by
`Threads.nthreads() > 1` and a minimum batch size, the same pattern used
throughout this project family. `parallel=false` (or a single thread, or
a small batch) falls back to a plain serial loop.
"""
function generate_specs(series_list::AbstractVector, options_list::AbstractVector; parallel::Bool = true)
    n = length(series_list)
    length(options_list) == n ||
        throw(ArgumentError("series_list (length $n) and options_list (length $(length(options_list))) must have the same length"))
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

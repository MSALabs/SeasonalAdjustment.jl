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
    spec_args::Dict{String,String}                      # W.5.4: raw "block.setting"=>"value" passthrough for any
                                                          # spec block with no typed field (forecast, slidingspans,
                                                          # history, check, pickmdl, force, ...); see render/validate!
end

"""
    X13Spec(y; start=(1980,1), period=12, title=..., order=(0,1,1), seasonal_order=nothing,
            arima_model=nothing, transform=nothing, outlier=false, automdl=false,
            maxorder=nothing, maxdiff=nothing, x11_mode=nothing, seats=false,
            save=nothing, trading=false, regression_variables=String[],
            regression_user=nothing, regression_usertype=nothing, regression_user_name=:user1,
            exog=nothing, aictest=Symbol[], residuals=false,
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
   combined with `x11_mode` in `(:multiplicative, :logadditive)`.
6. `spec_args` (W.5.4) can't name a block (`transform`, `x11`, `automdl`,
   `regression`, `estimate`, `series`, `arima`, `seats`, `outlier`) this
   struct already renders via a typed field -- two sources of truth for
   one block is a silent-misconfiguration risk worth failing loudly on,
   not a real binary error to reproduce. A dotless `spec_args` key (no
   `block.setting` shape) must have an empty value -- it renders an
   empty block (`"slidingspans" => ""` -> `slidingspans { }`); a
   non-empty value on a dotless key has no defined shape and is rejected
   rather than guessed at.
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

    if _has_regression(spec) && !spec.seats && spec.x11_mode in (:multiplicative, :logadditive)
        spec.transform === :log || throw(ArgumentError(
            "combining a RegARIMA model (a regression block is present) with " *
            "x11_mode=:$(spec.x11_mode) requires transform=:log -- confirmed directly " *
            "against the real binary's own error: \"Multiplicative or log additive " *
            "seasonal adjustment cannot be performed when preadjustment factors are " *
            "derived from a regARIMA model for data which have not been log transformed.\"",
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

    return spec
end

# Blocks X13Spec already renders via a dedicated typed field -- a
# spec_args key targeting one of these throws in validate! above rather
# than silently creating a second, conflicting source of truth for it.
const _TYPED_SPEC_BLOCKS = Set([
    "transform", "x11", "automdl", "regression", "estimate", "series",
    "arima", "seats", "outlier",
])

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
    io = IOBuffer()
    println(io, "series {")
    println(io, "  title = \"$(spec.title)\"")
    println(io, "  start = $(spec.start[1]).$(spec.start[2])")
    println(io, "  period = $(spec.period)")
    print(io, "  data = (")
    _write_wrapped(io, spec.y)
    println(io, ")")
    println(io, "}")

    spec.transform !== nothing && println(io, "transform { function = $(spec.transform) }")

    if _has_regression(spec)
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
    spec.outlier && println(io, "outlier { }")
    spec.residuals && println(io, "estimate { save = (rsd) }")

    if spec.seats
        savepart = spec.save === nothing ? "s10 s11 s12 s13" : join(spec.save, " ")
        println(io, "seats { save = ($savepart) }")
    else
        savepart = spec.save === nothing ? "d10 d11 d12 d13" : join(spec.save, " ")
        if spec.x11_mode === nothing
            println(io, "x11 { save = ($savepart) }")
        else
            println(io, "x11 { mode = $(_X11_MODE_KEYWORDS[spec.x11_mode])  save = ($savepart) }")
        end
    end

    _render_spec_args(io, spec.spec_args)

    return String(take!(io))
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

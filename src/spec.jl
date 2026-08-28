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
    start::Tuple{Int,Int}                          # (year, period); period is always 1-12 (monthly) -- quarterly not yet supported, see note below
    title::String
    order::NTuple{3,Int}                            # non-seasonal (p,d,q), Python-style default (0,1,1)
    seasonal_order::Union{Nothing,NTuple{4,Int}}     # seasonal (P,D,Q,period), Python-style
    arima_model::Union{Nothing,String}               # R-style raw passthrough, overrides order/seasonal_order if given
    transform::Union{Nothing,Symbol}                 # :log, :auto, :none, or nothing (no transform block)
    outlier::Bool
    automdl::Bool
    x11_mode::Union{Nothing,Symbol}                  # :multiplicative, :additive, :logadditive, :pseudoadditive
    seats::Bool                                       # seats{} instead of x11{}
    save::Union{Nothing,Vector{Symbol}}               # tables to save; defaults to the standard d10-d13/s10-s13 set
    regression_variables::Vector{String}              # R-style passthrough (e.g. ["td", "easter[1]"])
    regression_user::Union{Nothing,Vector{Float64}}   # user-defined regressor DATA (W.0 generates this)
    regression_usertype::Union{Nothing,Symbol}        # e.g. :holiday, :td
    regression_user_name::Symbol                      # the regressor's name in the spec, default :user1
    exog::Union{Nothing,Vector{Float64}}              # a generic companion regressor (also triggers a regression block)
    aictest::Vector{Symbol}                            # e.g. [:td, :easter]
end

"""
    X13Spec(y; start=(1980,1), title=..., order=(0,1,1), seasonal_order=nothing,
            arima_model=nothing, transform=nothing, outlier=false, automdl=false,
            x11_mode=nothing, seats=false, save=nothing, regression_variables=String[],
            regression_user=nothing, regression_usertype=nothing, regression_user_name=:user1,
            exog=nothing, aictest=Symbol[]) -> X13Spec

Builds and [`validate!`](@ref)s a spec from `y` (a plain numeric
series -- W.4 is responsible for bridging TSAnalytics.jl-style dated
series into this) and keyword arguments, mixing Python-style curated
options (`transform`, `outlier`, `seasonal_order`, ...) with R-style raw
passthrough (`regression_variables`, `arima_model`) -- see
handoff/w2-spec.md section 2 for the design rationale. Throws
`ArgumentError` immediately (before any subprocess is ever spawned) if
the spec violates one of the three rules `validate!` checks, each
confirmed directly against the real binary during this task's own
development, not hypothetical.

Monthly series only (period 1-12) -- quarterly isn't exercised by any
verified fixture in this project yet, so it isn't claimed as supported.
"""
function X13Spec(
    y::AbstractVector{<:Real};
    start::Tuple{Int,Int} = (1980, 1),
    title::AbstractString = "SeasonalAdjustment.jl series",
    order::NTuple{3,Int} = (0, 1, 1),
    seasonal_order::Union{Nothing,NTuple{4,Int}} = nothing,
    arima_model::Union{Nothing,AbstractString} = nothing,
    transform::Union{Nothing,Symbol} = nothing,
    outlier::Bool = false,
    automdl::Bool = false,
    x11_mode::Union{Nothing,Symbol} = nothing,
    seats::Bool = false,
    save::Union{Nothing,Vector{Symbol}} = nothing,
    regression_variables::AbstractVector{<:AbstractString} = String[],
    regression_user::Union{Nothing,AbstractVector{<:Real}} = nothing,
    regression_usertype::Union{Nothing,Symbol} = nothing,
    regression_user_name::Symbol = :user1,
    exog::Union{Nothing,AbstractVector{<:Real}} = nothing,
    aictest::AbstractVector{Symbol} = Symbol[],
)
    spec = X13Spec(
        Float64.(collect(y)),
        start,
        String(title),
        order,
        seasonal_order,
        arima_model === nothing ? nothing : String(arima_model),
        transform,
        outlier,
        automdl,
        x11_mode,
        seats,
        save,
        String.(collect(regression_variables)),
        regression_user === nothing ? nothing : Float64.(collect(regression_user)),
        regression_usertype,
        regression_user_name,
        exog === nothing ? nothing : Float64.(collect(exog)),
        collect(aictest),
    )
    validate!(spec)
    return spec
end

"""
    validate!(spec::X13Spec) -> X13Spec

Checks the three real requirements confirmed directly against the real
`x13prebuilt` binary during this project's development (see
handoff/w2-spec.md section 2 and development-sequence.md), throwing
`ArgumentError` with a message that names the actual binary error it's
preventing -- fast, native, BEFORE any subprocess round-trip:

1. Series length >= 36 months (3 complete years).
2. `regression_user` data must cover the series length plus the
   RegARIMA forecast horizon (1 year), not just the historical length.
3. `transform = :log` is required whenever a regression block is
   combined with `x11_mode` in `(:multiplicative, :logadditive)`.
"""
function validate!(spec::X13Spec)
    spec.x11_mode === nothing || haskey(_X11_MODE_KEYWORDS, spec.x11_mode) || throw(ArgumentError(
        "x11_mode=:$(spec.x11_mode) isn't recognized -- must be one of " *
        "$(join(sort(string.(keys(_X11_MODE_KEYWORDS))), ", ")), or `nothing`",
    ))

    n = length(spec.y)
    n >= 36 || throw(ArgumentError(
        "series has $n observations, but x13prebuilt requires at least 36 months " *
        "(3 complete years) of data -- confirmed directly against the real binary's " *
        "own error: \"Series to be modelled and/or seasonally adjusted must have at " *
        "least 3 complete years of data.\"",
    ))

    if spec.regression_user !== nothing
        min_len = n + 12
        length(spec.regression_user) >= min_len || throw(ArgumentError(
            "regression_user has $(length(spec.regression_user)) data points, but must " *
            "cover the series length ($n) plus the RegARIMA forecast horizon (12 months) " *
            "= $min_len -- confirmed directly against the real binary's own error: " *
            "\"forecasts end date ... must end on or before user-defined regression " *
            "variables end date\"",
        ))
    end

    has_regression = !isempty(spec.regression_variables) || spec.regression_user !== nothing ||
                      spec.exog !== nothing || !isempty(spec.aictest)
    if has_regression && !spec.seats && spec.x11_mode in (:multiplicative, :logadditive)
        spec.transform === :log || throw(ArgumentError(
            "combining a RegARIMA model (a regression block is present) with " *
            "x11_mode=:$(spec.x11_mode) requires transform=:log -- confirmed directly " *
            "against the real binary's own error: \"Multiplicative or log additive " *
            "seasonal adjustment cannot be performed when preadjustment factors are " *
            "derived from a regARIMA model for data which have not been log transformed.\"",
        ))
    end

    return spec
end

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

function _write_wrapped(io::IO, vec::AbstractVector{<:Real}; per_line::Int = 12)
    n = length(vec)
    for chunk_start in 1:per_line:n
        chunk = vec[chunk_start:min(chunk_start + per_line - 1, n)]
        print(io, join(chunk, " "))
        chunk_start + per_line <= n && println(io)
    end
end

"""
    render(spec::X13Spec) -> String

Renders `spec` to `.spc` text, in the same format already confirmed
working against the real binary throughout this project's development
(`series { ... }`, `transform { function = ... }`, `regression { ... }`,
`arima { model = ... }`, `automdl { }`, `outlier { }`, `x11 { ... }` /
`seats { ... }`, each block only emitted if relevant).
"""
function render(spec::X13Spec)
    io = IOBuffer()
    println(io, "series {")
    println(io, "  title = \"$(spec.title)\"")
    println(io, "  start = $(spec.start[1]).$(spec.start[2])")
    print(io, "  data = (")
    _write_wrapped(io, spec.y)
    println(io, ")")
    println(io, "}")

    spec.transform !== nothing && println(io, "transform { function = $(spec.transform) }")

    has_regression = !isempty(spec.regression_variables) || spec.regression_user !== nothing ||
                      spec.exog !== nothing || !isempty(spec.aictest)
    if has_regression
        println(io, "regression {")
        !isempty(spec.regression_variables) &&
            println(io, "  variables = ($(join(spec.regression_variables, " ")))")
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

    spec.automdl && println(io, "automdl { }")
    spec.outlier && println(io, "outlier { }")

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

    return String(take!(io))
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

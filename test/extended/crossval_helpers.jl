# test/extended/crossval_helpers.jl
#
# Shared plumbing for the extended, R/Python-cross-validated test suite
# (see development-sequence.md's Post-W.4a section for the full
# methodology writeup and the real discrepancies found and fixed while
# building this). Only loaded when SEASONALADJUSTMENT_EXTENDED_TESTS=1
# (see test/extended/runtests.jl) -- a plain `Pkg.test()` never touches
# R/Python at all.
#
# R/Python interpreter locations are read from environment variables
# with plain-PATH fallbacks, NOT hardcoded to this development
# session's own WSL/micromamba paths -- CI (a standard r-lib/actions
# setup) and a fresh local machine both just need `Rscript`/`python3`
# on PATH; the env vars exist for exactly this development session's
# own non-standard micromamba-env setup, not as the assumed norm.
const _RSCRIPT = get(ENV, "SEASONALADJUSTMENT_RSCRIPT", "Rscript")
const _PYTHON = get(ENV, "SEASONALADJUSTMENT_PYTHON", "python3")
const _X13_BIN_DIR = get(ENV, "SEASONALADJUSTMENT_X13_BIN_DIR") do
    # Python's statsmodels needs a DIRECTORY containing a binary named
    # one of a fixed set (x13as/x12a/x13as_html, confirmed directly via
    # statsmodels.tsa.x13._binary_names) -- x13ashtml (this package's
    # own binary name) isn't among them, so a same-named-as-expected
    # symlink is created once, lazily, the first time it's needed.
    dir = mktempdir()
    link = joinpath(dir, Sys.iswindows() ? "x13as_html.exe" : "x13as_html")
    try
        symlink(x13_binary_path(), link)
    catch
        cp(x13_binary_path(), link)
    end
    dir
end

const _EXTENDED_DIR = @__DIR__

"""
    _r_available() -> Bool
    _python_available() -> Bool

`true` if the corresponding interpreter, with the packages this suite
needs (`seasonal`+`jsonlite` for R, `statsmodels` for Python), can
actually run right now -- never throws. Every cross-validation testset
is gated on these, exactly like every real-binary testset elsewhere in
this project is gated on `x13_binary_available()` (same convention,
same reasoning: skip cleanly with a clear warning rather than fail on
an environment that was never expected to have this installed).
"""
function _r_available()
    try
        out = read(`$_RSCRIPT -e 'library(seasonal); library(jsonlite); cat("OK")'`, String)
        return occursin("OK", out)
    catch
        return false
    end
end

function _python_available()
    try
        out = read(`$_PYTHON -c "import statsmodels; print('OK')"`, String)
        return occursin("OK", out)
    catch
        return false
    end
end

"""
    CrossvalCase

One matched, explicit spec to run through Julia, R, and/or Python and
compare. Deliberately has NO defaults for the fields that this
session's own investigation found silently diverge between tools
(`transform`/`arima_model`/`outlier`/`aictest`/`regression_variables`)
-- see `r_helper.R`'s own module comment for the real ~3-unit-magnitude
discrepancy that motivated this (R's `regression.aictest` silently
defaulting to td+easter even with `regression.variables=NULL`).
"""
struct CrossvalCase
    y::Vector{Float64}
    start::Tuple{Int,Int}
    transform::Symbol            # :none, :log, or :auto
    arima_model::Union{Nothing,String}   # nothing => automdl
    outlier::Bool
    seats::Bool
    trading::Bool
    aictest::Vector{Symbol}      # only :td/:easter meaningfully cross-checked (see r_helper.R)
    period::Int                  # 12 (monthly) or 4 (quarterly) -- see quarterly interval support
end

# 8-arg convenience constructor, defaulting period=12 -- keeps every
# existing monthly call site (the whole Stage-1 grid) unchanged; only
# quarterly-specific cases need to pass period explicitly.
CrossvalCase(y, start, transform, arima_model, outlier, seats, trading, aictest) =
    CrossvalCase(y, start, transform, arima_model, outlier, seats, trading, aictest, 12)

function _case_to_json_dict(c::CrossvalCase; x13_path::AbstractString = _X13_BIN_DIR)
    Dict(
        "y" => c.y,
        "start_year" => c.start[1],
        "start_period" => c.start[2],
        "transform" => string(c.transform),
        "arima_model" => c.arima_model,
        "outlier" => c.outlier,
        "seats" => c.seats,
        "trading" => c.trading,
        "period" => c.period,
        "regression_variables" => String[],
        "aictest" => string.(c.aictest),
        "x13_path" => x13_path,
    )
end

"""
    _run_r(case) -> Dict

Runs `case` through `r_helper.R` (which itself runs R's own
`seasonal::seas()`), returning the parsed JSON result dict (same shape
`_run_julia`/`_run_python` return, so callers compare uniformly).
Throws if R itself can't be invoked -- callers should check
`_r_available()` first, matching this project's established
`x13_binary_available()`-gating convention.
"""
function _run_r(case::CrossvalCase)
    indir = mktempdir()
    inpath = joinpath(indir, "in.json")
    outpath = joinpath(indir, "out.json")
    open(inpath, "w") do io
        JSON_write(io, _case_to_json_dict(case))
    end
    run(`$_RSCRIPT $(joinpath(_EXTENDED_DIR, "r_helper.R")) $inpath $outpath`)
    return JSON_read(outpath)
end

function _run_python(case::CrossvalCase)
    indir = mktempdir()
    inpath = joinpath(indir, "in.json")
    outpath = joinpath(indir, "out.json")
    open(inpath, "w") do io
        JSON_write(io, _case_to_json_dict(case))
    end
    run(`$_PYTHON $(joinpath(_EXTENDED_DIR, "python_helper.py")) $inpath $outpath`)
    return JSON_read(outpath)
end

"""
    _r_calendar_available() -> Bool

`true` if R plus `timeDate`/`bizdays`/`jsonlite` (Stage 2's own
calendar-engine cross-validation packages, distinct from Stage 1's
`seasonal`) are available right now -- never throws. A session could
have one dependency set without the other (`seasonal` is a much larger,
slower install than `timeDate`/`bizdays`), so this is checked
separately from `_r_available()`, not assumed to imply it.
"""
function _r_calendar_available()
    try
        out = read(`$_RSCRIPT -e 'library(timeDate); library(bizdays); library(jsonlite); cat("OK")'`, String)
        return occursin("OK", out)
    catch
        return false
    end
end

"""
    _run_r_calendar(input::Dict) -> Dict

Runs `input` (see `r_calendar_helper.R`'s own module comment for the
JSON contract) through R's `timeDate`/`bizdays` packages, returning the
parsed JSON result dict. Throws if R itself can't be invoked --
callers should check `_r_calendar_available()` first.
"""
function _run_r_calendar(input::AbstractDict)
    indir = mktempdir()
    inpath = joinpath(indir, "in.json")
    outpath = joinpath(indir, "out.json")
    open(inpath, "w") do io
        JSON_write(io, input)
    end
    run(`$_RSCRIPT $(joinpath(_EXTENDED_DIR, "r_calendar_helper.R")) $inpath $outpath`)
    return JSON_read(outpath)
end

# ---------------------------------------------------------------------
# A tiny, self-contained JSON reader/writer -- this package has no JSON
# dependency (deliberately: parse_udg/parse_table are plain-text, not
# JSON, per W.3/W.4's own design), and pulling one in as a real
# dependency just for this opt-in extended suite isn't worth it. Only
# handles the flat {string => number|string|bool|null|array} shape
# `_case_to_json_dict` and the two helper scripts' own output actually
# use -- not a general-purpose JSON implementation.
# ---------------------------------------------------------------------

function JSON_write(io::IO, d::AbstractDict)
    _json_write_value(io, d)
end

_json_write_value(io::IO, v::Nothing) = print(io, "null")
_json_write_value(io::IO, v::Bool) = print(io, v ? "true" : "false")
_json_write_value(io::IO, v::Real) = print(io, v)
_json_write_value(io::IO, v::AbstractString) = print(io, "\"", replace(v, "\"" => "\\\""), "\"")
function _json_write_value(io::IO, v::AbstractVector)
    print(io, "[")
    for (i, x) in enumerate(v)
        i > 1 && print(io, ",")
        _json_write_value(io, x)
    end
    print(io, "]")
end
# Nested Dicts (e.g. one entry per {from,to} pair inside an array) need
# their own dispatch, not just the top-level JSON_write entry point --
# jsonlite's own default auto-simplifies a JSON array of same-shaped
# objects into an R data.frame on read, which r_calendar_helper.R
# relies on directly (`nrow(...)`, `...$from[i]`-style access).
function _json_write_value(io::IO, d::AbstractDict)
    print(io, "{")
    first = true
    for (k, v) in d
        first || print(io, ",")
        first = false
        print(io, "\"", k, "\":")
        _json_write_value(io, v)
    end
    print(io, "}")
end

function JSON_read(path::AbstractString)
    text = read(path, String)
    pos = Ref(1)
    return _json_parse_value(text, pos)
end

function _json_skip_ws(text, pos)
    while pos[] <= lastindex(text) && isspace(text[pos[]])
        pos[] = nextind(text, pos[])
    end
end

function _json_parse_value(text, pos)
    _json_skip_ws(text, pos)
    c = text[pos[]]
    if c == '{'
        return _json_parse_object(text, pos)
    elseif c == '['
        return _json_parse_array(text, pos)
    elseif c == '"'
        return _json_parse_string(text, pos)
    elseif c == 't'
        pos[] += 4
        return true
    elseif c == 'f'
        pos[] += 5
        return false
    elseif c == 'n'
        pos[] += 4
        return nothing
    else
        return _json_parse_number(text, pos)
    end
end

function _json_parse_object(text, pos)
    d = Dict{String,Any}()
    pos[] += 1  # {
    _json_skip_ws(text, pos)
    if text[pos[]] == '}'
        pos[] += 1
        return d
    end
    while true
        _json_skip_ws(text, pos)
        key = _json_parse_string(text, pos)
        _json_skip_ws(text, pos)
        pos[] += 1  # :
        val = _json_parse_value(text, pos)
        d[key] = val
        _json_skip_ws(text, pos)
        if text[pos[]] == ','
            pos[] += 1
        else
            pos[] += 1  # }
            break
        end
    end
    return d
end

function _json_parse_array(text, pos)
    arr = Any[]
    pos[] += 1  # [
    _json_skip_ws(text, pos)
    if text[pos[]] == ']'
        pos[] += 1
        return arr
    end
    while true
        val = _json_parse_value(text, pos)
        push!(arr, val)
        _json_skip_ws(text, pos)
        if text[pos[]] == ','
            pos[] += 1
        else
            pos[] += 1  # ]
            break
        end
    end
    return arr
end

function _json_parse_string(text, pos)
    pos[] += 1  # opening "
    start = pos[]
    buf = IOBuffer()
    while text[pos[]] != '"'
        if text[pos[]] == '\\'
            pos[] = nextind(text, pos[])
            print(buf, text[pos[]])
        else
            print(buf, text[pos[]])
        end
        pos[] = nextind(text, pos[])
    end
    pos[] += 1  # closing "
    return String(take!(buf))
end

function _json_parse_number(text, pos)
    start = pos[]
    while pos[] <= lastindex(text) && (isdigit(text[pos[]]) || text[pos[]] in ('-', '+', '.', 'e', 'E'))
        pos[] = nextind(text, pos[])
    end
    s = text[start:pos[]-1]
    return occursin('.', s) || occursin('e', lowercase(s)) ? parse(Float64, s) : parse(Int, s)
end

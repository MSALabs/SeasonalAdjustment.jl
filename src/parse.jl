# src/parse.jl
#
# W.3 -- output-table parsing. See handoff/w3-run-parse.md for the
# verified references (X-11 `.dNN` vs SEATS `.sNN` share one internal
# format, confirmed directly by running a real SEATS spec) and the test
# plan this file's tests implement.

"""
    parse_table(path) -> Vector{Tuple{Date,Float64}}

Parses one `x13ashtml` output table -- a `.d10`/`.d11`/`.d12`/`.d13`
(X-11) or `.s10`/`.s11`/`.s12`/`.s13` (SEATS) file. Both share the exact
same internal format (confirmed directly by running a real SEATS spec
and inspecting the output, not assumed from documentation): a 2-line
header (`date\\t<name>` then a `------\\t---...` separator), then
tab-separated `<YYYYMM>\\t<value>` rows -- one parser handles both,
dispatching on nothing but the file's own content.

Only the monthly `YYYYMM` date format is supported (every fixture in
this project is monthly) -- a differently-shaped date string throws a
clear error rather than being silently misparsed as some other
frequency that hasn't actually been verified.
"""
function parse_table(path::AbstractString)
    lines = readlines(path)
    length(lines) >= 2 || error("$path: expected at least a 2-line header, got $(length(lines)) line(s)")
    out = Tuple{Date,Float64}[]
    for line in @view lines[3:end]
        isempty(strip(line)) && continue
        parts = split(line, '\t')
        length(parts) >= 2 || error("$path: malformed data line (expected 2 tab-separated fields): $(repr(line))")
        datestr = parts[1]
        length(datestr) == 6 || error(
            "$path: unsupported date format $(repr(datestr)) -- only monthly YYYYMM is " *
            "supported (every fixture verified in this project is monthly); a different " *
            "length suggests a different frequency (e.g. quarterly) that hasn't been " *
            "confirmed against a real fixture yet",
        )
        year = parse(Int, datestr[1:4])
        month = parse(Int, datestr[5:6])
        value = parse(Float64, parts[2])
        push!(out, (Date(year, month), value))
    end
    return out
end

"""
    parse_output(result::X13RunResult, tables) -> Dict{Symbol,Vector{Tuple{Date,Float64}}}

Convenience wrapper around [`parse_table`](@ref) for several tables at
once, resolving each symbol in `tables` (e.g. `:d10`, `:s11`) against
`result.dir`/`result.basename` (see [`run_x13`](@ref)). Deliberately
takes the whole `X13RunResult` rather than a bare basename string (as
first sketched in handoff/w3-run-parse.md) -- `run_x13` runs in a fresh
scratch directory per call, not the caller's current working directory,
so resolving output paths needs `result.dir` too; taking the result
directly avoids the caller having to track and re-pass it by hand.
"""
function parse_output(result::X13RunResult, tables::AbstractVector{Symbol})
    out = Dict{Symbol,Vector{Tuple{Date,Float64}}}()
    for t in tables
        path = joinpath(result.dir, "$(result.basename).$(t)")
        isfile(path) || error(
            "expected output table $path (requested :$t) does not exist -- was it " *
            "included in the spec's x11{save=(...)}/seats{save=(...)} list?",
        )
        out[t] = parse_table(path)
    end
    return out
end

"""
    parse_udg(path) -> Dict{String,String}

Parses a `.udg` file -- "user diagnostics", `key: value` pairs one per
line, colon-separated. Confirmed directly against a real fixture
(`handoff/udg_and_residuals/auto_test.udg`, 376 lines): every line has
exactly one colon, no duplicate keys, so a plain `Dict` loses nothing.
Values are left as raw strings (not parsed into numbers/tuples) -- the
`.udg` file mixes plain numbers, coefficient/se/t-stat triples, and free
text (e.g. `"Automatic selection"`) in ways specific to each key, so a
uniform numeric parse would either fail or silently misparse; callers
that need a specific key as a number should `parse` it themselves.

**Not produced by any spec-file setting** -- confirmed by testing every
documented `x13ashtml` flag individually: `.udg` is only written when
the binary is invoked with the `-S` command-line flag (see `run_x13`'s
`udg` keyword), not by anything in `X13Spec`/`render`.
"""
function parse_udg(path::AbstractString)
    d = Dict{String,String}()
    for line in eachline(path)
        idx = findfirst(':', line)
        idx === nothing && continue
        d[strip(line[1:idx-1])] = strip(line[idx+1:end])
    end
    return d
end

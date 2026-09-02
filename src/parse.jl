# src/parse.jl
#
# W.3 -- output-table parsing. See handoff/w3-run-parse.md for the
# verified references (X-11 `.dNN` vs SEATS `.sNN` share one internal
# format, confirmed directly by running a real SEATS spec) and the test
# plan this file's tests implement.

"""
    parse_table(path; period=12) -> Vector{Tuple{Date,Float64}}

Parses one `x13ashtml` output table -- a `.d10`/`.d11`/`.d12`/`.d13`
(X-11) or `.s10`/`.s11`/`.s12`/`.s13` (SEATS) file. Both share the exact
same internal format (confirmed directly by running a real SEATS spec
and inspecting the output, not assumed from documentation): a 2-line
header (`date\\t<name>` then a `------\\t---...` separator), then
tab-separated `<YYYYMM>\\t<value>` rows -- one parser handles both,
dispatching on nothing but the file's own content.

`period` selects how the trailing 2 digits of the 6-char date string are
interpreted: `12` (the default) for monthly `YYYYMM` (01-12); `4` for
quarterly `YYYYQQ` -- confirmed directly against a real quarterly fixture
that the binary reuses the exact same 6-char width for quarterly output,
just with the trailing digits meaning quarter-number (01-04) rather than
month-number. A quarter is mapped to the `Date` of its first month
(Q1->month 1, Q2->month 4, Q3->month 7, Q4->month 10). Any other `period`
value, or a trailing-digit value out of range for the given `period`,
throws a clear error rather than silently misparsing.

# Examples
This needs no real X-13 run -- it is pure text parsing against the
documented file format, so it is a genuine jldoctest:
```jldoctest
julia> path = joinpath(mktempdir(), "demo.d11");

julia> write(path, "date\\td11\\n------\\t---------\\n194901\\t124.55\\n194902\\t124.63\\n");

julia> parse_table(path)
2-element Vector{Tuple{Dates.Date, Float64}}:
 (Dates.Date("1949-01-01"), 124.55)
 (Dates.Date("1949-02-01"), 124.63)

julia> qpath = joinpath(mktempdir(), "demo.q11");

julia> write(qpath, "date\\tq11\\n------\\t---------\\n194901\\t124.55\\n194902\\t124.63\\n");

julia> parse_table(qpath; period = 4)
2-element Vector{Tuple{Dates.Date, Float64}}:
 (Dates.Date("1949-01-01"), 124.55)
 (Dates.Date("1949-04-01"), 124.63)
```
"""
function parse_table(path::AbstractString; period::Int=12)
    period in (4, 12) || error(
        "parse_table: period=$period isn't supported -- only 4 (quarterly) or 12 " *
        "(monthly) match x13ashtml's own output, confirmed directly against the real binary",
    )
    lines = readlines(path)
    length(lines) >= 2 || error("$path: expected at least a 2-line header, got $(length(lines)) line(s)")
    out = Tuple{Date,Float64}[]
    for line in @view lines[3:end]
        isempty(strip(line)) && continue
        parts = split(line, '\t')
        length(parts) >= 2 || error("$path: malformed data line (expected 2 tab-separated fields): $(repr(line))")
        datestr = parts[1]
        length(datestr) == 6 || error(
            "$path: unsupported date format $(repr(datestr)) -- only the 6-char " *
            "YYYYMM/YYYYQQ format is supported; a different length suggests a frequency " *
            "that hasn't been confirmed against a real fixture yet",
        )
        year = parse(Int, datestr[1:4])
        sub = parse(Int, datestr[5:6])
        value = parse(Float64, parts[2])
        if period == 12
            sub in 1:12 || error(
                "$path: date $(repr(datestr)) has month=$sub outside 1:12 for period=12",
            )
            push!(out, (Date(year, sub), value))
        else # period == 4
            sub in 1:4 || error(
                "$path: date $(repr(datestr)) has quarter=$sub outside 1:4 for period=4",
            )
            push!(out, (Date(year, (sub - 1) * 3 + 1), value))
        end
    end
    return out
end

"""
    parse_output(result::X13RunResult, tables; period=12) -> Dict{Symbol,Vector{Tuple{Date,Float64}}}

Convenience wrapper around [`parse_table`](@ref) for several tables at
once, resolving each symbol in `tables` (e.g. `:d10`, `:s11`) against
`result.dir`/`result.basename` (see [`run_x13`](@ref)). Deliberately
takes the whole `X13RunResult` rather than a bare basename string --
`run_x13` runs in a fresh
scratch directory per call, not the caller's current working directory,
so resolving output paths needs `result.dir` too; taking the result
directly avoids the caller having to track and re-pass it by hand.

`period` (`12` monthly / `4` quarterly) is threaded straight through to
[`parse_table`](@ref) for every requested table -- callers must pass the
same `period` the underlying spec was run with.

# Examples
```julia
julia> spec = X13Spec(dataset("airline").value; start = (1949, 1), automdl = true);

julia> path = write_spec(spec, joinpath(mktempdir(), "demo.spc"));

julia> result = run_x13(path);

julia> tables = parse_output(result, [:d10, :d11]);

julia> sort(collect(keys(tables)))
2-element Vector{Symbol}:
 :d10
 :d11
```
"""
function parse_output(result::X13RunResult, tables::AbstractVector{Symbol}; period::Int=12)
    out = Dict{Symbol,Vector{Tuple{Date,Float64}}}()
    for t in tables
        path = joinpath(result.dir, "$(result.basename).$(t)")
        isfile(path) || error(
            "expected output table $path (requested :$t) does not exist -- was it " *
            "included in the spec's x11{save=(...)}/seats{save=(...)} list?",
        )
        out[t] = parse_table(path; period=period)
    end
    return out
end

"""
    parse_udg(path) -> Dict{String,String}

Parses a `.udg` file -- "user diagnostics", `key: value` pairs one per
line, colon-separated. Confirmed directly against a real 376-line
fixture: every line has
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

# Examples
Pure text parsing, no real X-13 run needed:
```jldoctest
julia> path = joinpath(mktempdir(), "demo.udg");

julia> write(path, "aic: 1397.25779143434\\ntransform: Log(y)\\n");

julia> d = parse_udg(path);

julia> d["aic"]
"1397.25779143434"

julia> d["transform"]
"Log(y)"
```
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

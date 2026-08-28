# src/run.jl
#
# W.3 -- subprocess invocation. See handoff/w3-run-parse.md for the
# verified references and the test plan this file's tests implement.

"""
    X13RunResult

The typed result of one `x13ashtml` invocation -- `success`,
`stdout` (the full captured text; the binary writes ALL of its banner/
warning/error output to stdout, confirmed directly -- stderr is always
empty), and `warnings`/`errors` already extracted from it, instead of
leaving the caller to grep raw text themselves (the concrete
"superior to R/Python" claim for this task: both references return
either raw text or leave error inspection entirely manual).

`dir`/`basename` locate the run's working directory and the spec's
basename (without extension) -- `x13ashtml` writes its output tables
(`<basename>.<table>`) there; use with [`parse_output`](@ref) or
[`parse_table`](@ref) directly.

`success` is derived from `errors` being empty, NOT the process exit
code -- confirmed directly that `x13ashtml` exits 0 even when it prints
an `ERROR:` and produces no seasonal adjustment at all.
"""
struct X13RunResult
    success::Bool
    stdout::String
    warnings::Vector{String}
    errors::Vector{String}
    dir::String
    basename::String
end

"""
    _extract_messages(text, marker) -> Vector{String}

Pulls out each `marker`-prefixed message block from `x13ashtml`'s
stdout, joining a message's wrapped continuation lines into one string
(confirmed necessary directly: e.g. the minimum-length error's
identifying text, "3 complete years", is on the message's SECOND line,
not its first). A block ends at a blank line or the start of the next
`ERROR:`/`WARNING:`/`NOTE:` block.
"""
function _extract_messages(text::AbstractString, marker::AbstractString)
    lines = split(text, '\n')
    n = length(lines)
    messages = String[]
    i = 1
    while i <= n
        stripped = strip(lines[i])
        if startswith(stripped, marker)
            block = String[stripped]
            j = i + 1
            while j <= n
                nxt = strip(lines[j])
                if isempty(nxt) || startswith(nxt, "ERROR:") || startswith(nxt, "WARNING:") || startswith(nxt, "NOTE:")
                    break
                end
                push!(block, nxt)
                j += 1
            end
            push!(messages, join(block, " "))
            i = j
        else
            i += 1
        end
    end
    return messages
end

"""
    _prepare_run_dir(spec_path) -> (dir, basename)

Copies `spec_path` into a fresh temporary directory and returns it
along with the spec's basename (no extension). Runs always happen in a
scratch directory, never in-place next to a committed fixture --
`x13ashtml` writes several output files (`.html`, `_err.html`,
`_log.html`, plus whichever `.dNN`/`.sNN` tables were requested) that
would otherwise repeatedly litter this repo's own verification
fixtures on every test run.
"""
function _prepare_run_dir(spec_path::AbstractString)
    dir = mktempdir()
    dest = joinpath(dir, basename(spec_path))
    cp(spec_path, dest)
    base = splitext(basename(spec_path))[1]
    return dir, base
end

"""
    run_x13(spec_path; binary_path=x13_binary_path()) -> X13RunResult

Runs `x13ashtml` against `spec_path` (copied into a fresh scratch
directory first, see [`_prepare_run_dir`](@ref)) and returns a typed
[`X13RunResult`](@ref).
"""
function run_x13(spec_path::AbstractString; binary_path::AbstractString = x13_binary_path())
    dir, base = _prepare_run_dir(spec_path)
    cmd = Cmd(`$binary_path $base`; dir = dir)
    buf = IOBuffer()
    run(pipeline(ignorestatus(cmd); stdout = buf, stderr = buf))
    text = String(take!(buf))
    errors = _extract_messages(text, "ERROR:")
    warnings = _extract_messages(text, "WARNING:")
    return X13RunResult(isempty(errors), text, warnings, errors, dir, base)
end

"""
    run_x13_batch(spec_paths; binary_path=x13_binary_path(), parallel::Bool=true) -> Vector{X13RunResult}

Runs `x13ashtml` against each of `spec_paths`. When `parallel=true`
(the default), every process is spawned asynchronously up front (`run(
cmd; wait=false)`), then all are waited on together -- the OS scheduler
runs the already-fast (~10ms) subprocesses genuinely concurrently, with
no Julia-side worker-process layer. This is DELIBERATELY NOT a
worker-pool design: handoff/w3-run-parse.md found that pattern (each
worker itself spawning a subprocess -- Python's `ProcessPoolExecutor`)
made things slower, since the coordination overhead exceeded the ~10ms
of actual work being parallelized. The direct async-spawn approach here
was benchmarked for real (not just reasoned structurally) against the
real binary, unlike the Python finding it's motivated by: 20 runs,
serial 1.02s vs parallel 0.54s (1.89x); 100 runs, serial 15.67s vs
parallel 5.62s (2.79x) -- see development-sequence.md's W.3 row for
the exact numbers and how they were produced.
"""
function run_x13_batch(
    spec_paths::AbstractVector{<:AbstractString};
    binary_path::AbstractString = x13_binary_path(),
    parallel::Bool = true,
)
    n = length(spec_paths)
    if !parallel
        return [run_x13(p; binary_path = binary_path) for p in spec_paths]
    end

    dirs = Vector{String}(undef, n)
    bases = Vector{String}(undef, n)
    bufs = Vector{IOBuffer}(undef, n)
    procs = Vector{Base.Process}(undef, n)
    for i in 1:n
        dirs[i], bases[i] = _prepare_run_dir(spec_paths[i])
        bufs[i] = IOBuffer()
        cmd = Cmd(`$binary_path $(bases[i])`; dir = dirs[i])
        procs[i] = run(pipeline(ignorestatus(cmd); stdout = bufs[i], stderr = bufs[i]); wait = false)
    end
    foreach(wait, procs)

    results = Vector{X13RunResult}(undef, n)
    for i in 1:n
        text = String(take!(bufs[i]))
        errors = _extract_messages(text, "ERROR:")
        warnings = _extract_messages(text, "WARNING:")
        results[i] = X13RunResult(isempty(errors), text, warnings, errors, dirs[i], bases[i])
    end
    return results
end

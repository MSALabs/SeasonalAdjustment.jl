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

# Runs `cmd` (stdout and stderr merged) and returns the combined output
# as a String. Deliberately does NOT use `run(pipeline(cmd; stdout=buf,
# stderr=buf))` with an `IOBuffer` destination: that form has Base spawn
# one internal relay task per redirected stream (one for stdout, one for
# stderr) that copies bytes into the destination as they arrive, and
# under concurrent/multi-task use this raced in practice -- confirmed
# for real via CI (intermittent `ArgumentError: ensureroom failed,
# IOBuffer is not writeable`, and mismatched parallel-vs-serial results
# even after routing each subprocess through its own private buffer
# inside its own `@async` task, which ruled out cross-task buffer
# sharing as the cause -- the race was between stdout's and stderr's own
# relay tasks for a SINGLE process, not between processes). Passing the
# SAME `Pipe` as both `stdout` and `stderr` merges both streams at the
# OS level instead, with no Base-managed relay task at all: the calling
# task reads the pipe directly via `read(out, String)`, which blocks
# (cooperatively yielding, so concurrent `@async` callers still overlap)
# until EOF. The spawn itself is wrapped in `_spawn_retrying_eacces`
# (see its own docstring in artifacts.jl): a transient permission-denied
# spawn failure on a just-extracted executable, confirmed for real on
# Windows CI, not hypothetical.
function _run_capture(cmd::Cmd)
    return _spawn_retrying_eacces() do
        out = Pipe()
        proc = run(pipeline(ignorestatus(cmd); stdout = out, stderr = out); wait = false)
        close(out.in)
        text = read(out, String)
        wait(proc)
        return text
    end
end

"""
    run_x13(spec_path; binary_path=x13_binary_path(), udg::Bool=false) -> X13RunResult

Runs `x13ashtml` against `spec_path` (copied into a fresh scratch
directory first, see `_prepare_run_dir`) and returns a typed
[`X13RunResult`](@ref).

`udg=true` passes the `-S` command-line flag, which is what actually
produces the `.udg` diagnostics file -- confirmed directly by testing
every documented `x13ashtml` flag individually (`handoff/w4-addendum-
udg-residuals-static.md`): `.udg` is NOT controlled by anything in the
spec file itself (`X13Spec`/`render`), only by this flag on the
invocation. Parse the result with [`parse_udg`](@ref).
"""
function run_x13(spec_path::AbstractString; binary_path::AbstractString = x13_binary_path(), udg::Bool = false)
    dir, base = _prepare_run_dir(spec_path)
    cmd = udg ? Cmd(`$binary_path $base -S`; dir = dir) : Cmd(`$binary_path $base`; dir = dir)
    text = _run_capture(cmd)
    errors = _extract_messages(text, "ERROR:")
    warnings = _extract_messages(text, "WARNING:")
    return X13RunResult(isempty(errors), text, warnings, errors, dir, base)
end

"""
    run_x13_batch(spec_paths; binary_path=x13_binary_path(), parallel::Bool=true) -> Vector{X13RunResult}

Runs `x13ashtml` against each of `spec_paths`. When `parallel=true`
(the default), every command runs inside its own `@async` task, all
started up front and joined with `@sync` -- the already-fast (~10ms)
subprocesses genuinely overlap at the OS level, since Julia yields the
current task while `_run_capture` is waiting on its subprocess's pipe,
with no Julia-side worker-process layer. This is DELIBERATELY NOT a
worker-pool design: handoff/w3-run-parse.md found that pattern (each
worker itself spawning a subprocess -- Python's `ProcessPoolExecutor`)
made things slower, since the coordination overhead exceeded the ~10ms
of actual work being parallelized. The direct async-task approach here
was benchmarked for real (not just reasoned structurally) against the
real binary -- see development-sequence.md's W.3 row for the exact
numbers. See `_run_capture`'s own comment for why output capture uses a
merged `Pipe` read directly by the calling task, not an `IOBuffer`
redirect target -- that form raced under concurrent use even with each
task given its own private buffer.
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
    for i in 1:n
        dirs[i], bases[i] = _prepare_run_dir(spec_paths[i])
    end

    texts = Vector{String}(undef, n)
    @sync for i in 1:n
        @async begin
            cmd = Cmd(`$binary_path $(bases[i])`; dir = dirs[i])
            texts[i] = _run_capture(cmd)
        end
    end

    results = Vector{X13RunResult}(undef, n)
    for i in 1:n
        errors = _extract_messages(texts[i], "ERROR:")
        warnings = _extract_messages(texts[i], "WARNING:")
        results[i] = X13RunResult(isempty(errors), texts[i], warnings, errors, dirs[i], bases[i])
    end
    return results
end

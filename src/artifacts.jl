# src/artifacts.jl
#
# W.1 -- binary artifact management for x13prebuilt (Linux, Windows,
# macOS) via Julia's Artifacts system. See handoff/w1-artifacts.md for
# the verified per-platform archive layouts and the findings below,
# each confirmed directly (empirically tested against a genuinely
# fresh, never-before-populated artifact cache -- not just re-finding
# a copy this package's own tooling had already placed there, an
# earlier blind spot in this task's own verification caught and
# corrected while pushing this to CI for the first time), not assumed.

import Pkg
import SHA
import Downloads
import p7zip_jll

"""
    _download_verified(dl::Dict) -> String

Downloads `dl["url"]`, verifies it against `dl["sha256"]` (the same
hash already declared in Artifacts.toml), and returns the downloaded
file's path. Throws a clear error naming both hashes on a mismatch,
refusing to install anything that doesn't match.
"""
function _download_verified(dl::Dict)
    tmpfile = Downloads.download(dl["url"])
    actual_sha256 = bytes2hex(open(SHA.sha256, tmpfile))
    actual_sha256 == dl["sha256"] || error(
        "SHA256 mismatch downloading $(dl["url"]) -- expected $(dl["sha256"]), got " *
        "$actual_sha256. Refusing to install a binary that doesn't match the hash " *
        "declared in Artifacts.toml.",
    )
    return tmpfile
end

"""
    _custom_artifact_dir(unpack!, platform) -> String

Shared scaffolding for the two platforms whose upstream archive format
Julia's own `@artifact_str`/`ensure_artifact_installed` can't install
automatically (see `_linux_x13_artifact_dir`/
`_windows_x13_artifact_dir` for which, and why, each). Resolves
`x13ashtml`'s meta for `platform`, and if not already installed,
downloads + sha256-verifies it, hands the result to `unpack!(tmpfile,
dir)` inside `create_artifact`, and confirms the resulting tree hash
matches the one already declared in Artifacts.toml before returning the
artifact's directory. `unpack!` first (not a keyword) so callers can
use `do`-block syntax, which always passes the block as the first
positional argument.
"""
function _custom_artifact_dir(unpack!, platform::Base.BinaryPlatforms.AbstractPlatform)
    toml = find_artifacts_toml(@__DIR__)
    toml === nothing && error("could not locate Artifacts.toml relative to $(@__DIR__)")
    meta = artifact_meta("x13ashtml", toml; platform = platform)
    meta === nothing && error("no x13ashtml artifact entry matches $platform in $toml")
    hash = Base.SHA1(meta["git-tree-sha1"])
    if !artifact_exists(hash)
        tmpfile = _download_verified(only(meta["download"]))
        computed_hash = Pkg.Artifacts.create_artifact() do dir
            unpack!(tmpfile, dir)
        end
        computed_hash == hash || error(
            "the freshly-downloaded x13prebuilt binary's computed git-tree-sha1 " *
            "($computed_hash) doesn't match the one declared in Artifacts.toml " *
            "($hash) -- something is inconsistent between the declared artifact " *
            "and what was actually installed.",
        )
    end
    return artifact_path(hash)
end

"""
    _linux_x13_artifact_dir() -> String

Resolves (installing on first use if needed) the Linux x13prebuilt
artifact and returns its directory.

Upstream serves the Linux binary as a BARE raw executable file, not an
archive (confirmed directly against the x13org/x13prebuilt repo at the
pinned commit -- no tar.gz/zip alternative exists for Linux). Julia's
normal automatic artifact installer only knows how to unpack recognized
archive formats and hard-errors on a bare file (`"Is not archive"`) --
hit directly while preparing this task, not a hypothetical concern.
Installs it manually instead, via `_custom_artifact_dir`.
"""
function _linux_x13_artifact_dir()
    platform = Base.BinaryPlatforms.Platform("x86_64", "linux")
    return _custom_artifact_dir(platform) do tmpfile, dir
        dest = joinpath(dir, "x13ashtml")
        cp(tmpfile, dest)
        chmod(dest, 0o755)
    end
end

"""
    _windows_x13_artifact_dir() -> String

Resolves (installing on first use if needed) the Windows x13prebuilt
artifact and returns its directory.

Upstream serves the Windows binary as a plain `.zip`. This looked like
it should be exactly what Julia's normal `@artifact_str` installer
handles -- and W.1's original verification treated it as confirmed
working, but that check only ever re-found a copy this package's own
`tools/generate_artifacts.jl` had already placed in the local artifact
cache; the genuinely fresh download path was never actually exercised
until pushing to CI surfaced it failing for real. **Julia's built-in
unpacker cannot extract plain zip files at all**, confirmed directly
from Pkg's own source (`Pkg.PlatformEngines.unpack`, stdlib
`PlatformEngines.jl`): it always pipes `7z x <archive> -so` into
`Tar.extract`, which only produces a valid result for tar-based
archives (`.tar`/`.tar.gz`/...), where 7z's `-so` reveals an inner tar
stream. For a plain zip -- no tar layer inside at all -- that pipe
produces the raw extracted file bytes, which `Tar.extract` then fails
to parse (`"This does not appear to be a TAR file/stream"`), confirmed
directly by hitting exactly that error against a genuinely fresh
artifact cache. Installs it manually instead, via `p7zip_jll` (the same
7-Zip binary Pkg itself already depends on and uses internally) invoked
as a normal, complete zip extraction (`7z x <archive> -o<dir> -y`), not
routed through the tar-only pipe.
"""
function _windows_x13_artifact_dir()
    platform = Base.BinaryPlatforms.Platform("x86_64", "windows")
    return _custom_artifact_dir(platform) do tmpfile, dir
        run(`$(p7zip_jll.p7zip()) x $tmpfile -o$dir -y`)
    end
end

"""
    x13_binary_path() -> String

Resolves the x13prebuilt artifact for the running platform and returns
the actual invokable executable path within it -- not just the
artifact directory, since each platform's archive has a different
internal layout (confirmed directly, see handoff/w1-artifacts.md):

- Linux: a bare executable file at the artifact root (`x13ashtml`),
  installed via `_linux_x13_artifact_dir` since it isn't an
  archive Julia's normal installer can handle.
- Windows: `x13ashtml/x13ashtml.exe` (a subfolder), installed via
  `_windows_x13_artifact_dir` -- a real zip archive, but one
  Julia's normal installer *also* can't handle (see that function's own
  docstring for the real bug this surfaced).
- macOS: `x13ashtml/bin/x13ashtml`, dynamically linked against three
  `.dylib` files in the sibling `x13ashtml/lib/` directory -- this
  function asserts that directory and those specific files are present
  and throws a clear error if not, rather than let a broken extraction
  fail silently at first actual use. A real tar.gz, which Julia's
  normal installer genuinely does handle correctly (confirmed directly
  against a fresh artifact cache, unlike the Windows case above).
"""
function x13_binary_path()
    if Sys.islinux()
        return joinpath(_linux_x13_artifact_dir(), "x13ashtml")
    elseif Sys.iswindows()
        return joinpath(_windows_x13_artifact_dir(), "x13ashtml", "x13ashtml.exe")
    elseif Sys.isapple()
        dir = @artifact_str("x13ashtml")
        root = joinpath(dir, "x13ashtml")
        binpath = joinpath(root, "bin", "x13ashtml")
        libdir = joinpath(root, "lib")
        isdir(libdir) || error(
            "x13prebuilt macOS artifact is missing its lib/ directory " *
            "(expected at $libdir) -- bin/x13ashtml is dynamically linked " *
            "against libgfortran/libquadmath/libgcc_s in that directory " *
            "and will fail to run without it. This means the artifact " *
            "extraction is broken/incomplete, not a normal runtime condition.",
        )
        for lib in ("libgfortran.5.dylib", "libquadmath.0.dylib", "libgcc_s.1.dylib")
            isfile(joinpath(libdir, lib)) || error(
                "x13prebuilt macOS artifact is missing $lib in $libdir -- " *
                "broken/incomplete artifact extraction.",
            )
        end
        return binpath
    else
        error(
            "x13prebuilt has no known binary layout for this platform " *
            "(Sys.KERNEL = $(Sys.KERNEL)) -- only Linux, Windows, and " *
            "macOS are supported (see Artifacts.toml).",
        )
    end
end

"""
    _spawn_retrying_eacces(f::Function; max_attempts=6, initial_delay=0.25)

Calls `f()` (expected to spawn a subprocess), retrying with a short
exponential backoff if it throws an `IOError` whose message contains
"permission denied" -- confirmed for real via CI, not a hypothetical:
a genuinely fresh install on Windows CI failed with `IOError: could not
spawn ... permission denied (EACCES)` on the very first invocation of a
just-extracted `.exe`, a well-documented pattern where Windows Defender
(or another real-time AV) briefly locks a freshly-written executable
while scanning it. Any other exception, or a `max_attempts`-th
consecutive EACCES, propagates immediately -- this only smooths over
the specific transient case, it doesn't mask a genuine, persistent
inability to execute the binary.
"""
function _spawn_retrying_eacces(f::Function; max_attempts::Int = 6, initial_delay::Real = 0.25)
    delay = initial_delay
    for attempt in 1:max_attempts
        try
            return f()
        catch e
            is_eacces = e isa Base.IOError && occursin("permission denied", lowercase(e.msg))
            (is_eacces && attempt < max_attempts) || rethrow()
            sleep(delay)
            delay *= 2
        end
    end
end

"""
    x13_binary_available() -> Bool

`true` if the x13prebuilt binary can be resolved AND actually invoked
(a trivial no-args run) on this platform, `false` otherwise (never
throws). Exists so W.3/W.4 can give a clear, actionable error --
"the x13prebuilt binary could not be resolved for this platform" --
instead of a cryptic subprocess failure three layers deep.
"""
function x13_binary_available()
    path = try
        x13_binary_path()
    catch
        return false
    end
    isfile(path) || return false
    try
        # A bare invocation with no spec file exits non-zero (it prints
        # a usage error) -- that's still "available", so ignorestatus
        # the exit code and only treat a genuine spawn failure (missing
        # file, not executable, permission denied) as unavailable.
        # Retries transient EACCES (see `_spawn_retrying_eacces`).
        _spawn_retrying_eacces() do
            run(pipeline(ignorestatus(`$path`); stdout = devnull, stderr = devnull))
        end
        return true
    catch e
        # A bare `catch; return false` here previously swallowed the
        # actual reason silently -- made this function impossible to
        # debug from CI output alone when a fresh install resolves a
        # path but genuinely can't execute it (e.g. a platform-level
        # execution block, not a code bug). Surfacing the exception via
        # @warn costs nothing on the common/available path (unreached)
        # and turns an opaque "false" into an actionable CI log line.
        @warn "x13_binary_available(): invocation failed" path exception = (e, catch_backtrace())
        return false
    end
end

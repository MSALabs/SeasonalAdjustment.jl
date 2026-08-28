# src/artifacts.jl
#
# W.1 -- binary artifact management for x13prebuilt (Linux, Windows,
# macOS) via Julia's Artifacts system. See handoff/w1-artifacts.md for
# the verified per-platform archive layouts and the findings below,
# each confirmed directly (empirically tested), not assumed.

import Pkg
import SHA
import Downloads

"""
    _linux_x13_artifact_dir() -> String

Resolves (installing on first use if needed) the Linux x13prebuilt
artifact and returns its directory.

Upstream serves the Linux binary as a BARE raw executable file, not an
archive (confirmed directly against the x13org/x13prebuilt repo at the
pinned commit -- no tar.gz/zip alternative exists for Linux). Julia's
normal automatic artifact installer (what `@artifact_str`/LazyArtifacts
uses under the hood) only knows how to unpack recognized archive
formats and hard-errors on a bare file (`"Is not archive"`) -- hit
directly while preparing this task, not a hypothetical concern. This
function installs it manually instead: download, verify against the
same sha256 already declared in Artifacts.toml, then hand the result to
`create_artifact`, mirroring exactly what `tools/generate_artifacts.jl`
does for a maintainer -- but lazily, at first actual use, matching this
artifact's own `lazy = true` declaration.

Windows (zip) and macOS (tar.gz) don't need this -- both are real
archives Julia's normal installer already handles correctly (confirmed
directly too, see handoff/w1-artifacts.md).
"""
function _linux_x13_artifact_dir()
    toml = find_artifacts_toml(@__DIR__)
    toml === nothing && error("could not locate Artifacts.toml relative to $(@__DIR__)")
    meta = artifact_meta("x13ashtml", toml)
    meta === nothing && error("no x13ashtml artifact entry matches this platform in $toml")
    hash = Base.SHA1(meta["git-tree-sha1"])
    if !artifact_exists(hash)
        dl = only(meta["download"])
        tmpfile = Downloads.download(dl["url"])
        actual_sha256 = bytes2hex(open(SHA.sha256, tmpfile))
        actual_sha256 == dl["sha256"] || error(
            "SHA256 mismatch downloading the x13prebuilt Linux binary from " *
            "$(dl["url"]) -- expected $(dl["sha256"]), got $actual_sha256. " *
            "Refusing to install a binary that doesn't match the hash " *
            "declared in Artifacts.toml.",
        )
        computed_hash = Pkg.Artifacts.create_artifact() do dir
            dest = joinpath(dir, "x13ashtml")
            cp(tmpfile, dest)
            chmod(dest, 0o755)
        end
        computed_hash == hash || error(
            "the freshly-downloaded x13prebuilt Linux binary's computed " *
            "git-tree-sha1 ($computed_hash) doesn't match the one declared " *
            "in Artifacts.toml ($hash) -- something is inconsistent between " *
            "the declared artifact and what was actually installed.",
        )
    end
    return artifact_path(hash)
end

"""
    x13_binary_path() -> String

Resolves the x13prebuilt artifact for the running platform and returns
the actual invokable executable path within it -- not just the
artifact directory, since each platform's archive has a different
internal layout (confirmed directly, see handoff/w1-artifacts.md):

- Linux: a bare executable file at the artifact root (`x13ashtml`),
  installed via [`_linux_x13_artifact_dir`](@ref) since it isn't an
  archive Julia's normal installer can handle.
- Windows: `x13ashtml/x13ashtml.exe` (a subfolder), a real zip archive
  Julia's normal `@artifact_str` handles directly.
- macOS: `x13ashtml/bin/x13ashtml`, dynamically linked against three
  `.dylib` files in the sibling `x13ashtml/lib/` directory -- this
  function asserts that directory and those specific files are present
  and throws a clear error if not, rather than let a broken extraction
  fail silently at first actual use. A real tar.gz Julia's normal
  installer also handles directly.
"""
function x13_binary_path()
    if Sys.islinux()
        return joinpath(_linux_x13_artifact_dir(), "x13ashtml")
    elseif Sys.iswindows()
        dir = @artifact_str("x13ashtml")
        return joinpath(dir, "x13ashtml", "x13ashtml.exe")
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
        run(pipeline(ignorestatus(`$path`); stdout = devnull, stderr = devnull))
        return true
    catch
        return false
    end
end

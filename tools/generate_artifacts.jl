#!/usr/bin/env julia
# tools/generate_artifacts.jl
#
# Run this ONCE, in a real Julia environment with network access, to
# finalize Artifacts.toml -- specifically, to compute the git-tree-sha1
# values that are currently placeholders (see the note at the top of
# Artifacts.toml for why this can't be done without a Julia runtime).
#
# Usage:
#   julia --project=. tools/generate_artifacts.jl
#
# This downloads each platform binary fresh (verifying against the
# sha256 values already in Artifacts.toml -- if any of those don't
# match, STOP and re-verify the source before proceeding, don't silently
# accept a mismatch), wraps each in its own artifact directory, computes
# the real git-tree-sha1, and rewrites Artifacts.toml with the correct
# values in place of the placeholders.

using Pkg.Artifacts
using SHA
using Downloads

const COMMIT = "61c4043949f43c1ea5ad0fbbc7b6c11fc5073d19"
const BASE = "https://raw.githubusercontent.com/x13org/x13prebuilt/$COMMIT"

# (artifact_name, relative_url_path, expected_sha256, extracted_filename)
const PLATFORMS = [
    ("x13ashtml",               "v1.1.57/linux/64/x13ashtml",
     "c4496c94985984ae9acdcf7fa164197a91fa52c2690b1e1a456312b96920f652", "x13ashtml"),
    ("x13ashtml_linux_armv7l",  "v1.1.57/linux/armv7l/x13ashtml",
     "c0fa23a2ee4683d1c370c1b7916fbcf7d22b631135ecfc350b40b5ae12762864", "x13ashtml"),
    ("x13ashtml_windows",       "v1.1.57/windows/x13ashtml.zip",
     "360def33266deea0640b75b998ae62da5aaeb174b1b284da94dcfe1f1fb0bb83", "x13ashtml.zip"),
    ("x13ashtml_mac_x86_64",    "v1.1.57/mac/64/x13ashtml.tar.gz",
     "99feaaab6c0ccbbc47b736310c69ff88127b1d99b4b2ce851db5aee844fe9b2c", "x13ashtml.tar.gz"),
    ("x13ashtml_mac_arm64",     "v1.1.57/mac/arm64/x13ashtml.tar.gz",
     "99feaaab6c0ccbbc47b736310c69ff88127b1d99b4b2ce851db5aee844fe9b2c", "x13ashtml.tar.gz"),
]

# NOTE: the two mac hashes above are IDENTICAL in the source repo as of
# the pinned commit -- confirm this is a genuine universal binary and
# not a repo mistake before trusting both platform entries; the tarball
# is downloaded and verified against this hash either way, but the
# *meaning* of "same hash for two architectures" is worth a human
# glance, not just a machine check passing.

results = Dict{String,String}()

for (name, relpath, expected_sha, fname) in PLATFORMS
    println("Processing $name ...")
    url = "$BASE/$relpath"
    tmpfile = Downloads.download(url)

    actual_sha = bytes2hex(open(sha256, tmpfile))
    if actual_sha != expected_sha
        error("""
        SHA256 MISMATCH for $name -- STOP.
        Expected: $expected_sha
        Actual:   $actual_sha
        Do not proceed until this is resolved (the source file may have
        changed since Artifacts.toml was written, or something is wrong
        with the download).
        """)
    end

    tree_hash = create_artifact() do artifact_dir
        dest = joinpath(artifact_dir, fname)
        cp(tmpfile, dest)
        if endswith(fname, ".zip")
            run(`unzip -q $dest -d $artifact_dir`)
        elseif endswith(fname, ".tar.gz")
            run(`tar -xzf $dest -C $artifact_dir`)
        else
            chmod(dest, 0o755)  # linux binaries need +x
        end
    end

    results[name] = bytes2hex(tree_hash.bytes)
    println("  git-tree-sha1 = ", results[name])
end

println()
println("Now edit Artifacts.toml: replace each PLACEHOLDER")
println("git-tree-sha1 value with the corresponding hash printed above.")
println("Consider automating this rewrite with TOML.jl if this script")
println("gets run more than once during development.")

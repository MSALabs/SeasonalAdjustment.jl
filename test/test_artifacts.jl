# test/test_artifacts.jl -- W.1
#
# Test plan follows handoff/w1-artifacts.md section 4, adapted to what
# this session could actually confirm -- see development-sequence.md's
# W.1 status note for exactly which platforms were verified how.
#
# CONFIRMED THIS SESSION, directly (not assumed):
# - Linux: full end-to-end via WSL (fresh artifact cache, real
#   download+install+run) -- x13_binary_path() resolved correctly,
#   x13_binary_available() returned true, and the real binary printed
#   its expected usage banner. This is the strongest of the three.
# - Windows: artifact resolution is structurally correct (right path,
#   right git-tree-sha1, `file` confirms a valid PE32+ executable) --
#   but actually RUNNING it could not be confirmed in this specific
#   sandboxed session: this sandbox blocks executing ANY binary placed
#   under ~/.julia/artifacts/ (confirmed via a control test -- even a
#   plain copy of julia.exe itself fails identically from that
#   directory tree with "Access is denied", while running fine from any
#   other directory). This is a sandbox execution policy, not a
#   resolution bug. `x13_binary_available()`'s hard assertion below is
#   therefore expected to fail in THIS environment specifically; a real
#   Windows machine or the CI matrix (.github/workflows/CI.yml) is
#   needed to confirm it positively, exactly as the handoff anticipated
#   ("don't mark this task complete based on Linux passing only").
# - macOS: archive extraction and the bin/+lib/ directory layout are
#   confirmed correct (forced platform resolution + direct file
#   checks); actual execution is unverifiable without macOS hardware,
#   same CI dependency.

function _parse_x13_table(path::AbstractString)
    lines = readlines(path)
    vals = Float64[]
    for line in lines[3:end]  # skip the 2-line header (see CLAUDE.md's documented output format)
        isempty(strip(line)) && continue
        parts = split(line, '\t')
        push!(vals, parse(Float64, parts[2]))
    end
    return vals
end

@testset "artifact resolution -- path exists" begin
    path = x13_binary_path()
    @test isfile(path)
    if !Sys.iswindows()
        # Sys.isexecutable isn't a meaningful check on Windows (no real
        # x-bit concept); only assert it on POSIX platforms.
        @test Sys.isexecutable(path)
    end
end

@testset "macOS specifically -- lib/ directory present alongside bin/" begin
    if Sys.isapple()
        binpath = x13_binary_path()
        libdir = joinpath(dirname(dirname(binpath)), "lib")
        @test isdir(libdir)
        @test isfile(joinpath(libdir, "libgfortran.5.dylib"))
        @test isfile(joinpath(libdir, "libquadmath.0.dylib"))
        @test isfile(joinpath(libdir, "libgcc_s.1.dylib"))
    end
end

@testset "the resolved binary actually runs" begin
    # See the module-level comment above: expected to fail specifically
    # in this sandboxed session on native Windows (confirmed sandbox
    # execution restriction, not a resolution bug); confirmed passing
    # on real Linux via WSL, and on real macOS/Windows CI once two real
    # bugs were fixed -- a macOS artifact tree-hash that was never
    # actually verified against Julia-native extraction on real
    # hardware, and a transient Windows `EACCES` on a just-extracted
    # exe (see `_spawn_retrying_eacces` in src/artifacts.jl), both
    # root-caused via a temporary diagnostic that briefly lived here
    # (removed once real CI evidence was in hand). Kept as a hard
    # assertion per handoff/w1-artifacts.md -- it should pass in every
    # environment except this one, and a regression here is worth
    # seeing even where this specific machine can't clear it.
    @test x13_binary_available()
end

@testset "end-to-end: resolved binary reproduces already-verified output" begin
    # Guarded on x13_binary_available() rather than calling run()
    # unconditionally: on a platform/environment where the binary can't
    # actually be spawned, that's already reported once, clearly, by
    # "the resolved binary actually runs" above -- letting a raw spawn
    # IOError propagate out of this testset too would just be the same
    # root cause crashing two more tests noisily instead of failing
    # them cleanly.
    if x13_binary_available()
        path = x13_binary_path()
        fixture_dir = joinpath(@__DIR__, "..", "handoff", "verification", "airline_baseline")
        spc_text = read(joinpath(fixture_dir, "airline_official.spc"), String)
        mktempdir() do dir
            write(joinpath(dir, "airline_official.spc"), spc_text)
            cd(dir) do
                run(pipeline(ignorestatus(`$path airline_official`); stdout = devnull, stderr = devnull))
            end
            for table in ("d10", "d11", "d12", "d13")
                generated = joinpath(dir, "airline_official.$table")
                committed = joinpath(fixture_dir, "airline_official.$table")
                if !isfile(generated)
                    @test isfile(generated)  # records the failure with a clear name
                    continue
                end
                gen_vals = _parse_x13_table(generated)
                committed_vals = _parse_x13_table(committed)
                @test length(gen_vals) == length(committed_vals)
                @test all(isapprox.(gen_vals, committed_vals; atol = 1e-9))
            end
        end
    else
        @warn "skipping end-to-end binary-output test: x13_binary_available() is false in this environment (see the module-level comment at the top of this file)"
    end
end

@testset "bonus: official Census Bureau test spec runs cleanly" begin
    # x13ashtml/Testairline.spc, bundled directly inside the Windows
    # distribution's zip -- a genuine Census Bureau test fixture (its
    # series data is byte-identical to airline_official.spc's, an
    # independent cross-check that the corrected fixture matches the
    # real official series). Copied here as
    # handoff/verification/airline_baseline/Testairline_official.spc
    # rather than re-extracted from the Windows artifact at test time,
    # since the point is running the fixed spec content, not testing
    # zip extraction again (already covered above).
    fixture = joinpath(@__DIR__, "..", "handoff", "verification", "airline_baseline", "Testairline_official.spc")
    @test isfile(fixture)
    if x13_binary_available()
        path = x13_binary_path()
        mktempdir() do dir
            cp(fixture, joinpath(dir, "Testairline_official.spc"))
            cd(dir) do
                run(pipeline(ignorestatus(`$path Testairline_official`); stdout = devnull, stderr = devnull))
            end
            # x13as writes its main output to <name>.html (confirmed
            # directly by running this exact spec via WSL) -- its
            # presence means the run completed rather than crashing.
            @test isfile(joinpath(dir, "Testairline_official.html"))
        end
    else
        @warn "skipping official Census Bureau test-spec run: x13_binary_available() is false in this environment (see the module-level comment at the top of this file)"
    end
end

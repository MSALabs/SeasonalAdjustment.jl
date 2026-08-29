# test/extended/test_plots_backend.jl -- W.6, Level 3
#
# The ONE test level that actually caught a real bug this session: Level
# 1/2 (test/test_plots.jl, RecipesBase.apply_recipe called directly on
# the ResidPlot/MonthPlot/SpectrumPlot wrapper types) CANNOT catch a
# regression of the exact architectural conflict this file exists to
# guard against (see src/plots.jl's own `residplot` docstring for the
# full story: X13Result's bare type recipe silently shadowed
# residplot(r)/monthplot(r)/spectrumplot(r) when they were first written
# as plain series-type recipes -- residplot(r) rendered plot(r)'s OWN
# series instead, byte-IDENTICAL PNG output, confirmed only by hashing
# real rendered images with a real GR backend, never by apply_recipe).
#
# Deliberately NOT a hard requirement anywhere: Plots.jl is a large,
# heavy dependency (GR_jll, FFMPEG_jll, Qt6*_jll, ~100 transitive
# packages, several minutes to precompile from cold) that has no place
# in this package's own Project.toml (RecipesBase.jl's whole point is
# that consumers choose their own backend) OR in the extended suite's
# otherwise-lightweight R/Python-cross-validation dependency set. This
# file checks for Plots.jl via `Base.find_package` and skips cleanly
# (not a failure) if it isn't installed in whatever environment
# SEASONALADJUSTMENT_EXTENDED_TESTS=1 happens to run in -- installing it
# once (`] add Plots` in that environment) is what turns this from
# skipped to real, verified coverage.

@testset "extended -- every recipe renders through its REAL entry point (backend-gated)" begin
    if Base.find_package("Plots") === nothing
        @warn "skipping real-backend plot smoke test: Plots.jl is not installed in this " *
              "environment -- `] add Plots` (once, ~5-10 min cold) to get real coverage here"
    else
        @eval using Plots
        Plots.gr()

        r = _build_result()
        q = QUARTERLY_RESULT

        cases = [
            ("plot overlay", () -> Plots.plot(r)),
            ("plot components", () -> Plots.plot(r; panels = :components)),
            ("plot pc+trend", () -> Plots.plot(r; transform = :pc, trend = true)),
            ("residplot", () -> Plots.residplot(r)),
            ("monthplot", () -> Plots.monthplot(r)),
            ("monthplot irregular", () -> Plots.monthplot(r; choice = :irregular)),
            ("monthplot quarterly", () -> Plots.monthplot(q; siratios = false)),
            ("spectrumplot", () -> Plots.spectrumplot(r)),
        ]

        pngs = Dict{String,Vector{UInt8}}()
        for (name, f) in cases
            p = f()
            @test p isa Plots.Plot
            io = IOBuffer()
            show(io, MIME"image/png"(), p)
            bytes = take!(io)
            @test length(bytes) > 1000   # a real image, not a blank canvas
            pngs[name] = bytes
        end

        # The actual regression guard: every recipe must render SOMETHING
        # genuinely different from every other -- this is exactly the
        # check that would have caught residplot/monthplot/spectrumplot
        # silently rendering plot(r)'s own series (all four were
        # byte-identical PNGs before the RecipesBase.@userplot fix).
        names = first.(cases)
        for i in eachindex(names), j in (i+1):length(names)
            @test pngs[names[i]] != pngs[names[j]]
        end
    end
end

# test/extended/runtests.jl
#
# Entry point for the extended, R/Python-cross-validated test suite
# (see development-sequence.md's Post-W.4a section). Included from
# test/runtests.jl only when SEASONALADJUSTMENT_EXTENDED_TESTS=1 -- a
# plain local `Pkg.test()` never touches R/Python or runs this at all,
# keeping the default suite exactly as fast as it always was.

include(joinpath(@__DIR__, "crossval_helpers.jl"))

@testset "extended (R/Python cross-validated + extreme cases)" begin
    include(joinpath(@__DIR__, "test_x13_crossval.jl"))
    include(joinpath(@__DIR__, "test_spec_extreme.jl"))
    include(joinpath(@__DIR__, "test_calendar_crossval.jl"))
    include(joinpath(@__DIR__, "test_regressor_crossval.jl"))
    include(joinpath(@__DIR__, "test_calendar_extreme.jl"))
    include(joinpath(@__DIR__, "test_parse_extreme.jl"))
end

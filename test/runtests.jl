using SeasonalAdjustment
using Test
using Dates: Date, dayofweek  # NOT a blanket `using Dates` -- Dates also
                               # exports `adjust`, which collides with
                               # SeasonalAdjustment's own `adjust` and
                               # forces qualification everywhere; import
                               # only the specific names tests need.
import Dates
using BusinessDays
using Random

# Each stage's own test file gets included here as it's implemented.
# See development-sequence.md for the task sequence -- one @testset
# block per task, added in the same order tasks are completed, never
# out of order (a later task's tests shouldn't silently mask an earlier
# task not actually being done).

@testset "SeasonalAdjustment.jl" begin
    include("test_calendars.jl")   # W.0
    include("test_artifacts.jl")   # W.1
    include("test_spec.jl")        # W.2
    include("test_run_parse.jl")   # W.3
    # include("test_api.jl")         # W.4
end

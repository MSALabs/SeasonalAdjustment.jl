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
import StatsAPI
import StatsBase   # W.7: StatsBase.coeftable(r) is used fully-qualified,
                    # matching src/api.jl's own convention (see that
                    # file's own comment on why coeftable/vcov/summary
                    # aren't re-exported under their bare names)
import TSAnalytics  # W.9: `using SeasonalAdjustment` does NOT bring the
                    # TSAnalytics module name into test/Main scope (only
                    # SeasonalAdjustment's OWN exports come through) --
                    # needed to test the TSAnalytics.tsvalues/tsindex
                    # extensions in test_datasets.jl fully-qualified

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
    include("test_api.jl")         # W.4
    include("test_diagnostics.jl") # W.5 -- diagnostics API and seasonal-parity functions
    include("test_plots.jl")       # W.6 -- RecipesBase.jl plot recipes
    include("test_quarterly.jl")   # quarterly interval support
    include("test_known_tables.jl") # W.7.1 -- full save-table catalogue + per-block routing
    include("test_w7.jl")          # W.7.2-W.7.8 -- forecast, missing values, components,
                                    #                vcov, summary/update, force/seasonalma,
                                    #                slidingspans/history
    include("test_datasets.jl")    # W.9 -- bundled example datasets (data/*.csv)
    include("test_book_examples.jl") # Introduction book -- asserts the premises
                                    # of the worked examples behind each chapter's
                                    # figures and numbers (currently: Chapter 9)

    # Extended suite (R/Python-cross-validated extreme cases) -- opt-in
    # only, see test/extended/runtests.jl's own module comment. Kept out
    # of the default suite since it needs R+Python+seasonal+statsmodels
    # installed, none of which a plain `Pkg.test()` should require.
    if get(ENV, "SEASONALADJUSTMENT_EXTENDED_TESTS", "0") == "1"
        include(joinpath("extended", "runtests.jl"))
    end
end

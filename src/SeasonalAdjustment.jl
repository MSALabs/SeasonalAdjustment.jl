module SeasonalAdjustment

using Dates
using Artifacts
using LazyArtifacts
using BusinessDays
using TSAnalytics: tsvalues, tsindex

# ---------------------------------------------------------------------
# Part 1: x13prebuilt wrapper (the active development track --
# see development-sequence.md, Part 1, stages W.0-W.4)
# ---------------------------------------------------------------------
include("artifacts.jl")    # W.1 -- binary artifact resolution
include("calendars.jl")    # W.0 -- India + major-market holiday calendars,
                            #        trading-day / Easter / custom holiday
                            #        regressor generation
include("spec.jl")         # W.2 -- .spc spec-file generation
include("run.jl")          # W.3 -- subprocess invocation
include("parse.jl")        # W.3 -- output-table parsing
include("api.jl")          # W.4 -- the user-facing x13(...) entry point

# ---------------------------------------------------------------------
# Part 2: native Julia engine (deferred -- see development-sequence.md,
# Part 2, stages S.0-S.5). Nothing here yet; included eagerly once each
# stage lands so native/, once it exists, is part of the normal module
# load path rather than a separate opt-in.
# ---------------------------------------------------------------------
# include("native/x11.jl")       # S.1
# include("native/regarima.jl")  # S.2
# include("native/outliers.jl")  # S.3
# include("native/pipeline.jl")  # S.4
# include("native/seats.jl")     # S.5

export x13, X13Result, static
export x13_binary_path, x13_binary_available
export INDIA_NSE
export Calendar, TableCalendar
export isbusinessday, isholiday, isweekend, adjust, advance, businessdaysbetween, holidaylist
export trading_day_regressors, easter_regressor, custom_holiday_regressor
export easter_date
export X13Spec, render, validate!, write_spec, generate_specs
export X13RunResult, run_x13, run_x13_batch
export parse_table, parse_output, parse_udg

end # module

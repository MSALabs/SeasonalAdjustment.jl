module SeasonalAdjustment

using Dates
using Artifacts
using LazyArtifacts
using BusinessDays
using TSAnalytics: tsvalues, tsindex
import StatsAPI
import StatsBase
using RecipesBase

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
include("diagnostics.jl")  # W.5 -- typed .udg accessor layer (Dict-based;
                            #        the X13Result-dispatching overloads live
                            #        in api.jl, included next, since X13Result
                            #        is defined there)
include("api.jl")          # W.4 -- the user-facing x13(...) entry point
                            # W.5 -- StatsAPI contract, series(), show(),
                            #        select_order/open_output/import_spc
include("plots.jl")        # W.6 -- RecipesBase.jl plot recipes

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

# W.5 -- diagnostics accessor layer, StatsAPI contract, seasonal-parity
# functions. StatsAPI generic functions (aic, bic, coef, ...) are used
# fully-qualified (StatsAPI.aic(r), not aic(r)) -- not re-exported under
# their bare names, to avoid silently shadowing whatever the caller's own
# session already has `using StatsAPI`/`using StatsBase` for.
export udg, transformfunction, arima_model, mstats, qs, outliers,
    outlier_counts, fivebestmdl, seasonality_tests, residual_diagnostics,
    spectral_peaks, filters, nobs_effective, spectrum_peaks
export series, select_order, open_output, import_spc

# W.6 -- plot recipes. `plot`/`plot!` themselves are NOT exported (or
# even defined) here -- they belong to whatever plotting backend the
# caller loads (Plots.jl, a Makie backend, ...); this package only adds
# a method via `@recipe function f(r::X13Result; ...)`, which that
# backend's own `plot(r)` picks up automatically once loaded.
# `residplot`/`monthplot`/`spectrumplot` are NOT exported here -- each is
# auto-exported by its own `RecipesBase.@userplot` invocation in
# plots.jl (confirmed directly: @userplot's own macro-generated code
# includes `export $funcname, $funcname!`), so a second manual export
# here would just be redundant.

end # module

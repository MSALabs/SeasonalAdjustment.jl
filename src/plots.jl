# src/plots.jl
#
# W.6 -- plot recipes via RecipesBase.jl. See handoff/w6-plot-recipes-handoff.md
# for the verified references and test plan this file's tests implement,
# cross-checked directly against the real binary and the committed
# fixture before writing any recipe body (spectrum table names/format,
# quarterly outlier-label format, D8's own length relative to D10-D13 --
# see development-sequence.md's W.6 row for exactly what was confirmed
# and what, if anything, the handoff got wrong).
#
# RecipesBase.jl has zero dependencies of its own and pulls in no
# plotting backend -- `@recipe`/`@shorthands` only define data+attribute
# methods; nothing draws until the caller loads Plots.jl or a Makie
# backend. Every test in test/test_plots.jl runs via
# `RecipesBase.apply_recipe` directly, with NO backend installed.

const _MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const _QUARTER_LABELS = ["Q1", "Q2", "Q3", "Q4"]

"""
    _apply_transform(dates, y, transform, period) -> (dates', y')

`:none` (unchanged), `:pc` (period-on-period growth,
`(y[i]-y[i-1])/y[i-1]`, dropping the first observation), or `:pcy`
(year-on-year growth at lag `period`, dropping the first `period`
observations) -- R's `plot.seas`'s own `c("none","PC","PCY")`, lower-
cased to Julia convention. `period` is the caller's own `spec.period`
(4 or 12), not hardcoded to 12 -- confirmed directly this needs to be
period-aware for `:pcy` to mean the right thing on a quarterly result.
"""
function _apply_transform(dates::AbstractVector{Date}, y::AbstractVector{<:Real}, transform::Symbol, period::Int)
    if transform === :none
        return dates, y
    elseif transform === :pc
        return dates[2:end], (y[2:end] .- y[1:end-1]) ./ y[1:end-1]
    elseif transform === :pcy
        return dates[period+1:end], (y[period+1:end] .- y[1:end-period]) ./ y[1:end-period]
    else
        throw(ArgumentError("transform=:$transform isn't recognized -- must be :none, :pc, or :pcy"))
    end
end

"""
    _outlier_date(o, period) -> Union{Date,Nothing}

Converts one [`outliers`](@ref) element's `(year, period)` back into a
`Date` (the first day of that month/quarter) -- `period` here is the
CALLER's spec period (4 or 12), matching [`parse_table`](@ref)'s own
quarter-to-month convention (`Q1`->month 1, `Q2`->month 4, ...).
`nothing` if the outlier's own `period` field couldn't be resolved (see
[`outliers`](@ref)'s own docstring for when that happens).
"""
function _outlier_date(o::NamedTuple, period::Int)
    o.period === nothing && return nothing
    return period == 12 ? Date(o.year, o.period, 1) : Date(o.year, (o.period - 1) * 3 + 1, 1)
end

"""
    _outlier_marker_points(r, dates, values) -> (Vector{Date}, Vector{Float64})

The `(x, y)` points for an outlier scatter overlay, positioned by
looking up each outlier's date directly in `dates` and reading `values`
at that SAME index -- so a marker always sits exactly on the line it's
overlaid on, transformed or not, and an outlier whose date falls outside
`dates` (a `:pc`/`:pcy`-shortened window, or `residplot`'s own shorter
`nefobs`-length window) is silently dropped rather than plotted at the
wrong place. Shared by `plot`'s and `residplot`'s outlier overlays --
they differ only in which `dates`/`values` get passed in.
"""
function _outlier_marker_points(r::X13Result, dates::AbstractVector{Date}, values::AbstractVector{<:Real})
    period = r.spec.period
    xs = Date[]
    ys = Float64[]
    for o in outliers(r)
        d = _outlier_date(o, period)
        d === nothing && continue
        idx = findfirst(==(d), dates)
        idx === nothing && continue
        push!(xs, d)
        push!(ys, values[idx])
    end
    return xs, ys
end

"""
    _subseries_layout(values, period) -> (positions::Vector{Float64}, means::Vector{Float64})

The generic cycle-subseries layout `monthplot` (W.6) needs: for `period`
bands (12 or 4), `positions[k] = k - 0.5` (the mean-bar x-position,
centred in band `[k-1, k)`) and `means[k]` = the mean of every `values`
entry whose 1-indexed position `i` satisfies `((i-1) % period) + 1 ==
k`. Deliberately period-generic and free of any `X13Result`/date
dependency -- per the handoff's own §7, this is designed so the same
geometry can move to TSAnalytics.jl later for a generic seasonal-
subseries plot, with SA's own `monthplot` becoming a thin specialisation
adding the SI-ratio overlay on top.
"""
function _subseries_layout(values::AbstractVector{<:Real}, period::Integer)
    means = Vector{Float64}(undef, period)
    for k in 1:period
        idxs = k:period:length(values)
        means[k] = sum(values[i] for i in idxs) / length(idxs)
    end
    positions = collect((1:period) .- 0.5)
    return positions, means
end

"""
    _band_indices(n, period) -> Vector{Vector{Int}}

1-indexed observation indices grouped by cycle band (band `k` gets every
index `i` with `((i-1) % period) + 1 == k`) -- handles a ragged series
(length not a multiple of `period`) the same way X-13's own monthplot
does: an earlier band simply gets one more point than a later one,
rather than requiring `n` to divide evenly.
"""
function _band_indices(n::Integer, period::Integer)
    bands = [Int[] for _ in 1:period]
    for i in 1:n
        push!(bands[((i - 1) % period) + 1], i)
    end
    return bands
end

# x-positions for the nk raw points inside band k ([k-1, k)), evenly
# spaced -- the exact formula the handoff's own §5 specifies.
_band_positions(k::Integer, nk::Integer) = (k - 1) .+ ((0:nk-1) .+ 0.5) ./ nk

"""
    plot(r::X13Result; panels=:overlay, outliers=true, trend=false, transform=:none)

Matches R's `plot.seas` (`panels=:overlay`, the default) and Python's
`X13ArimaAnalysisResult.plot()` (`panels=:components`) in one recipe.
Needs a plotting backend loaded (Plots.jl, a Makie backend, ...) to
actually draw -- this package depends only on `RecipesBase.jl`.

| Keyword | Values | Default | Meaning |
|---|---|---|---|
| `panels` | `:overlay`, `:components` | `:overlay` | `:overlay`: original + adjusted (+ trend) on one axis, R's own shape. `:components`: observed/SA/trend/irregular as 4 stacked panels, Python's own shape. |
| `outliers` | `Bool` | `true` | Mark detected outliers (`:overlay` only) |
| `trend` | `Bool` | `false` | Add the trend-cycle as a third `:overlay` line; ignored (with a warning) under `:components`, where it is already its own panel |
| `transform` | `:none`, `:pc`, `:pcy` | `:none` | Levels, period-on-period growth, or year-on-year growth -- see [`_apply_transform`](@ref) |
"""
@recipe function f(r::X13Result; panels = :overlay, outliers = true, trend = false, transform = :none)
    panels in (:overlay, :components) || throw(ArgumentError(
        "plot: panels=:$panels isn't recognized -- must be :overlay or :components",
    ))
    period = r.spec.period
    tf(y) = _apply_transform(r.dates, y, transform, period)

    if panels === :components
        trend && @warn "plot: trend=true is ignored under panels=:components (trend is already its own panel)"
        layout := (4, 1)
        legend --> false
        panel_series = (("Observed", r.observed), ("Seasonally Adjusted", r.seasonally_adjusted),
                         ("Trend", r.trend), ("Irregular", r.irregular))
        for (i, (label, vals)) in enumerate(panel_series)
            dts, tv = tf(vals)
            @series begin
                subplot := i
                seriestype := :path
                title := label
                label := label
                dts, tv
            end
        end
    else
        dts_o, obs_t = tf(r.observed)
        @series begin
            seriestype := :path
            label --> "Original"
            dts_o, obs_t
        end
        dts_s, sa_t = tf(r.seasonally_adjusted)
        @series begin
            seriestype := :path
            label --> "Seasonally Adjusted"
            dts_s, sa_t
        end
        if trend
            dts_tr, tr_t = tf(r.trend)
            @series begin
                seriestype := :path
                label --> "Trend"
                dts_tr, tr_t
            end
        end
        if outliers
            mx, my = _outlier_marker_points(r, dts_s, sa_t)
            if !isempty(mx)
                @series begin
                    seriestype := :scatter
                    label --> ""
                    mx, my
                end
            end
        end
    end
end

"""
    residplot(r::X13Result; outliers=true)

Matches R's `residplot` -- regARIMA residuals plotted against `r.dates`.

**A real correction to the plot handoff's own design, not just an
implementation detail**: the handoff assumed `.rsd` is shorter than
`r.dates` (`nefobs`, 131 in the committed fixture, vs. `nobs`, 144) and
built the date axis around tail-aligning a shorter residual window.
Checked directly against the real binary this session (re-running BOTH
the exact automdl spec that produces the committed `auto_test.udg`
`nefobs=131`, AND the separately-committed `resid_test.rsd` fixture's
own spec, with `estimate{save=(rsd)}` added): the real `.rsd` file has
144 rows in both cases -- one residual per original observation, always
-- `nefobs` is an internal likelihood/AIC bookkeeping count, NOT the
`.rsd` file's actual length. `r.residuals` and `r.dates` are therefore
always the same length in practice; the tail-alignment below
(`r.dates[end-length(r.residuals)+1:end]`) is kept anyway as a harmless,
purely defensive no-op for a length mismatch that has not actually been
observed, rather than assumed away entirely.

Adds a zero reference line (R doesn't draw one; regARIMA residuals are
mean-zero by construction and it costs nothing).

Throws `ArgumentError` if `r.residuals` is empty.

**A real, confirmed architectural finding, not in the handoff at all**:
`residplot`/`monthplot`/`spectrumplot` can NOT be plain series-type
recipes (`@recipe function f(::Type{Val{:name}}, r::X13Result; ...)`) as
the handoff specified, because `X13Result` ALSO has its own bare type
recipe (for `plot(r)`) -- confirmed directly this session (a real
Plots.jl/GR smoke test where `residplot(r)` silently rendered `plot(r)`'s
OWN series instead of the residual data, byte-identical PNG output,
caught only by hashing the actual rendered images, not by
`RecipesBase.apply_recipe`-based structural testing, which does not
exercise the real `plot`/`residplot`/... entry-point functions at all).
`RecipesPipeline`'s own `_process_userrecipes!` dispatches
`apply_recipe(attrs, args...)` on ARGUMENT TYPES alone, before
`seriestype` is ever consulted -- so a bare type recipe on `X13Result`
always intercepts every call involving one, regardless of what
`seriestype` a caller requested. The standard, correct fix (used
throughout the Plots.jl ecosystem for exactly this "named plot for a
type that already has its own generic recipe" situation) is
`RecipesBase.@userplot`: a small wrapper struct is the recipe's real
dispatch target instead of `X13Result` directly, sidestepping the
conflict by construction. `RecipesBase.@userplot ResidPlot` also
auto-exports `residplot`/`residplot!` -- see `src/SeasonalAdjustment.jl`,
which does NOT separately export these names itself.
"""
RecipesBase.@userplot ResidPlot
@recipe function f(rp::ResidPlot; outliers = true)
    r = rp.args[1]
    isempty(r.residuals) && throw(ArgumentError("residplot: this X13Result has no residuals"))
    n = length(r.residuals)
    dts = r.dates[end-n+1:end]

    legend --> false
    @series begin
        seriestype := :path
        label --> ""
        dts, r.residuals
    end
    @series begin
        seriestype := :hline
        label --> ""
        [0.0]
    end
    if outliers
        mx, my = _outlier_marker_points(r, dts, r.residuals)
        if !isempty(mx)
            @series begin
                seriestype := :scatter
                label --> ""
                mx, my
            end
        end
    end
end

"""
    monthplot(r::X13Result; choice=:seasonal, siratios=true)

Matches R's `monthplot.seas` -- the seasonal factor (or irregular)
laid out by calendar period, one band per month (`period=12`) or
quarter (`period=4`), each a thick mean-bar plus its own raw
cycle-subseries points, with the SI ratios (table D8) overlaid as
vertical stems (R's own second layer -- the actual diagnostic content
of this chart: the stems show the scatter the mean bar smooths through).

| Keyword | Values | Default | Meaning |
|---|---|---|---|
| `choice` | `:seasonal`, `:irregular` | `:seasonal` | Which component to lay out |
| `siratios` | `Bool` | `true` | Overlay D8 SI ratios as stems (`:seasonal` only -- ignored, with a warning, under `:irregular`: SI ratios are seasonal-plus-irregular by construction, so the overlay is meaningless there) |

D8 is fetched via [`series`](@ref)`(r, :d8)` -- already present with no
re-run for any `x13()`-produced result (W.6 added `:d8` to `x13()`'s
always-saved set for exactly this); a hand-built `X13Spec`/`run_x13`
result triggers `series`'s own automatic (and announced) re-run instead.

Implemented via `RecipesBase.@userplot` (see [`residplot`](@ref)'s own
docstring for exactly why a plain series-type recipe doesn't work here).
"""
RecipesBase.@userplot MonthPlot
@recipe function f(mp::MonthPlot; choice = :seasonal, siratios = true)
    r = mp.args[1]
    choice in (:seasonal, :irregular) || throw(ArgumentError(
        "monthplot: choice=:$choice isn't recognized -- must be :seasonal or :irregular",
    ))
    period = r.spec.period
    values = choice === :seasonal ? r.seasonal_factors : r.irregular
    n = length(values)
    bands = _band_indices(n, period)
    labels = period == 12 ? _MONTH_LABELS : _QUARTER_LABELS

    legend --> false
    xticks --> (collect((1:period) .- 0.5), labels)
    xlims --> (0, period)

    for k in 1:period
        idxs = bands[k]
        xs = _band_positions(k, length(idxs))
        @series begin
            seriestype := :path
            color --> :gray
            label --> ""
            xs, values[idxs]
        end
    end

    _, means = _subseries_layout(values, period)
    for k in 1:period
        @series begin
            seriestype := :path
            linewidth --> 3
            color --> :red
            label --> ""
            [k - 1, k], [means[k], means[k]]
        end
    end

    if choice === :irregular
        siratios && @warn "monthplot: siratios is ignored for choice=:irregular (SI ratios are seasonal-plus-irregular by construction)"
    elseif siratios
        si = series(r, :d8)
        m = min(length(si), n)
        si_bands = _band_indices(m, period)
        for k in 1:period
            idxs = si_bands[k]
            isempty(idxs) && continue
            xs = _band_positions(k, length(idxs))
            @series begin
                seriestype := :sticks
                color --> :blue
                label --> ""
                xs, si[idxs]
            end
        end
    end
end

"""
    spectrumplot(r::X13Result; series=:sa)

Not in either reference pipeline -- [`spectrum_peaks`](@ref) (W.6) makes
it nearly free, and spectral peaks are how residual seasonality and
trading-day effects are actually judged in official statistics. Plots
the confirmed real spectrum curve (`.sp0`/`.sp1`/`.sp2`/`.spr`, fetched
via `_spectrum_series`, re-running once if not already saved)
with vertical markers at every seasonal/trading-day frequency `.udg`
itself reports as a visually significant peak (see [`spectrum_peaks`](@ref)).

| Keyword | Values | Default | Meaning |
|---|---|---|---|
| `series` | `:original`, `:sa`, `:irregular`, `:residual` | `:sa` | Which spectrum |

Implemented via `RecipesBase.@userplot` (see [`residplot`](@ref)'s own
docstring for exactly why a plain series-type recipe doesn't work here).
"""
RecipesBase.@userplot SpectrumPlot
@recipe function f(sp::SpectrumPlot; series = :sa)
    r = sp.args[1]
    haskey(_SPECTRUM_UDG_PREFIX, series) || throw(ArgumentError(
        "spectrumplot: series=:$series isn't recognized -- must be :original, :sa, :irregular, or :residual",
    ))
    curve = _spectrum_series(r, series)
    freqs = [c.freq for c in curve]
    vals = [c.value for c in curve]

    legend --> false
    xlabel --> "Frequency"
    ylabel --> "10*log(Spectrum)"

    @series begin
        seriestype := :path
        label --> _SPECTRUM_UDG_PREFIX[series]
        freqs, vals
    end

    for p in spectrum_peaks(r; series = series)
        p.significant || continue
        @series begin
            seriestype := :vline
            label --> ""
            [p.freq]
        end
    end
end

# W.8's own function-name kwargs (`backcast::Bool` on forecastplot) would
# otherwise shadow the real `backcast`/`forecast` FUNCTIONS inside that
# recipe's own body (a kwarg introduces a local binding of the same
# name) -- private aliases captured here, before any such shadowing can
# happen, sidestep it entirely.
const _forecast_fn = forecast
const _backcast_fn = backcast

"""
    _seasonal_layout(values, dates, period) -> Vector{@NamedTuple{year::Int, x::Vector{Int}, y::Vector{Float64}}}

The layout [`seasonalplot`](@ref) (W.8.1) needs: one entry per CALENDAR
YEAR present in `dates`, `x` the period-of-year (`1:12` or `1:4`) for
each observation in that year, `y` the matching values -- a partial
year (the series doesn't start/end on a year boundary) plots short
rather than being dropped, the same way a ragged `monthplot` band does.
Deliberately period-generic and `X13Result`-free (values/dates/period
only), matching W.6 §7's own design intent for `_subseries_layout` --
`seasonalplot` is this layout's transpose of `monthplot`'s.
"""
function _seasonal_layout(values::AbstractVector{<:Real}, dates::AbstractVector{Date}, period::Integer)
    n = length(values)
    out = NamedTuple{(:year, :x, :y),Tuple{Int,Vector{Int},Vector{Float64}}}[]
    i = 1
    while i <= n
        yr = Dates.year(dates[i])
        xs = Int[]
        ys = Float64[]
        while i <= n && Dates.year(dates[i]) == yr
            p = period == 12 ? Dates.month(dates[i]) : ((Dates.month(dates[i]) - 1) ÷ 3 + 1)
            push!(xs, p)
            push!(ys, values[i])
            i += 1
        end
        push!(out, (year = yr, x = xs, y = ys))
    end
    return out
end

const _SEASONALPLOT_SERIES_FIELD = Dict(
    :observed => :observed, :seasonal => :seasonal_factors, :sa => :seasonally_adjusted,
    :trend => :trend, :irregular => :irregular,
)

"""
    seasonalplot(r::X13Result; series=:seasonal, polar=false, highlight=nothing)

**(W.8.1) The genuinely missing chart** -- `monthplot`'s transpose:
calendar period on the x-axis, one line per YEAR, all overlaid, so an
evolving seasonal pattern (the shape of the year drifting) is visible at
a glance, the thing a subseries plot like `monthplot` can't show
directly. Matches R's `forecast::ggseasonplot`/`feasts::gg_season`.

| Keyword | Values | Default | Meaning |
|---|---|---|---|
| `series` | `:observed`, `:seasonal`, `:sa`, `:trend`, `:irregular` | `:seasonal` | Which component to lay out |
| `polar` | `Bool` | `false` | Wrap onto a polar axis (`gg_season`'s `polar=TRUE`) -- backend support for this varies (confirmed Plots.jl-specific, not independently checked against every backend); decide per-backend rather than assuming |
| `highlight` | `nothing`, `:last`, an `Int` year, or a collection of years | `nothing` | Emphasise the given year(s) (full opacity, thicker line); every other year is drawn muted |

Year labelling: each line's own `label` is set to its year (R places the
year at the line's right end rather than in a legend, which matters past
~12 years; whether a backend actually draws it that way is its own
choice, not controlled here).
"""
RecipesBase.@userplot SeasonalPlot
@recipe function f(sp::SeasonalPlot; series::Symbol = :seasonal, polar::Bool = false, highlight = nothing)
    r = sp.args[1]
    haskey(_SEASONALPLOT_SERIES_FIELD, series) || throw(ArgumentError(
        "seasonalplot: series=:$series isn't recognized -- must be :observed, :seasonal, :sa, :trend, or :irregular",
    ))
    values = getfield(r, _SEASONALPLOT_SERIES_FIELD[series])
    period = r.spec.period
    bands = _seasonal_layout(values, r.dates, period)
    labels = period == 12 ? _MONTH_LABELS : _QUARTER_LABELS

    highlight_years = if highlight === nothing
        Int[]
    elseif highlight === :last
        [bands[end].year]
    elseif highlight isa Integer
        [Int(highlight)]
    else
        Int.(collect(highlight))
    end

    legend --> false
    xticks --> (collect(1:period), labels)
    xlims --> (0.5, period + 0.5)
    polar && (projection := :polar)

    for entry in bands
        is_hi = entry.year in highlight_years
        muted = !isempty(highlight_years) && !is_hi
        @series begin
            seriestype := :path
            label --> string(entry.year)
            alpha --> (muted ? 0.3 : 1.0)
            linewidth --> (is_hi ? 2 : 1)
            entry.x, entry.y
        end
    end
end

"""
    forecastplot(r::X13Result; backcast=false, level=0.95, history=nothing)

**(W.8.2)** Observed series, then the forecast extension as a distinct
series joined to the last observation (`(dates[end], observed[end])`
prepended, so the line doesn't start floating one period later), with
the prediction interval drawn via a `ribbon`-attributed series covering
ONLY the true forecast horizon (no join-point extension -- there is no
interval at a known observation).

| Keyword | Values | Default | Meaning |
|---|---|---|---|
| `backcast` | `Bool` | `false` | Also draw the backcast extension, joined the same way at `dates[1]` |
| `level` | `Real` in (0,1) | `0.95` | Interval width, passed to [`forecast`](@ref)/[`backcast`](@ref) |
| `history` | `nothing`, `Int` | `nothing` | Show only the last `n` observations before the forecast -- truncates the OBSERVED series only, never the forecast/backcast extensions |

`.fct`/`.bct` already carry point/lower/upper on the original scale
(W.7.2), so nothing here needs back-transforming.
"""
RecipesBase.@userplot ForecastPlot
@recipe function f(fp::ForecastPlot; backcast::Bool = false, level::Real = 0.95, history::Union{Nothing,Int} = nothing)
    r = fp.args[1]
    fc = _forecast_fn(r; level = level)

    legend --> false
    obs_dates = history === nothing ? r.dates : r.dates[max(1, end - history + 1):end]
    obs_vals = history === nothing ? r.observed : r.observed[max(1, end - history + 1):end]
    @series begin
        seriestype := :path
        label --> "Observed"
        obs_dates, obs_vals
    end

    @series begin
        seriestype := :path
        label --> "Forecast"
        vcat([r.dates[end]], fc.dates), vcat([r.observed[end]], fc.point)
    end

    if backcast
        bc = _backcast_fn(r; level = level)
        @series begin
            seriestype := :path
            label --> "Backcast"
            vcat(bc.dates, [r.dates[1]]), vcat(bc.point, [r.observed[1]])
        end
    end

    # ribbon series LAST, deliberately -- test/test_plots.jl relies on
    # this being `last(...)` to check it starts at the first forecast
    # date, not the join point.
    @series begin
        seriestype := :path
        label --> ""
        linealpha --> 0
        ribbon := (fc.point .- fc.lower, fc.upper .- fc.point)
        fillalpha --> 0.2
        fc.dates, fc.point
    end
end

"""
    residdiagplot(r::X13Result; panels=[:series,:acf,:histogram], lags=24)

**(W.8.3)** The standard X-13 residual review panel. Uses the binary's
OWN `.acf`/`.pcf`/`.ac2` (`check{}`-block tables, W.8's own reference
work) rather than recomputing from `r.residuals`, so the plotted values
match what X-13 itself reports.

| Keyword | Values | Default | Meaning |
|---|---|---|---|
| `panels` | any of `:series`, `:acf`, `:pacf`, `:acfsquared`, `:histogram` (`:qq` throws, see below) | `[:series, :acf, :histogram]` | Which panels, in order, one per row |
| `lags` | `Int` | `24` | Lags shown on the ACF/PACF/ACF² panels |

**`:qq` deliberately throws** rather than silently rendering nothing --
it needs a normal quantile function this package doesn't have (the same
open dependency question W.8's own handoff raises: is a
`Distributions.jl` dependency worth adding for one panel? Not resolved
here, so not silently guessed at either).

Confidence bands on the ACF-family panels are the standard
`±1.96/√n` large-sample approximation (`n` = `length(r.residuals)`),
drawn as two horizontal reference lines -- `.acf`'s own file DOES carry
a proper per-lag standard error column (`SE_of_ACF`), not currently
exposed here (only the primary statistic column is fetched, see
`SeasonalAdjustment._check_series`).
"""
RecipesBase.@userplot ResidDiagPlot
@recipe function f(rd::ResidDiagPlot; panels::AbstractVector{Symbol} = [:series, :acf, :histogram], lags::Int = 24)
    r = rd.args[1]
    isempty(r.residuals) && throw(ArgumentError("residdiagplot: this X13Result has no residuals"))
    valid_panels = (:series, :acf, :pacf, :acfsquared, :histogram, :qq)
    for p in panels
        p in valid_panels || throw(ArgumentError(
            "residdiagplot: panels contains :$p -- must be one of $(valid_panels)",
        ))
        p === :qq && throw(ArgumentError(
            "residdiagplot: panels=:qq isn't supported -- no normal quantile function is " *
            "wired up (see this recipe's own docstring)",
        ))
    end

    layout := (length(panels), 1)
    legend --> false
    n = length(r.residuals)
    band = 1.96 / sqrt(n)

    for (i, p) in enumerate(panels)
        if p === :series
            @series begin
                subplot := i
                seriestype := :path
                title := "Residuals"
                r.dates, r.residuals
            end
        elseif p in (:acf, :pacf, :acfsquared)
            table = p === :acf ? :acf : p === :pacf ? :pcf : :ac2
            vals = _check_series(r, table)
            m = min(lags, length(vals))
            @series begin
                subplot := i
                seriestype := :sticks
                title := (p === :acf ? "ACF" : p === :pacf ? "PACF" : "ACF (squared)")
                1:m, vals[1:m]
            end
            @series begin
                subplot := i
                seriestype := :hline
                linestyle --> :dash
                [band]
            end
            @series begin
                subplot := i
                seriestype := :hline
                linestyle --> :dash
                [-band]
            end
        elseif p === :histogram
            @series begin
                subplot := i
                seriestype := :histogram
                title := "Histogram"
                r.residuals
            end
        end
    end
end

"""
    componentplot(r::X13Result; which=:all, reference=true)

**(W.8.4) Closes the India-calendar loop**: `coef(r)` gives the Diwali
coefficient itself; this shows its month-by-month path.

| Keyword | Values | Default | Meaning |
|---|---|---|---|
| `which` | `:all`, `:trading_day`, `:holiday`, `:user`, `:outlier` | `:all` | Which factor series, via [`components`](@ref) |
| `reference` | `Bool` | `true` | Draw the no-effect reference line -- read `finmode` from `.udg` rather than assumed: `1.0` for a multiplicative spec, `0.0` for additive |

Components absent from the model are skipped silently (not drawn as
flat lines) -- `which=:all` with NO regression effects at all throws
`ArgumentError`, via [`components`](@ref)'s own check (not duplicated
here).
"""
RecipesBase.@userplot ComponentPlot
@recipe function f(cp::ComponentPlot; which::Symbol = :all, reference::Bool = true)
    r = cp.args[1]
    which in (:all, :trading_day, :holiday, :user, :outlier) || throw(ArgumentError(
        "componentplot: which=:$which isn't recognized -- must be :all, :trading_day, " *
        ":holiday, :user, or :outlier",
    ))
    mode = get(r.udg, "finmode", "multiplicative")
    ref_value = occursin("mult", lowercase(mode)) ? 1.0 : 0.0

    legend --> true
    if reference
        @series begin
            seriestype := :hline
            label --> ""
            linestyle --> :dash
            [ref_value]
        end
    end

    pairs = if which === :all
        c = components(r) # throws ArgumentError itself if there's nothing at all
        ((:trading_day, c.trading_day), (:holiday, c.holiday), (:user, c.user), (:outlier, c.outlier))
    else
        ((which, components(r; which = which)),)
    end
    for (name, vals) in pairs
        vals === nothing && continue
        @series begin
            seriestype := :path
            label --> string(name)
            r.dates, vals
        end
    end
end

"""
    spanplot(r::X13Result; kind=:slidingspans)

**(W.8.5, done last per the handoff's own sequencing -- its scope
genuinely depends on [`slidingspans`](@ref)/[`revision_history`](@ref),
W.7.8)**. Those two accessors deliberately surface `.udg`'s HEADLINE
summary statistics rather than the per-span TIME SERIES the original
handoff's own sketch envisioned (`slidingspans.sfspans` etc. -- separate
saveable tables, not modeled by W.7.8, see that deliverable's own
"honest gap" note) -- so this recipe's scope is correspondingly
reduced: `kind=:slidingspans` draws the per-period average seasonal-
factor revision (`.udg`'s own `s3.a.brk.pNN` breakdown, the closest real
per-period detail actually exposed); `kind=:history` draws the
concurrent-vs-most-recent SEASONALLY ADJUSTED average-absolute-revision
series `revision_history` already collects. NOT the full "each span its
own line" chart the original handoff sketched -- that needs the raw
per-span tables, a genuine future extension, not silently pretended here.
"""
RecipesBase.@userplot SpanPlot
@recipe function f(sp::SpanPlot; kind::Symbol = :slidingspans)
    r = sp.args[1]
    kind in (:slidingspans, :history) || throw(ArgumentError(
        "spanplot: kind=:$kind isn't recognized -- must be :slidingspans or :history",
    ))
    period = r.spec.period
    labels = period == 12 ? _MONTH_LABELS : _QUARTER_LABELS

    legend --> false
    if kind === :slidingspans
        ss = slidingspans(r)
        ss === nothing && throw(ArgumentError(
            "spanplot: kind=:slidingspans requires the spec to have requested slidingspans{} " *
            "-- see slidingspans()'s own docstring",
        ))
        vals = Float64[]
        for k in 1:period
            raw = get(ss.raw, "s3.a.brk.p" * lpad(k, 2, '0'), nothing)
            toks = raw === nothing ? nothing : split(strip(raw))
            v = toks === nothing || isempty(toks) ? nothing : tryparse(Float64, toks[end])
            push!(vals, something(v, NaN))
        end
        xticks --> (1:period, labels)
        @series begin
            seriestype := :bar
            label --> "Avg abs seasonal-factor revision (sliding spans)"
            1:period, vals
        end
    else
        h = revision_history(r)
        h === nothing && throw(ArgumentError(
            "spanplot: kind=:history requires the spec to have requested history{} -- see " *
            "revision_history()'s own docstring",
        ))
        isempty(h.sa_estimates) && throw(ArgumentError(
            "spanplot: kind=:history found no sa_estimates in revision_history(r) to plot",
        ))
        @series begin
            seriestype := :path
            label --> "SA revision history (avg abs revision)"
            1:length(h.sa_estimates), h.sa_estimates
        end
    end
end


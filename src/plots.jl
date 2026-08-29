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
auto-exports `residplot`/`residplot!` -- see [`SeasonalAdjustment`](@ref)'s
own module file, which does NOT separately export these names itself.
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
via [`_spectrum_series`](@ref), re-running once if not already saved)
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


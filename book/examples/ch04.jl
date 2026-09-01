# book/examples/ch04.jl -- the toy X-11, three-pass, multiplicative-only,
# no outlier handling. Pedagogical only (see the chapter's own constraint:
# inline in the text, clearly labelled a toy, never exported, never in
# src/). Figures B-1, B-2, B-3 all come from `toy_x11`'s own return value.

"""
    toy_x11(y::AbstractVector{<:Real}; period::Int=12, passes::Int=3) -> NamedTuple

The whole idea in about fifteen lines: moving-average trend, divide it out,
average what remains by calendar position to get the seasonal pattern,
divide that out too, repeat. Returns `(trend=, seasonal=, sa=, trend_history=,
seasonal_history=)` -- the history vectors are what Figure B-3 plots to show
convergence across passes.
"""
function toy_x11(y::AbstractVector{<:Real}; period::Int = 12, passes::Int = 3)
    n = length(y)
    trend_history = Vector{Vector{Union{Missing,Float64}}}()
    seasonal_history = Vector{Vector{Float64}}()
    sa = copy(float.(y))
    local trend, seasonal
    for _ in 1:passes
        # Step 1: centred 12-term moving average (2x12: average two
        # consecutive 12-term averages so it centres on an observation).
        trend = Vector{Union{Missing,Float64}}(missing, n)
        for t in (period÷2+1):(n-period÷2)
            lo, hi = t - period ÷ 2, t + period ÷ 2
            trend[t] = (sum(sa[lo:hi-1]) / period + sum(sa[lo+1:hi]) / period) / 2
        end
        # Step 2: divide the ORIGINAL series (not the running `sa`) by the
        # latest trend -> SI ratios. This is the detail that makes the
        # iteration actually converge rather than oscillate: dividing `sa`
        # here (a real bug caught by inspecting Figure B-3 directly -- pass
        # 2 collapsed to a flat, seasonality-free line, and pass 3 jumped
        # straight back to matching pass 1) measures whatever seasonality is
        # left in an already-deseasonalized series against its own smoothed
        # trend, which is approximately nothing, every time. Each pass must
        # re-measure the FULL seasonal-plus-irregular signal in `y` against
        # a progressively better trend, not a shrinking residual.
        si = [trend[t] === missing ? missing : y[t] / trend[t] for t in 1:n]
        # Step 3: average by calendar position -> raw seasonal factors.
        raw_seasonal = zeros(period)
        for p in 1:period
            vals = [si[t] for t in p:period:n if si[t] !== missing]
            raw_seasonal[p] = sum(vals) / length(vals)
        end
        # Normalise so the seasonal factors average to 1 over a full cycle.
        raw_seasonal ./= (sum(raw_seasonal) / period)
        seasonal = [raw_seasonal[mod1(t, period)] for t in 1:n]
        # Step 4: divide out the seasonal -> a better series for the next pass.
        sa = y ./ seasonal
        push!(trend_history, copy(trend))
        push!(seasonal_history, copy(seasonal))
    end
    return (trend = trend, seasonal = seasonal, sa = sa,
            trend_history = trend_history, seasonal_history = seasonal_history)
end

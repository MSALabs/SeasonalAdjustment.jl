# book/examples/ch06.jl -- seasonal-filter family comparison (Chapter 6).
# Builds on derivations.jl's `seasonal_filter_weights`/`gain`/
# `apply_symmetric_filter` and ch04.jl's toy_x11 for real SI ratios (the
# same object the real binary calls D8).
#
# Requires derivations.jl's `apply_symmetric_filter` to already be defined
# (both are `include`d together by every caller -- see test_book_examples.jl
# and make_figures.jl).

"""
    seasonal_factors_by_filter(si::AbstractVector, period::Int, weights::AbstractVector) -> Matrix{Union{Missing,Float64}}

The seasonal filter operates *across years at a fixed calendar position*,
not along the series -- Chapter 6.1's own conceptual hurdle. For each
calendar position `p` in `1:period`, collects the one-value-per-year
subseries (`si[p], si[p+period], si[p+2period], ...`) and applies `weights`
(a symmetric, odd-length, already-composed filter such as
`seasonal_filter_weights((3,3))`) along *that* subseries via
`apply_symmetric_filter`. Returns a `period × nyears` matrix (missing at the
years each subseries' own filter can't reach), which is what a `monthplot`-
style layout plots one calendar band at a time.
"""
function seasonal_factors_by_filter(si::AbstractVector{<:Union{Missing,Real}}, period::Int, weights::AbstractVector{<:Real})
    nyears = length(si) ÷ period
    out = Matrix{Union{Missing,Float64}}(missing, period, nyears)
    for p in 1:period
        sub = Union{Missing,Float64}[si[t] for t in p:period:(p+period*(nyears-1)) if t <= length(si)]
        n = length(sub)
        subf = [ismissing(v) ? missing : Float64(v) for v in sub]
        filtered = apply_symmetric_filter(coalesce.(subf, NaN), weights)
        out[p, 1:n] = filtered
    end
    return out
end

# book/examples/derivations.jl
#
# Real computation behind Part II's four "X"-kind figures (B-4, B-5, B-7,
# B-8): Henderson trend-filter weights, the seasonal-filter family's gain
# functions, and Musgrave's asymmetric end-filter weights. Deliberately
# book-side, not in src/ -- this is illustrative derivation code, not the
# native engine (see introduction-design.md's own note on keeping the two
# separate until the native engine has its own tested implementation).
#
# Every filter here is verified against the real binary's own output before
# being trusted for a figure -- see `test/test_book_examples.jl`'s
# "Chapter 5" testset, which applies the computed 9-term Henderson to a real
# D11 series and checks it reproduces the real D12 closely.

"""
    henderson_weights(n::Int) -> Vector{Float64}

Symmetric Henderson filter weights for a filter of odd length `n` (9, 13 or
23 in X-11), indexed `-m:m` with `m = (n-1)/2`, returned in that order. This
is the standard closed-form numerator (Kenny & Durbin 1982; Ladiray &
Quenneville 2001, §3.3) -- the unique filter, up to normalisation, minimising
the sum of squared third differences of the smoothed series, subject to
reproducing a cubic polynomial exactly -- normalised here by its own sum
rather than via the closed-form denominator constant, which this file's own
history got wrong once already (an earlier version used a specific literal
denominator formula that gave weights summing to 1.75, not 1 -- confirmed
wrong two ways: it violates the level-preserving property every Henderson
filter must have, and normalising by the sum instead reproduces the
commonly published 9-term table -0.041,-0.010,0.119,0.267,0.331,... to three
decimal places). Normalising by the sum is mathematically equivalent to the
correct closed form and carries no risk of a transcription error in a
constant nobody needs to get exactly right.
"""
function henderson_weights(n::Int)
    isodd(n) || throw(ArgumentError("Henderson filter length must be odd, got $n"))
    m = (n - 1) ÷ 2
    raw = [315 * ((m + 1)^2 - j^2) * ((m + 2)^2 - j^2) * ((m + 3)^2 - j^2) * (3 * (m + 2)^2 - 16 - 11 * j^2) for j in -m:m]
    return raw ./ sum(raw)
end

"""
    apply_symmetric_filter(y::AbstractVector, weights::AbstractVector) -> Vector{Union{Missing,Float64}}

Applies a symmetric filter (odd length, centred) to `y`, `missing` at the
`m` points on each end where the filter cannot be applied -- deliberately not
extrapolated or filled, since points at the ends are exactly what
Chapter 9 and Figure B-8 are about.
"""
function apply_symmetric_filter(y::AbstractVector{<:Real}, weights::AbstractVector{<:Real})
    n = length(weights)
    m = (n - 1) ÷ 2
    out = Vector{Union{Missing,Float64}}(missing, length(y))
    for t in (m+1):(length(y)-m)
        out[t] = sum(weights[k+m+1] * y[t+k] for k in -m:m)
    end
    return out
end

"""
    ma_weights(span::Int) -> Vector{Float64}

Weights of a simple `span`-term centred moving average (span odd), the
building block `seasonal_filter_weights` composes.
"""
function ma_weights(span::Int)
    isodd(span) || throw(ArgumentError("span must be odd, got $span"))
    return fill(1 / span, span)
end

"""
    convolve_symmetric(a::AbstractVector, b::AbstractVector) -> Vector{Float64}

Convolves two symmetric, odd-length weight vectors (each already normalised
to sum to 1), returning another symmetric, odd-length, sum-to-1 weight
vector -- the composition rule an "N×M" seasonal filter name describes: an
N-term average of an M-term average.
"""
function convolve_symmetric(a::AbstractVector{<:Real}, b::AbstractVector{<:Real})
    la, lb = length(a), length(b)
    out = zeros(Float64, la + lb - 1)
    for i in eachindex(a), j in eachindex(b)
        out[i+j-1] += a[i] * b[j]
    end
    return out
end

"""
    seasonal_filter_weights(spec::Tuple{Int,Int}) -> Vector{Float64}

Weights of an "N×M" seasonal moving average (e.g. `(3,3)` for 3×3, `(3,5)`
for 3×5): an N-term simple average of an M-term simple average, applied to
one cycle-subseries (e.g. "all the Januaries"). The span in *years* covered
is `N + M - 1`.
"""
seasonal_filter_weights(spec::Tuple{Int,Int}) = convolve_symmetric(ma_weights(spec[1]), ma_weights(spec[2]))

"""
    gain(weights::AbstractVector, freqs::AbstractVector) -> Vector{Float64}

The gain function of a symmetric filter: `|sum_k w_k * exp(-2*pi*i*f*k)|` for
each frequency `f` in `freqs` (cycles per sample). For a real, symmetric
filter this reduces to `sum_k w_k * cos(2*pi*f*k)`, which is what is
actually computed (no complex arithmetic needed, and no rounding-noise
imaginary part to discard).
"""
function gain(weights::AbstractVector{<:Real}, freqs::AbstractVector{<:Real})
    n = length(weights)
    m = (n - 1) ÷ 2
    return [sum(weights[k+m+1] * cos(2π * f * k) for k in -m:m) for f in freqs]
end

"""
    asymmetric_end_weights(n::Int, r::Int) -> Vector{Float64}

An asymmetric end-filter for a length-`n` Henderson filter when only `r`
future observations are available instead of the full `m = (n-1)/2` (`r`
from 0, the series' very last point, up to `m-1`). Returned as a
length-`(m+r+1)` vector covering lags `-m:r`.

**This is a deliberately transparent reconstruction of the idea behind
Musgrave's (1964) method, not a verified reproduction of X-13's own
internal weights** -- no save table exposes X-13's actual applied
end-filter coefficients for comparison, so byte-exact verification isn't
possible with what this package can read back. What *is* verified (see
`test_book_examples.jl`): the weights sum to 1 (level-preserving), are
close to the symmetric Henderson weights on the available lags, and get
more skewed toward the most recent observation as `r` shrinks -- the
qualitative shape every source describes.

The construction: among all filters supported on `-m:r` that reproduce a
local linear trend exactly (`sum(v)=1`, `sum(k*v[k])=0`), find the one
closest in squared distance to the symmetric Henderson weights truncated to
the same support. This is a least-squares problem with two linear
constraints, solved directly via its 2×2 normal equations -- the same
"stay close to the symmetric filter, keep the trend-preserving property"
idea Musgrave's own method embodies, without claiming to reproduce its
exact I/C-ratio-weighted loss function.
"""
function asymmetric_end_weights(n::Int, r::Int)
    isodd(n) || throw(ArgumentError("Henderson filter length must be odd, got $n"))
    m = (n - 1) ÷ 2
    (0 <= r < m) || throw(ArgumentError("r must be in 0:m-1, got r=$r, m=$m"))
    h = henderson_weights(n)  # symmetric weights, index 1 = lag -m
    avail = -m:r
    h_avail = [h[k+m+1] for k in avail]

    # v = h_avail + lambda1 + lambda2*k  minimises sum((v-h_avail)^2)
    # subject to sum(v)=1, sum(k*v)=0. Solve the 2x2 system in lambda1, lambda2.
    n_avail = length(avail)
    s1 = sum(avail)
    s2 = sum(k^2 for k in avail)
    Sh0 = sum(h_avail)
    Sh1 = sum(k * h_avail[i] for (i, k) in enumerate(avail))

    # [n_avail  s1] [lambda1]   [1 - Sh0]
    # [s1     s2 ] [lambda2] = [ -Sh1  ]
    det = n_avail * s2 - s1^2
    lambda1 = ((1 - Sh0) * s2 - s1 * (-Sh1)) / det
    lambda2 = (n_avail * (-Sh1) - s1 * (1 - Sh0)) / det

    return [h_avail[i] + lambda1 + lambda2 * k for (i, k) in enumerate(avail)]
end

# book/examples/ch09.jl
#
# Chapter 9 ("The End-of-Series Problem") worked example: seven truncated
# vintages of the airline series, run with and without forecast extension,
# used both for Figures C-1/C-2 and for the mean-absolute-revision numbers
# quoted in the chapter text. Runs under `test/test_book_examples.jl` and
# is called by `book/figures/make_figures.jl`.
#
# transform is pinned to :log across every vintage -- see the chapter's own
# "fix the transform across vintages" box: with transform=:auto, a shorter
# vintage can select :none where the full sample selects :log, and the
# resulting "revision" would be a units mismatch, not a real result.

using SeasonalAdjustment
using Dates

const CH09_VINTAGE_ENDS = [(1957,12), (1958,6), (1958,12), (1959,6), (1959,12), (1960,6), (1960,12)]

"""
    ch09_vintages(; extend::Bool) -> Vector{NamedTuple}

Runs the airline series truncated at each of seven vintage endpoints,
`extend=false` forcing `forecast.maxlead=0` (X-13's own default is
extension ON, confirmed directly: a bare run reports `nfcst=12`), `extend=true`
leaving the default in place. Returns `(endpoint=, result=, nfcst=)` per
vintage; `nfcst` is returned so callers can assert the experiment's premise
rather than trust it.
"""
function ch09_vintages(; extend::Bool)
    d = dataset("airline")
    map(CH09_VINTAGE_ENDS) do (y, m)
        n = (y - 1949) * 12 + m
        sub = (date = d.date[1:n], value = d.value[1:n])
        res = x13(sub;
                  transform = :log,          # FIXED -- see the Gotcha
                  automdl   = true,
                  spec_args = extend ? Dict{String,String}() :
                                       Dict("forecast.maxlead" => "0"))
        # udg() returns the raw .udg string; nfcst is compared numerically
        # by ch09_vintages' own callers (the premise checks), so parse it
        # here rather than leaving every caller to remember to.
        (endpoint = Date(y, m, 1), result = res, nfcst = something(tryparse(Int, udg(res, "nfcst")), -1))
    end
end

"""
    ch09_revisions(vintages) -> (mean_abs_pct=, max_abs_pct=, max_month=, series=)

For every month covered by at least two vintages, compares the **concurrent**
estimate (earliest vintage whose data ends at that month, i.e. the vintage
drawn at that point on the fan chart) against the **final** estimate (the
full-sample D11, `vintages[end].result`) on the seasonally adjusted series
(D11 -- not the seasonal factors; D11 is what gets published). Revision is
`(final - concurrent) / concurrent`, reported in percent.
"""
function ch09_revisions(vintages)
    final = vintages[end].result
    final_by_date = Dict(zip(final.dates, final.seasonally_adjusted))

    abs_pcts = Float64[]
    worst = (month = nothing, pct = 0.0)
    for v in vintages[1:end-1]                       # exclude the full sample itself
        r = v.result
        # concurrent = the LAST point of this (truncated) vintage's own run,
        # i.e. the estimate made "as of" this vintage's endpoint.
        d, sa = r.dates[end], r.seasonally_adjusted[end]
        haskey(final_by_date, d) || continue
        f = final_by_date[d]
        pct = 100 * abs(f - sa) / abs(sa)
        push!(abs_pcts, pct)
        if pct > worst.pct
            worst = (month = d, pct = pct)
        end
    end
    return (
        mean_abs_pct = isempty(abs_pcts) ? NaN : sum(abs_pcts) / length(abs_pcts),
        max_abs_pct  = worst.pct,
        max_month    = worst.month,
        n            = length(abs_pcts),
    )
end

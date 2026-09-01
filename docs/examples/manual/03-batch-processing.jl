# docs/examples/manual/03-batch-processing.jl -- the real worked loop behind
# the Manual's "Many Series at Once" page, extracted so it's tested rather
# than only eyeballed once when the page was written.

"""
    manual_batch_diagnostics(names) -> Vector{NamedTuple}

Builds specs for each dataset name via `generate_specs`, runs each with
`run_x13` directly (NOT `run_x13_batch`, which has no `udg` keyword and so
never produces a `.udg` file to read diagnostics from), and returns one row
per series with the headline diagnostics -- the exact pattern the Manual
page shows.
"""
function manual_batch_diagnostics(names::AbstractVector{<:AbstractString})
    series_list = [dataset(n).value for n in names]
    options_list = [(; automdl = true, outlier = true, transform = :auto) for _ in names]
    specs = generate_specs(series_list, options_list)

    paths = [write_spec(specs[i], joinpath(mktempdir(), "batch_$i.spc")) for i in eachindex(specs)]
    results = Vector{X13RunResult}(undef, length(specs))
    @sync for i in eachindex(specs)
        @async results[i] = run_x13(paths[i]; udg = true)
    end

    return map(zip(names, results)) do (name, result)
        udgd = parse_udg(joinpath(result.dir, "$(result.basename).udg"))
        m = mstats(udgd)
        q = qs(udgd)
        (series = name,
         transform = transformfunction(udgd),
         model = arima_model(udgd),
         q = m === nothing ? missing : m.q,
         m7 = m === nothing ? missing : m.m7,
         qs_p_adjusted = q.sa.pvalue,
         n_outliers = outlier_counts(udgd).total,
         converged = result.success)
    end
end

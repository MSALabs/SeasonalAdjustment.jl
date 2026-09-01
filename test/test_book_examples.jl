# test_book_examples.jl -- asserts the premises of the book's own worked
# examples, not merely eyeballing them once at figure-generation time.
# Pure-math checks (derivations.jl, ch04.jl's toy_x11) run unconditionally;
# real-binary cross-checks are gated on x13_binary_available(), same
# convention as test_w7.jl.

include(joinpath(@__DIR__, "..", "book", "examples", "derivations.jl"))
include(joinpath(@__DIR__, "..", "book", "examples", "ch04.jl"))
include(joinpath(@__DIR__, "..", "book", "examples", "ch06.jl"))
include(joinpath(@__DIR__, "..", "book", "examples", "ch09.jl"))

@testset "Chapter 5 -- Henderson weights, pure math" begin
    for n in (9, 13, 23)
        w = henderson_weights(n)
        @test length(w) == n
        @test isapprox(sum(w), 1.0; atol = 1e-10)
        @test all(isapprox(w[i], w[end+1-i]; atol = 1e-12) for i in eachindex(w))  # symmetric
    end
    # The commonly published 9-term table (Ladiray & Quenneville), to 3 dp --
    # this is the check that caught a real bug: an earlier closed-form
    # denominator gave weights summing to 1.75, not 1.
    h9 = henderson_weights(9)
    published = [-0.041, -0.010, 0.119, 0.267, 0.331, 0.267, 0.119, -0.010, -0.041]
    @test all(isapprox.(h9, published; atol = 2e-3))
end

@testset "Chapter 5 -- asymmetric end weights, pure math" begin
    for r in 0:3
        w = asymmetric_end_weights(9, r)
        @test length(w) == 4 + r + 1
        @test isapprox(sum(w), 1.0; atol = 1e-8)   # level-preserving
    end
    # More skewed toward the most recent point as fewer future obs remain:
    # the last (most recent) weight should grow as r shrinks.
    last_weights = [asymmetric_end_weights(9, r)[end] for r in 0:3]
    @test issorted(last_weights; rev = true)
end

@testset "Chapter 6 -- seasonal filter weights, pure math" begin
    w33 = seasonal_filter_weights((3, 3))
    w35 = seasonal_filter_weights((3, 5))
    w39 = seasonal_filter_weights((3, 9))
    @test length(w33) == 5   # 3+3-1 years span
    @test length(w35) == 7
    @test length(w39) == 11
    for w in (w33, w35, w39)
        @test isapprox(sum(w), 1.0; atol = 1e-10)
    end
    # Gain at frequency 0 must be 1 for every filter in the family (none of
    # them touch the series' overall level).
    for w in (w33, w35, w39)
        @test isapprox(gain(w, [0.0])[1], 1.0; atol = 1e-10)
    end
end

@testset "Chapter 4 -- toy X-11, pure math" begin
    y = 100.0 .+ 10.0 .* sin.(2π .* (1:120) ./ 12) .+ (1:120) .* 0.5
    t4 = toy_x11(y)
    @test length(t4.seasonal_history) == 3
    # The real bug this session found: dividing the RUNNING sa (not the
    # original y) by the trend each pass causes the seasonal estimate to
    # oscillate -- pass 2 collapses toward flat, pass 3 jumps back to
    # matching pass 1. With the fix, passes should be close to each other,
    # not alternating between two different shapes.
    p1, p2, p3 = t4.seasonal_history
    @test maximum(abs.(p1[1:12] .- p3[1:12])) < 0.05
    @test maximum(abs.(p2[1:12] .- p3[1:12])) < 0.05
    # Seasonal factors must average to 1 over a full cycle (normalisation).
    @test isapprox(sum(t4.seasonal_history[end][1:12]) / 12, 1.0; atol = 1e-8)
end

if x13_binary_available()
    @testset "Chapter 5 -- Henderson-9 reproduces real D12 closely" begin
        d = dataset("airline")
        res = x13(d)
        h9 = henderson_weights(9)
        computed = apply_symmetric_filter(res.seasonally_adjusted, h9)
        errs = Float64[abs(computed[t] - res.trend[t]) / abs(res.trend[t])
                        for t in eachindex(computed) if computed[t] !== missing]
        @test !isempty(errs)
        # Confirmed directly: mean ~0.6%, max ~2.2% -- the residual gap is
        # real X-11 extreme-value handling this simplified filter doesn't
        # replicate, not a wrong formula (see derivations.jl's own docstring).
        @test sum(errs) / length(errs) < 0.02
        @test maximum(errs) < 0.05
    end

    @testset "Chapters 1-2 -- appliance December spike, multiplicative vs additive divergence" begin
        d = dataset("appliance")
        dec_idx = findall(t -> Dates.month(t) == 12, d.date)
        feb_idx = findall(t -> Dates.month(t) == 2, d.date)
        overall_mean = sum(d.value) / length(d.value)
        dec_ratio = (sum(d.value[dec_idx]) / length(dec_idx)) / overall_mean
        feb_ratio = (sum(d.value[feb_idx]) / length(feb_idx)) / overall_mean
        # Matches dataset_info("appliance")'s own cited "Dec 1.52x, Feb 0.86x" --
        # generated independently here, not copied from that notes field.
        @test isapprox(dec_ratio, 1.52; atol = 0.02)
        @test isapprox(feb_ratio, 0.86; atol = 0.02)

        da = dataset("airline")
        res_mult = x13(da; transform = :log, x11_mode = :multiplicative)
        res_add = x13(da; transform = :none, x11_mode = :additive)
        diff = res_mult.seasonally_adjusted .- res_add.seasonally_adjusted
        # The two modes should track closely early (low level) and diverge
        # later (high level) -- confirmed directly, not merely expected.
        @test maximum(abs.(diff[1:24])) < maximum(abs.(diff[end-24:end]))
    end

    @testset "Chapter 9 -- end-of-series vintages" begin
        v_noext = ch09_vintages(; extend = false)
        v_ext = ch09_vintages(; extend = true)

        @test length(v_noext) == 7
        @test length(v_ext) == 7
        @test length(v_noext[1].result.observed) == 108   # shortest vintage, 9 years

        # The experiment's premise: forecast.maxlead=0 actually suppresses
        # extension, and leaving it unset actually uses it. If either of
        # these fails, Figures C-1/C-2 are the same experiment twice.
        @test all(v.nfcst == 0 for v in v_noext)
        @test all(v.nfcst > 0 for v in v_ext)

        # The Gotcha fix: transform pinned to :log across every truncated
        # vintage, so revisions aren't a units-mismatch artifact.
        @test all(transformfunction(v.result) === :log for v in v_noext)
        @test all(transformfunction(v.result) === :log for v in v_ext)

        rev_noext = ch09_revisions(v_noext)
        rev_ext = ch09_revisions(v_ext)
        @test rev_noext.n == 6
        @test rev_ext.n == 6
        @test rev_noext.mean_abs_pct > 0
        @test rev_ext.mean_abs_pct > 0
        # Forecast extension should reduce mean absolute revision on this
        # series -- confirmed directly (~14%), not merely expected from the
        # literature. A regression here would mean the chapter's own central
        # claim no longer reproduces.
        @test rev_ext.mean_abs_pct < rev_noext.mean_abs_pct
    end

    @testset "Chapters 17-19 -- canonical airline spec, the QS-vs-spectrum disagreement" begin
        res = x13(dataset("airline"); automdl = true, outlier = true, aictest = [:td, :easter], transform = :auto)
        m = mstats(res)
        @test all(getfield(m, f) < 1.0 for f in (:m1, :m2, :m3, :m4, :m5, :m6, :m7, :m8, :m9, :m10, :m11))
        @test m.q < 1.0

        q = qs(res)
        @test q.original.pvalue < 0.01     # strongly seasonal before adjustment
        @test q.sa.pvalue > 0.99           # QS reports essentially no seasonality left...

        peaks = spectrum_peaks(res.udg; series = :sa)
        s1 = only(filter(x -> x.label == :s1, peaks))
        @test s1.significant               # ...yet the spectrum still flags a seasonal peak.
        # This is Chapter 18's central point: both diagnostics are correct and they disagree.

        rd = residual_diagnostics(res)
        @test rd.n_ljung_box > 0            # the model that produced the clean Q above still
                                             # fails Ljung-Box at some lag (Chapter 19)
    end

    @testset "Chapter 20 -- appliance sliding spans and revision history are real, populated" begin
        res = x13(dataset("appliance"); automdl = true, outlier = true, transform = :auto,
            spec_args = Dict("slidingspans" => "", "history.estimates" => "(sadj sadjchng)"))
        ss = slidingspans(res)
        @test ss !== nothing
        @test 0 <= ss.seasonal_pct <= 100
        rh = revision_history(res)
        @test rh !== nothing
        @test !isempty(rh.sa_estimates)
        @test all(>=(0), rh.sa_estimates)   # average absolute revisions are non-negative
    end

    @testset "Chapters 10-13 -- trading day, Diwali, COVID outliers, model selection" begin
        res_appl_td = x13(dataset("appliance"); automdl = true, outlier = true, aictest = [:td], transform = :auto)
        ftest_td = res_appl_td.udg["ftest\$Trading Day"]
        fields = split(ftest_td)
        @test parse(Float64, fields[3]) > 10.0   # strongly significant F-statistic
        @test parse(Float64, fields[4]) < 0.01   # p-value

        # Diwali: weekend-drop rule -- a holiday landing on a weekend must
        # contribute 0.0, not 1.0, to the regressor.
        function diwali_main_date(y)
            entries = get(INDIA_NSE.table_holidays, y, nothing)
            entries === nothing && return nothing
            idx = findfirst(e -> occursin("Laxmi", e[2]), entries)
            idx === nothing && return nothing
            return entries[idx][1]
        end
        diwali_years = sort(collect(keys(INDIA_NSE.table_holidays)))
        weekend_years = filter(y -> dayofweek(diwali_main_date(y)) in (6, 7), diwali_years)
        @test !isempty(weekend_years)   # confirms the test actually exercises the rule
        chr = custom_holiday_regressor(Date(minimum(diwali_years), 1, 1), Date(maximum(diwali_years), 12, 1),
            INDIA_NSE, diwali_main_date; freq = :month)
        for y in weekend_years
            d = diwali_main_date(y)
            month_idx = (Dates.year(d) - minimum(diwali_years)) * 12 + Dates.month(d)
            @test chr[month_idx] == 0.0
        end

        # COVID on iip_india: a real, large, correctly-timed disruption.
        res_iip = x13(dataset("iip_india"); transform = :log, automdl = true, outlier = true)
        oc = outlier_counts(res_iip)
        @test oc.total > 0
        outl = outliers(res_iip)
        @test any(o -> o.type == :ls && o.year == 2020, outl)   # a 2020 level shift

        # automdl: the chosen model is not necessarily the best-BIC candidate.
        res_air = x13(dataset("airline"); automdl = true, outlier = true, aictest = [:td, :easter], transform = :auto)
        fb = fivebestmdl(res_air)
        @test length(fb) == 5
        @test issorted([m.bic for m in fb])   # fivebestmdl's own list is BIC-sorted
        best_bic_model = fb[1].model
        @test replace(best_bic_model, " " => "") != replace(arima_model(res_air), " " => "")
    end

    @testset "Chapters 14-15 -- SEATS field availability, X-11 vs SEATS divergence" begin
        res_seats = x13(dataset("airline"); seats = true, transform = :log, automdl = true)
        @test length(res_seats.seasonally_adjusted) == length(res_seats.observed)
        @test mstats(res_seats) === nothing
        f = filters(res_seats)
        @test f.trend_ma === nothing
        @test isempty(f.seasonal_ma)
        @test qs(res_seats) !== nothing
        @test spectral_peaks(res_seats.udg) !== nothing
        # A real correction to this book's own original plan: seasonality_tests
        # needs an X-11-only .udg key (f2.fsb1) and returns nothing for SEATS,
        # contrary to what was originally assumed before checking directly.
        @test seasonality_tests(res_seats.udg) === nothing

        d_air = dataset("airline")
        res_x11 = x13(d_air; automdl = true, transform = :auto)
        res_seats2 = x13(d_air; automdl = true, transform = :auto, seats = true)
        diff_air = abs.(res_x11.seasonally_adjusted .- res_seats2.seasonally_adjusted) ./ res_x11.seasonally_adjusted
        @test maximum(diff_air) < 0.05   # close agreement on airline

        d_iip = dataset("iip_india")
        res_iip_x11 = x13(d_iip; automdl = true, transform = :auto)
        res_iip_seats = x13(d_iip; automdl = true, transform = :auto, seats = true)
        diff_iip = abs.(res_iip_x11.seasonally_adjusted .- res_iip_seats.seasonally_adjusted) ./ res_iip_x11.seasonally_adjusted
        @test maximum(diff_iip) > maximum(diff_air)   # a genuinely larger divergence than airline's
    end
else
    @warn "skipping real-binary book-example tests: x13_binary_available() is false in this environment"
end

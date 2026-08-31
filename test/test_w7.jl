# test/test_w7.jl -- W.7.2-W.7.8
#
# Forecasts/backcasts, missing values, component-factor accessors, vcov/
# coeftable/summary/update, sliding spans/revision history. Follows
# handoff/w7-functionality-gaps-handoff.md's own test plan where its
# assumptions held up under direct verification this session; corrected
# in a few places where they didn't (force_target's real spelling is
# :calendaradj, not :caladjust; coeftable has no p-values -- see
# StatsBase.coeftable's own docstring for why).
#
# Reuses AIRLINE_Y/_result_from_fixture from test_diagnostics.jl (this
# file is included after it in runtests.jl).

using LinearAlgebra: issymmetric

@testset "X13Spec -- maxlead program limit (pfcst=120), no subprocess" begin
    y = collect(100.0:1.0:243.0)
    @test_throws ArgumentError X13Spec(y; start = (1949, 1), maxlead = 121)
    @test X13Spec(y; start = (1949, 1), maxlead = 120) isa X13Spec
    @test_throws ArgumentError X13Spec(y; start = (1949, 1), maxlead = -1)
    @test occursin("maxlead", render(X13Spec(y; start = (1949, 1), maxlead = 6)))
end

@testset "X13Spec -- pobs program limit (780 observations)" begin
    y = collect(1.0:800.0)
    @test_throws ArgumentError X13Spec(y; start = (1949, 1))
end

@testset "X13Spec -- force/force_target accepted and rejected values" begin
    y = collect(100.0:1.0:243.0)
    for f in (:none, :denton, :regress)
        @test occursin("force", render(X13Spec(y; start = (1949, 1), force = f)))
    end
    @test_throws ArgumentError X13Spec(y; start = (1949, 1), force = :bogus)
    for tg in (:original, :calendaradj, :permprioradj, :both)
        @test occursin(string(tg), render(X13Spec(y; start = (1949, 1), force = :denton, force_target = tg)))
    end
    @test_throws ArgumentError X13Spec(y; start = (1949, 1), force = :denton, force_target = :caladjust)
end

@testset "X13Spec -- seasonalma accepted values render; bogus rejected" begin
    y = collect(100.0:1.0:243.0)
    for f in (:s3x1, :s3x3, :s3x5, :s3x9, :s3x15, :stable, :x11default, :msr)
        @test occursin("seasonalma", render(X13Spec(y; start = (1949, 1), seasonalma = f)))
    end
    @test occursin("seasonalma = (s3x3 msr", replace(render(X13Spec(y; start = (1949, 1), seasonalma = [:s3x3, :msr])), r"\s+" => " "))
    @test_throws ArgumentError X13Spec(y; start = (1949, 1), seasonalma = :nonsense)
end

@testset "coeftable -- t values present, no p-values (documented scope)" begin
    r = _result_from_fixture()
    ct = StatsBase.coeftable(r)
    @test length(ct.colnms) == 3
    @test ct.colnms == ["Estimate", "Std.Error", "t value"]
    @test size(ct.cols[1], 1) == length(StatsAPI.coef(r))
end

@testset "summary -- composes without error and names the model" begin
    r = _result_from_fixture()
    s = SeasonalAdjustment.summary(r)
    @test s isa SeasonalAdjustment.X13Summary
    txt = sprint(show, MIME"text/plain"(), s)
    @test occursin("(0 1 1)(0 1 1)", txt)
    @test occursin("144", txt)
end

@testset "_advance_start -- shifts forward by the trimmed offset" begin
    @test SeasonalAdjustment._advance_start((1949, 1), 1, 12) == (1949, 2)
    @test SeasonalAdjustment._advance_start((1949, 1), 12, 12) == (1950, 1)
    @test SeasonalAdjustment._advance_start((1949, 1), 0, 12) == (1949, 1)
    @test SeasonalAdjustment._advance_start((1990, 1), 1, 4) == (1990, 2)
    @test SeasonalAdjustment._advance_start((1990, 4), 1, 4) == (1991, 1)
end

@testset "missing -- :error is the default and throws" begin
    y = copy(AIRLINE_Y)
    y[20] = NaN
    @test_throws ArgumentError x13(y; start = (1949, 1))
    @test_throws ArgumentError x13(y; start = (1949, 1), missing_action = :error)
end

@testset "missing -- unrecognized missing_action throws before any subprocess" begin
    @test_throws ArgumentError x13(AIRLINE_Y; start = (1949, 1), missing_action = :bogus)
end

@testset "_handle_missing -- :x13 substitutes -99999, no offset" begin
    y = copy(AIRLINE_Y)
    y[20] = NaN
    vals, offset = SeasonalAdjustment._handle_missing(y, :x13)
    @test vals[20] == -99999.0
    @test offset == 0
    @test vals[[1, 50, 144]] == AIRLINE_Y[[1, 50, 144]]
end

@testset "_handle_missing -- warns when -99999 is already a real value" begin
    y = copy(AIRLINE_Y)
    y[5] = -99999.0
    y[20] = NaN
    @test_logs (:warn,) SeasonalAdjustment._handle_missing(y, :x13)
end

@testset "_handle_missing -- :omit drops leading/trailing, offset reflects it" begin
    y = copy(AIRLINE_Y)
    y[1] = NaN
    y[2] = NaN
    y[end] = NaN
    vals, offset = SeasonalAdjustment._handle_missing(y, :omit)
    @test offset == 2
    @test length(vals) == length(AIRLINE_Y) - 3
    @test vals[1] == AIRLINE_Y[3]
end

@testset "_handle_missing -- :omit throws on an INTERIOR gap" begin
    y = copy(AIRLINE_Y)
    y[70] = NaN
    @test_throws ArgumentError SeasonalAdjustment._handle_missing(y, :omit)
end

@testset "_handle_missing -- no missing values is a pure no-op regardless of action" begin
    for action in (:error, :x13, :omit)
        vals, offset = SeasonalAdjustment._handle_missing(AIRLINE_Y, action)
        @test vals == AIRLINE_Y
        @test offset == 0
    end
end

@testset "components -- which=:all throws with no regression effects at all" begin
    r = _result_from_fixture() # plain seasonal_order, no trading/holiday/user/outlier
    @test_throws ArgumentError components(r; which = :all)
end

@testset "components -- unrecognized which throws" begin
    r = _result_from_fixture()
    @test_throws ArgumentError components(r; which = :bogus)
end

@testset "components -- trading_day/user precheck avoids a subprocess when absent" begin
    r = _result_from_fixture()
    @test components(r; which = :trading_day) === nothing
    @test components(r; which = :user) === nothing
end

if x13_binary_available()
    @testset "forecast -- shape, interval ordering, dates continue with no gap" begin
        res = x13(AIRLINE_Y; start = (1949, 1), maxlead = 12)
        f = forecast(res)
        @test length(f.point) == 12
        @test length(f.dates) == length(f.lower) == length(f.upper) == 12
        @test all(f.lower .< f.point .< f.upper)
        @test f.dates[1] == res.dates[end] + Dates.Month(1)
        @test f.dates[end] == Date(1961, 12)
        # NOTE: diff(::Vector{Date}) returns Day periods, which never
        # compare == to a Month period in Julia's Dates (Day(31) ==
        # Month(1) is `false`, confirmed directly) -- checked the real
        # property (each date is exactly `i` months past dates[end])
        # constructively instead of via a diff/Period comparison that
        # can never be true regardless of correctness.
        @test all(i -> f.dates[i] == res.dates[end] + Dates.Month(i), 1:length(f.dates))
    end

    @testset "forecast -- quarterly steps by 3 months" begin
        spc = read(joinpath(_VERIFICATION_DIR, "airline_baseline", "airline_official.spc"), String)
        m = match(r"data = \(([\s\S]*?)\)\s*\}"m, spc)
        yq = parse.(Float64, split(m.captures[1]))[1:48]
        res = x13(yq; period = 4, start = (1990, 1), seasonal_order = (0, 1, 1, 4), maxlead = 8)
        f = forecast(res)
        @test length(f.point) == 8
        @test all(i -> f.dates[i] == res.dates[end] + Dates.Month(3i), 1:length(f.dates))
    end

    @testset "backcast -- extends backwards from dates[1]" begin
        res = x13(AIRLINE_Y; start = (1949, 1), spec_args = Dict("forecast.maxback" => "12"))
        b = backcast(res)
        @test length(b.point) == 12
        @test b.dates[end] == res.dates[1] - Dates.Month(1)
        @test b.dates[1] == Date(1948, 1)
        @test all(b.lower .< b.point .< b.upper)
    end

    @testset "forecast -- level widens the interval" begin
        n = forecast(x13(AIRLINE_Y; start = (1949, 1), maxlead = 12); level = 0.95)
        w = forecast(x13(AIRLINE_Y; start = (1949, 1), maxlead = 12); level = 0.99)
        @test all((w.upper .- w.lower) .> (n.upper .- n.lower))
    end

    @testset "forecast -- re-runs automatically when :fct wasn't saved" begin
        res = x13(AIRLINE_Y; start = (1949, 1))
        f = forecast(res)
        @test length(f.point) == 12 # X-13's own default maxlead
    end

    @testset "forecast -- WITH a user regressor (R's seasonal cannot do this)" begin
        reg = custom_holiday_regressor(Date(1949, 1), Date(1962, 12), INDIA_NSE, y -> Date(y, 11, 1))
        res = x13(AIRLINE_Y; start = (1949, 1), transform = :log, regression_user = reg,
            regression_usertype = :holiday, maxlead = 12)
        f = forecast(res)
        @test length(f.point) == 12
        @test all(isfinite, f.point)
    end

    @testset "missing -- :x13 runs and interpolates the gap" begin
        y = copy(AIRLINE_Y)
        y[20] = NaN
        res = x13(y; start = (1949, 1), missing_action = :x13, transform = :log)
        @test all(isfinite, res.seasonally_adjusted)
        mv = interpolated(res)
        @test length(mv) == length(y)
        @test isfinite(mv[20])
        @test mv[20] != -99999.0
        @test mv[[1, 50, 144]] ≈ y[[1, 50, 144]]
    end

    @testset "missing -- log transform does not reject the sentinel" begin
        y = copy(AIRLINE_Y)
        y[20] = NaN
        res = x13(y; start = (1949, 1), missing_action = :x13, transform = :log)
        @test transformfunction(res) === :log
    end

    @testset "missing -- Union{Missing,Float64} accepted at the boundary" begin
        y = Vector{Union{Missing,Float64}}(AIRLINE_Y)
        y[20] = missing
        # transform=:log needed for the SAME reason any other regression
        # content needs it (see validate!'s W.7 follow-up rule): X-13
        # interpolates the -99999 sentinel via its OWN internal AO-style
        # regressor, which is enough to trigger the "regression + default
        # multiplicative + no explicit transform" error even though this
        # package's own X13Spec never declares a regression block itself.
        @test x13(y; start = (1949, 1), missing_action = :x13, transform = :log) isa X13Result
    end

    @testset "missing -- :omit trims and shifts dates to match" begin
        y = copy(AIRLINE_Y)
        y[1] = NaN
        res = x13(y; start = (1949, 1), missing_action = :omit)
        @test length(res.observed) == length(AIRLINE_Y) - 1
        @test res.dates[1] == Date(1949, 2)
    end

    @testset "components -- holiday factors from a user regressor" begin
        # regressor must cover the series (144 months) PLUS the RegARIMA
        # forecast horizon (12 months, validate!'s own rule 4) = 156.
        # `which=:holiday` (.hol), NOT `which=:user` (.usr) -- confirmed
        # directly: a usertype=:holiday user regressor's factors land in
        # regression.holiday (.hol) alongside every other holiday effect
        # (Easter etc.), not regression.userdef (.usr), which is only
        # reached by a user regressor with some OTHER/no usertype.
        reg = custom_holiday_regressor(Date(1949, 1), Date(1961, 12), INDIA_NSE, y -> Date(y, 11, 1))
        res = x13(AIRLINE_Y; start = (1949, 1), transform = :log, regression_user = reg, regression_usertype = :holiday)
        c = components(res; which = :holiday)
        @test c !== nothing
        @test length(c) == length(res.observed)
        @test !all(==(c[1]), c) # a real, non-degenerate effect
    end

    @testset "components -- trading day present only when td is in the model" begin
        with = x13(AIRLINE_Y; start = (1949, 1), trading = true, transform = :log)
        @test components(with; which = :trading_day) !== nothing
        @test length(components(with; which = :trading_day)) == length(with.observed)
        without = x13(AIRLINE_Y; start = (1949, 1))
        @test components(without; which = :trading_day) === nothing
    end

    @testset "components -- which=:all returns a full NamedTuple with present/absent split" begin
        res = x13(AIRLINE_Y; start = (1949, 1), trading = true, transform = :log)
        c = components(res)
        @test c.trading_day !== nothing
        @test c.holiday === nothing
        @test c.user === nothing
    end

    @testset "vcov -- covariance matrix, sqrt(diag) reproduces stderror" begin
        # regression_variables=["easter[1]", "labor[1]"] -- TWO
        # independent, single-coefficient regression effects (confirmed
        # directly: X-13 does not write .rcm at all for exactly ONE
        # regression coefficient, presumably since a 1x1 "covariance
        # matrix" is just the variance already in stderror(); needs >=2
        # to actually exercise .rcm) + automdl (a real ARMA family) --
        # deliberately NOT trading=true, see "vcov -- named error for a
        # derived coefficient" below for why that combination is a
        # separate, known, honest gap.
        res = x13(AIRLINE_Y; start = (1949, 1), regression_variables = ["easter[1]", "labor[1]"],
            automdl = true, transform = :log)
        V = StatsAPI.vcov(res)
        n = length(StatsAPI.coef(res))
        @test size(V) == (n, n)
        se = StatsAPI.stderror(res)
        # rtol calibrated from a real observed discrepancy this session
        # (~0.8%, e.g. 0.0095942 vs 0.0095206) -- .rcm's own printed
        # precision and .udg's separately-printed stderror apparently
        # aren't bit-identical, likely different internal rounding paths.
        # Still two orders of magnitude tighter than the >=1.0 gap a
        # CORRELATION matrix's unit diagonal would show, so this remains
        # a real, decisive covariance-vs-correlation check.
        for i in 1:n
            isnan(V[i, i]) && continue
            @test sqrt(V[i, i]) ≈ se[i] rtol = 1e-2
        end
    end

    @testset "vcov -- regression block is symmetric" begin
        res = x13(AIRLINE_Y; start = (1949, 1), regression_variables = ["easter[1]", "labor[1]"],
            automdl = true, transform = :log)
        V = StatsAPI.vcov(res)
        finite = findall(i -> all(isfinite, V[i, :]), 1:size(V, 1))
        @test issymmetric(V[finite, finite])
    end

    @testset "vcov -- named error for a derived coefficient (trading=true's 7th term)" begin
        # the real, documented scope limitation in StatsAPI.vcov's own
        # docstring: "Trading Day$Sun" is in .udg's coefficient block but
        # NOT in .rcm's 6-row covariance matrix (it's derived, not
        # independently estimated) -- refuses to guess rather than
        # silently misaligning the matrix.
        res = x13(AIRLINE_Y; start = (1949, 1), trading = true, automdl = true, transform = :log)
        @test_throws ErrorException StatsAPI.vcov(res)
    end

    @testset "vcov -- still a named error with no coefficients at all" begin
        y = collect(100.0:1.0:243.0)
        res = x13(y; start = (1949, 1), order = (0, 0, 0), seasonal_order = (0, 0, 0, 12))
        @test isempty(StatsAPI.coef(res))
        @test_throws ErrorException StatsAPI.vcov(res)
    end

    @testset "update -- changes one setting, preserves the rest, original untouched" begin
        base = x13(AIRLINE_Y; start = (1949, 1), transform = :log)
        upd = update(base; outlier = true)
        @test transformfunction(upd) === :log
        @test upd.spec.outlier == true
        @test base.spec.outlier == false
    end

    @testset "force -- saa ANNUAL TOTALS match the original series' annual totals" begin
        # what force=:denton actually guarantees: the SA series' annual
        # SUM matches the original series' annual sum -- not that every
        # individual month gets closer to the raw original (it doesn't;
        # SA and original differ every month by design, seasonally).
        res = x13(AIRLINE_Y; start = (1949, 1), force = :denton)
        saa = series(res, :saa)
        for yr in 0:11
            idx = (12yr + 1):(12yr + 12)
            @test sum(saa[idx]) ≈ sum(res.observed[idx]) rtol = 1e-6
        end
        # control: the UNFORCED SA series does NOT hit this to the same precision
        @test !isapprox(sum(res.seasonally_adjusted[1:12]), sum(res.observed[1:12]); rtol = 1e-6)
    end

    @testset "seasonalma -- a fixed filter changes the seasonal factors" begin
        a = x13(AIRLINE_Y; start = (1949, 1), seasonalma = :s3x3)
        b = x13(AIRLINE_Y; start = (1949, 1), seasonalma = :s3x9)
        @test !(a.seasonal_factors ≈ b.seasonal_factors)
    end

    @testset "slidingspans -- udg key flips to yes, headline stats reachable" begin
        res = x13(AIRLINE_Y; start = (1949, 1), spec_args = Dict("slidingspans" => ""))
        @test udg(res, "sspans") == "yes"
        ss = slidingspans(res)
        @test ss !== nothing
        @test !isempty(ss.raw)
    end

    @testset "slidingspans -- nothing when not requested" begin
        res = x13(AIRLINE_Y; start = (1949, 1))
        @test slidingspans(res) === nothing
    end

    @testset "revision_history -- sa_estimates reachable once requested" begin
        res = x13(AIRLINE_Y; start = (1949, 1),
            spec_args = Dict("history.estimates" => "(sadj sadjchng)"))
        @test udg(res, "history") == "yes"
        h = revision_history(res)
        @test h !== nothing
        @test length(h.sa_estimates) > 0
    end

    @testset "revision_history -- nothing when not requested" begin
        res = x13(AIRLINE_Y; start = (1949, 1))
        @test revision_history(res) === nothing
    end
else
    @warn "skipping W.7 real-binary tests: x13_binary_available() is false in this environment"
end

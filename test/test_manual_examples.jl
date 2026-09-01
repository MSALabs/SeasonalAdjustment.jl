# test_manual_examples.jl -- asserts the Manual's own genuinely new claims
# (not already covered by test_api.jl/test_datasets.jl/etc.), same
# extracted-script convention as test_book_examples.jl.

include(joinpath(@__DIR__, "..", "docs", "examples", "manual", "03-batch-processing.jl"))

@testset "Manual -- calendar signature (advance needs a Period, not an Int)" begin
    d = advance(INDIA_NSE, Date(2025, 10, 21), Dates.Day(1))
    @test d isa Date
    @test d > Date(2025, 10, 21)
end

if x13_binary_available()
    @testset "Manual -- batch diagnostics loop (Many Series at Once)" begin
        rows = manual_batch_diagnostics(["airline", "appliance"])
        @test length(rows) == 2
        @test rows[1].series == "airline"
        @test rows[2].series == "appliance"
        @test all(r.converged for r in rows)
        @test all(r.transform === :log for r in rows)
        # real numbers confirmed directly while writing the page -- a
        # regression here means the page's own quoted output is stale
        @test isapprox(rows[1].q, 0.26; atol = 0.01)
        @test isapprox(rows[2].q, 0.28; atol = 0.01)
    end

    @testset "Manual -- run_x13_batch never produces .udg (the page's own Gotcha)" begin
        d = dataset("airline")
        spec = X13Spec(d.value; start = (1949, 1), automdl = true)
        path = write_spec(spec, joinpath(mktempdir(), "nogatcha.spc"))
        results = run_x13_batch([path])
        @test results[1].success
        @test !isfile(joinpath(results[1].dir, "$(results[1].basename).udg"))
    end

    @testset "Manual -- validate! error text for the automdl/seasonal_order conflict" begin
        d = dataset("airline")
        err = try
            X13Spec(d.value; start = (1949, 1), automdl = true, seasonal_order = (0, 1, 1, 12)) |> validate!
            nothing
        catch e
            sprint(showerror, e)
        end
        @test err !== nothing
        @test occursin("automdl", err)
        @test occursin("Cannot specify arima and automdl", err)
    end

    @testset "Manual -- custom_holiday_regressor: naming it in regression_variables breaks the spec" begin
        d = dataset("iip_india")
        # A real regressor with actual variation, not an all-zero one --
        # X-13 rejects a degenerate (constant) user regressor outright, so
        # an all-zero vector would fail for a different reason than the one
        # this test is checking.
        function diwali_main_date(y)
            entries = get(INDIA_NSE.table_holidays, y, nothing)
            entries === nothing && return nothing
            idx = findfirst(e -> occursin("Laxmi", e[2]), entries)
            idx === nothing && return nothing
            return entries[idx][1]
        end
        chr = custom_holiday_regressor(Date(2011, 4, 1), Date(2027, 3, 1), INDIA_NSE, diwali_main_date; freq = :month)
        spec_bad = X13Spec(d.value; start = (2011, 4), transform = :log, automdl = true,
            regression_user = chr, regression_variables = ["diwali"],
            regression_usertype = :holiday, regression_user_name = :diwali)
        path_bad = write_spec(spec_bad, joinpath(mktempdir(), "bad.spc"))
        result_bad = run_x13(path_bad)
        @test !result_bad.success
        @test any(occursin("not found", e) for e in result_bad.errors)

        spec_good = X13Spec(d.value; start = (2011, 4), transform = :log, automdl = true,
            regression_user = chr, regression_usertype = :holiday, regression_user_name = :diwali)
        path_good = write_spec(spec_good, joinpath(mktempdir(), "good.spc"))
        result_good = run_x13(path_good)
        @test result_good.success
    end

    try
        using TimeSeries
        @testset "Manual -- TimeArray sink (closes a previously-unverified gap)" begin
            d = dataset("airline")
            ta = TimeArray(d; timestamp = :date)
            @test length(ta) == 144
            ta2 = dataset("airline", x -> TimeArray(x; timestamp = :date))
            @test length(ta2) == 144
        end
    catch e
        e isa ArgumentError && @warn "skipping TimeArray sink test: TimeSeries.jl not available in this environment"
    end
else
    @warn "skipping real-binary Manual tests: x13_binary_available() is false in this environment"
end

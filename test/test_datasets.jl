# test/test_datasets.jl -- W.9
#
# Test plan follows handoff/w9-datasets-handoff.md section 4, adapted to
# this session's own real implementation (a `kind` field on DatasetInfo,
# added now rather than deferred per the handoff's own §9 recommendation;
# a fourth dataset, iip_india, sourced and normalized this session --
# the handoff itself only shipped airline/appliance/appliance_q).
# Every numeric literal below was read directly from the real, committed
# CSV files (or computed from them), not copied from the handoff without
# checking -- see the sha256 test, which pins the files against
# independently-computed hashes, not the handoff's own (truncated,
# 16-char) prefixes.

using SHA: sha256, bytes2hex
using Tables

# diff(::Vector{Date}) returns Day periods, which never compare == to a
# Month period in Julia's Dates (Day(31) == Month(1) is `false`, a real
# finding confirmed directly earlier this session, see test_w7.jl's own
# forecast-date tests for the first place it bit) -- check the actual
# constructive property instead of a diff/Period comparison that could
# never be true regardless of correctness.
_consecutive_months(dates::AbstractVector{Date}, step::Integer) =
    all(i -> dates[i] == dates[1] + Dates.Month(step * (i - 1)), eachindex(dates))

const _DATASET_SHA256 = Dict(
    "airline" => "9312906f56e35f92a7b6d54c0aad123092299b07d2ad7b930b031451ad6755af",
    "appliance" => "d8752510b5d01541ad312051fbc9248bcb19718003be0bf93115eca4db15a6d4",
    "appliance_q" => "515aed844aa2a198f4a20bd7fccb855d50a7d5cc4ecfa389df613bad6ff69e28",
    "iip_india" => "91762330b4486b94373a28e26217b728f728795cbdbcc7feff4f7fbce2420adc",
)

@testset "datasets -- discovery" begin
    @test "airline" in datasets()
    @test "appliance" in datasets()
    @test "appliance_q" in datasets()
    @test "iip_india" in datasets()
    @test issorted(datasets())
    @test length(datasets()) == 4
end

@testset "datasets -- every file matches its committed sha256" begin
    for name in datasets()
        path = joinpath(SeasonalAdjustment._DATA_DIR, name * ".csv")
        @test isfile(path)
        @test bytes2hex(sha256(read(path))) == _DATASET_SHA256[name]
    end
end

@testset "airline -- shape and content" begin
    d = dataset("airline")
    @test length(d.value) == 144
    @test d.date[1] == Date(1949, 1, 1)
    @test d.date[end] == Date(1960, 12, 1)
    @test sum(d.value) == 40363.0
    @test mean(d.value) ≈ 280.2986 atol = 1e-4
    @test d.value[1] == 112.0
    @test d.value[end] == 432.0
    @test _consecutive_months(d.date, 1)
end

@testset "appliance -- shape and content" begin
    d = dataset("appliance")
    @test length(d.value) == 192
    @test d.date[1] == Date(1972, 7, 1)
    @test d.date[end] == Date(1988, 6, 1)
    @test sum(d.value) == 248096.0
    @test d.value[1] == 530.0
    @test d.value[end] == 2520.0
end

@testset "seasonal shape is as documented" begin
    # guards against a silently reordered or corrupted file: airline and
    # appliance have deliberately different seasonal structures
    for (name, peak, trough) in (("airline", 7, 11), ("appliance", 12, 2))
        d = dataset(name)
        gm = mean(d.value)
        shape = [mean(d.value[Dates.month.(d.date).==m]) / gm for m in 1:12]
        @test argmax(shape) == peak
        @test argmin(shape) == trough
    end
end

@testset "appliance_q -- quarterly convention, derived from appliance" begin
    d = dataset("appliance_q")
    @test length(d.value) == 64
    @test d.date[1] == Date(1972, 7, 1) # Q3 -> month 7
    @test d.date[end] == Date(1988, 4, 1) # Q2 -> month 4
    @test all(m -> m in (1, 4, 7, 10), Dates.month.(d.date))
    @test _consecutive_months(d.date, 3)
    @test sum(d.value) == sum(dataset("appliance").value)
    @test dataset_info("appliance_q").kind === :derived
end

@testset "iip_india -- shape, content, and the real COVID level shift" begin
    d = dataset("iip_india")
    @test length(d.value) == 180
    @test d.date[1] == Date(2011, 4, 1)
    @test d.date[end] == Date(2026, 3, 1)
    @test _consecutive_months(d.date, 1)
    # the sharpest single-month move in the series -- guards against a
    # silently reordered/corrupted file the same way the airline outlier
    # regression test does below
    i = findfirst(==(Date(2020, 4, 1)), d.date)
    @test d.value[i] == 54.0
    @test d.value[i-1] == 117.2 # March 2020
    @test (d.value[i-1] - d.value[i]) == maximum(abs.(diff(d.value)))
    @test dataset_info("iip_india").kind === :published
end

@testset "known outlier -- AO1951.May survives in the committed fixture" begin
    # a regression test in the sense the handoff means it: if airline.csv
    # were ever silently reordered or corrupted, this exact outlier
    # (detected on the fixture's own regARIMA residuals, not levels --
    # not visually obvious from the surrounding 163/172/178 levels)
    # would move or disappear. Reads the already-committed fixture udg
    # directly -- no new binary run needed.
    udg_path = joinpath(@__DIR__, "..", "handoff", "udg_and_residuals", "auto_test.udg")
    d = parse_udg(udg_path)
    @test any(k -> occursin("AO1951.May", k), keys(d))
    ad = dataset("airline")
    apr, may, jun = ad.value[28], ad.value[29], ad.value[30]
    @test (apr, may, jun) == (163.0, 172.0, 178.0)
end

@testset "mutation safety" begin
    a = dataset("airline")
    a.value[1] = -999.0
    @test dataset("airline").value[1] == 112.0
end

@testset "unknown name lists what is available" begin
    err = try
        dataset("airlines")
    catch e
        sprint(showerror, e)
    end
    @test occursin("airline", err)
    @test occursin("appliance", err)
end

@testset "Symbol names accepted" begin
    @test dataset(:airline).value == dataset("airline").value
    @test dataset_info(:appliance).n == dataset_info("appliance").n
end

@testset "no vector method exists -- broadcasting is the vector story" begin
    @test !hasmethod(dataset, Tuple{Vector{String}})
end

@testset "broadcasting" begin
    ds = dataset.(["airline", "appliance"])
    @test length(ds) == 2
    @test length(ds[1].value) == 144
    @test length(dataset.(datasets())) == length(datasets())
end

@testset "Tables.jl interface" begin
    d = dataset("airline")
    @test Tables.istable(d)
    @test Tables.columnnames(d) == (:date, :value)
    @test length(dataset("airline", Tables.rowtable)) == 144
    @test size(dataset("airline", Tables.matrix)) == (144, 2)
end

@testset "sink failures pass through unchanged" begin
    @test_throws MethodError dataset("airline", Vector)
end

@testset "datasets(sink) -- metadata table" begin
    meta = datasets(Tables.rowtable)
    @test length(meta) == 4
    row = only(filter(r -> r.name == "airline", meta))
    @test row.frequency == 12
    @test row.n == 144
end

@testset "dataset_info" begin
    i = dataset_info("appliance")
    @test i.frequency == 12
    @test i.n == 192
    @test occursin("Census", i.source)
    @test !isempty(i.licence)
    for name in datasets() # provenance is never blank
        @test !isempty(dataset_info(name).licence)
        @test !isempty(dataset_info(name).citation)
        @test dataset_info(name).kind in (:published, :derived, :synthetic)
    end
    # DatasetInfo has its own show method -- confirm it actually renders
    # (not just that the struct has the field)
    txt = sprint(show, MIME"text/plain"(), dataset_info("iip_india"))
    @test occursin("MOSPI", txt)
    @test occursin("published", txt)
end

@testset "tsvalues/tsindex extensions -- what makes x13(dataset(...)) work" begin
    d = dataset("airline")
    @test TSAnalytics.tsvalues(d) === d.value
    @test TSAnalytics.tsindex(d) === d.date
end

@testset "x13 accepts a dataset directly" begin
    if x13_binary_available()
        res = x13(dataset("airline"); seasonal_order = (0, 1, 1, 12))
        @test res.dates[1] == Date(1949, 1, 1) # start inferred, not passed
        @test length(res.seasonally_adjusted) == 144
        res_q = x13(dataset("appliance_q"); period = 4, seasonal_order = (0, 1, 1, 4))
        @test length(res_q.seasonally_adjusted) == 64
    end
end

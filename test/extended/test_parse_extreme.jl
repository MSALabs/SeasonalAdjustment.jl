# test/extended/test_parse_extreme.jl -- Stage 3
#
# Tier 1 (structural, synthetic fixtures) extreme-case expansion for
# parse_table/parse_udg/parse_output -- boundary/malformed inputs the
# existing test_run_parse.jl's real-fixture tests don't specifically
# target (those confirm the REAL format is parsed correctly; these
# confirm edge cases around that format fail or succeed as designed,
# not by accident).

function _write_table(path::AbstractString, rows::Vector{Tuple{String,String}}; header = "date\tValue")
    open(path, "w") do io
        println(io, header)
        println(io, "------\t---------------")
        for (d, v) in rows
            println(io, "$d\t$v")
        end
    end
end

@testset "extreme: parse_table malformed/boundary inputs" begin
    dir = mktempdir()

    # header-only (0 data rows) -- empty result, not an error.
    p1 = joinpath(dir, "empty.d11")
    _write_table(p1, Tuple{String,String}[])
    @test parse_table(p1) == Tuple{Date,Float64}[]

    # fewer than 2 lines total -- must throw, not silently return empty.
    p2 = joinpath(dir, "oneline.d11")
    write(p2, "date\tValue\n")
    @test_throws ErrorException parse_table(p2)

    # zero lines (genuinely empty file).
    p3 = joinpath(dir, "zero.d11")
    write(p3, "")
    @test_throws ErrorException parse_table(p3)

    # malformed data line -- no tab at all.
    p4 = joinpath(dir, "notab.d11")
    open(p4, "w") do io
        println(io, "date\tValue")
        println(io, "------\t---------------")
        println(io, "194901 124.5")  # space, not tab
    end
    @test_throws ErrorException parse_table(p4)

    # wrong date length -- a genuinely 5-character quarterly-shaped
    # date ("2024Q1" is 6 chars, the SAME length as YYYYMM, so it slips
    # past the length check entirely and fails later with a different,
    # real error instead -- confirmed directly, not assumed, and worth
    # keeping as its own case below since it's a genuine, if minor,
    # finding: the length check alone doesn't catch every malformed
    # shape, only differently-LENGTHED ones).
    p5 = joinpath(dir, "shortdate.d11")
    _write_table(p5, [("2024Q", "100.0")])
    err5 = nothing
    try
        parse_table(p5)
    catch e
        err5 = e
    end
    @test err5 isa ErrorException
    @test occursin("only the 6-char YYYYMM/YYYYQQ format is supported", err5.msg)

    # a same-length (6-char) but non-numeric date string -- confirmed
    # directly this is NOT caught by the length check (both are 6
    # chars) and instead fails later, parsing the month digits, with a
    # different, real Julia error (ArgumentError from `parse(Int, ...)`)
    # -- not as clear a message as the length-mismatch case, but still
    # a hard failure, not a silent misparse.
    p5b = joinpath(dir, "quarterly.d11")
    _write_table(p5b, [("2024Q1", "100.0")])
    @test_throws ArgumentError parse_table(p5b)

    p6 = joinpath(dir, "toolong.d11")
    _write_table(p6, [("20240101", "100.0")])
    @test_throws ErrorException parse_table(p6)

    # negative, zero, very large, and scientific-notation values -- all
    # legitimate Float64 values a real X-13 output could contain.
    p7 = joinpath(dir, "extremevals.d11")
    _write_table(p7, [
        ("194901", "-123.456"),
        ("194902", "0.0"),
        ("194903", "999999999.999"),
        ("194904", "1.23456789E+02"),
        ("194905", "-0.100000000000000E-05"),
    ])
    r7 = parse_table(p7)
    @test length(r7) == 5
    @test r7[1][2] == -123.456
    @test r7[2][2] == 0.0
    @test r7[3][2] == 999999999.999
    @test r7[4][2] ≈ 123.456789
    @test r7[5][2] ≈ -1e-6

    # blank lines interspersed among real data rows -- confirmed the
    # parser skips them (per its own `isempty(strip(line)) && continue`)
    # rather than erroring or miscounting.
    p8 = joinpath(dir, "blanks.d11")
    open(p8, "w") do io
        println(io, "date\tValue")
        println(io, "------\t---------------")
        println(io, "194901\t100.0")
        println(io, "")
        println(io, "194902\t200.0")
        println(io, "   ")  # whitespace-only line
        println(io, "194903\t300.0")
    end
    r8 = parse_table(p8)
    @test length(r8) == 3
    @test last.(r8) == [100.0, 200.0, 300.0]

    # a large, wide date range -- spanning multiple centuries, still
    # parses correctly (no assumption baked in about "reasonable" years).
    p9 = joinpath(dir, "widerange.d11")
    rows9 = [("$(y)01", string(Float64(y))) for y in 1000:100:9000]
    _write_table(p9, rows9)
    r9 = parse_table(p9)
    @test length(r9) == length(rows9)
    @test Dates.year(r9[1][1]) == 1000
    @test Dates.year(r9[end][1]) == 9000

    # a genuinely large file (1000+ rows) -- confirms no accidental
    # quadratic behavior or row-count ceiling.
    p10 = joinpath(dir, "large.d11")
    rows10 = [("$(1900 + div(i,12))" * string(mod(i, 12) + 1, pad = 2), string(100.0 + i)) for i in 0:1199]
    _write_table(p10, rows10)
    r10 = parse_table(p10)
    @test length(r10) == 1200
end

@testset "extreme: parse_udg malformed/boundary inputs" begin
    dir = mktempdir()

    # empty file -- empty dict, not an error.
    p1 = joinpath(dir, "empty.udg")
    write(p1, "")
    @test parse_udg(p1) == Dict{String,String}()

    # a line with no colon at all -- skipped, not an error (matches the
    # function's own `idx === nothing && continue`).
    p2 = joinpath(dir, "nocolon.udg")
    write(p2, "this line has no colon\nkey: value\n")
    r2 = parse_udg(p2)
    @test length(r2) == 1
    @test r2["key"] == "value"

    # a value that itself contains colons (e.g. a timestamp) -- only
    # the FIRST colon splits key from value, confirmed the rest stay
    # part of the value, not truncated.
    p3 = joinpath(dir, "timestamp.udg")
    write(p3, "time: 19.43.44\nspan: 1st month,1949 to 12th month,1960\nratio: 3:1:2\n")
    r3 = parse_udg(p3)
    @test r3["time"] == "19.43.44"
    @test r3["ratio"] == "3:1:2"  # everything after the FIRST colon (the one right after "ratio")

    # duplicate keys -- confirmed the LAST occurrence wins (plain Dict
    # overwrite semantics), not an error and not silently the first.
    p4 = joinpath(dir, "dup.udg")
    write(p4, "key: first\nkey: second\n")
    r4 = parse_udg(p4)
    @test r4["key"] == "second"

    # leading/trailing whitespace around both key and value -- stripped.
    p5 = joinpath(dir, "whitespace.udg")
    write(p5, "  spacedkey  :   spaced value   \n")
    r5 = parse_udg(p5)
    @test r5["spacedkey"] == "spaced value"

    # an empty value after the colon.
    p6 = joinpath(dir, "emptyval.udg")
    write(p6, "emptykey:\n")
    r6 = parse_udg(p6)
    @test r6["emptykey"] == ""

    # a genuinely large file (2000+ keys).
    p7 = joinpath(dir, "large.udg")
    open(p7, "w") do io
        for i in 1:2000
            println(io, "key$i: value$i")
        end
    end
    r7 = parse_udg(p7)
    @test length(r7) == 2000
    @test r7["key1000"] == "value1000"
end

@testset "extreme: parse_output missing/partial tables" begin
    dir = mktempdir()
    _write_table(joinpath(dir, "test.d11"), [("194901", "100.0")])
    result = X13RunResult(true, "", String[], String[], dir, "test")

    # requesting an empty table list -- returns an empty dict, not an
    # error.
    @test parse_output(result, Symbol[]) == Dict{Symbol,Vector{Tuple{Date,Float64}}}()

    # a table that genuinely exists.
    r1 = parse_output(result, [:d11])
    @test haskey(r1, :d11)
    @test length(r1[:d11]) == 1

    # a table that doesn't exist -- throws with a clear message naming
    # the missing table.
    err = nothing
    try
        parse_output(result, [:d12])
    catch e
        err = e
    end
    @test err isa ErrorException
    @test occursin("d12", err.msg)

    # a MIX of present and missing tables -- confirmed it throws on
    # hitting the first missing one, not silently returning a partial
    # dict.
    @test_throws ErrorException parse_output(result, [:d11, :d99])
end

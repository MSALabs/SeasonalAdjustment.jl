# test/test_known_tables.jl -- W.7.1
#
# Tests the generated 281-table catalogue (src/known_tables.jl, built by
# tools/generate_known_tables.jl from handoff/x13-saveable-tables.md) and
# render()'s per-block save routing that catalogue drives -- the real bug
# found while reviewing the W.7/W.8 handoffs: every `save` table used to
# be dumped unconditionally into `x11{}`/`seats{}`, regardless of which
# spec block actually owned it.

@testset "_KNOWN_TABLES -- catalogue completeness" begin
    @test length(SeasonalAdjustment._KNOWN_TABLES) > 250
    for t in (:fct, :bct, :ftr, :btr, :fvr, :hol, :td, :usr, :otl, :ao, :ls,
              :tc, :so, :a10, :a13, :rcm, :acm, :mv, :saa, :ffc, :rnd,
              :sfs, :chs, :ycs, :tds, :sae, :sar, :che, :chr, :tre, :lkh,
              :acf, :pcf, :ac2, :sp0, :sp1, :sp2, :spr, :a1, :a18, :a19, :rmx)
        @test t in SeasonalAdjustment._KNOWN_TABLES
    end
end

@testset "_KNOWN_TABLES -- X-11 table numbers are NOT the save keywords" begin
    for bogus in (:a6, :a7, :a8, :a9)
        @test !(bogus in SeasonalAdjustment._KNOWN_TABLES)
    end
    @test :hol in SeasonalAdjustment._KNOWN_TABLES   # A7 is spelled `hol`
    @test :td  in SeasonalAdjustment._KNOWN_TABLES   # A6 is spelled `td`
    @test :a10 in SeasonalAdjustment._KNOWN_TABLES   # but A10 IS spelled a10
end

@testset "_TABLE_BLOCK -- routes tables to the block that owns them" begin
    @test SeasonalAdjustment._TABLE_BLOCK[:hol] == "regression"
    @test SeasonalAdjustment._TABLE_BLOCK[:td]  == "regression"
    @test SeasonalAdjustment._TABLE_BLOCK[:rsd] == "estimate"
    @test SeasonalAdjustment._TABLE_BLOCK[:rcm] == "estimate"
    @test SeasonalAdjustment._TABLE_BLOCK[:fct] == "forecast"
    @test SeasonalAdjustment._TABLE_BLOCK[:acf] == "check"
    @test SeasonalAdjustment._TABLE_BLOCK[:saa] == "force"
    @test SeasonalAdjustment._TABLE_BLOCK[:sfs] == "slidingspans"
    @test SeasonalAdjustment._TABLE_BLOCK[:sae] == "history"
    @test SeasonalAdjustment._TABLE_BLOCK[:d10] == "x11"
    @test SeasonalAdjustment._TABLE_BLOCK[:s10] == "seats"
    # cross-block ext collisions, resolved by document order (series/x11
    # before composite/seats -- see tools/generate_known_tables.jl)
    @test SeasonalAdjustment._TABLE_BLOCK[:b1]  == "series"
    @test SeasonalAdjustment._TABLE_BLOCK[:tac] == "x11"
end

@testset "save -- print-only keywords rejected with a specific message" begin
    y = collect(100.0:1.0:243.0)
    for kw in (:all, :none, :alltables, :default, :brief)
        err = try
            X13Spec(y; start = (1949, 1), save = [kw])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("print-only", err.msg)
    end
end

@testset "save -- an unrecognized table symbol is rejected before any subprocess" begin
    y = collect(100.0:1.0:243.0)
    @test_throws ArgumentError X13Spec(y; start = (1949, 1), save = [:bogus_table_xyz])
    # the specific naming-trap case: A7 is NOT spelled :a7
    err = try
        X13Spec(y; start = (1949, 1), save = [:a7])
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("a7", err.msg)
end

@testset "render -- save routes per-table to the correct block, not x11{} for everything" begin
    y = collect(100.0:1.0:243.0)
    s = X13Spec(y; start = (1949, 1), trading = true, residuals = true, transform = :none,
                save = [:d10, :hol, :td, :rsd, :rcm])
    txt = render(s)

    # regression{} gets its own save=, not x11{}
    reg_block = match(r"regression \{([\s\S]*?)\n\}"m, txt).captures[1]
    @test occursin("save = (hol td)", reg_block) || occursin("save = (hol td)", replace(reg_block, r"\s+" => " "))
    @test occursin(r"save\s*=\s*\(.*\btd\b.*\)", reg_block)
    @test occursin(r"save\s*=\s*\(.*\bhol\b.*\)", reg_block)

    # estimate{} carries rsd AND rcm merged together, not two blocks
    est_block = match(r"estimate \{([\s\S]*?)\}"m, txt).captures[1]
    @test occursin("rcm", est_block)
    @test occursin("rsd", est_block)

    # x11{} carries ONLY the x11-block table requested (d10), not the
    # whole flat save list the old, buggy code would have dumped there
    x11_block = match(r"x11 \{([\s\S]*?)\}"m, txt).captures[1]
    @test occursin("d10", x11_block)
    @test !occursin("hol", x11_block)
    @test !occursin("rsd", x11_block)
end

@testset "render -- save naming ONLY a non-x11 table still runs the decomposition" begin
    # a real behavioural guarantee: requesting a regression-only table
    # must not silently turn off x11's own d10-d13 default quartet
    y = collect(100.0:1.0:243.0)
    s = X13Spec(y; start = (1949, 1), trading = true, transform = :none, save = [:hol])
    txt = render(s)
    x11_block = match(r"x11 \{([\s\S]*?)\}"m, txt).captures[1]
    @test occursin("d10", x11_block)
    @test occursin("d11", x11_block)
    @test occursin("d12", x11_block)
    @test occursin("d13", x11_block)
end

@testset "render -- generic (non-typed) block save merges into spec_args" begin
    y = collect(100.0:1.0:243.0)
    s = X13Spec(y; start = (1949, 1), save = [:fct, :bct],
                spec_args = Dict("forecast.maxlead" => "12"))
    txt = render(s)
    fc_block = match(r"forecast \{([\s\S]*?)\}"m, txt).captures[1]
    @test occursin("maxlead", fc_block)
    @test occursin("save", fc_block)
    @test occursin("fct", fc_block)
    @test occursin("bct", fc_block)
    # only ONE forecast{} block, not two
    @test count("forecast {", txt) == 1
end

@testset "render -- outlier{} save merges with the outlier=true bool" begin
    y = collect(100.0:1.0:243.0)
    s = X13Spec(y; start = (1949, 1), outlier = true, save = [:d10, :fts])
    txt = render(s)
    otl_block = match(r"outlier \{([\s\S]*?)\}"m, txt).captures[1]
    @test occursin("save", otl_block)
    @test occursin("fts", otl_block)
end

@testset "render -- series{} save appends inside the always-rendered series block" begin
    y = collect(100.0:1.0:243.0)
    s = X13Spec(y; start = (1949, 1), save = [:d10, :mv])
    txt = render(s)
    series_block = match(r"series \{([\s\S]*?)\n\}"m, txt).captures[1]
    @test occursin("save", series_block)
    @test occursin("mv", series_block)
end

@testset "render -- x11 default quartet unchanged when save is nothing" begin
    y = collect(100.0:1.0:243.0)
    s = X13Spec(y; start = (1949, 1))
    txt = render(s)
    @test occursin("x11 { save = (d10 d11 d12 d13) }", txt)
end

@testset "series() -- spectrum tables reachable through the same whitelist" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949, 1))
        v = series(res, :sp1)
        @test v isa Vector{Float64}
        @test !isempty(v)
    end
end

@testset "series() -- unconfirmed spectrum-format table refused, not mis-parsed" begin
    if x13_binary_available()
        res = x13(AIRLINE_Y; start = (1949, 1))
        # :str (Tukey spectrum of regARIMA residuals) is a real, single-
        # series-safe spectrum-block table (confirmed producible: it
        # already appears as a byproduct of sp0/sp1/sp2/spr requests, see
        # W.6) but its column format was never independently checked --
        # series() must refuse it explicitly rather than guess.
        @test_throws ErrorException series(res, :str)
    end
end

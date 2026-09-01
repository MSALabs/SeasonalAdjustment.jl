# test_book_examples.jl -- asserts the premises of the book's own worked
# examples, not merely eyeballing them once at figure-generation time. Gated
# on x13_binary_available() -- these are real-binary runs, same convention as
# test_w7.jl.

include(joinpath(@__DIR__, "..", "book", "examples", "ch09.jl"))

if x13_binary_available()
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
else
    @warn "skipping book-example tests: x13_binary_available() is false in this environment"
end

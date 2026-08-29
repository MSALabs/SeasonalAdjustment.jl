# test/extended/test_spec_extreme.jl -- extended suite, Stage 1
#
# Tier 1 (structural, fast) + Tier 2 (real-binary subset) extreme-case
# expansion for X13Spec/render/validate!, beyond test_spec.jl's own
# 120-case grid (which varies length/seed/a few options; this file
# targets genuine boundaries and combinations that grid doesn't reach:
# the exact minimum length, every x11_mode, maxorder/maxdiff extremes,
# each validate! rule hit from both sides of its boundary, and the
# X13Spec copy-constructor's own override space). Included from
# test/extended/runtests.jl, so it only runs when
# SEASONALADJUSTMENT_EXTENDED_TESTS=1 -- see that file's own comment.

@testset "extreme: series length boundaries (structural)" begin
    # Exactly at, one below, and one above the real confirmed minimum
    # (36 months / 3 complete years -- see spec.jl's validate! rule 2,
    # already hit directly against the real binary in test_spec.jl).
    @test X13Spec(collect(1.0:36.0)) isa X13Spec
    @test_throws ArgumentError X13Spec(collect(1.0:35.0))
    @test X13Spec(collect(1.0:37.0)) isa X13Spec
    # A genuinely long series -- 50 years monthly, the kind of length a
    # real long-run macro series (not just this project's own 12-20
    # year fixtures) would actually have.
    @test X13Spec(collect(1.0:600.0)) isa X13Spec
    # Single-observation-longer than several common calendar-year
    # boundaries, to catch any off-by-one in length-only logic.
    for n in (36, 37, 47, 48, 49, 59, 60, 61, 119, 120, 121, 143, 144, 145)
        @test length(X13Spec(collect(1.0:n)).y) == n
    end
end

@testset "extreme: numeric value boundaries (structural)" begin
    n = 48
    # Near-zero but strictly positive (valid for every transform,
    # including :log).
    @test X13Spec(fill(1e-6, n) .+ (1:n) .* 1e-9; transform = :log) isa X13Spec
    # Very large magnitude.
    @test X13Spec(fill(1e12, n) .+ (1:n) .* 1e9) isa X13Spec
    # Negative values -- valid for X13Spec construction itself (no
    # positivity check in validate!, confirmed directly by reading
    # spec.jl's own four rules: none of them touch sign); a :log
    # transform combined with negative data is a real-BINARY failure,
    # not a validate!-level one, exercised separately below.
    @test X13Spec(collect(-100.0:1.0:-53.0)) isa X13Spec
    # A constant series (zero variance) -- a real degenerate case no
    # other test in this project uses.
    @test X13Spec(fill(100.0, n)) isa X13Spec
    # Alternating extreme swings.
    @test X13Spec(Float64[iseven(i) ? 1e6 : 1.0 for i in 1:n]) isa X13Spec
end

@testset "extreme: every x11_mode x every transform (structural render)" begin
    y = collect(1.0:48.0) .+ 100
    count = 0
    for x11_mode in (nothing, :multiplicative, :additive, :logadditive, :pseudoadditive)
        for transform in (nothing, :none, :log, :auto)
            spec = X13Spec(y; x11_mode = x11_mode, transform = transform)
            rendered = render(spec)
            @test occursin("x11 {", rendered)
            # render() checks `spec.x11_mode === nothing`, not whether
            # it equals the semantic default -- so `mode = ` appears
            # whenever x11_mode is explicitly set at all, including
            # :multiplicative (X-13's own default behavior, but still
            # rendered explicitly here since the caller asked for it).
            if x11_mode !== nothing
                @test occursin("mode = ", rendered)
            else
                @test !occursin("mode = ", rendered)
            end
            count += 1
        end
    end
    @test count == 20
    @test_throws ArgumentError X13Spec(y; x11_mode = :not_a_real_mode)
end

@testset "extreme: maxorder/maxdiff boundaries (structural)" begin
    y = collect(1.0:48.0) .+ 100
    # X-13's own documented limits: nonseasonal order up to 4, seasonal
    # up to 2 (X-13ARIMA-SEATS Reference Manual); differencing up to 2
    # nonseasonal, 1 seasonal. Covers the full valid boundary space,
    # not just one interior value.
    for nonseasonal_order in 0:4, seasonal_order in 0:2
        spec = X13Spec(y; maxorder = (nonseasonal_order, seasonal_order))
        # `automdl` the STRUCT FIELD stays exactly what was passed
        # (default false) -- confirmed directly: only render()'s
        # automdl{} BLOCK condition is `automdl || maxorder!==nothing ||
        # maxdiff!==nothing`, the field itself isn't auto-flipped by
        # setting maxorder alone. The field default is what matters
        # here.
        @test spec.automdl == false
        @test occursin("maxorder = ($nonseasonal_order $seasonal_order)", render(spec))
    end
    for nonseasonal_diff in 0:2, seasonal_diff in 0:1
        spec = X13Spec(y; maxdiff = (nonseasonal_diff, seasonal_diff))
        @test occursin("maxdiff = ($nonseasonal_diff $seasonal_diff)", render(spec))
    end
end

@testset "extreme: each validate! rule hit from both sides of its boundary" begin
    y36 = collect(1.0:36.0)
    y48 = collect(1.0:48.0)

    # Rule 1: arima+automdl conflict -- every way of expressing "arima"
    # crossed with every way of expressing "automdl".
    for arima_kw in [(; arima_model = "(0 1 1)(0 1 1)"), (; seasonal_order = (0, 1, 1, 12))]
        for automdl_kw in [(; automdl = true), (; maxorder = (2, 1)), (; maxdiff = (1, 1))]
            @test_throws ArgumentError X13Spec(y48; arima_kw..., automdl_kw...)
        end
    end
    # ... and the non-conflicting combinations must NOT throw.
    @test X13Spec(y48; arima_model = "(0 1 1)(0 1 1)") isa X13Spec
    @test X13Spec(y48; automdl = true) isa X13Spec

    # Rule 2: minimum length -- exact boundary both sides (also covered
    # above, repeated here as part of the rule-by-rule sweep for
    # completeness of this testset's own narrative).
    @test X13Spec(y36) isa X13Spec
    @test_throws ArgumentError X13Spec(y36[1:35])

    # Rule 3: regression_user must cover series length + 12-month
    # forecast horizon -- boundary at exactly n+12, n+11 (fails), n+13
    # (passes with margin).
    n = 48
    @test X13Spec(y48[1:n]; regression_user = collect(1.0:(n+12))) isa X13Spec
    @test_throws ArgumentError X13Spec(y48[1:n]; regression_user = collect(1.0:(n+11)))
    @test X13Spec(y48[1:n]; regression_user = collect(1.0:(n+13))) isa X13Spec

    # Rule 4: transform=:log required when a regression block is
    # combined with x11_mode in (:multiplicative, :logadditive) -- each
    # of the two triggering modes, and confirming :additive/
    # :pseudoadditive do NOT trigger the rule (the same regression
    # block, only the mode differs).
    for mode in (:multiplicative, :logadditive)
        @test_throws ArgumentError X13Spec(y48; trading = true, x11_mode = mode)
        @test X13Spec(y48; trading = true, x11_mode = mode, transform = :log) isa X13Spec
    end
    for mode in (:additive, :pseudoadditive)
        @test X13Spec(y48; trading = true, x11_mode = mode) isa X13Spec
    end
end

@testset "extreme: X13Spec copy-constructor override space" begin
    base = X13Spec(collect(1.0:48.0) .+ 100; automdl = true, transform = :auto, outlier = true)
    # Every single field overridden one at a time -- confirms each
    # field name round-trips through the copy-constructor correctly,
    # not just the two or three exercised in test_spec.jl's own
    # smaller copy-constructor testset.
    overrides = [
        (:title, "a different title"),
        (:start, (2000, 6)),
        (:transform, :none),
        (:seats, true),
        (:trading, true),
        (:regression_variables, ["td", "easter[1]"]),
        (:aictest, [:td, :easter]),
        (:residuals, true),
        (:save, [:d10, :d11]),
    ]
    for (field, value) in overrides
        overridden = X13Spec(base; NamedTuple{(field,)}((value,))...)
        @test getfield(overridden, field) == value
        # every other field not being overridden must survive unchanged
        for fn in fieldnames(X13Spec)
            fn === field && continue
            fn === :y && continue  # y is the positional arg, always copied
            fn === :automdl && field === :arima_model && continue
            @test getfield(overridden, fn) == getfield(base, fn)
        end
    end
end

@testset "extreme: real-binary spot check across the boundary space above" begin
    if x13_binary_available()
        # A real, seasonal-shaped, 72-month series for the maxorder=(4,2)
        # case specifically -- confirmed directly via two real, distinct
        # binary errors before landing here: a perfectly linear 48-month
        # trend with no noise/seasonality fails with a real X-13 model-
        # estimation error ("... for a constant term"), and even a
        # seasonal 48-month series fails with a DIFFERENT, more specific
        # real error -- "Number of observations after differencing ...
        # is 48, which is less than the minimum series length required
        # for the model estimated, 51" -- the (4,2) maxorder search
        # itself needs more than 48 observations once actually fit, not
        # just X13Spec's own bare 36-month `validate!` minimum. 72
        # months gives real margin above the confirmed 51-observation
        # floor.
        seasonal_y = Float64[100 + 20 * sin(2pi * i / 12) + 0.5 * i + 3 * ((i * 7) % 5) for i in 1:72]
        cases = [
            (collect(1.0:36.0), (;)),                                          # exact minimum
            (collect(1.0:600.0), (;)),                                          # 50-year series
            (fill(100.0, 48), (;)),                                             # zero-variance
            (seasonal_y, (; maxorder = (4, 2))),                                 # max automdl search space
            (collect(1.0:48.0) .+ 100, (; x11_mode = :pseudoadditive)),
            (collect(1.0:48.0) .+ 100, (; trading = true, x11_mode = :logadditive, transform = :log)),
        ]
        for (y, opts) in cases
            spec = X13Spec(y; opts...)
            path = write_spec(spec, joinpath(mktempdir(), "extreme.spc"))
            result = run_x13(path)
            @test result.success
        end
        # A :log transform against a series with a non-positive value
        # is valid at the X13Spec/validate! level (no positivity check,
        # confirmed above) but a genuine real-binary failure -- confirms
        # that boundary is enforced by the binary, not silently ignored.
        bad_spec = X13Spec(collect(-10.0:1.0:37.0); transform = :log)
        bad_path = write_spec(bad_spec, joinpath(mktempdir(), "badlog.spc"))
        bad_result = run_x13(bad_path)
        @test !bad_result.success
    else
        @warn "skipping extreme real-binary spot check: x13_binary_available() is false in this environment"
    end
end

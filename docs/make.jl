using Documenter
using SeasonalAdjustment

DocMeta.setdocmeta!(SeasonalAdjustment, :DocTestSetup, :(using SeasonalAdjustment); recursive = true)

include("pages.jl")

makedocs(;
    modules = [SeasonalAdjustment],
    authors = "MSALabs",
    sitename = "SeasonalAdjustment.jl",
    format = Documenter.HTML(;
        canonical = "https://MSALabs.github.io/SeasonalAdjustment.jl",
        edit_link = "main",
        assets = String[],
        # Sidebar defaults to collapsed except for whichever section is
        # currently active (Documenter auto-expands the active page's own
        # branch regardless of this setting) -- landing on Home therefore
        # shows Home expanded and every other section collapsed to just
        # its label, exactly the requested landing state.
        collapselevel = 1,
        # api.md transcludes every exported function's full docstring
        # (~110 functions, each now carrying worked examples and, where
        # applicable, math) onto one page -- genuinely over Documenter's
        # own default 200 KiB hard limit (confirmed directly: a real CI
        # run failed with HTMLSizeThresholdError at 213.48 KiB, caught
        # only by a genuinely fresh Pkg resolve + build, since a stale
        # local Documenter install had silently been treating it as a
        # sub-200KiB warning this whole time). Raised with real headroom
        # rather than tuned to just clear the current size -- api.md
        # will keep growing. Splitting api.md into smaller per-topic
        # pages (matching Getting Started/Manual's own structure) is the
        # real fix and is worth doing next; this keeps the site building
        # in the meantime.
        size_threshold = 500 * 1024,
        size_threshold_warn = 400 * 1024,
    ),
    pages = PAGES,
    # doctest=:fix locally regenerates expected doctest output when you
    # deliberately change behaviour; leave as default (true) in CI so a
    # docstring example silently drifting out of date fails the build --
    # same policy as TSAnalytics.jl.
    doctest = true,
    checkdocs = :exports,  # build fails if an exported name has no docstring
)

deploydocs(;
    repo = "github.com/MSALabs/SeasonalAdjustment.jl",
    devbranch = "main",
)

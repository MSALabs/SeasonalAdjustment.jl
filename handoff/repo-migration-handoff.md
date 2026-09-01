# Handoff: Repository Migration and Registration

`MSALabs` → `xKDR`. Short document, but it contains one item that must be
settled **before** registration and is expensive to fix afterwards.

---

## 1. The UUIDs are placeholders

```toml
# SeasonalAdjustment/Project.toml
uuid = "a1b2c3d4-0001-4e5f-8a9b-000000000001"

# TSAnalytics (from the CI error in development-sequence.md)
uuid = "b1a2c3d4-..."
```

These are hand-typed, not generated. `a1b2c3d4` / `b1a2c3d4` and a run of zeros
ending in `1` is a pattern, not a random 128-bit identifier.

**Why this matters more than the org move.** A package's UUID is its permanent
identity in the General registry. It cannot be changed after registration
without registering under a different name — every downstream `Project.toml`
pins the UUID, and altering it is a hard break for every consumer. The registry's
AutoMerge does not check that a UUID looks random, so nothing will stop a
placeholder from being registered permanently.

**Fix before registering, in both packages:**

```julia
julia> using UUIDs; uuid4()
```

Regenerate now, while the only consumers are your own two repositories and
`Pkg.develop` resolves by path and URL rather than by registry. Doing it after
the org move is the natural moment; doing it after registration is not possible.

Check whether any handoff, fixture or test file has the placeholder UUID written
into it before changing it.

---

## 2. The CI dependency URL is hardcoded three times

```
.github/workflows/CI.yml:32    Pkg.develop(url="https://github.com/MSALabs/TSAnalytics.jl")
.github/workflows/CI.yml:55    (same)
.github/workflows/Docs.yml:40  Pkg.develop([PackageSpec(path=pwd()),
                                 PackageSpec(url="https://github.com/MSALabs/TSAnalytics.jl")])
```

`development-sequence.md` records that these lines were hard-won: every CI run
since the project's first scaffold failed at dependency resolution, and the
`Docs.yml` variant needed a second, different fix in which both `develop` calls
had to be combined into a single atomic call.

**The org move breaks all three, and the failure mode is the same
dependency-resolution error that was already diagnosed once.** Anyone hitting it
cold will spend the same time again.

Update all three in the same commit as the transfer, and keep `Docs.yml`'s
single-call structure intact — splitting it back into two sequential
`Pkg.develop` calls reintroduces the second bug.

GitHub redirects transferred repositories, so these would keep working for a
while. They should still be updated, because the redirect stops working the
moment anyone creates a repository at the old path.

---

## 3. Everything else pinned to the org

| File | Line | What |
|---|---|---|
| `Project.toml` | 3 | `authors = ["MSALabs"]` |
| `LICENSE` | 3 | `Copyright (c) 2026 MSALabs` |
| `docs/make.jl` | 8 | `authors` |
| `docs/make.jl` | 11 | `canonical = "https://MSALabs.github.io/..."` |
| `docs/make.jl` | 29 | `deploydocs repo` |
| `README.md` | 3 | docs badge URL |
| `README.md` | 4 | CI badge URL |
| `README.md` | 15, 40 | TSAnalytics link, install instruction |
| `docs/src/index.md` | 16, 21 | TSAnalytics link, dev-sequence link |
| `docs/src/getting_started.md` | 10 | install instruction |
| `CLAUDE.md` | 12 | TSAnalytics URL |

Thirteen locations across both docs and config. A single
`grep -rn "MSALabs\|msalabs"` catches them; run it again after the transfer to
confirm nothing was missed.

`Artifacts.toml` points at `x13org/x13prebuilt` and is unaffected.

---

## 4. Registration order

**Register after the transfer, not before.**

The General registry records the repository URL. Registering under `MSALabs` and
then transferring means the registry entry points at a redirect, which works
until it does not. A follow-up PR to General can correct it, but it is avoidable
work.

Sequence:

1. Regenerate both UUIDs (§1)
2. Transfer both repositories to `xKDR`
3. Update the thirteen references (§3) and the three CI lines (§2)
4. Confirm CI and Docs both pass on the new org
5. Register `TSAnalytics` first — `SeasonalAdjustment` depends on it, and the
   registry will not accept a package whose dependency is unregistered
6. Register `SeasonalAdjustment`
7. Remove the `Pkg.develop(url=...)` workaround from both CI workflows once
   TSAnalytics resolves from the registry

Step 7 is the payoff: the hardcoded-URL problem in §2 disappears entirely once
TSAnalytics is registered, because `Pkg.instantiate()` resolves it normally.

---

## 5. Documentation URL

`msalabs.github.io/SeasonalAdjustment.jl` → `xkdr.github.io/SeasonalAdjustment.jl`,
unless XKDR uses a custom domain.

`deploydocs` derives the deploy target from its `repo` argument, so §3's change
covers it. What it does not cover:

- The `canonical` URL in `makedocs`
- Any absolute documentation links in the book's PDF build, which rewrites
  `@ref` into URLs against the published docs (see `book-build-handoff.md` §4)

The second is worth noting because it fails silently — the PDF builds fine and
its links point somewhere that no longer exists.

---

## 6. Until the move happens

**All repository URLs stay `MSALabs`.** Changing them before the transfer would
point testers at a repository that does not exist yet, and changing them
mid-alpha would invalidate install instructions already circulated.

The single exception is the Home page's BibTeX `author` field, which is
`{{XKDR Forum}}` and is unaffected by where the repository sits. The Home page
carries a short note that the move is coming.

Everything in §2 and §3 is therefore staged work, executed in one commit when
the transfer happens, not applied piecemeal beforehand.

## 7. Wording in the docs

XKDR is the creator, host and sponsor, not an external funder. The Home page
section is therefore titled **About XKDR Forum** and reads *created and
maintained at*, rather than borrowing JuMP's fiscal-sponsor framing.

The practical consequence: `MSALabs` was scratch infrastructure, so **XKDR
should be the attribution everywhere from the start** — not a name substituted
in after a handover. That covers `LICENSE`, `Project.toml` `authors`,
`docs/make.jl` `authors`, and the BibTeX entry on the Home page.

---

## 8. Open questions

1. **Exact legal name for the copyright line.** XKDR is the creator, so the
   attribution is XKDR rather than MSALabs — but the registered entity name may
   differ from "XKDR Forum" as used in prose. Confirm before it goes in
   `LICENSE`, since that is the one line that is awkward to change later.
2. **Custom documentation domain?** Affects `canonical` and the PDF link
   rewriting.
3. **Is TSAnalytics moving at the same time?** If the two move separately there
   is a window where the CI URLs are correct for one and wrong for the other.
   Moving both in one session is simpler.
4. **Package names on registration.** `SeasonalAdjustment` and `TSAnalytics` are
   both generic enough that General's AutoMerge may flag them for name review.
   Worth checking the registry for near-collisions before submitting.

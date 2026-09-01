# Handoff: Alpha Release for Internal Testing

`SeasonalAdjustment.jl v0.1.0-alpha`, unregistered, installed from the current
`MSALabs` repository. Companion to `repo-migration-handoff.md`.

**Org note.** The repository moves to `xKDR` later. For the alpha, every URL
stays `MSALabs` — a move mid-alpha would invalidate the install instructions
already in testers' hands. `xKDR` is hardcoded only in the Home page's citation
block, which the move does not affect.

---

## 1. The trap testers will hit on day one

Neither package is in the General registry. So this fails:

```julia
Pkg.add(url = "https://github.com/MSALabs/SeasonalAdjustment.jl")
```

```
ERROR: expected package TSAnalytics [b1a2c3d4] to be registered
```

**This is the exact error `development-sequence.md` records as having failed
every CI run since the project's first scaffold.** `Project.toml`'s `[deps]`
entry names TSAnalytics but cannot say where to get it, and a fresh environment
has no sibling checkout to fall back on.

Every internal tester will hit it, on their first command, unless the install
instructions handle it.

### The instruction to publish

Both packages in **one** `Pkg.add` call, so the resolver treats both as fixed
from the start of a single resolve pass:

```julia
using Pkg
Pkg.add([
    PackageSpec(url = "https://github.com/MSALabs/TSAnalytics.jl"),
    PackageSpec(url = "https://github.com/MSALabs/SeasonalAdjustment.jl"),
])
```

Two sequential `Pkg.add` calls **fail in either order** — whichever runs first
triggers a resolve pass needing the other package already present. That is the
second bug `development-sequence.md` documents, from the `Docs.yml` fix. Do not
let the tester instructions reintroduce it.

Ship this as a copy-pasteable block. Any tester who improvises will hit one of
the two failure modes.

---

## 2. Do the UUIDs before the alpha, not after

`repo-migration-handoff.md` §1 flags both UUIDs as hand-typed placeholders. The
alpha makes that **more** urgent, not less.

Once testers install, the placeholder UUID is written into their `Manifest.toml`
files. Changing it afterwards silently breaks every tester environment, and the
resulting errors are confusing because nothing in the package appears to have
changed.

Regenerate with `uuid4()` in both packages, then tag the alpha. Cheapest now,
awkward in a week, impossible after registration.

---

## 3. Tag it, and have testers pin the tag

```toml
version = "0.1.0-alpha.1"
```

Tag `v0.1.0-alpha.1` and include the `rev` in the instructions:

```julia
PackageSpec(url = "https://github.com/MSALabs/SeasonalAdjustment.jl",
            rev = "v0.1.0-alpha.1")
```

Without a pinned revision, testers install `main` at whatever moment they happen
to run the command. Two people then report incomparable behaviour and neither
report is reproducible. Pinning costs one line and removes a whole class of
wasted debugging.

Bump to `alpha.2` for the next round rather than moving the tag.

---

## 4. What to fix in the docs before shipping

Both drafts currently promise registered-package installation, which is wrong
for the alpha.

**Home page**, the tip under *What is SeasonalAdjustment.jl?*, currently says
`Pkg.add("SeasonalAdjustment")` is the whole installation. The claim worth
keeping is about the **binary**, not the package — no separate X-13 download is
needed, unlike R and Python. Rewrite so that survives the alpha and stays true
after registration.

**Getting Started chapter 1** opens with `Pkg.add("SeasonalAdjustment")` and
"That is the whole installation. There is no second step." Same fix. The chapter
then spends a page on the bundled binary, which is the real point and stands
unchanged.

Suggested shape for both: give the two-package block from §1, then note that
after registration it becomes a single `Pkg.add("SeasonalAdjustment")`. Testers
see the current truth; the sentence to delete later is obvious.

---

## 5. What testers should be told

A short README section or a pinned issue, not a document.

**Known gaps in the alpha**, so nobody reports them as bugs:

| Area | Status |
|---|---|
| Forecast and backcast accessors | not implemented (W.7.2) |
| Missing-value handling | not implemented (W.7.3) |
| Regression component tables (`.td`, `.hol`, `.usr`) | not reachable (W.7.4) |
| `vcov` | throws by design; `.rcm` route not implemented (W.7.5) |
| `summary`, `update` | not implemented (W.7.6) |
| `force`, `seasonalma` typed fields | via `spec_args` only (W.7.7) |
| Sliding spans, revision history accessors | not implemented (W.7.8) |
| `seasonalplot`, `forecastplot`, `residdiagplot`, `componentplot`, `spanplot` | not implemented (W.8) |
| Bundled datasets | pending (W.9) |
| `_KNOWN_TABLES` | 17 of 281 tables reachable |

**What is worth reporting**, in priority order:

1. Anything where the package's output disagrees with R's `seasonal` on the same
   specification. That is the highest-value signal and the hardest to find
   internally.
2. Platform failures — `x13_binary_available()` returning `false`, or macOS
   dynamic-library errors. The artifact covers Linux, macOS and Windows but
   real-world coverage is untested.
3. Specifications the package cannot express. `spec_args` is the escape hatch;
   if something needs it that a tester expected as a keyword, that is a design
   signal.
4. Error messages that do not say what to do next.

**What is not worth reporting yet:** anything in the gaps table, and missing
documentation — Getting Started and the Introduction are both in draft.

---

## 6. Sequence

1. Regenerate both UUIDs (§2)
2. Transfer both repositories to `xKDR`
3. Update the thirteen org references and three CI URLs
   (`repo-migration-handoff.md` §2–3)
4. Confirm CI and Docs pass on the new org
5. Fix the install instructions in the Home page and Getting Started ch. 1 (§4)
6. Bump to `0.1.0-alpha.1`, tag both packages
7. Verify the §1 install block in a **genuinely clean depot**, not a machine that
   already has either package developed
8. Circulate the block, the gaps table and the reporting priorities

Step 7 is the one that gets skipped and shouldn't. The CI failures in
`development-sequence.md` persisted precisely because local machines always had
TSAnalytics developed from a sibling checkout and never exercised the fresh
path.

---

## 7. Open questions

1. **Is TSAnalytics tagged too?** If SeasonalAdjustment pins a TSAnalytics
   revision, both need tags. If it tracks TSAnalytics `main`, a TSAnalytics
   commit can change SeasonalAdjustment's behaviour mid-alpha and nobody will
   know why. Recommend tagging both.
2. **Does the docs site deploy for the alpha?** Testers benefit from the API
   Reference being live. The book drafts are not ready and should not deploy
   yet — consider building only `index.md` and `api.md` for now.
3. **Where do testers report?** GitHub issues on a private repo, or a channel?
   Issues are better: they survive, they are searchable, and they can carry the
   `.spc` and `.udg` files that make a report reproducible.
4. **Should the alpha ask testers for their series?** A tester's real Indian
   monthly data may resolve the `iip_india` gap, or supply the failing-diagnostic
   and near-zero series the book still needs. Worth asking explicitly rather
   than hoping.

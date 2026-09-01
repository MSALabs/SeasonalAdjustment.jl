# Handoff: Introduction, Part I — Foundations (Chapters 1–3)

~12 pages, 6 figures. Written **fourth**, after Chapter 9, Part II and Part V.

**Status: done.** See `book/src/introduction/01-why-adjust.md` through
`03-origins.md` and `test/test_book_examples.jl`'s "Chapters 1-2" testset.
Chapter 3's historical claims were verified via web search before writing
(§4's own instruction) -- two real corrections came out of that: "Estela
Bee Dagum" not "Estella" (a misspelling this project's own Chapter 9 had
already introduced, fixed there too), and "Julius Shiskin" not "Julian"
(one secondary source has it wrong). The "X-11 = eleventh variant" story
could not be traced to a primary source and is left out, with a boxed note
explaining why rather than silently dropped.

**Master:** `introduction-design.md`

---

## 0. Why this part is written late

Introductions drafted first promise what the body does not deliver. By the time
this part is written, Chapter 9 exists, Part II has explained X-11 concretely,
and Part V has demonstrated that the diagnostics disagree with each other on the
canonical example. Part I can then set up exactly those things, in the language
they were actually written in.

Two specific dependencies run backwards into already-written chapters:

**Chapter 2 must set up Chapter 16.** Part V's argument is that the diagnostic
battery exists because the decomposition is not identified. Chapter 2 is where
that non-identification gets established, and it should be phrased so Chapter 16
can pay it off in one sentence rather than re-arguing it.

**Chapter 3 must set up Chapter 9 without duplicating it.** The end-of-series
problem is Chapter 9's whole subject. Here it is one paragraph of history
pointing forward, not a second treatment.

Read Chapters 9, 16 and 18 before drafting anything in this part.

---

## 1. Chapters

| Ch | Title | pp | Figures | Primary dataset |
|---|---|---|---|---|
| 1 | Why Adjust? | 4 | A-1 | `appliance`, then `iip_india` |
| 2 | The Decomposition and Its Ambiguity | 4 | A-2, A-3, A-4 | `airline` |
| 3 | Where X-13 Came From | 4 | A-5, A-6 | — |

### Dataset change from the master design

The master assigned `iip_india` to chapters 1 and 2. **Lead with `appliance`
instead**, for the same reason Part V stopped depending on a designed failing
series: the dataset that exists beats the dataset that might.

`appliance` peaks at 1.52 in December against a February trough of 0.86. That is
a textbook illustration of "is business improving, or is December always like
this", it is public domain, and it already ships.

`iip_india` then becomes Chapter 1's **second** example — the one that motivates
Part III, because Diwali moves between October and November and no fixed
seasonal factor can absorb it. If licensing clears, it strengthens the chapter.
If it does not, Chapter 1 still works and the Diwali material lives entirely in
Chapter 11 where it belongs.

This makes Part I writable today apart from figure A-2.

---

## 2. Chapter 1 — Why Adjust?

### What it must establish

That the question "is the economy improving" cannot be answered from raw monthly
data, and that the obvious workaround has real costs.

### Outline

| § | pp | Content |
|---|---|---|
| 1.1 | 1 | A number that changes every month — **Figure A-1** |
| 1.2 | 1.5 | Why not just compare with last year? |
| 1.3 | 1 | The calendar is not only seasons |
| 1.4 | 0.5 | What adjustment is not |

**1.1.** Open with the practitioner's situation, not the algorithm. Retail sales
rose 40% from November to December. Is that good news? No: December is always
like that. Figure A-1 shows `appliance` with the December spike, and the reader
sees the problem before meeting any machinery.

**1.2 is the section that earns the chapter.** The obvious fix is
year-over-year comparison, and most readers already use it. It deserves a fair
hearing and then an honest accounting of what it costs:

- It discards eleven months of information to make one comparison.
- It is contaminated by whatever happened in the same month last year, so one
  anomalous month pollutes twelve subsequent comparisons.
- **It cannot detect a turning point until up to a year after it happens.** This
  is the decisive argument and it is underused. A series that turns in March
  shows a year-on-year decline only once the base months catch up.

Seasonal adjustment exists so that adjacent months can be compared. That is the
whole value proposition, and stating it this plainly is rarer than it should be.

**1.3.** Seasonality is not only weather and holidays. Trading-day composition,
the number of weekends in a month, moving holidays, fiscal-year effects. Preview
Part III briefly. **This is where `iip_india` enters if it is available** —
Diwali moving between October and November is the cleanest possible example of a
calendar effect that no fixed monthly factor can capture.

**1.4.** Half a page of negative space, which prevents a lot of later confusion.
Seasonal adjustment is not forecasting, not smoothing, not detrending, and not a
way to make a series look nicer. It removes one specific, repeating,
calendar-linked component and leaves everything else — including the noise —
alone.

---

## 3. Chapter 2 — The Decomposition and Its Ambiguity

**The most important chapter in Part I**, because Part V depends on it.

### Outline

| § | pp | Content |
|---|---|---|
| 2.1 | 1 | Three components — **Figure A-3** |
| 2.2 | 1 | Multiplicative or additive — **Figure A-4** |
| 2.3 | 1.5 | Why there is no right answer — **Figure A-2** |
| 2.4 | 0.5 | What "seasonal" means, operationally |

**2.1.** Observed = trend-cycle × seasonal × irregular. Figure A-3 is a
schematic, not data. Note that trend and cycle are deliberately not separated,
which surprises people who expect a business-cycle component.

**2.2.** When the swing grows with the level, the pattern is multiplicative.
Short — Getting Started covered the mechanics, and Chapter 8 covers the four
modes. What this section adds is that the choice is **a modelling assumption,
not a measurement**, which sets up 2.3.

**2.3 is the chapter, and the whole part's reason for existing.**

The argument, which should be made carefully and without hedging:

> Given an observed series, infinitely many trend-and-seasonal splits reproduce
> it exactly. Nothing in the data chooses between them.

Make it concrete rather than abstract. A seasonal pattern that drifts slowly over
twenty years — is that a changing seasonal, or is the drift part of the trend?
Both readings fit the data. Similarly at the other end: a seasonal that jitters
month to month, or a smooth seasonal plus a large irregular?

**There is no data-based answer. Every method supplies a convention.** X-11's
convention is encoded in its filters: the seasonal filter's span sets how fast
the seasonal may change, the Henderson length sets how wiggly the trend may be.
SEATS' convention comes from the fitted ARIMA model's structure. Chapters 6 and
14 are those two conventions in detail.

Then the sentence Chapter 16 pays off:

> Because there is no true seasonal component to compare against, there is no
> test for whether a decomposition is correct. What the field has instead is a
> battery of checks, each targeting one specific way it can go wrong. Part V is
> that battery.

Figure A-2 (`seasonalplot`, year-over-year) illustrates a seasonal pattern
changing shape over time, which is the concrete case that makes 2.3's ambiguity
visible. ~~Blocked on W.8.1.~~ **RESOLVED** — `seasonalplot` shipped with W.8;
buildable directly.

**2.4.** The honest closing: operationally, "seasonal" is whatever the chosen
filters call seasonal. Uncomfortable, and true, and a reader who accepts it will
read the rest of the book correctly.

---

## 4. Chapter 3 — Where X-13 Came From

### What it must establish

That X-13 is an accumulation of fixes to specific problems, and that it contains
two rival philosophies rather than one method.

### Outline

| § | pp | Content |
|---|---|---|
| 3.1 | 1.25 | A program, not a model |
| 3.2 | 0.75 | The end-of-series problem |
| 3.3 | 1 | The model-based challenge |
| 3.4 | 1 | Convergence — **Figures A-5, A-6** |

**3.1.** Census Method II, then X-11 in 1965 at the U.S. Census Bureau. The
point worth making: X-11 was published as *a program*, a specific sequence of
moving averages, with no underlying statistical model. That is why it worked
immediately in practice and why it made statisticians uneasy for thirty years.
Chapter 4's toy implementation is the reader's evidence that this description is
literally accurate.

The name story — X-11 being the eleventh experimental variant — is worth telling
**if it can be sourced.** It is widely repeated; verify before printing.

**3.2.** Three-quarters of a page, no more. Dagum at Statistics Canada,
X-11-ARIMA in 1980, and the idea in one sentence: if the problem is that the
future has not arrived, forecast it. Then point at Chapter 9, which has already
shown the reader what this buys, with a number.

**3.3.** The model-based tradition: signal extraction from an ARIMA model,
developed through the 1980s, and TRAMO/SEATS from Gómez and Maravall at the Bank
of Spain. Europe largely adopted it while the US kept X-11. Point at Chapter 14.

**3.4.** X-12-ARIMA in 1998 adds regARIMA, outlier detection and the modern
diagnostics; X-13ARIMA-SEATS merges the SEATS engine in. Figure A-5 is the
timeline; A-6 is the two-philosophies diagram that the rest of the book refers
back to.

Close on the framing that organises everything after: **two philosophies, one
program, and the diagnostics as the shared ground on which they are judged.**

### Sourcing

**Verify every date, name and attribution before printing.** The retellings of
this history vary, and a non-academic book is not licence to be loose with it.
Specifically to check:

| Claim | Verify |
|---|---|
| X-11 released 1965; Shiskin, Young & Musgrave, Census Technical Paper 15 (1967) | date of program vs paper |
| "X-11" = eleventh experimental variant | widely repeated; find a primary source or drop it |
| Dagum, X-11-ARIMA, Statistics Canada, 1980 | date and exact title |
| Burman / Hillmer & Tiao, model-based decomposition | attribution and dates |
| Gómez & Maravall, TRAMO/SEATS, Bank of Spain | dates |
| X-12-ARIMA, 1998, Findley et al. | the JBES paper is 1998; the software release may differ |
| X-13ARIMA-SEATS release year | **check** — the manual read for this project is v1.1, April 2015 |

Cite properly even in a non-academic document. Appendix B carries the full
reading list.

---

## 5. Figures

| ID | Kind | Content | Status |
|---|---|---|---|
| A-1 | custom | `appliance` raw, December spike annotated | buildable |
| A-2 | recipe | `seasonalplot` — seasonal shape changing over time | RESOLVED |
| A-3 | diagram | Decomposition schematic | draw |
| A-4 | custom | Multiplicative vs additive on `airline`, difference panel | buildable |
| A-5 | diagram | Lineage timeline | draw |
| A-6 | diagram | Two philosophies converging on X-13 | draw |

**Three of six are diagrams**, more than any other part, which is appropriate for
a part that is mostly argument. They age slowly, so hand-drawn SVG is defensible
over Luxor.jl here.

A-4 duplicates Getting Started's GS-7 in construction. **Do not reuse the
figure** — GS-7 makes a practical point about a keyword, A-4 makes a conceptual
point about modelling assumptions. Same data, different annotation and different
caption.

---

## 6. Verification checklist

| Item | Chapter | Status |
|---|---|---|
| `appliance` seasonal shape: Dec 1.52, Feb 0.86 | 1 | **verified** (dataset) |
| `airline` seasonal shape: Jul 1.25, Nov 0.83 | 2 | **verified** (dataset) |
| Multiplicative selected for `airline` | 2 | **verified** (fixture, `aictrans`) |
| Every historical date and attribution | 3 | **verify — see §4** |
| "X-11" naming story | 3 | **verify or drop** |
| Figures A-1, A-4 | 1, 2 | build |
| Figures A-3, A-5, A-6 | 2, 3 | draw |
| Figure A-2 | 2 | RESOLVED — build |

Part I quotes very few numbers, which is correct for a part that is argument
rather than demonstration. Its risk is not wrong figures but loose history.

---

## 7. Open questions

1. **RESOLVED — `iip_india` ships** as a bundled dataset
   (`dataset("iip_india")`). §1.3 gets its best example.
2. **Is the "X-11 = eleventh variant" story sourceable?** It is repeated
   everywhere and attributed nowhere. If no primary source turns up, drop it —
   a memorable anecdote is not worth an unsourced claim in a book that otherwise
   verifies everything.
3. **Should Chapter 2 use a worked numerical example of non-identification** —
   two different splits of the same series, side by side? It would make §2.3
   concrete rather than argued. It also risks implying the ambiguity is larger
   than it is in practice. Consider it; decide after drafting §2.3 in prose.
4. **Where does the two-philosophies diagram (A-6) actually belong?** It is
   drawn in Chapter 3 but referred to from Parts II, IV and V. Consider
   reproducing it small in Chapter 14 rather than cross-referencing eighty pages
   back.
5. **Is 12 pages enough for Part I?** It is the shortest part and carries the
   book's conceptual foundation. If §2.3 wants more room, take it from Chapter 3,
   which is the most compressible.

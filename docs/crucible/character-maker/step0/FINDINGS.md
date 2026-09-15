# Step 0 — art-viability spike: PASSED

**Question (BLADE.md step 0, from Temper flaw 13):** do modular parts read at 32px wide,
*before* we commit the enum surface? If parts turn to mud at game scale, the whole
procedural-parts premise collapses toward "recolor" — the option we rejected as too thin.

**Verdict: they read clearly. The premise holds. Proceed to Step 1.**

## Method — real art, not programmer-art

Deliberately did NOT generate placeholder parts to test this. Crude generated shapes would
confound two different failures: *"32px is too small to carry part detail"* versus *"the
placeholder art is bad"*. A negative result would have been unattributable.

Instead: measured the **information budget** of the 32×64 cell using the three sprites already
shipping (`NPC11/12/13`), rendered at true display scale. `gridSquareSize = 32`, so a sprite is
32×64 logical px — about 64×128 physical on a retina display, i.e. `legibility_2x.png` is
approximately what a player actually sees.

## What reads at true scale

Comparing the three idle (down, frame 0) cells side by side:

| Axis | Reads? | Evidence |
|---|---|---|
| **Hair** — colour AND silhouette | **Strongly** | dark short / brown long / white short are unmistakable |
| **Skin tone** | **Strongly** | NPC13's darker skin is clear at 1× |
| **Outfit** — colour + shape | **Strongly** | black suit / blue top / lavender cardigan |
| **Accessory** | **Yes** | NPC13 carries a **cane**, legible at true scale |
| **Fine accent detail** | **Yes, surprisingly** | NPC11's red tie is ~2px and still reads as an accent |

## Why this settles the design question

The four slots proposed in `DESIGN.md` — **body / hair / outfit / accessory** — are exactly the
axes that demonstrably carry information at this scale. This is not a guess that parts *might*
work; the shipping art already varies along all four and stays legible.

**Bonus finding:** NPC13 already has an accessory (the cane) drawn in. The accessory slot isn't a
speculative addition to this art style — the style is already using one.

**Caveat, stated honestly:** this proves the 32×64 cell can *carry* four distinguishable axes. It
does not prove that arbitrary *combinations* of independently-authored parts will register
correctly (a hat drawn for one head silhouette on another), which is a per-asset registration
concern — see RESEARCH.md Q5 gotcha 3 and the F7 512×64 asset invariant. That risk is managed by
authoring discipline, not by scale.

## Still open from Step 0

**OV2 — art source + licence.** Unresolved and still blocking real preset content (not the Step-1
type/compositor scaffolding). Options: LPC-derived (dual CC-BY-SA / GPL-3.0, so copyleft and
attribution attach to the art) versus Robin authoring to the 512×64 / 3-frame grid. The existing
NPC sprites prove the house style already works, which argues for authoring to it.

## Artifacts

`legibility_1x.png` (true logical pixels) · `legibility_2x.png` (≈retina display size) ·
`legibility_4x.png` (inspection zoom)

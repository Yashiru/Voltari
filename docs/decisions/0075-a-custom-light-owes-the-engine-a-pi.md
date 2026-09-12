# 0075 — A custom `light()` owes the engine a 1/π

**Status:** Accepted
**Date:** 2026-09-11
**Renumbered:** written as 0067, which decision 0067 (the turf watches the map)
already held. Text older than this repair cites it as 0067.
**Fixes:** a defect introduced by decision 0073
**Recorded in:** spec 16, section 9

## Context

The maintainer reported two things at once: the colours were over-saturated, and
the saturation control "did not really work". They turned out to be the same
fault, and neither was about saturation.

## How it was found

`enrich` is the identity at `saturation = 1.0`, so at that setting **what comes
out of the look must be what went in**. That is a test nothing had to be guessed
for: six flat swatches, one shader, everything but the paint silenced, the sun
head-on so nothing is in shadow, and a read-back of the pixels.

It was not the identity. Every channel of every swatch came out brighter, by the
same ratio:

```
gris   0.500 sRGB → linéaire 0.2140 → sortie linéaire 0.673   ratio 3.14
brun r 0.550        → 0.2623        → 0.831                   ratio 3.17
bleu r 0.400        → 0.1329        → 0.4125                  ratio 3.10
bleu g 0.420        → 0.1471        → 0.4610                  ratio 3.13
```

A constant of 3.14 across unrelated colours is not an exposure and not a colour
space. It is π.

## What was wrong

**Godot hands `LIGHT_COLOR` already multiplied by π.** Its own lighting path
divides it out again inside the Lambert term, which carries a 1/π. A shader that
writes its own `light()` never reaches that term, so it has to do the division
itself. The shared look did not, so **every surface in the game was rendered 3.14
times too bright**.

What makes it worth a decision entry is that it did not look like a brightness
fault. Most channels clipped at 1.0, and **a colour with a clipped channel is a
pure hue** — the minor channels are driven to zero and cannot come back. So:

- the world read as over-saturated, because it literally was: clipping raised the
  measured saturation of the ground green from 0.974 to 1.000 and the chest orange
  from 0.889 to 1.000
- the saturation control appeared dead, because at the shipped value of 1.08 two
  of four coloured swatches were already at the ceiling. There was no headroom for
  it to push into, so pushing it did nothing

## Decision

**`OVER_PI`, applied where the look writes `DIFFUSE_LIGHT`** — both in the sun
branch and in the lamp branch. After it, the chart is the identity to within
0.0065, which is 8-bit rounding.

## Consequences

**Three compensations are undone, because they were compensations.** Each was
tuned against a pipeline nobody knew was over-bright, and each was a number coming
down to fight a symptom:

| | during the fault | now | why it was wrong |
| --- | --- | --- | --- |
| `saturation` default | 1.34 → 1.08 | **1.0** | a control that pushes a colour should default to not pushing it |
| `comic-manga` saturation | 1.25 → 1.05 | **1.0** | the same, in the preset |
| `ink` | 0.84 | **0.92** | the low number was half an exposure fix; what is left is the real reason, that a printed fill sits just under its paper |
| `Daylight.brightness` | 1.0 → 0.88 → 0.72 | **1.0** | a sun at full strength lights the paint at its own value, which is what a sun is for |

Measured after: zero clipped channels anywhere on the chart at 0.70, 1.00 and
1.30, and the saturation moves continuously across all three.

**The lesson generalises past this bug.** Two of the three numbers above were
changed on the strength of looking at a render and disliking it, which is the
method this project uses for shaders and will keep using. It works for questions
of taste and it cannot find an arithmetic fault — a wrong constant looks like a
taste you have not found yet. The identity test is what separated them: pick a
setting where the transform must be the identity, and check that it is.

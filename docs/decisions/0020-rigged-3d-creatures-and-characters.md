# 0020 — Creatures and characters are rigged 3D, not pixel-art sprites

**Status:** Accepted — **its consequences section is superseded by decision 0045**
**Date:** 2026-09-08
**Supersedes the rendering direction in:** `docs/architecture/layers.md`, L4

> The decision itself stands: rigged 3D, no pixel art, no billboards, a free
> camera. What no longer holds is the **mitigation** below — shared archetype
> skeletons with retargetable animations. A working pipeline took 860 rigged
> models to playable scenes with one rig each and no retargeting, and the fakemon
> follow that contract. Decision 0045 records why the argument here did not carry
> and what is being paid instead.

## Context

The original direction was smooth 3D environments at native resolution with
creatures and characters as billboarded pixel-art sprites. Reconciling the two
was identified from the start as the delicate point of the renderer.

## Decision

Creatures and characters are **rigged, animated 3D models**. No pixel art in the
runtime, no billboarded sprites, no global low-resolution viewport.

The camera loses its fixed distance and zoom constraint, which existed solely to
keep sprite pixel density stable.

## Options rejected

- **Billboarded pixel-art sprites**, the original direction. Far cheaper per
  creature. But it requires the whole sprite/3D reconciliation apparatus —
  nearest filtering, constant pixel density, a locked camera distance and zoom,
  texel-to-pixel consistency between creatures and characters — and in the
  overworld it multiplies every character animation by four to eight facings.
- **3D produced in pipeline, pre-rendered offline to sprite sheets.** Keeps the
  pixel-art look with a modern production pipeline and a very cheap runtime, but
  forfeits the free camera.

## Consequences

**What disappears.** The sprite/3D reconciliation problem, entirely, and the
fixed-camera constraint with it. Dynamic battle framing and freer overworld level
design become available — which makes this a decision that must land before
spec 14, since it changes level design.

**What gets more expensive.** Production cost per creature rises sharply: model,
UV, texture, rig, skinning and an animation set, against a few poses for a
sprite. On a monster-catching roster this is the dominant constraint. The
mitigation is **shared archetype skeletons** — biped, quadruped, serpentine,
winged — with retargetable animations, so the marginal cost per creature
collapses. Without that, the approach does not scale.

> **Superseded by decision 0045.** The mitigation was never built and is not the
> plan. The dominant constraint named in the paragraph above is real and is now
> accepted unmitigated rather than argued away.

**What is added to the plan.** Spec 16 widens from a rendering technique to an
asset pipeline: skeleton conventions, animation clip naming, retargeting, LOD,
`.glb` import settings. Spec 17 gains weight, because the battle log carries no
timing (spec 07) while 3D animations have durations and blending — sequencing
them against an untimed event stream is now a real design problem. Spec 09 gains
per-creature model and animation-set references. The mobile budget becomes a
first-order spec concern rather than a note, since mobile constraints win
arbitrations.

**What does not change.** Nothing in L0, L1 or L2. Nothing in specs 01 to 08.
The core, the fidelity contract, the turn machine and the effect system are
untouched — and this is demonstrated rather than predicted, since all of them
were already implemented when the decision was taken.

That is the dividend of two earlier choices: the layering, and the rule that the
core emits identifiers and never presentation (decision 0001). The battle log
describes what happened, not how it is shown, so a consumer animating skeletons
reads exactly the stream a consumer animating sprites would have read.

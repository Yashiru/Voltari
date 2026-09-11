# 0045 — Each creature brings its own rig

**Status:** Accepted
**Date:** 2026-09-09
**Supersedes:** the archetype-skeleton mitigation in decision 0020
**Recorded in:** spec 16, section 3

## Context

Decision 0020 chose rigged 3D over pixel-art sprites and named the objection to
it: production cost per creature rises sharply, and on a monster-catching roster
that is the dominant constraint. Its answer was **shared archetype skeletons** —
biped, quadruped, serpentine, winged — with retargetable animations, and it said
plainly that without them "the approach does not scale".

A working pipeline has since taken 860 rigged models to playable Godot scenes.
It uses no archetypes, no shared skeleton and no retargeting. Each model arrives
with its own skeleton — 62 joints on one, 38 on another — and its own clips.

## Decision

**One rig per creature. No shared skeleton, no retargeting.** The fakemon follow
the contract the pipeline already produces, because that is what the artist is
reproducing.

## Why 0020's argument does not carry

It is not that the argument was wrong. It is that the thing it measured is not
the thing that happened.

The species **arrive already rigged**. The cost 0020 worried about had been
paid by somebody else before the pipeline saw the file, so scaling to 860 models
says nothing about the cost of authoring 860 rigs.

That distinction matters because it means **the original worry still stands for
the real roster** — and is being accepted rather than solved. What has changed is
only that archetypes are no longer claimed as the thing that makes it possible.

## Options rejected

**Keeping archetypes as the target.** The animation cost per creature genuinely
would collapse, and for a large roster that is a serious sum.

Rejected because the whole toolchain — the pipeline, the runtime script, the
manifest — is built around a model that brings its own skeleton, and because a
target nothing reaches is worse than an honest constraint. It would also put the
shape of the creatures, which is the IP, at the mercy of four skeletons.

**Allowing bespoke rigs as exceptions**, archetypes otherwise. The usual
compromise. Rejected because nothing bounds the number of exceptions, so it
decays into this decision with extra machinery — and the machinery is the
retargeting layer, which is the expensive part.

## Consequences

**The dominant production cost of the project is now explicit and unmitigated.**
Every creature needs a model, UVs, textures, a rig, skinning and a full animation
set. Nothing in the engine reduces that, and no future decision should imply
otherwise without measuring it.

Two things soften it and are worth knowing about. The animation *vocabulary* is
shared even though the skeletons are not (spec 16, section 4), so a creature can
declare a fallback rather than author a clip it does not need yet. And the
runtime is one script for every creature, so the per-creature work is asset work
only.

Decision 0020 stands in everything else: rigged 3D, no pixel art, no billboards,
a free camera. Only its consequences section is superseded.

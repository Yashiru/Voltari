# 0039 — Maps are painted and validated, not written and exported

**Status:** Accepted
**Date:** 2026-09-09
**Refines:** decision 0004 (YAML as the source of truth)
**Recorded in:** spec 14, sections 3 and 7

## Context

All authored content is YAML, reviewed as text, built into a committed payload.
Decision 0004 rests on diff readability: the maintainer reviews every change, so
a change must be legible on the page.

A map does not fit. Writing a tile grid by hand in text is not a workflow anybody
would keep, and its diff — coordinates and indices — is unreadable in either
direction.

## Decision

**A map is a Godot scene**, painted in the editor. Tiles carry the collision;
warps and encounter zones are nodes placed on it.

**Maps are validated and nothing is exported.** The scene is the truth at
runtime, so there is nothing to extract.

The validation runs **engine-side rather than in the Node content build**: only
Godot can load a scene, so a Node script would have to reimplement the scene
format to read a map. Spec 09 already makes that split for effect ids, which the
build cannot see either.

**Encounter tables remain YAML content**, one per file, referenced by a zone
through an identifier.

## Why the criterion of 0004 is suspended here, and only here

Decision 0004 buys review, and review buys different amounts in different files.
A species file reviews well because its meaning *is* its text: a base stat of 130
is wrong on the page. A tile grid's meaning is visual, and nobody has ever caught
a level-design mistake by reading coordinates.

So the criterion is suspended for the geometric part of a map and for nothing
else. **What review would have caught is caught mechanically instead**: the parts
of a map that are not geometric — which table a zone names, where a warp
leads — are exactly what the validator checks.

That check is not a consolation prize. A warp's destination lives in a *different
file* from the warp, which is precisely the class of error a scene cannot catch
by itself and a reviewer catches only by holding two maps in their head.

## Options rejected

**Maps as YAML, like everything else.** Consistent, diffable, validated by the
existing pipeline. Rejected on the workflow: every retouch of level design would
mean editing a grid by hand, which makes the cheap iteration that good level
design depends on expensive.

**Painting in the editor and exporting the grid to a payload.** The maintainer
initially selected this, and it conflicts with the scene remaining the runtime
truth: the payload would be rebuilt into a tile map on load, so the same
information would exist twice with nothing keeping the copies equal. Raised, and
resolved to validation only.

**Exporting the non-geometric part** — warps and zones — while leaving tiles in
the scene. Would make that data readable without loading a scene. Rejected for
the same duplication, for a benefit nothing currently needs.

**No build step at all.** Least machinery. Rejected because nothing else can
catch this class of error. The world's own tests run on fixture maps
(decision 0038), which proves that warps *work* — it says nothing about whether
the warps in the shipped maps point anywhere real. Only a pass over the actual
content can, and without it a broken warp is discovered by walking to it.

## Consequences

Map scenes are reviewed by opening them, not by reading the diff. Their pull
requests are read for what changed in the *validated* data and played for the
rest.

The validator needs failing fixtures — maps built to be broken — or nobody ever
sees it reject anything. Spec 14 makes that a test obligation.

Encounter tables stay shared: a table used by three maps exists once and is
balanced in one place, which would have been lost had the table been a property
on the zone.

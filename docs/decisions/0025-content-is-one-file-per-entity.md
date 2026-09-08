# 0025 — Content is one file per entity, in and out

**Status:** Accepted
**Date:** 2026-09-08
**Refines:** decision 0004 (YAML as source of truth)
**Recorded in:** spec 09, sections 2 and 9

## Context

Decision 0004 settled the format and made diff readability a first-order
criterion, because the maintainer reviews every change. It did not settle
granularity — there were nine moves, so the question had no teeth.

At a real roster's size it has teeth. A single `species.yaml` runs to thousands
of lines.

## Decision

**One file per entity**, named by its identifier: `content/species/emberling.yaml`.
The build emits the same shape, one JSON per entity, plus an index per kind.

The filename *is* the identifier and the file does not repeat it.

Tables stay single files. `type-chart.yaml` and `natures.yaml` each describe one
structure, not a collection.

## Options rejected

**One file per kind**, as today. A single place to look and a trivial build.
Rejected on the criterion 0004 already set: every edit lands in an enormous file,
and two people editing unrelated creatures conflict over lines they never read.

**Sharding into ranges** — `species/001-050.yaml`. Rejected because the shard
boundary describes nothing. It has no meaning in the game, and moving an entry
across one becomes a decision somebody has to take for no reason.

**A single bundled payload** out of the per-entity sources. Simpler loader, and
data this small loads instantly either way. Rejected in favour of mirroring the
source layout: the split already exists upstream, and collapsing it in the build
only to reconstruct it later is work that buys nothing. The index makes the
split usable.

## Consequences

An **index per kind is mandatory**, not a convenience. Without it nothing can
enumerate the roster and a loader is reduced to guessing filenames.

Renaming an entity is a `git mv`, and its history stays its own.

The build now walks a directory rather than reading one file, so a stray or
misnamed file is a case it has to report rather than one it cannot encounter.

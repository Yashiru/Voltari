# 0040 — The world bridges itself to the save

**Status:** Accepted
**Date:** 2026-09-09
**Refines:** decision 0037 (saves are read tolerantly, per section)
**Recorded in:** spec 14, section 8

## Context

Spec 13 has each system declare its part of a save: a key, a version, and the
pair of functions that write and read it. `VltSaveSection` is pure — it assembles
dictionaries and never sees a file — and lives under the purity lint.

Decision 0038 put the world's state in the scene tree. So the first real section
the game will declare is one whose data is held by the engine, in nodes, behind
an API the purity lint forbids.

The maintainer asked for exactly this: a module able to convert native Godot data
into the save's shape.

## Decision

**The world's save section lives with the world**, in the Godot-dependent layer,
and extends `VltSaveSection`.

`VltSaveSection` is pure and L3 depends on it. The dependency runs downward, so
this is not an inversion — the section is simply not under the lint, because the
directory it sits in is not.

**One direction only.** The section reads the world and produces dictionaries.
The world never reads a file; L5 still owns the bytes, unchanged from spec 13.

It carries the map id, the cell and the facing. Nothing else — quest flags will
declare their own section when spec 15 gives them an owner.

## Options rejected

**Putting the section in `save/` with the others.** One directory holds every
section, which is the obvious place to look. Rejected because it would either
break the purity lint on a directory whose whole value is that it is clean, or
force the world back into a pure model that decision 0038 rejected. A lint with
one exemption is a lint nobody trusts.

**A neutral snapshot structure**, with the world filling a plain object and the
section reading only that. It keeps the section pure and looks tidy.

Rejected because the conversion does not disappear — it moves one step earlier
and stops being anybody's declared job. There would then be two places where the
world's shape is written down, and the only thing keeping them equal would be
attention.

**Letting L5 read the scene tree directly.** Fewest pieces. Rejected because it
would make the layer that writes bytes depend on the layer that draws the world,
inverting the whole stack for a saving of one class.

## Consequences

`save/` holds the *mechanism*; sections live with whoever owns the data. That is
the general rule this establishes, and the world is only the first case — a
section belongs to its system, wherever that system lives.

**A map id is now held in a save.** The content identifier rule (spec 09,
section 3) therefore applies outside content for the first time: stable,
`snake_case`, never reused for a different map. Renaming a map file is a
migration, not a rename.

The round-trip test that comes with declaring a section (spec 13, section 8) is
the one piece of mechanical coverage the world gets, since decision 0038 gives up
the rest. It proves the conversion, not the world.

# 0026 — Content carries no presentation

**Status:** Accepted
**Date:** 2026-09-08
**Depends on:** decision 0020 (rigged 3D), spec 07 (§ localisation)
**Recorded in:** spec 09, section 7

## Context

A species needs a display name and a 3D model. Both are obvious candidates for
the species entry — everything about a creature in one place — and both would
put presentation into data the simulation core consumes.

## Decision

**Names live in L4.** Content holds identifiers only.

**Assets live in a separate presentation manifest**, keyed by species id,
declaring model, animations and scale.

## Options rejected

**A `name:` field beside the stats**, in English, doubling as a translation key.
The most direct thing to edit. Rejected because spec 07 already settled the same
question for the battle log — events carry identifiers, localisation is L4 and
lives nowhere else — and answering it differently one document later would give
the project two rules for one thing.

**A locale file under `content/`**, versioned and validated with the rest. This
one is defensible: names are IP and reviewed content. Rejected for the same
reason, and because validation is not the argument it appears to be — the build
can check a manifest in L4 just as well as one under `content/`.

**Asset paths in the species entry.** Nothing to keep in sync. Rejected because
a Godot resource path in a file the core consumes couples simulation data to the
engine's layout, which is precisely the coupling the layered decomposition
exists to prevent.

**Naming convention instead of a manifest** — the id gives the path. No data to
maintain and impossible to desynchronise. Rejected because nothing is verifiable
at review time, a missing asset surfaces only at runtime, and two species can
never share a rig.

## Consequences

Editing a species file shows identifiers and numbers only, so identifiers have
to stay legible to a person. That is a constraint on naming, and it is cheaper
than the coupling it avoids.

The build checks the manifest **in both directions**. A species with no manifest
entry and a manifest entry naming no species are both errors — a one-way check
would let dead asset references accumulate silently.

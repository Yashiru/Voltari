# 07 — Battle log

**Status:** Draft
**Depends on:** specs 03, 04, 05, 06; decisions 0001, 0009, 0012

The core drives no animation and prints no text. It emits an ordered,
serialisable stream of events, and everything downstream reads that stream.

Four consumers, with genuinely different needs, all served by one artefact:

| Consumer | Needs |
|----------|-------|
| UI | Enough granularity and the right order to reproduce the original pacing |
| Tests | Something to assert on other than internal state |
| Differential | A projection comparable to the oracle's log (spec 02) |
| Replay, PvP | Completeness, and per-viewer filtering |

---

## 1. Completeness is an obligation, not an aspiration

Invariant 8 of spec 05: **replaying the log onto the initial state reproduces the
final state.**

That single property carries the whole design. An effect that mutates state
without emitting an event breaks it, so forgetting to log is not a subtle
omission that surfaces months later in the UI — it is a failing test.

To make replay assignment rather than arithmetic, **events carry resulting
values, not deltas**: `damage` records the damage dealt *and* the resulting HP.
Replay then sets values instead of recomputing them, which removes an entire
class of drift between the log and the state it describes.

## 2. Event shape

Events are **typed classes, one per kind**, not a kind enum with a dictionary
payload. A dictionary would forfeit static typing, which is mandatory — the same
reasoning that governs state classes in spec 03.

Every event carries a visibility tag (section 5).

## 3. Granularity

**One event per observable state change.** Fine-grained and strictly ordered.

The reference is what a player perceives: the effectiveness message, the health
bar draining, the faint, the stat change, the replacement request. If two things
are perceived as two beats, they are two events. A log too coarse cannot be
re-paced by the UI, and coarseness is not recoverable after the fact.

Illustrative, not exhaustive — the vocabulary closes with spec 08:

```
turn_start, turn_end
switch_out, switch_in
move_used, move_failed, move_missed
effectiveness, critical_hit
damage, heal, faint
stat_change
effect_applied, effect_removed, effect_triggered
input_requested
```

## 4. Ordering

The core emits **in resolution order**, and holds no knowledge of presentation —
which the purity rule requires in any case.

In Gen 4 the two coincide: the game resolves and presents in lockstep. Where they
appear to diverge, the correction is to **change the resolution order, not to add
presentation hints**. The oracle's log is itself in resolution order, so the
differential catches a mismatch rather than letting it hide behind a UI mapping.

## 5. Visibility and filtering

Every event is one of:

| Tag | Meaning |
|-----|---------|
| `public` | Visible to everyone, unchanged |
| `private` | Visible only to the side it belongs to |
| `transformed` | Visible to everyone, in a reduced form |

Filtering is not only dropping. An opponent does not see exact HP, they see a
percentage — so `transformed` events carry a declared transformation rule per
event kind.

This yields a filtered analogue of invariant 8:

> Replaying a viewer's filtered log reproduces the state **observable by that
> viewer**.

Which is what makes the filtering testable at all, rather than a hand-checked
list of what should have been hidden.

## 6. Identifiers, never text

Events carry move IDs, effect IDs and slot references. The core emits no
localised string, and no string intended for display.

Localisation is L4 and lives nowhere else (`docs/architecture/layers.md`). This
is the decision that prevents English messages from being hardcoded across
hundreds of effects.

## 7. Normalisation for the differential

The differential compares a **normalised projection** of our log against the
oracle's (spec 02, decision 0009).

The projection lives here as a concept; the mapping from Showdown protocol
messages, and the ignore list of events that exist in only one vocabulary, live
in `tools/oracle/` — on the tooling side of the clean-room boundary.

The ignore list is part of the fidelity contract: an event silently dropped from
the projection is a hole in the differential.

## 8. One mechanism, two layers

The event stream is a general mechanism, not a battle-only one. The post-battle
pipeline — XP, level-up, learning moves, evolution (spec 10, layer L1) — emits
into the **same stream shape**, with its own partition of the vocabulary.

The UI therefore consumes one continuous stream across the battle and its
aftermath, which is how a player perceives it, without L0 and L1 being merged to
achieve it.

---

## Open points

- The event vocabulary closes with spec 08, alongside the anchor enumeration of
  spec 06.
- Transformation rules are declared per event kind as the kinds are defined; the
  set is not fixed here.
- Whether the log carries a monotonic sequence number per event, or relies on
  array position, is decided when replay is built.

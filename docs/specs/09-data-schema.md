# 09 — Data schema and content build

**Status:** Draft
**Depends on:** specs 01, 02, 03, 06; decisions 0004, 0020

What authored content looks like, what it may and may not contain, and the
pipeline that turns it into something the core can be handed.

The core reads no file and knows no format (spec 03). Everything here happens
upstream of it.

---

## 1. Three stages, three jobs

```
content/**.yaml   →   build   →   content/generated/**.json   →   loader   →   typed core input
   authored          validated        committed payload          typing boundary
```

Each stage has exactly one job, and none of them overlaps another:

- **YAML** is the only thing written and reviewed. Nothing else is edited by
  hand, ever.
- **The build** validates and flattens. Validation lives here, where a human is
  watching and a failure costs nothing, rather than at runtime where it costs a
  session. A malformed file must never reach the engine.
- **The payload** is committed. CI regenerates it and fails on any difference,
  so the source and the artefact cannot drift apart unnoticed.
- **The loader** is the typing boundary (spec 01): parsed data in, typed objects
  out. It is the only place untyped values are handled.

## 2. One file per entity

`content/species/emberling.yaml`, one creature per file. Likewise for moves,
abilities and items.

The maintainer reviews every change, so diff readability is a first-order
criterion (decision 0004). At a roster's real size, a single `species.yaml` runs
to thousands of lines: every edit produces a diff inside an enormous file, and
two people editing unrelated creatures collide. Per-entity files make each
creature's history its own, and a rename a `git mv`.

**The filename is the identifier.** The file does not repeat it. One source, and
a whole class of mismatch that cannot occur rather than one the build has to
check for.

Tables are not collections and stay single files: `type-chart.yaml` and
`natures.yaml` describe one structure each, not a set of entities.

## 3. Identifiers

`snake_case`, stable, and **never reused once published** — a saved game holds
them, so reusing one silently reinterprets somebody's party.

Namespaced per kind. A move and a species may share a spelling; nothing resolves
an identifier without knowing what kind it is looking for.

Identifiers are the *only* names in content. They are read by people editing
YAML, so they should be legible — but they are not display names, which live
elsewhere entirely (section 7).

## 4. The species schema

| Field | Meaning | Validated |
|-------|---------|-----------|
| `types` | One or two, in order | Declared in the type chart |
| `base_stats` | Six integers, `hp` first (spec 08 stat order) | 1–255 each |
| `abilities` | Effect ids granted intrinsically | Engine-side only — see section 8 |
| `learnset` | `level_up:` list of `{level, move}` | Move exists; levels ascending |
| `evolutions` | List of `{into, trigger, …}` | Target species exists; no cycle |
| `growth_rate` | Named level curve | Curve id is known — spec 10 |
| `base_experience` | Yield on defeat | Positive — spec 10 |
| `ev_yield` | Six integers | Sum ≤ 3 — spec 10 |
| `catch_rate` | Capture difficulty | 3–255 — spec 11 |
| `gender_ratio` | Eighths female, or genderless | 0–8 or the sentinel — spec 10 |

The last five are **named and bounded here, given meaning later**. Specs 10 and
11 write the formulas that read them. Content can be authored in one pass rather
than every creature being revisited each time a spec lands, and a field whose
range is declared is a field the build can already check.

Learnsets and evolutions live in the species file. Splitting them out would undo
most of what section 2 just bought: a creature would take three files to read.

## 5. The move schema

Power, type, category, accuracy, priority and PP as authored today, plus:

| Field | Meaning |
|-------|---------|
| `target` | Which position(s) it may be aimed at |
| `effects` | What it does beyond damage (section 6) |

`target` is not optional detail. With two slots a side (spec 03), "the opponent"
stops being a single position, and a move that hits one foe, both foes, an ally
or the user is describing a different thing each time.

## 6. Effects in content: parameters, never behaviour

```yaml
effects:
  - id: burn
    chance: 10
```

The id names a component class (spec 06); the numbers are its parameters. The
engine resolves the id to code, so adding a mechanic writes GDScript and does
not widen this schema.

A move with two effects needs no new field. Validation is **per effect id** —
each declares the parameters it takes and their ranges — rather than one global
rule that would have to admit every parameter any effect might want.

Evolution triggers take the same shape for the same reason: `trigger: level` with
a `level:`, `trigger: item` with an `item:`. One mechanism, not two.

**The rule of spec 06 §8 governs here and is not restated:** no conditional logic
in YAML. A move whose power doubles against a sleeping target is a component
class. The first `if` in content is the moment the format became a DSL.

## 7. What content does not carry

**Display names.** Content holds identifiers; names are localisation and live in
L4, which is already what spec 07 requires of the battle log. A name in a file
the core consumes would put presentation text inside simulation data.

**Asset references.** A separate presentation manifest, keyed by species id,
declares model, animations and scale (decision 0020). Keeping it out of the
species entry preserves the layer boundary, and lets two species share a rig
without duplicating anything. The build checks the correspondence in both
directions: a species with no manifest entry, and a manifest entry naming no
species, are both errors.

## 8. What the build validates

Three kinds, and the distinction matters because they fail differently:

- **Shape** — a field is missing, or the wrong type, or out of range.
- **Cross-reference** — a move names an unknown type, a learnset an unknown
  move, an evolution an unknown species. These are the typos that survive review
  and produce content that looks right and plays wrong.
- **Invariants** — an evolution cycle, a duplicate nature pairing, a status move
  carrying power. Structural claims that can be checked rather than trusted.

Every failure names the file and the field. The build reports **all** problems
and then exits, rather than stopping at the first: a content pass fixes ten
typos in one go or ten times over.

**One reference the build cannot check: effect ids.** A move's `effects` and a
species' `abilities` name component classes, and those live in GDScript where a
Node build cannot see them. Checking them is the engine-side meta-test's job
(section 10), which is the only place that knows what is registered. Until a
loader exists for a given kind, those ids are unchecked — stated here rather
than left to be discovered.

## 9. What the build emits

One JSON per entity, mirroring the source layout, plus an **index** per kind
listing the ids that exist:

```
content/generated/
  species/index.json, emberling.json, …
  moves/index.json,   ember.json, …
  type-chart.json
  natures.json
```

The index is what makes per-entity output usable: without it nothing can
enumerate the roster, and a loader would be reduced to guessing filenames.

Payload files carry a schema `version`. A change that existing payloads cannot
satisfy raises it, and the loader refuses a version it does not know — refusing
to load is recoverable, misreading is not.

## 10. Testing obligations

- **Every id resolves.** A meta-test walks every cross-reference in the built
  payload. Unlike the build's own check, it runs in the engine's own terms.
- **Every authored entity loads** into its typed form without error.
- **The payload is current.** CI regenerates and diffs; this is the guard that
  makes a committed artefact safe.
- **Content is not a fixture.** Core tests build their data in memory (spec 03).
  A core test that reads `content/generated/` is coupling the engine's
  correctness to the roster's balance.

## Open points

- **Learnset methods beyond level-up** — machines and tutors have no spec yet,
  so `learnset` declares only `level_up`. Adding a key is not a breaking change.
- **Breeding** has no spec in the plan, so no egg groups are defined. Inventing
  the fields now would be guessing at a system nobody has designed.
- **Items and abilities as content** are named here as ids but have no schema of
  their own until the effects behind them exist.

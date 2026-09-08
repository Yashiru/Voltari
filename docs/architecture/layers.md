# Engine layers

Voltari is organised in layers. **A layer may only depend on layers below it.**
The core depends on nothing.

---

## L0 — Simulation core

Pure computation. Deterministic, headless, fully testable.

- Battle state (sides x slots)
- Injected RNG (named streams)
- Turn state machine
- Effect system: ordered modifier pipeline, veto mechanism, event queue
- Gen 4 formulas
- Battle log emission

### Purity rule (normative)

The core runs inside Godot but uses **only the language, never the engine**.
Forbidden anywhere under the core directory:

- `Node`, scene tree access, `Resource`
- `await`, `signal`
- Global or internally created RNG (`randi`, `randf`, `RandomNumberGenerator`)
- Clocks (`Time.*`)
- File I/O (`FileAccess`, `load`, `preload`)

The core receives already-parsed, typed data injected by an external loader. It
performs no I/O and never touches a data format. Tests build their fixtures in
memory, without files.

To be enforced by a CI purity lint, not by convention alone.

### The core emits no text

Log events carry identifiers, never localised strings. Localisation lives in L4.

### Slots, not attacker/defender

Double battles are in scope from day one. Battle state is sides x slots and
targeting is a first-class concept. There is no `attacker` / `defender` shortcut
anywhere in the model.

### Online-PvP constraints (deferred feature, non-deferred constraints)

PvP is not built yet, but retrofitting these would be a rewrite, so they hold now:

1. Turn resolution is a pure function
   `(state, commands from all sides, seed) -> (state', log)`.
   No code path may let one side inspect another side's pending choice.
2. Commands are serialisable structures, not method calls.
3. Every log event carries a visibility tag, so each side can be shown only what
   it is entitled to see.

---

## L0bis — Deciders

Produce commands; read state only. Kept out of the core because a policy is not
a rule — and that separation is what makes lockstep possible later.

- Battle AI
- Player input
- Network input (deferred)

---

## L1 — Out-of-battle rules

Same purity constraints as L0.

- Progression: XP, EV gain, level-up, learnsets, evolution
- Capture
- Creature generation (IVs, nature, gender)
- Party, box, inventory

> Not covered by the fidelity oracle — see `docs/specs/README.md`, spec 02.

---

## L2 — Data and content

- YAML schema (source of truth, versioned, reviewed in PR)
- Build-time validation: stable IDs, resolved references
- Content build: YAML -> `.tres` (editor integration) + core payload
- Type chart, species, moves, abilities, items, learnsets, evolutions,
  encounter tables

`.tres` files are build artefacts: gitignored, regenerated, never hand-edited.

---

## L3 — World

Depends on Godot.

- Tile-based overworld: grid, collision, warps
- Encounters
- Event scripting: dialogue, quest flags, cutscenes
- Time of day

---

## L4 — Presentation

- Creature and character rendering: **rigged, animated 3D models** in a smooth 3D
  scene at native resolution. No pixel art, no billboarded sprites, no global
  low-resolution viewport. The camera carries no fixed distance or zoom
  constraint — that constraint existed only to hold sprite pixel density stable.
- Battle log consumer, driving animation
- UI / HUD
- Audio
- Localisation

---

## L5 — Platform

- Save / load, versioning, migration
- Input abstraction (desktop and touch)
- Networking (deferred)

---

## Cross-cutting

- Test tooling: vector generator, property-based generators, mutation harness
- CI
- `docs/decisions/` — the why behind each structuring decision

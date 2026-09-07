# 01 — Conventions and repository structure

**Status:** Draft
**Depends on:** `docs/architecture/layers.md`, decisions 0007, 0008

Most of this specification's subject matter is already recorded elsewhere and is
**not repeated here**:

| Subject | Where it lives |
|---------|----------------|
| Decision gate, workflow, code standards, test commands | `CLAUDE.md` |
| Layer boundaries and the core purity rule | `docs/architecture/layers.md` |
| Repository layout rationale | decision 0007 |
| CI jobs and pinned tool versions | `.github/workflows/ci.yml` |
| Purity lint rules | `tools/purity-lint/purity-lint.mjs` |

What remains, and what this document is actually for, is the **naming
convention** — required by the code standards and recorded nowhere else.

---

## 1. Layout

```
addons/voltari/       the reusable engine
  core/               L0  — simulation core, purity-enforced
  deciders/           L0bis — AI, player input
  rules/              L1  — out-of-battle rules, purity-enforced
game/                 this game: scenes, assets, presentation
  assets/
content/              YAML source of truth
tests/                test suites, mirroring the source tree
tools/                build and lint tooling (Node)
docs/                 specs, architecture, decision journal
```

## 2. Naming

### Files and directories

`snake_case` for scripts and directories. `kebab-case` for assets, docs and
tooling. Test suites end in `_test.gd` and mirror the path of what they cover:
`addons/voltari/core/damage.gd` is tested by `tests/core/damage_test.gd`.

### GDScript

Standard GDScript conventions, no local invention:

| Kind | Convention |
|------|------------|
| Class | `PascalCase` |
| Function, variable, parameter | `snake_case` |
| Constant | `SCREAMING_SNAKE_CASE` |
| Enum type / enum value | `PascalCase` / `SCREAMING_SNAKE_CASE` |
| Private member | leading `_` |

Booleans read as assertions: `is_fainted`, `has_substitute`, `can_switch`. A
boolean named after a noun is a defect.

### The `Vlt` prefix on engine classes

Classes under `addons/voltari/` declare `class_name` with a **`Vlt` prefix** —
`VltBattleState`, `VltSlotRef`.

Not decoration: `class_name` registers globally in Godot, so an unprefixed engine
class would collide with a game class of the same name, and the engine is meant
to be dropped into future projects. The prefix is confined to `class_name`
declarations; it never appears in file names, member names or local variables.

`class_name` is also the only option available inside the core: referencing a
sibling script otherwise requires `preload`, which the purity rule bars.

Code under `game/` takes no prefix.

### Content identifiers

`snake_case`, stable, and never reused once published — an ID is a permanent
reference from save files and fixtures. Renaming a creature's display name is
free; renaming its ID is a migration.

## 3. Language

English for code, identifiers, file names, commits, comments and documentation.
French for conversation with the maintainer.

---

## Open point

The `Vlt` prefix trades readability for collision safety. It is the conventional
answer for a Godot addon, but it is a taste call and reversing it later is a
repo-wide rename — worth confirming before the first engine class is written.

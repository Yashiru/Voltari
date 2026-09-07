# 0007 — The engine lives in `addons/voltari/`

**Status:** Accepted
**Date:** 2026-09-07

## Context

One game is built in this repository, but the engine must stay reusable for
sequels and spin-offs. That requires a boundary between engine and game that
does not erode as the game grows.

## Decision

The engine lives under `addons/voltari/`, split by layer: `core/` (L0),
`deciders/` (L0bis), `rules/` (L1). Game content and scenes live under `game/`,
YAML sources under `content/`, tests under `tests/`, build and lint tooling under
`tools/`.

`addons/voltari/` is a plain namespaced folder, with no `plugin.cfg` and no
`EditorPlugin` script: the engine is a code library, not an editor extension, and
an empty plugin script would be ceremony with no behaviour.

## Options rejected

- **`engine/` and `game/` at the repository root.** More direct to read, but
  reuse happens by copying a folder, with no boundary the tooling recognises.
- **The engine as a git submodule.** The strictest separation and the cleanest
  reuse across several games, but two repositories to manage and a heavy
  workflow for a solo project at bootstrap stage.

## Consequences

Reuse is a folder copy into a future project, following the convention Godot
users already expect. The purity lint has an obvious, stable target path.

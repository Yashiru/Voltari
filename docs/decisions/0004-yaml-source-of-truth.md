# 0004 — YAML as content source of truth, `.tres` as build artefact

**Status:** Accepted
**Date:** 2026-09-07

## Context

Species, moves, abilities, items, learnsets and encounter tables need a storage
format. The maintainer reviews every change, so diff readability is a
first-order criterion, not a detail.

## Decision

YAML is the only thing edited, reviewed in PR and versioned. A content build
reads the YAML, validates it (schema, stable IDs, resolved references) and
generates `.tres` files for Godot editor integration. Those `.tres` files are
build artefacts: gitignored, regenerated, never hand-edited.

## Options rejected

- **`.tres` as source of truth.** Native to Godot, but hostile to review and
  awkward to validate outside the editor.
- **JSON as source of truth.** Machine-friendly, but noisier to read and it
  carries no comments — and content needs annotation.

## Consequences

The data format never reaches the simulation core: a loader parses it upstream
and injects typed structures (see 0001). The core is therefore indifferent to the
format, and tests build fixtures in memory without touching a file. The content
build is a separate tool, never the engine at runtime.

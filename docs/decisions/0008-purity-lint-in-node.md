# 0008 — The core purity lint is a Node script

**Status:** Accepted
**Date:** 2026-09-07

## Context

The purity rule of 0001 is the foundation the whole test strategy rests on. A
rule enforced only by review decays within weeks, especially on a long project.

## Decision

A Node script, `tools/purity-lint/purity-lint.mjs`, scans `addons/voltari/core/`
and `addons/voltari/rules/` for forbidden engine symbols and fails the build on
any hit. It strips comments and string literals before matching, so a symbol
named in prose or in a message identifier never trips it.

It runs as its own CI job, independent of the Godot job.

## Options rejected

- **A GDScript lint run inside Godot.** Consistent with the codebase language,
  but it only runs where Godot is installed, and it makes the purity check
  depend on the very engine it is meant to keep out.
- **A grep one-liner in CI.** Minimal, but it cannot distinguish code from
  comments and would fire on the documentation describing the rule.
- **Review discipline alone.** The status quo the rule exists to replace.

## Consequences

Node was already required for oracle vector generation (0002), so no new
toolchain enters the project. The lint is fast, runs without Godot, and can be
executed on any machine — including ones where the engine is not installed.

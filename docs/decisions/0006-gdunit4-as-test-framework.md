# 0006 — gdUnit4 as the test framework

**Status:** Accepted
**Date:** 2026-09-07

## Context

The three test pillars of 0005 need a runner: assertions, headless execution and
CI reporting. Two mature options exist for Godot 4, plus the option of writing
our own.

## Decision

gdUnit4, installed as an addon. It is not vendored: CI downloads it, local
development installs it from the Asset Library, and `addons/gdUnit4/` is
gitignored.

## Options rejected

- **GUT.** Older, simpler, widely used, and sufficient for pure computation. Less
  tooling around scene tests and mocking, which the effect system's interaction
  tests are expected to need.
- **An in-house harness.** Zero dependency and fully aligned with the pure core,
  but it means rewriting runner, assertions and CI reporting — effort stolen from
  the actual subject.

## Consequences

A third-party dependency enters the toolchain, though never the shipped engine.
Not vendoring keeps the repository free of thousands of lines of unreviewed code,
at the cost of an install step in CI and on every new machine.

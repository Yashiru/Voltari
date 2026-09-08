# Content

Authored game data, and the only thing in this tree that is edited by hand.

**The schema lives in [spec 09](../docs/specs/09-data-schema.md)**, not here. Field
meanings, ranges and validation rules are documented once, in the specification
the build implements.

## Layout

```
moves/<id>.yaml       one file per entity — the filename IS the identifier
type-chart.yaml       a table, not a collection: one structure, one file
natures.yaml          likewise
generated/            build output, committed, never hand-edited
```

One file per entity because the maintainer reviews every change and diff
readability is a first-order criterion (decisions 0004 and 0025). A file never
repeats its own id: the name is the id, so the two cannot disagree.

## Editing

```bash
npm --prefix tools run content:build
```

Regenerate after every edit and commit the result. CI rebuilds and fails on any
difference, so the source and the payload cannot drift apart unnoticed.

The build reports **every** problem it finds before exiting, so a content pass
fixes ten typos in one go rather than ten times over.

## Identifiers are placeholders

The current ids are **structural placeholders**. Names are part of the game's IP,
they are derived from no reference, and naming them is design work that has not
happened yet. Renaming one is a content edit and touches no engine code.

This starter set exists to exercise the pipeline end to end — one entry per
mechanically distinct shape the engine can currently express, not a roster.

Content carries no display names and no asset paths: those are presentation and
live in L4 (decision 0026).

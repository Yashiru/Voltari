# 0041 — An event is composed, not written and not parsed

**Status:** Accepted
**Date:** 2026-09-09
**Refines:** decision 0004 (YAML as the source of truth)
**Recorded in:** spec 15, sections 1 and 2

## Context

Spec 09 section 6 forbids conditional logic in authored content, in terms that
leave no room: "the first `if` in content is the moment the format became a DSL."

Event scripting is conditional by nature. A dialogue branches, a flag opens a
door, a scene plays only once. So spec 15 either weakens that rule, works around
it, or removes the thing it applies to.

## Decision

**An event is a subtree of typed nodes in the map scene.** Each node does one
thing; the order and nesting are the event. Behaviour is GDScript, in the node.

**Nothing is ever parsed as a language.** The rule of spec 09 is not weakened and
not excepted — it simply has nothing to apply to, because there is no format.

Adding a kind of step writes GDScript. It never widens a schema.

## Options rejected

**A declarative event format in YAML.** Diffable, reviewable, and it would reuse
the content pipeline whole. Rejected because it needs conditions and sequencing,
which is precisely the language spec 09 refused. Choosing it would mean
overturning that decision knowingly, and the reason it was made has not changed:
a format with an `if` in it grows a second one, then a loop, and ends up a
programming language with no debugger and no type checker.

**One GDScript class per event.** No format at all, maximum freedom, and each
event reads as ordinary code.

Rejected on scale rather than on principle. A hundred people is a hundred
near-identical scripts, and a change to how every dialogue closes becomes a
hundred edits — the duplication the code standards call a defect, arrived at by
a route that looks disciplined.

## Consequences

**A dialogue's diff is a scene diff, and unreadable.** This is the second file
class where decision 0004's readability criterion is suspended, after map scenes
(decision 0039). It should be the last, and the same compensation applies: what
review would have caught is caught by validation instead (spec 15, section 7).

Events live where the world lives (decision 0038). A map's people belong to the
map rather than to a parallel file keyed by map id, which is one fewer pair of
things that can disagree.

**The set of node types is the vocabulary.** It grows deliberately, in GDScript,
under review — which makes "what can an event do" a question with an answer that
can be read in one directory.

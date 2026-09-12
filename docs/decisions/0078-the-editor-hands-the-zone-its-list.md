# 0078 — The editor hands the zone its list

**Status:** Accepted
**Date:** 2026-09-12
**Recorded in:** spec 14, section 7

## Context

A zone's `table_id` was a text field. The way to find out it was wrong was to
paint a map, press *Validate maps*, and read `names unknown table "x"` — a good
check, doing its job, catching something that should never have been typeable.

Spec 14 section 7 is explicit that the validator exists for the cross-reference
mistakes a single file cannot see: a warp's destination lives in a different file
from the warp. A table id is not quite that. The ids exist, in one place, and the
editor is already holding them.

## Decision

`table_id` is a menu of the ids the content build produced.

**Strict**, on the maintainer's call: an id outside the list is not offered.

**Display only.** What a scene stores is the same string it always was, and
nothing about the menu writes to it. A zone naming a table that has since been
renamed keeps its id until somebody changes it, and `VltMapValidator` stays the
one thing that says an id is wrong. The menu makes a typo hard; it does not
become a second opinion about correctness.

**The zone does not go and look.** `addons/voltari_maps` already holds the path
to `content/generated/encounters` for the map check, and it hands the ids to the
zone; the zone displays them. One list, read in one call, used by both the check
and the menu — so the inspector cannot offer something the validator then
rejects.

**A plain text field when the list is empty**, which is a clone whose content has
never been built.

## Options rejected

**The zone reads the index itself.** `@tool` and fifteen lines in one file, no
editor involvement at all, and it nearly won on size. Rejected because
`VltEncounterZone` ships with the game: it would put a path into `content/` in a
runtime class — a second copy of a path the editor already holds, which is the
drift decision 0039 is about — and file-reading code into a class whose whole
documented job is that it *names a table and carries nothing else about it*.
`VltContentPayloads` makes the same point about itself: where the game reads
content from is a question for the spec that gives it a home, and answering it
sideways would settle it by accident.

**A full `EditorInspectorPlugin`.** The zone untouched, not even `@tool`, with
the editor replacing the field when it sees one. The cleanest layering available
and about seventy lines with an `EditorProperty` to subclass. Rejected as more
machinery than a dropdown is worth; `@tool` for one `_validate_property` is a
pattern the codebase already has in `turf_patch.gd`.

**Keeping the current value in the menu, marked unknown.** Offered and declined.
It would never lose a saved id to a stale build, at the cost of a menu that
sometimes contains something invalid — which is most of what the menu was for.

## Consequences

**The list is static state on a runtime class**, set by the editor plugin and
cleared when it leaves. Cleared on the way out deliberately: a zone offering a
menu with the plugin disabled would be offering whatever was on disk the last
time it ran.

**It follows a content rebuild without restarting the editor**, because the check
refreshes the list as well as reading it — and the check is what somebody presses
after rebuilding.

**A stale build shows a wrong selection rather than a wrong id.** With a strict
menu, a zone whose table was renamed displays as unselected in the inspector
while keeping its id in the scene. The validator still reports it, which is where
the answer was always going to come from.

class_name VltEventRequest
extends RefCounted

## What an event needs from outside before it can go on (spec 15, section 5).
##
## The same shape as the turn engine's `NeedsInput` (decision 0012): the run
## stops, says what it wants, and is resumed with an answer. Reusing that shape
## rather than reaching for `await` is what keeps an event testable without a
## scene, and what keeps a half-run event from existing while something else is
## awaited.
##
## **The kind is named**, so further kinds are added without changing the API —
## a dialogue choice is one more kind, not a redesign.

enum Kind {
	## Show a line and wait for it to be acknowledged.
	SAY,
}

var kind: Kind = Kind.SAY

## For SAY: the line to show. An id, never text — the text is localisation and
## lives in L4 (spec 15, section 6).
var line_id: String = ""


static func say(line: String) -> VltEventRequest:
	var request: VltEventRequest = VltEventRequest.new()
	request.kind = Kind.SAY
	request.line_id = line
	return request

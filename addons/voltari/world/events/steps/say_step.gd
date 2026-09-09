class_name VltSayStep
extends VltEventStep

## Show a line and wait for it to be acknowledged (spec 15, section 6).
##
## It holds a **line id, never text**. The text is localisation and lives in L4 —
## the rule spec 07 sets for the battle log and spec 09 section 7 sets for
## content, applied a third time. A line written into a scene would make
## translating the game an edit of every map.

@export var line_id: String = ""


func request(_run: VltEventRun) -> VltEventRequest:
	return VltEventRequest.say(line_id)

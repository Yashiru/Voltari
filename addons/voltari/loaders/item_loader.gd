class_name VltItemLoader
extends RefCounted

## Turns built item payloads into what capture reads.
##
## Only balls, and only their multiplier. There is no general item type here
## because there are no general items yet — spec 11 defines the least capture
## needs and no more, and a type invented ahead of its second use would be
## guessing at systems nobody has designed.

const BALL_KIND: String = "ball"


## Ball id to catch multiplier. Items of other kinds are skipped rather than
## refused: they are legitimate content, they simply have nothing to say here.
@warning_ignore_start("unsafe_cast")
static func ball_multipliers(entries: Array) -> Dictionary[String, float]:
	var balls: Dictionary[String, float] = {}

	for entry: Variant in entries:
		var data: Dictionary = entry as Dictionary
		if data["kind"] as String != BALL_KIND:
			continue

		var id: String = data["id"] as String
		assert(not balls.has(id), "duplicate ball id \"%s\"" % id)
		balls[id] = data["catch_multiplier"] as float

	return balls
@warning_ignore_restore("unsafe_cast")

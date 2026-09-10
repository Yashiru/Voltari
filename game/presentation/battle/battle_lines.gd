class_name BattleLines
extends RefCounted

## What an event says, as a translation key and its arguments (spec 17,
## section 5).
##
## The core emits identifiers and nothing else. **This is the single place an
## identifier becomes a sentence** — which is what stops English from spreading
## across hundreds of effects, and what makes translating the game an edit of one
## table.
##
## **One key per situation, never a sentence with a condition in it.** A critical
## hit, a super-effective hit and a resisted hit are three different sentences in
## every language, and stitching them into one string is the moment a language
## file becomes a language — the objection spec 09 raised about content, met
## again here.
##
## An event with nothing to say returns an empty key. Silence is the common case:
## a health bar draining says everything the damage event has to say.

const NONE: String = ""

## Arguments are named, so a translator may reorder them. Positional arguments
## survive exactly one language.
class Line:
	extends RefCounted

	var key: String = NONE
	var arguments: Dictionary[String, String] = {}

	func is_silent() -> bool:
		return key == NONE


## Every key this class can produce, for the meta-test that checks the table has
## them all. Written out rather than derived, because a key built by string
## concatenation at the point of use is a key nothing can enumerate.
const KEYS: Array[String] = [
	"battle.turn_start",
	"battle.move_used",
	"battle.move_failed.missed",
	"battle.move_failed.immune",
	"battle.move_failed.no_target",
	"battle.effectiveness.super",
	"battle.effectiveness.resisted",
	"battle.faint",
	"battle.switch_in",
	"battle.switch_out",
	"battle.heal",
	"battle.stat.rose",
	"battle.stat.rose_sharply",
	"battle.stat.fell",
	"battle.stat.fell_harshly",
	"battle.stat.no_higher",
	"battle.stat.no_lower",
	"battle.capture.shake",
	"battle.capture.caught",
	"battle.capture.broke_free",
]

## Effects and species name themselves. Their keys are these prefixes plus an
## identifier, so they cannot be listed above — the meta-test walks the content
## instead, which is the only thing that knows which ids exist.
const EFFECT_PREFIX: String = "effect."
const SPECIES_PREFIX: String = "species."


static func effect_key(definition_id: String, removed: bool) -> String:
	return "%s%s.%s" % [EFFECT_PREFIX, definition_id, "ended" if removed else "began"]


static func species_key(species_id: String) -> String:
	return SPECIES_PREFIX + species_id


## The line an event says, or a silent one.
##
## `names` maps a slot to what to call whoever is standing there — "Emberling"
## or "the wild Emberling" or "the foe's Emberling". Supplied rather than derived
## because the difference is a matter of whose battle it is, which an event does
## not know.
static func of(event: VltLogEvent, names: Dictionary[String, String]) -> Line:
	if event is VltLogTurnStart:
		return _line("battle.turn_start", {"number": str((event as VltLogTurnStart).number)})

	if event is VltLogMoveUsed:
		var used: VltLogMoveUsed = event as VltLogMoveUsed
		return _line(
			"battle.move_used",
			{"creature": _name(names, used.actor), "move": used.move_id}
		)

	if event is VltLogMoveFailed:
		return _line(_failure(event as VltLogMoveFailed), {})

	if event is VltLogEffectiveness:
		return _effectiveness(event as VltLogEffectiveness, names)

	if event is VltLogFaint:
		return _line(
			"battle.faint", {"creature": _name(names, (event as VltLogFaint).target)}
		)

	if event is VltLogSwitchIn:
		return _line(
			"battle.switch_in", {"creature": _name(names, (event as VltLogSwitchIn).target)}
		)

	if event is VltLogSwitchOut:
		return _line(
			"battle.switch_out", {"creature": _name(names, (event as VltLogSwitchOut).target)}
		)

	if event is VltLogHeal:
		return _line(
			"battle.heal", {"creature": _name(names, (event as VltLogHeal).target)}
		)

	if event is VltLogStatChange:
		return _stat_change(event as VltLogStatChange, names)

	if event is VltLogEffectChanged:
		return _effect(event as VltLogEffectChanged, names)

	if event is VltLogCaptureShake:
		return _line("battle.capture.shake", {})

	if event is VltLogCaptureResult:
		var result: VltLogCaptureResult = event as VltLogCaptureResult
		return _line(
			"battle.capture.caught" if result.captured else "battle.capture.broke_free",
			{"creature": _name(names, result.target)}
		)

	# Damage and a request for input say nothing. A bar draining is the sentence.
	return Line.new()


static func _failure(event: VltLogMoveFailed) -> String:
	match event.reason:
		VltLogMoveFailed.Reason.IMMUNE:
			return "battle.move_failed.immune"
		VltLogMoveFailed.Reason.NO_TARGET:
			return "battle.move_failed.no_target"
		_:
			return "battle.move_failed.missed"


## Neutral says nothing, which is why this is not a table: two of the four cases
## have no sentence at all.
static func _effectiveness(
	event: VltLogEffectiveness, names: Dictionary[String, String]
) -> Line:
	if event.exponent == 0:
		return Line.new()
	var key: String = (
		"battle.effectiveness.super" if event.exponent > 0 else "battle.effectiveness.resisted"
	)
	return _line(key, {"creature": _name(names, event.target)})


## Gen 4 says "rose", "rose sharply" and "won't go higher" — three sentences for
## one event, chosen by how far it moved and whether it moved at all.
static func _stat_change(
	event: VltLogStatChange, names: Dictionary[String, String]
) -> Line:
	var arguments: Dictionary[String, String] = {
		"creature": _name(names, event.target), "stat": str(event.stat)
	}

	if event.delta == 0:
		return _line(
			"battle.stat.no_higher" if event.stage_after > 0 else "battle.stat.no_lower",
			arguments
		)
	if event.delta > 0:
		return _line("battle.stat.rose" if event.delta == 1 else "battle.stat.rose_sharply", arguments)
	return _line("battle.stat.fell" if event.delta == -1 else "battle.stat.fell_harshly", arguments)


## An effect names itself, so its line is keyed on its identifier. A refresh or
## a count-down is not a sentence: only arriving and leaving are.
static func _effect(
	event: VltLogEffectChanged, names: Dictionary[String, String]
) -> Line:
	if event.owner == null:
		return Line.new()
	return _line(
		effect_key(event.definition_id, event.removed),
		{"creature": _name(names, event.owner)}
	)


static func _line(key: String, arguments: Dictionary[String, String]) -> Line:
	var line: Line = Line.new()
	line.key = key
	line.arguments = arguments
	return line


## An unnamed position still reads: a missing name is a content problem, not a
## reason to show nothing at all.
static func _name(names: Dictionary[String, String], at: VltSlotRef) -> String:
	if at == null:
		return "?"
	var seat: String = "%d,%d" % [at.side, at.slot]
	return names.get(seat, "?")

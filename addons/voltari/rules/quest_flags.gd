class_name VltQuestFlags
extends RefCounted

## What the world remembers (spec 15, section 3; decision 0042).
##
## Two kinds and no more: a named boolean for "this happened", a named integer
## for "where this quest stands" and "how many".
##
## The integer exists to stop a quest being encoded as several booleans. Five
## steps as five booleans permits step 4 true with step 2 false — a state nothing
## can describe, nobody will look for, and no event knows how to resume from.
## Advancing a stage backwards is a convention nothing enforces here; being
## *unable to hold two stages at once* is the property that mattered.
##
## Pure: names and values, no engine, no file. It is L1's kind of state, which is
## why it sits here with the party and the inventory rather than with the world
## that reads it.
##
## **Every name it was given is kept**, including ones this build does not
## recognise. That is not a special case in the code — the container holds what
## it was handed — and it is decision 0036's argument one level down: a build
## that has lost a quest must not silently erase the player's progress through
## it.

var _switches: Dictionary[String, bool] = {}
var _counters: Dictionary[String, int] = {}


## Absent reads as false, which is what lets an older save meet a newer build's
## flag: it simply is not there yet (spec 13, section 3).
func is_set(flag: String) -> bool:
	return _switches.get(flag, false)


func raise(flag: String) -> void:
	assert(not flag.is_empty(), "a flag needs a name")
	_switches[flag] = true


func lower(flag: String) -> void:
	assert(not flag.is_empty(), "a flag needs a name")
	_switches[flag] = false


## Absent reads as zero, for the same reason absent booleans read as false.
func count(flag: String) -> int:
	return _counters.get(flag, 0)


func set_count(flag: String, value: int) -> void:
	assert(not flag.is_empty(), "a flag needs a name")
	_counters[flag] = value


func switch_names() -> PackedStringArray:
	return _sorted(_switches.keys())


func counter_names() -> PackedStringArray:
	return _sorted(_counters.keys())


func is_empty() -> bool:
	return _switches.is_empty() and _counters.is_empty()


func clear() -> void:
	_switches.clear()
	_counters.clear()


## Copies another set over this one, leaving names it does not mention alone.
##
## This is how an event's atomic commit lands (decision 0044): the event
## accumulates its changes in a set of its own and merges them in one call, so
## there is no moment where half of them are visible.
func merge(other: VltQuestFlags) -> void:
	for flag: String in other.switch_names():
		_switches[flag] = other.is_set(flag)
	for flag: String in other.counter_names():
		_counters[flag] = other.count(flag)


## Sorted, so a save's contents never depend on insertion order — two identical
## worlds must produce identical documents or the round-trip test compares noise.
static func _sorted(names: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for flag: Variant in names:
		@warning_ignore("unsafe_cast")
		out.append(flag as String)
	out.sort()
	return out

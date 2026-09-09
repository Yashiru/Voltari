class_name VltQuestFlagsSection
extends VltSaveSection

## Quest flags as a save section (spec 15, section 8).
##
## The second application of decision 0040's general rule: **a section belongs
## to its system**. The world's section reads nodes and lives with the world;
## this one reads a dictionary and lives with the flags, in the purity-enforced
## layer.
##
## That the two were written by different systems, at different times, without
## either knowing about the other, is the mechanism of spec 13 working as
## intended rather than a coincidence.

const KEY: String = "quest_flags"
const VERSION: int = 1

const SWITCHES_FIELD: String = "switches"
const COUNTERS_FIELD: String = "counters"

var flags: VltQuestFlags


func _init(held: VltQuestFlags = null) -> void:
	flags = held if held != null else VltQuestFlags.new()


func key() -> String:
	return KEY


func version() -> int:
	return VERSION


func write() -> Dictionary:
	var switches: Dictionary[String, bool] = {}
	for flag: String in flags.switch_names():
		switches[flag] = flags.is_set(flag)

	var counters: Dictionary[String, int] = {}
	for flag: String in flags.counter_names():
		counters[flag] = flags.count(flag)

	return {SWITCHES_FIELD: switches, COUNTERS_FIELD: counters}


## Reads every name the document holds, including ones this build has never
## heard of. Nothing filters against a known list, which is exactly what makes a
## flag survive a build that lost the quest it belonged to (decision 0042).
func read(stored: Dictionary, _stored_version: int) -> void:
	flags.clear()

	var switches: Dictionary = VltSaveSection.read_dictionary(stored, SWITCHES_FIELD)
	for entry: Variant in switches.keys():
		@warning_ignore("unsafe_cast")
		var flag: String = entry as String
		if VltSaveSection.read_bool(switches, flag):
			flags.raise(flag)
		else:
			flags.lower(flag)

	var counters: Dictionary = VltSaveSection.read_dictionary(stored, COUNTERS_FIELD)
	for entry: Variant in counters.keys():
		@warning_ignore("unsafe_cast")
		var flag: String = entry as String
		flags.set_count(flag, VltSaveSection.read_int(counters, flag))

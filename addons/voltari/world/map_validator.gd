class_name VltMapValidator
extends RefCounted

## What a map scene cannot guarantee about itself (spec 14, section 7).
##
## The overworld gives up the strong test pillars (decision 0038), so this is
## the mechanical guard that replaces them — and it checks the one thing a scene
## structurally cannot: **a warp's destination lives in a different file from the
## warp**. No amount of care inside one map catches a door that leads nowhere.
##
## It runs engine-side rather than in the Node content build, because the maps
## are scenes and only Godot can load one. That is the same split spec 09 already
## makes for effect ids, which the build cannot see either.
##
## Every problem is reported, then the caller stops. A map pass fixes ten broken
## warps in one go or ten times over.


## `known_tables` is the ids the content build produced. `entry_map` is where a
## new game begins; leave it empty to skip the reachability check, which has no
## meaning without somewhere to start from. `known_lines` is the localisation
## table; leave it empty to skip the line check, which has nothing to check
## against until a localisation format exists (spec 15, open points).
static func check(
	maps: Array[VltWorldMap],
	known_tables: PackedStringArray,
	entry_map: String = "",
	known_lines: PackedStringArray = PackedStringArray()
) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var by_id: Dictionary[String, VltWorldMap] = {}

	for map: VltWorldMap in maps:
		if map.map_id.is_empty():
			problems.append("a map has no id")
			continue
		if by_id.has(map.map_id):
			# A save holds a map id (decision 0040), so two maps claiming one id
			# means a loaded save can land on either.
			problems.append("two maps claim the id \"%s\"" % map.map_id)
			continue
		by_id[map.map_id] = map

	for map: VltWorldMap in by_id.values():
		problems.append_array(_check_warps(map, by_id))
		problems.append_array(_check_zones(map, known_tables))
		problems.append_array(_check_events(map, known_lines))

	if not entry_map.is_empty():
		problems.append_array(_check_reachable(by_id, entry_map))

	problems.append_array(_check_flags(by_id))
	problems.append_array(_check_recovery(by_id))
	return problems


static func _check_warps(
	map: VltWorldMap, by_id: Dictionary[String, VltWorldMap]
) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var claimed: Dictionary[Vector2i, bool] = {}

	for warp: VltWarp in map.warps():
		var where: String = "map \"%s\", warp at %s" % [map.map_id, warp.cell]

		# A warp on a cell nobody can stand on can never fire, which looks
		# exactly like a warp that is merely hard to reach.
		if not map.is_walkable(warp.cell):
			problems.append("%s: sits on a cell that cannot be stood on" % where)
		if claimed.has(warp.cell):
			problems.append("%s: two warps on one cell" % where)
		claimed[warp.cell] = true

		if not warp.is_complete():
			problems.append("%s: leads nowhere" % where)
			continue
		if not by_id.has(warp.to_map):
			problems.append("%s: leads to unknown map \"%s\"" % [where, warp.to_map])
			continue

		# The check no single map can make on its own.
		var destination: VltWorldMap = by_id[warp.to_map]
		if not destination.is_walkable(warp.to_cell):
			problems.append(
				"%s: arrives at %s on \"%s\", which cannot be stood on"
				% [where, warp.to_cell, warp.to_map]
			)

	return problems


static func _check_zones(map: VltWorldMap, known_tables: PackedStringArray) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var zones: Array[VltEncounterZone] = map.zones()

	for index: int in range(zones.size()):
		var zone: VltEncounterZone = zones[index]
		var where: String = "map \"%s\", zone at %s" % [map.map_id, zone.origin]

		if zone.table_id.is_empty():
			problems.append("%s: names no encounter table" % where)
		elif not known_tables.has(zone.table_id):
			problems.append("%s: names unknown table \"%s\"" % [where, zone.table_id])

		if zone.size.x < 1 or zone.size.y < 1:
			problems.append("%s: covers no cells" % where)
			continue

		# Two tables claiming one cell has no right answer, and picking one
		# silently would be a bias nobody could see.
		for other: int in range(index + 1, zones.size()):
			if _overlap(zone, zones[other]):
				problems.append("%s: overlaps the zone at %s" % [where, zones[other].origin])

	return problems


static func _overlap(one: VltEncounterZone, two: VltEncounterZone) -> bool:
	if two.size.x < 1 or two.size.y < 1:
		return false
	return (
		one.origin.x < two.origin.x + two.size.x
		and two.origin.x < one.origin.x + one.size.x
		and one.origin.y < two.origin.y + two.size.y
		and two.origin.y < one.origin.y + one.size.y
	)


static func _check_events(map: VltWorldMap, known_lines: PackedStringArray) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()

	for event: VltEvent in map.events():
		var where: String = "map \"%s\", event at %s" % [map.map_id, event.cell]

		# An event with no steps has nothing to run, so it fires and appears
		# broken rather than absent.
		if not event.is_complete():
			problems.append("%s: has no steps" % where)

		for step: VltEventStep in steps_in(event):
			var say: VltSayStep = step as VltSayStep
			if say != null:
				if say.line_id.is_empty():
					problems.append("%s: a line with no id" % where)
				elif not known_lines.is_empty() and not known_lines.has(say.line_id):
					problems.append("%s: unknown line \"%s\"" % [where, say.line_id])

			var branch: VltBranchStep = step as VltBranchStep
			if branch != null and not branch.is_complete():
				# Both arms empty means the branch decides nothing, which is
				# either a mistake or a step that should not be there.
				problems.append("%s: a branch with no flag or no arm at all" % where)

			var set_flag: VltSetFlagStep = step as VltSetFlagStep
			if set_flag != null and set_flag.flag.is_empty():
				problems.append("%s: a set-flag step with no flag" % where)

			var set_counter: VltSetCounterStep = step as VltSetCounterStep
			if set_counter != null and set_counter.flag.is_empty():
				problems.append("%s: a set-counter step with no flag" % where)

	return problems


## The check nothing else can make (spec 15, section 7).
##
## A flag name misspelled at one of its two sites reads perfectly, sets
## perfectly, and gates something forever. No test of any single event finds it,
## because each half is correct on its own — only comparing every write against
## every read does.
##
## Both directions are reported. A flag written and never read is usually the
## other half of the same typo.
static func _check_flags(by_id: Dictionary[String, VltWorldMap]) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var written: Dictionary[String, bool] = {}
	var read: Dictionary[String, String] = {}
	var wrote_at: Dictionary[String, String] = {}

	for map: VltWorldMap in by_id.values():
		for event: VltEvent in map.events():
			var where: String = "map \"%s\", event at %s" % [map.map_id, event.cell]

			for step: VltEventStep in steps_in(event):
				var set_flag: VltSetFlagStep = step as VltSetFlagStep
				if set_flag != null and not set_flag.flag.is_empty():
					written[set_flag.flag] = true
					wrote_at[set_flag.flag] = where

				var set_counter: VltSetCounterStep = step as VltSetCounterStep
				if set_counter != null and not set_counter.flag.is_empty():
					written[set_counter.flag] = true
					wrote_at[set_counter.flag] = where

				var branch: VltBranchStep = step as VltBranchStep
				if branch != null and not branch.flag.is_empty():
					read[branch.flag] = where

	for flag: String in read.keys():
		if not written.has(flag):
			problems.append(
				"%s: branches on \"%s\", which nothing ever sets" % [read[flag], flag]
			)

	for flag: String in written.keys():
		if not read.has(flag):
			problems.append("%s: sets \"%s\", which nothing ever reads" % [wrote_at[flag], flag])

	return problems


## Every map has somewhere to be sent back to.
##
## Losing a battle teleports the player to the nearest rest point, so a map with
## none in front of it is content a defeat cannot recover from — the player
## falls and there is nowhere to put them. Nothing else would notice until it
## happened.
static func _check_recovery(by_id: Dictionary[String, VltWorldMap]) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if by_id.is_empty():
		return problems

	var anywhere: bool = false
	for map: VltWorldMap in by_id.values():
		if not VltRestPoint.points_on(map).is_empty():
			anywhere = true
			break

	# No rest point at all is one problem, not one per map. A map pass that
	# printed the same sentence for every room would bury everything else.
	if not anywhere:
		problems.append("no map has a rest point, so a defeat has nowhere to send anybody")
		return problems

	for map_id: String in by_id.keys():
		if VltRestPoint.nearest(by_id, map_id, Vector2i.ZERO) == null:
			problems.append(
				"map \"%s\" can reach no rest point, so a defeat there cannot recover" % map_id
			)

	return problems


## Every step under an event, arms included. Branch arms are children of the
## branch, so a plain walk of the subtree reaches everything an event can run.
static func steps_in(root: Node) -> Array[VltEventStep]:
	var found: Array[VltEventStep] = []
	var pending: Array[Node] = [root]

	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			var step: VltEventStep = child as VltEventStep
			if step != null:
				found.append(step)
			pending.append(child)

	return found


## Maps no warp leads to, walking outward from where a new game begins. An
## unreachable map is content nobody will ever see, and nothing else notices.
static func _check_reachable(
	by_id: Dictionary[String, VltWorldMap], entry_map: String
) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()

	if not by_id.has(entry_map):
		problems.append("the entry map \"%s\" does not exist" % entry_map)
		return problems

	var seen: Dictionary[String, bool] = {entry_map: true}
	var pending: Array[String] = [entry_map]

	while not pending.is_empty():
		var current: String = pending.pop_back()
		for warp: VltWarp in by_id[current].warps():
			if by_id.has(warp.to_map) and not seen.has(warp.to_map):
				seen[warp.to_map] = true
				pending.append(warp.to_map)

	for id: String in by_id.keys():
		if not seen.has(id):
			problems.append("map \"%s\" cannot be reached from \"%s\"" % [id, entry_map])

	return problems

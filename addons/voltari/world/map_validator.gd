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
##
## **Two readings of one run.** `problems` carries where each thing is, so a
## report can be walked to; `check` takes the sentence out of each and is what a
## log and a test want. The second is written in terms of the first, so there is
## no pass over the maps that the other does not make.


## Where a flag was written or read.
##
## The two halves of a flag typo are found in one walk of every event and
## reported after it, so the place each was seen has to be carried across. Three
## parallel dictionaries keyed by flag name would be the alternative, and they
## would be three things to keep in step.
class Site:
	extends RefCounted

	## The sentence's prefix, as the message has always begun.
	var where: String = ""

	## The scene the event is in, and the cell it is on.
	var path: String = ""
	var cell: Vector2i = Vector2i.ZERO


## The problems as sentences, which is what this has always returned.
##
## A projection of `problems` rather than a second pass over the maps: there is
## one implementation of every check, and this is the reading of it that a log, a
## test and a printout want. Nothing here can disagree with the structured form,
## because it *is* the structured form with one field taken.
static func check(
	maps: Array[VltWorldMap],
	known_tables: PackedStringArray,
	entry_map: String = "",
	known_lines: PackedStringArray = PackedStringArray()
) -> PackedStringArray:
	return lines(problems(maps, known_tables, entry_map, known_lines))


## The sentence out of each problem.
##
## Named rather than written out at each of its callers, so that "the text of a
## report" is one thing. A caller that already holds the problems — the dock,
## which needs both readings of the same run — takes this rather than running
## every check a second time.
static func lines(found: Array[VltMapProblem]) -> PackedStringArray:
	var said: PackedStringArray = PackedStringArray()
	for problem: VltMapProblem in found:
		said.append(problem.message)
	return said


## The same problems, each carrying where it is (`VltMapProblem`).
##
## What a report needs to be walked rather than only read. A door painted to
## nowhere was already found; going to look at it still meant opening maps and
## counting cells.
##
## `known_tables` is the ids the content build produced. `entry_map` is where a
## new game begins; leave it empty to skip the reachability check, which has no
## meaning without somewhere to start from. `known_lines` is the localisation
## table; leave it empty to skip the line check, which has nothing to check
## against until a localisation format exists (spec 15, open points).
static func problems(
	maps: Array[VltWorldMap],
	known_tables: PackedStringArray,
	entry_map: String = "",
	known_lines: PackedStringArray = PackedStringArray()
) -> Array[VltMapProblem]:
	var found: Array[VltMapProblem] = []
	var by_id: Dictionary[String, VltWorldMap] = {}

	for map: VltWorldMap in maps:
		if map.map_id.is_empty():
			# No id means no file it can be found by either, so there is nowhere
			# to send a reader — see `VltMapProblem`.
			found.append(VltMapProblem.of("a map has no id", map.scene_file_path))
			continue
		if by_id.has(map.map_id):
			# A save holds a map id (decision 0040), so two maps claiming one id
			# means a loaded save can land on either.
			found.append(VltMapProblem.of(
				"two maps claim the id \"%s\"" % map.map_id, map.scene_file_path
			))
			continue
		found.append_array(_check_filename(map))
		by_id[map.map_id] = map

	for map: VltWorldMap in by_id.values():
		found.append_array(_check_warps(map, by_id))
		found.append_array(_check_zones(map, known_tables))
		found.append_array(_check_events(map, known_lines))

	if not entry_map.is_empty():
		found.append_array(_check_reachable(by_id, entry_map))

	found.append_array(_check_flags(by_id))
	found.append_array(_check_recovery(by_id))
	return found


## The file a map lives in has to be named after its id.
##
## **This is what lets the game find a map without opening it.** The overworld
## lists the folder and takes each filename as an id; the alternative was loading
## and instantiating every map on every startup to ask, which costs the size of
## every map in the folder rather than the count. So the rule is not cosmetic, and
## it is enforced here rather than assumed there.
##
## A map whose id disagrees with its filename is not merely untidy: the game will
## never find it, and a save holding that id (decision 0040) loads into nothing.
##
## Skipped for a map with no file. A fixture built in code is a real map to every
## other check here, and this one is about files.
static func _check_filename(map: VltWorldMap) -> Array[VltMapProblem]:
	var problems: Array[VltMapProblem] = []
	if map.scene_file_path.is_empty():
		return problems

	var named: String = map.scene_file_path.get_file().get_basename()
	if named != map.map_id:
		problems.append(VltMapProblem.of(
			"map \"%s\" is in a file called \"%s\" — the game finds maps by filename, so it will never be found"
			% [map.map_id, named],
			map.scene_file_path
		))
	return problems


static func _check_warps(
	map: VltWorldMap, by_id: Dictionary[String, VltWorldMap]
) -> Array[VltMapProblem]:
	var problems: Array[VltMapProblem] = []
	var claimed: Dictionary[Vector2i, bool] = {}
	var file: String = map.scene_file_path

	for warp: VltWarp in map.warps():
		var where: String = "map \"%s\", warp at %s" % [map.map_id, warp.cell]

		# A warp on a cell nobody can stand on can never fire, which looks
		# exactly like a warp that is merely hard to reach.
		if not map.is_walkable(warp.cell):
			problems.append(VltMapProblem.at(
				"%s: sits on a cell that cannot be stood on" % where, file, warp.cell
			))
		if claimed.has(warp.cell):
			problems.append(VltMapProblem.at("%s: two warps on one cell" % where, file, warp.cell))
		claimed[warp.cell] = true

		if not warp.is_complete():
			problems.append(VltMapProblem.at("%s: leads nowhere" % where, file, warp.cell))
			continue
		if not by_id.has(warp.to_map):
			problems.append(VltMapProblem.at(
				"%s: leads to unknown map \"%s\"" % [where, warp.to_map], file, warp.cell
			))
			continue

		# The check no single map can make on its own.
		#
		# Reported against the warp rather than against where it arrives: the cell
		# that has to change is usually this one, and the destination may be in a
		# file the author is not looking at.
		var destination: VltWorldMap = by_id[warp.to_map]
		if not destination.is_walkable(warp.to_cell):
			problems.append(VltMapProblem.at(
				"%s: arrives at %s on \"%s\", which cannot be stood on"
				% [where, warp.to_cell, warp.to_map],
				file, warp.cell
			))

	return problems


static func _check_zones(
	map: VltWorldMap, known_tables: PackedStringArray
) -> Array[VltMapProblem]:
	var problems: Array[VltMapProblem] = []
	var zones: Array[VltEncounterZone] = map.zones()
	var file: String = map.scene_file_path

	for index: int in range(zones.size()):
		var zone: VltEncounterZone = zones[index]
		var where: String = "map \"%s\", zone at %s" % [map.map_id, zone.origin]

		if zone.table_id.is_empty():
			problems.append(VltMapProblem.at(
				"%s: names no encounter table" % where, file, zone.origin
			))
		elif not known_tables.has(zone.table_id):
			problems.append(VltMapProblem.at(
				"%s: names unknown table \"%s\"" % [where, zone.table_id], file, zone.origin
			))

		if zone.size.x < 1 or zone.size.y < 1:
			problems.append(VltMapProblem.at("%s: covers no cells" % where, file, zone.origin))
			continue

		# Two tables claiming one cell has no right answer, and picking one
		# silently would be a bias nobody could see.
		for other: int in range(index + 1, zones.size()):
			if _overlap(zone, zones[other]):
				problems.append(VltMapProblem.at(
					"%s: overlaps the zone at %s" % [where, zones[other].origin],
					file, zone.origin
				))

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


static func _check_events(
	map: VltWorldMap, known_lines: PackedStringArray
) -> Array[VltMapProblem]:
	var problems: Array[VltMapProblem] = []
	var file: String = map.scene_file_path

	for event: VltEvent in map.events():
		var where: String = "map \"%s\", event at %s" % [map.map_id, event.cell]

		# An event with no steps has nothing to run, so it fires and appears
		# broken rather than absent.
		if not event.is_complete():
			problems.append(VltMapProblem.at("%s: has no steps" % where, file, event.cell))

		for step: VltEventStep in steps_in(event):
			var say: VltSayStep = step as VltSayStep
			if say != null:
				if say.line_id.is_empty():
					problems.append(VltMapProblem.at(
						"%s: a line with no id" % where, file, event.cell
					))
				elif not known_lines.is_empty() and not known_lines.has(say.line_id):
					problems.append(VltMapProblem.at(
						"%s: unknown line \"%s\"" % [where, say.line_id], file, event.cell
					))

			var branch: VltBranchStep = step as VltBranchStep
			if branch != null and not branch.is_complete():
				# Both arms empty means the branch decides nothing, which is
				# either a mistake or a step that should not be there.
				problems.append(VltMapProblem.at(
					"%s: a branch with no flag or no arm at all" % where, file, event.cell
				))

			var set_flag: VltSetFlagStep = step as VltSetFlagStep
			if set_flag != null and set_flag.flag.is_empty():
				problems.append(VltMapProblem.at(
					"%s: a set-flag step with no flag" % where, file, event.cell
				))

			var set_counter: VltSetCounterStep = step as VltSetCounterStep
			if set_counter != null and set_counter.flag.is_empty():
				problems.append(VltMapProblem.at(
					"%s: a set-counter step with no flag" % where, file, event.cell
				))

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
static func _check_flags(by_id: Dictionary[String, VltWorldMap]) -> Array[VltMapProblem]:
	var problems: Array[VltMapProblem] = []
	var read: Dictionary[String, Site] = {}
	var written: Dictionary[String, Site] = {}

	for map: VltWorldMap in by_id.values():
		for event: VltEvent in map.events():
			var site: Site = Site.new()
			site.where = "map \"%s\", event at %s" % [map.map_id, event.cell]
			site.path = map.scene_file_path
			site.cell = event.cell

			for step: VltEventStep in steps_in(event):
				var set_flag: VltSetFlagStep = step as VltSetFlagStep
				if set_flag != null and not set_flag.flag.is_empty():
					written[set_flag.flag] = site

				var set_counter: VltSetCounterStep = step as VltSetCounterStep
				if set_counter != null and not set_counter.flag.is_empty():
					written[set_counter.flag] = site

				var branch: VltBranchStep = step as VltBranchStep
				if branch != null and not branch.flag.is_empty():
					read[branch.flag] = site

	for flag: String in read.keys():
		if not written.has(flag):
			var site: Site = read[flag]
			problems.append(VltMapProblem.at(
				"%s: branches on \"%s\", which nothing ever sets" % [site.where, flag],
				site.path, site.cell
			))

	for flag: String in written.keys():
		if not read.has(flag):
			var site: Site = written[flag]
			problems.append(VltMapProblem.at(
				"%s: sets \"%s\", which nothing ever reads" % [site.where, flag],
				site.path, site.cell
			))

	return problems


## Every map has somewhere to be sent back to.
##
## Losing a battle teleports the player to the nearest rest point, so a map with
## none in front of it is content a defeat cannot recover from — the player
## falls and there is nowhere to put them. Nothing else would notice until it
## happened.
static func _check_recovery(by_id: Dictionary[String, VltWorldMap]) -> Array[VltMapProblem]:
	var problems: Array[VltMapProblem] = []
	if by_id.is_empty():
		return problems

	var anywhere: bool = false
	for map: VltWorldMap in by_id.values():
		if not VltRestPoint.points_on(map).is_empty():
			anywhere = true
			break

	# No rest point at all is one problem, not one per map. A map pass that
	# printed the same sentence for every room would bury everything else.
	#
	# It is also the one problem with nowhere to send a reader: it is about the
	# world rather than about a file, and opening any one map would be a guess.
	if not anywhere:
		problems.append(VltMapProblem.of(
			"no map has a rest point, so a defeat has nowhere to send anybody"
		))
		return problems

	for map_id: String in by_id.keys():
		if VltRestPoint.nearest(by_id, map_id, Vector2i.ZERO) == null:
			problems.append(VltMapProblem.of(
				"map \"%s\" can reach no rest point, so a defeat there cannot recover" % map_id,
				by_id[map_id].scene_file_path
			))

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
) -> Array[VltMapProblem]:
	var problems: Array[VltMapProblem] = []

	if not by_id.has(entry_map):
		# Named but absent: there is no file to open, because that is the problem.
		problems.append(VltMapProblem.of("the entry map \"%s\" does not exist" % entry_map))
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
			problems.append(VltMapProblem.of(
				"map \"%s\" cannot be reached from \"%s\"" % [id, entry_map],
				by_id[id].scene_file_path
			))

	return problems

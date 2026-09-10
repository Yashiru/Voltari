class_name WorldSandbox
extends Node3D

## Somewhere to walk (specs 14, 15 and 18).
##
## The scene that assembles what the tests have been proving in pieces: a map, a
## walker, the quantiser, encounters, events, flags and a save. Every part of it
## already had tests; none of them had a place to meet.
##
## Rough on purpose, like the battle screen. Nothing here is a camera direction
## or a HUD design, and its replacement should be a deletion.

const MAPS: Dictionary[String, String] = {
	"starter_field": "res://game/maps/starter_field.tscn",
	"starter_cave": "res://game/maps/starter_cave.tscn",
}

const START_MAP: String = "starter_field"
const START_CELL: Vector2i = Vector2i(1, 1)
const SAVE_PATH: String = "user://sandbox.json"

## How long one cell takes. The pace lives here, the way it lives in the battle
## stage — nothing below has an opinion about it.
const STEP_SECONDS: float = 0.16
const CELL: float = 2.0

var _tables: Dictionary[String, VltEncounterTable] = {}
var _species: Dictionary[String, VltSpecies] = {}
var _flags: VltQuestFlags = VltQuestFlags.new()
var _encounters: VltSeededEncounterDecider

var _map: VltWorldMap = null
var _walker: VltGridWalker
var _held: VltStepIntent.Held = VltStepIntent.Held.new()
var _cooldown: float = 0.0

var _run: VltEventRun = null
var _message: Label
var _hint: Label
var _stick: TouchStick
var _camera: Camera3D
var _body: Node3D


func _ready() -> void:
	var library: ContentLibrary = ContentLibrary.load_all()
	_species = library.species
	_tables = VltEncounterTableLoader.all_from_payload(
		VltContentPayloads.read_indexed("res://content/generated/encounters")
	)
	_encounters = VltSeededEncounterDecider.new(int(Time.get_unix_time_from_system()))

	_build_interface()
	_enter(START_MAP, START_CELL, VltFacing.Direction.SOUTH)
	_load_if_present()


## Where the walker is standing, and on which map. The way in for anything
## outside — a scene above, or a test.
func cell() -> Vector2i:
	return _walker.cell


func map_id() -> String:
	return "" if _map == null else _map.map_id


func flags() -> VltQuestFlags:
	return _flags


## True while an event is playing, which is when nothing else may happen.
func in_event() -> bool:
	return _run != null


## One step, bypassing the stick. Public because driving the world from outside
## is what a sandbox is for.
func walk(direction: VltFacing.Direction) -> void:
	_step(direction)


## Turn without moving — what a flick does, and what you do before reading a
## sign you cannot walk into.
func face(direction: VltFacing.Direction) -> void:
	_walker.facing = direction


func interact() -> void:
	_interact()


func save_now() -> void:
	_save()


func load_now() -> void:
	_load_if_present()


# --- walking -----------------------------------------------------------------


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)

	if _run != null:
		_advance_event()
		return

	var stick: Vector2 = _stick.stick()
	if not _stick.is_held():
		stick = VltStepIntent.from_keys(
			Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W),
			Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S),
			Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D),
			Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
		)

	var intent: VltStepIntent.Step = VltStepIntent.of(stick, _held, delta)
	if not intent.wanted:
		return

	# A flick turns without moving, which is how you face a sign you are about
	# to read.
	_walker.facing = intent.direction
	if intent.walk and _cooldown <= 0.0:
		_step(intent.direction)


func _step(direction: VltFacing.Direction) -> void:
	var step: VltGridWalker.Step = _walker.step(direction)
	_cooldown = STEP_SECONDS
	_place_body()

	if step.warp != null:
		_enter(step.warp.to_map, step.warp.to_cell, step.warp.to_facing)
		return
	if step.event != null:
		_begin(step.event)
		return
	if step.encounter != null:
		_message.text = "A wild %s appeared! (level %d)" % [
			tr(BattleLines.species_key(step.encounter.species_id)), step.encounter.level
		]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return

	match (event as InputEventKey).keycode:
		KEY_SPACE, KEY_ENTER:
			if _run == null:
				_interact()
		KEY_F5:
			_save()
		KEY_F9:
			_load_if_present()


func _interact() -> void:
	var event: VltEvent = _walker.interact()
	if event == null:
		_message.text = "Nothing there."
		return
	_begin(event)


# --- events ------------------------------------------------------------------


func _begin(event: VltEvent) -> void:
	_run = VltEventRun.of(event, _flags)
	_advance_event()


## One event at a time, advanced by a key. The run suspends rather than awaiting
## (decision 0044), so driving it is a loop and not a coroutine.
func _advance_event() -> void:
	_run.advance()

	if _run.is_finished():
		_run = null
		_hint.text = _controls()
		return

	var request: VltEventRequest = _run.request()
	if request == null:
		return
	_message.text = tr(request.line_id)
	_hint.text = "space to continue"

	if Input.is_action_just_pressed("ui_accept"):
		_run.resume()


# --- maps --------------------------------------------------------------------


func _enter(into: String, at: Vector2i, facing: VltFacing.Direction) -> void:
	if _map != null:
		_map.queue_free()

	var packed: PackedScene = load(MAPS[into])
	_map = packed.instantiate() as VltWorldMap
	add_child(_map)

	_walker.map = _map
	_walker.place(at, facing)
	_place_body()
	_message.text = into

	# Arriving on a map is one of the three moments an event may fire
	# (decision 0043).
	var arrival: VltEvent = _map.event_at(at, VltEvent.Trigger.ENTER_MAP)
	if arrival != null:
		_begin(arrival)


func _place_body() -> void:
	var where: Vector3 = Vector3(float(_walker.cell.x) * CELL, 0.8, float(_walker.cell.y) * CELL)
	_body.position = where
	_camera.position = where + Vector3(0, 9, 7)
	_camera.look_at(where)


# --- the save ----------------------------------------------------------------
#
# Two sections, written by two systems that know nothing about each other, into
# one document (spec 13, section 2). This is the first place both exist at once.


func _sections() -> Array[VltSaveSection]:
	var where: VltWorldSaveSection = VltWorldSaveSection.new(_walker)
	var quest: VltQuestFlagsSection = VltQuestFlagsSection.new(_flags)
	var both: Array[VltSaveSection] = [where, quest]
	return both


func _save() -> void:
	var written: bool = VltSaveStore.write(SAVE_PATH, VltSaveCodec.write(_sections()))
	_message.text = "Saved." if written else "Could not save."


func _load_if_present() -> void:
	if not VltSaveStore.exists(SAVE_PATH):
		return

	var where: VltWorldSaveSection = VltWorldSaveSection.new()
	var quest: VltQuestFlagsSection = VltQuestFlagsSection.new(_flags)
	var sections: Array[VltSaveSection] = [where, quest]
	var report: VltSaveCodec.Report = VltSaveCodec.read(
		VltSaveStore.read(SAVE_PATH), sections
	)

	if not MAPS.has(where.map_id):
		_message.text = "Saved on a map this build does not have."
		return

	_enter(where.map_id, where.cell, where.facing)
	_message.text = "Loaded." if report.complete() else "Loaded what could be read."


## On a phone this is the ordinary way a session ends. Writing is refused while
## an event is running, which is decision 0044 arriving where it matters: a
## half-run event has set no flags, and saving now would record a world it
## cannot resume.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_PAUSED and what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _run != null or _walker == null:
		return
	VltSaveStore.write(SAVE_PATH, VltSaveCodec.write(_sections()))


# --- what it looks like ------------------------------------------------------


func _build_interface() -> void:
	_camera = Camera3D.new()
	add_child(_camera)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)

	_walker = VltGridWalker.new()
	_walker.tables = _tables
	_walker.encounter_decider = _encounters
	add_child(_walker)

	_body = MeshInstance3D.new()
	var pill: CapsuleMesh = CapsuleMesh.new()
	pill.radius = 0.4
	pill.height = 1.6
	(_body as MeshInstance3D).mesh = pill
	add_child(_body)

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	_message = Label.new()
	_message.position = Vector2(24, 24)
	_message.add_theme_font_size_override("font_size", 24)
	layer.add_child(_message)

	_hint = Label.new()
	_hint.position = Vector2(24, 60)
	_hint.text = _controls()
	layer.add_child(_hint)

	_stick = TouchStick.new()
	_stick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(_stick)


static func _controls() -> String:
	return "arrows or drag to walk  ·  space to interact  ·  F5 save  ·  F9 load"

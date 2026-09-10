class_name CreatureBody
extends Node3D

## One creature, on screen (spec 16, section 1).
##
## It instances what a manifest names, sizes it to the height the manifest
## declares, and plays clips by slot. Everything it needs to know about a model
## is in the manifest; everything it needs to know about which clip is in the
## vocabulary. It knows nothing about either's contents.
##
## **It is never still.** A clip that ends hands back to the idle, which repeats
## itself for as long as nothing else is asked for. A creature frozen in its rest
## pose between attacks is the thing that makes a battle look broken, and it is
## what this did before.
##
## **A missing model is not an error here.** The placeholder models live on one
## machine (decision 0027), so a clone has manifests naming scenes it has not
## got — and a battle that refused to draw would be a battle nobody else could
## run. It shows a shape instead, and says so once.

## What stands in when there is no model. Deliberately not creature-shaped:
## something obviously a placeholder is better than something that could be
## mistaken for art nobody finished.
const STAND_IN_RADIUS: float = 0.45
const STAND_IN_HEIGHT: float = 1.6

## The slot that plays when nothing else is.
const IDLE: String = "idle"

## How often the idle reaches past its first take, when a creature has more than
## one. Every repeat would make a creature twitchy; never would make the extra
## takes decoration nobody sees (decision 0055).
const VARIANT_IN: int = 4

var _entry: PresentationEntry = null
var _player: AnimationPlayer = null
var _shown: Node3D = null

## Cosmetic only, and its own source on purpose: the battle's randomness is a
## vocabulary of named questions (decision 0010) and "which breath does it take"
## is not one of them. Mixing them would let a screen's animation change what a
## battle does.
var _flourish: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_flourish.randomize()


## Shows a species, replacing whatever was here. Returns whether a real model
## was found, so a caller that wants to report the difference can.
func show_creature(entry: PresentationEntry) -> bool:
	_clear()
	_entry = entry

	var found: bool = false
	if entry != null and ResourceLoader.exists(entry.scene_path):
		var packed: PackedScene = load(entry.scene_path)
		if packed != null:
			_shown = packed.instantiate() as Node3D
			if _shown != null:
				add_child(_shown)
				_player = _player_under(_shown)
				_resize(entry.height)
				found = true

	if not found:
		_shown = _stand_in()
		add_child(_shown)

	# Straight into the idle. A creature only ever plays its entry clip on a
	# switch, so waiting for one would leave whoever opened the battle standing
	# in a rest pose until it was hit.
	_idle()
	return found


## Plays the clip a slot names, and returns how long it runs.
##
## The length is the caller's pacing: a stage that waited a fixed time would run
## the next thing over the top of a long attack and leave a gap after a short
## one. That gap is what makes a hit look late.
##
## Silence is an ordinary answer, not a failure: a manifest may declare a
## fallback, a model may be a stand-in, and a slot the vocabulary has may be one
## this creature never earned. It returns zero, and the caller decides what zero
## is worth.
func play(slot: String) -> float:
	if _player == null or _entry == null:
		return 0.0

	var take: String = _take_for(slot)
	if take.is_empty():
		return 0.0

	_player.play(take)
	return _player.current_animation_length


func has_model() -> bool:
	return _player != null


## Which clip is running, or empty. For a caller that needs to see what a screen
## is doing — which, without a display, is only ever a test.
func playing() -> String:
	return "" if _player == null else String(_player.current_animation)


func is_animating() -> bool:
	return _player != null and _player.is_playing()


## How tall the creature is drawn, after being sized to its manifest.
func shown_height() -> float:
	if _shown == null:
		return 0.0
	return _height_of(_shown) * _shown.scale.y


## Hands back to the idle, as the end of a clip does.
##
## Public because the end of a clip is a signal, and a headless test has no
## frames to wait for one in — so the same door the signal comes through is left
## open rather than a second path being written for tests.
func finished_playing() -> void:
	_idle()


# --- being alive -------------------------------------------------------------


## Starts the idle, if this creature has one.
func _idle() -> void:
	if _player == null:
		return
	var take: String = _take_for(IDLE)
	if take.is_empty():
		return
	_player.play(take)


## Every clip hands back to the idle, and the idle hands back to itself — which
## is what loops it, and what lets each repeat be a different take without any
## of this knowing that a loop is what it is doing.
func _on_finished(_which: StringName) -> void:
	_idle()


## Which take of a slot to play.
##
## The first one, mostly. A creature with several takes for a slot reaches past
## the first now and then, which is what stops an idle reading as a loop
## (decision 0055). Everything else in the vocabulary has one take in practice,
## so this only ever varies the breathing.
func _take_for(slot: String) -> String:
	if _entry == null:
		return ""

	var takes: PackedStringArray = _entry.takes_for(slot)
	if takes.is_empty():
		return ""

	var chosen: String = takes[0]
	if takes.size() > 1 and _flourish.randi_range(0, VARIANT_IN - 1) == 0:
		chosen = takes[_flourish.randi_range(1, takes.size() - 1)]

	return chosen if _player.has_animation(chosen) else ""


## Scales the model to the height the manifest declares.
##
## The field was loaded, documented and read by nobody, so a creature drawn at
## whatever its exporter happened to produce — half a metre against a metre and a
## half — made framing a battle impossible. A model with no mesh is left alone
## rather than divided by zero.
func _resize(height: float) -> void:
	if _shown == null or height <= 0.0:
		return

	var tall: float = _height_of(_shown)
	if tall <= 0.0:
		return
	_shown.scale = Vector3.ONE * (height / tall)


static func _height_of(node: Node) -> float:
	var tallest: float = 0.0
	for found: MeshInstance3D in _meshes_under(node):
		tallest = maxf(tallest, found.mesh.get_aabb().size.y)
	return tallest


static func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		found.append(mesh)
	for child: Node in node.get_children():
		found.append_array(_meshes_under(child))
	return found


func _clear() -> void:
	if _player != null and _player.animation_finished.is_connected(_on_finished):
		_player.animation_finished.disconnect(_on_finished)
	if _shown != null:
		_shown.queue_free()
	_shown = null
	_player = null


func _player_under(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			var player: AnimationPlayer = child as AnimationPlayer
			player.animation_finished.connect(_on_finished)
			return player
		var deeper: AnimationPlayer = _player_under(child)
		if deeper != null:
			return deeper
	return null


static func _stand_in() -> Node3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var shape: CapsuleMesh = CapsuleMesh.new()
	shape.radius = STAND_IN_RADIUS
	shape.height = STAND_IN_HEIGHT
	mesh.mesh = shape
	mesh.position = Vector3(0, STAND_IN_HEIGHT * 0.5, 0)
	return mesh

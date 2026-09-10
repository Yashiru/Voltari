class_name CreatureBody
extends Node3D

## One creature, on screen (spec 16, section 1).
##
## It instances what a manifest names and plays clips by slot. Everything it
## needs to know about a model is in the manifest; everything it needs to know
## about which clip is in the vocabulary. It knows nothing about either's
## contents.
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

var _entry: PresentationEntry = null
var _player: AnimationPlayer = null
var _shown: Node3D = null


## Shows a species, replacing whatever was here. Returns whether a real model
## was found, so a caller that wants to report the difference can.
func show_creature(entry: PresentationEntry) -> bool:
	_clear()
	_entry = entry

	if entry != null and ResourceLoader.exists(entry.scene_path):
		var packed: PackedScene = load(entry.scene_path)
		if packed != null:
			_shown = packed.instantiate() as Node3D
			if _shown != null:
				add_child(_shown)
				_player = _player_under(_shown)
				return true

	_shown = _stand_in()
	add_child(_shown)
	return false


## Plays the clip a slot names, if this creature has one.
##
## Silence is the ordinary answer, not a failure: a manifest may declare a
## fallback, a model may be a stand-in, and a slot the vocabulary has may be one
## this creature never earned.
func play(slot: String) -> void:
	if _player == null or _entry == null:
		return

	var takes: PackedStringArray = _entry.takes_for(slot)
	if takes.is_empty():
		return

	# The first take, every time. Spec 16 leaves the choice open — at random, in
	# rotation, or weighted — and picking randomly here would make a screen
	# irreproducible before anybody had decided it should be.
	var take: String = takes[0]
	if _player.has_animation(take):
		_player.play(take)


func has_model() -> bool:
	return _player != null


func _clear() -> void:
	if _shown != null:
		_shown.queue_free()
	_shown = null
	_player = null


static func _player_under(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
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

class_name TouchStick
extends Control

## A floating stick (spec 18, section 2).
##
## Touch anywhere in this control and the stick appears under the finger;
## dragging gives a vector. It produces **only a vector** — the quantiser turns
## that into a direction, and this knows nothing about the grid.
##
## It also serves the mouse, which is what lets it be exercised on a desktop
## rather than only on a phone.

## How far from the origin counts as fully pushed.
const RADIUS: float = 90.0

var _touching: int = -1
var _origin: Vector2 = Vector2.ZERO
var _vector: Vector2 = Vector2.ZERO


## The push, as a vector no longer than one.
func stick() -> Vector2:
	return _vector


func is_held() -> bool:
	return _touching != -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		_begin_or_end(touch.pressed, touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touching:
			_drag_to(drag.position)
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT:
			_begin_or_end(click.pressed, 0, click.position)
	elif event is InputEventMouseMotion and _touching == 0:
		_drag_to((event as InputEventMouseMotion).position)


## The stick appears where the finger landed rather than at a fixed place. That
## is the whole difference from a d-pad: the control comes to the thumb.
func _begin_or_end(pressed: bool, index: int, at: Vector2) -> void:
	if pressed:
		if _touching != -1:
			return
		_touching = index
		_origin = at
		_vector = Vector2.ZERO
		return

	if index != _touching:
		return
	_touching = -1
	_vector = Vector2.ZERO
	queue_redraw()


func _drag_to(at: Vector2) -> void:
	_vector = (at - _origin) / RADIUS
	if _vector.length() > 1.0:
		_vector = _vector.normalized()
	queue_redraw()


## Drawn only while held, because a stick that is always visible is a d-pad
## wearing a circle.
func _draw() -> void:
	if _touching == -1:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.12))
	draw_circle(_origin + _vector * RADIUS, RADIUS * 0.35, Color(1, 1, 1, 0.35))

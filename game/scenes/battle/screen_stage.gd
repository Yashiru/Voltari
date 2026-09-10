class_name BattleScreenStage
extends BattleStage

## A stage that draws (spec 17, section 2).
##
## The counterpart of the recorder the tests use. It holds every number about
## how long things take, because the reader holds none — pacing lives in one
## place and can be tuned without touching a rule.
##
## Deliberately plain. Nothing here is an art direction: it is the least thing
## that lets a battle be watched, and it should be easy to throw away.

const STEP: float = 0.45
const LINE_HOLD: float = 0.8
const BAR_SPEED: float = 60.0

var _tree: SceneTree
var _message: Label
var _bars: Dictionary[String, ProgressBar] = {}
var _titles: Dictionary[String, Label] = {}
var _bodies: Dictionary[String, Node3D] = {}

## Held down to skip. The reader never asks — it always awaits, and this is what
## makes the awaiting take no time (decision 0050).
var skip: bool = false


func _init(tree: SceneTree, message: Label) -> void:
	_tree = tree
	_message = message


## Wires one position to the nodes that show it. Called once per slot at setup.
func seat(at: VltSlotRef, title: Label, bar: ProgressBar, body: Node3D) -> void:
	var key: String = _key(at)
	_titles[key] = title
	_bars[key] = bar
	_bodies[key] = body


func skipping() -> bool:
	return skip


func play(at: VltSlotRef, slot: String) -> void:
	var body: Node3D = _bodies.get(_key(at))
	if body != null:
		_animate(body, slot)
	await _pause(STEP)


func say(line: BattleLines.Line) -> void:
	_message.text = _sentence(line)
	await _pause(LINE_HOLD)


func refresh(view: VltBattleView) -> void:
	for row: Array[VltBattleView.Combatant] in [view.mine, view.theirs]:
		for seat_at: VltBattleView.Combatant in row:
			_draw(seat_at)
	await _pause(STEP * 0.5)


## The sentence a line becomes. Arguments are named, so a translation may put
## them in any order — which is the whole reason they are not positional.
func _sentence(line: BattleLines.Line) -> String:
	var text: String = tr(line.key)
	for name: String in line.arguments:
		text = text.replace("{%s}" % name, line.arguments[name])
	return text


func _draw(seat_at: VltBattleView.Combatant) -> void:
	var key: String = _key(seat_at.reference)
	if not _titles.has(key):
		return

	var title: Label = _titles[key]
	var bar: ProgressBar = _bars[key]
	var body: Node3D = _bodies.get(key)

	if not seat_at.present:
		title.text = ""
		bar.value = 0
		if body != null:
			body.visible = false
		return

	if body != null:
		body.visible = true

	# Exact for your own side, a proportion for the other — which is the filter
	# of decision 0017 arriving on screen without the screen knowing about it.
	var health: String = (
		"%d/%d" % [seat_at.current_hp, seat_at.max_hp]
		if seat_at.knows_exact_health()
		else "%d%%" % seat_at.health
	)
	var status: String = "" if seat_at.status_id.is_empty() else "  [%s]" % seat_at.status_id
	title.text = "%s  Lv %d  %s%s" % [
		tr(BattleLines.species_key(seat_at.species_id)), seat_at.level, health, status
	]
	bar.value = seat_at.health


## Plays a clip if the creature has one under that name. A body with no
## animation is the common case while the roster is placeholders, and it must
## not stop a battle.
static func _animate(body: Node3D, slot: String) -> void:
	var player: AnimationPlayer = null
	for child: Node in body.get_children():
		if child is AnimationPlayer:
			player = child as AnimationPlayer

	if player != null and player.has_animation(slot):
		player.play(slot)


## The one place time passes. Skipping returns instantly, which is why the
## reader has no branch of its own.
func _pause(seconds: float) -> void:
	if skip:
		return
	await _tree.create_timer(seconds).timeout


static func _key(at: VltSlotRef) -> String:
	return "?" if at == null else "%d,%d" % [at.side, at.slot]

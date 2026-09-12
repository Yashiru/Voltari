class_name TurfTreading
extends RefCounted

## Tells the turf where somebody has put their weight.
##
## The shader holds no state: it is handed a list of places, how long ago each was
## stood on and how wide each press is, and it lays over whatever is still down.
## Everything with a past is here, and there is not much of it — a press is a
## position and an age, and once it has recovered its slot goes back.
##
## **Nothing accumulates and nothing is recorded.** A contact that has finished
## recovering is gone, so what this holds is never a history of where anybody has
## walked — it is the handful of presses that are still visible. That is the same
## promise `turf_patch.gd` makes about geometry, kept for the same reason.
##
## The counterpart for the tall tufts is `GrassField`, and the two are deliberately
## **not** one thing: a tuft jostles without changing shape (decision 0060) and
## turf is laid over. Decision 0076 records why one mechanism cannot serve both.
##
## It knows nothing about the grid, about cells, or about who is walking. A caller
## hands over a world position and a radius; a press is as wide as whatever made it
## says it is.

## The name of every uniform this writes. The array's size is fixed in
## `turf_scatter.gdshader` and `MOST_CONTACTS` must equal it: a shader array cannot
## be sized at run time, so this is the one number that has to be written twice.
const CONTACTS: String = "contacts"
const COUNT: String = "contact_count"
const SECONDS: String = "recover_seconds"
const STRENGTH: String = "press_strength"

## How many presses may be visible at once.
##
## **Not a limit on actors.** It is a limit on how many presses are recovering at
## the same moment, which at one press every fifteen centimetres is about two
## seconds of one person walking. Past it the oldest is forgotten first — the one
## that has recovered furthest and is therefore the least visible thing to lose.
const MOST_CONTACTS: int = 32

## How long a blade takes to stand back up, in seconds.
##
## **Held here as well as in the shader**, because this is what decides a contact
## has stopped mattering and can have its slot back, and the shader is what draws
## the curve. Two places that both know it are two places that disagree the first
## time one is tuned, so it is pushed rather than left to the shader's default.
const RECOVER_SECONDS: float = 1.1

## How far somebody moves before they press the grass again, as a share of their
## own radius.
##
## **Measured against the radius rather than against a clock**, so a walk and a run
## leave the same footprints instead of a sprint leaving a dotted line. Under about
## half and a slow walk fills every slot without covering any ground; over one and
## the presses stop touching and the trail comes apart.
const SPACING_OF_A_RADIUS: float = 0.75

var _materials: Array[ShaderMaterial] = []

## The live presses, oldest first, packed against the front of a fixed-size array.
##
## Packed because the shader loops up to `_live` and not over the whole array: a
## still player costs it one iteration. Whatever sits past `_live` is last frame's
## rubbish and is never read.
var _contacts: PackedVector4Array = PackedVector4Array()
var _live: int = 0

## Where each actor last pressed the grass, so the next press can be spaced against
## it. Keyed by whatever the caller uses to mean "the same feet as last frame".
var _last: Dictionary[int, Vector2] = {}
var _strength: float = 1.0


func _init() -> void:
	_contacts.resize(MOST_CONTACTS)


## Collects the scatter materials of the patches on a map. Safe to call again — a
## warp changes the map, and the patches with it.
func of_patches(patches: Array[TurfPatch]) -> void:
	_materials = []
	for patch: TurfPatch in patches:
		if patch == null:
			continue
		var material: ShaderMaterial = patch.scatter_material()
		if material != null and not _materials.has(material):
			_materials.append(material)
	_push()


## Every `TurfPatch` under a node, at whatever depth.
##
## A patch is a child of the map it was sown on, but nothing promises it is a
## direct one — the map dock groups what it sows. Static because a caller with a
## map in hand should not have to build one of these to ask.
static func patches_under(root: Node) -> Array[TurfPatch]:
	var found: Array[TurfPatch] = []
	if root == null:
		return found
	if root is TurfPatch:
		found.append(root as TurfPatch)
	for child: Node in root.get_children():
		found.append_array(patches_under(child))
	return found


## Somebody is standing here, this wide.
##
## Called every frame for every actor that touches the ground. Most of those calls
## do nothing: a press is dropped only once the actor has moved `SPACING_OF_A_RADIUS`
## of its own radius since its last one, so standing still leaves one press rather
## than one a frame.
##
## `who` only has to be stable for one actor across frames. It is never read for
## anything but spacing, and an actor nobody has seen before presses immediately.
func stand(who: int, where: Vector3, radius: float) -> void:
	if not where.is_finite() or radius <= 0.0:
		return

	var on_ground: Vector2 = Vector2(where.x, where.z)
	if _last.has(who):
		var moved: float = on_ground.distance_to(_last[who])
		if moved < radius * SPACING_OF_A_RADIUS:
			return

	_last[who] = on_ground
	if _live >= MOST_CONTACTS:
		_forget_oldest()
	_contacts[_live] = Vector4(on_ground.x, on_ground.y, 0.0, radius)
	_live += 1
	_push()


## Somebody is no longer standing anywhere — they left, or they are in a battle.
##
## Their presses stay and recover normally; what goes is the memory of where they
## last pressed, so returning does not have to walk a whole radius before the grass
## reacts again.
func lift(who: int) -> void:
	@warning_ignore("return_value_discarded")
	_last.erase(who)


## Ages every press by a frame and gives back the slots of the ones that are over.
##
## Stops writing once nothing is down: a player standing in a bare field costs one
## comparison a frame and no uniform writes at all.
func advance(delta: float) -> void:
	if delta <= 0.0 or _live == 0:
		return

	for index: int in _live:
		var one: Vector4 = _contacts[index]
		one.z += delta
		_contacts[index] = one

	# Every press ages by the same amount and the front is the oldest, so what has
	# recovered is always a run at the front. That is the whole reason they are kept
	# in order rather than in a ring: expiry is a loop that stops, not a scan.
	while _live > 0 and _contacts[0].z >= RECOVER_SECONDS:
		_forget_oldest()

	_push()


## Drops the oldest press and closes the gap it leaves.
##
## A shift of at most thirty-two vectors, which is cheaper than the bookkeeping a
## ring buffer would need to keep the live presses contiguous for the shader.
func _forget_oldest() -> void:
	if _live <= 0:
		return
	for index: int in range(1, _live):
		_contacts[index - 1] = _contacts[index]
	_live -= 1


## Whether any grass is still down because of somebody. The only question a caller
## can usefully ask.
func settling() -> bool:
	return _live > 0


## Nothing is pressed, and nobody has stood anywhere.
##
## What a warp and a defeat need: a press left over from the map you came from
## would flatten grass on this one that nobody has walked on.
func quiet() -> void:
	_live = 0
	_last.clear()
	_push()


## Fades the press out without pretending nobody is there. A battle hides the
## world, and grass going down under somebody off screen is worse than grass
## standing still.
func set_strength(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_push()


## What the shader is being told, for the tests.
func contact_count() -> int:
	return _live


func contact_at(index: int) -> Vector4:
	if index < 0 or index >= _live:
		return Vector4.ZERO
	return _contacts[index]


func material_count() -> int:
	return _materials.size()


func _push() -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(CONTACTS, _contacts)
		material.set_shader_parameter(COUNT, _live)
		material.set_shader_parameter(SECONDS, RECOVER_SECONDS)
		material.set_shader_parameter(STRENGTH, _strength)

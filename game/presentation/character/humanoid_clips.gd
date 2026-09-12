class_name HumanoidClips
extends RefCounted

## The character's animation vocabulary, and where each clip comes from.
##
## The creature equivalent is `ClipMap`, and the shape is deliberately the same:
## a closed list of slots, a rule for which of them loop, and one place that
## knows how a source's own naming becomes ours. What differs is where the clips
## live — a creature carries its own inside its model, and a character does not.
##
## ## A character model is a rig, and nothing else
##
## Every clip is a separate file under `SOURCE_FOLDER`, imported as an
## `AnimationLibrary` rather than as a scene: there is no mesh in any of them and
## no second skeleton is wanted at runtime. The model contributes the body, the
## library contributes the motion, and neither has to be re-exported when the
## other changes. `main-char.glb` still carries three clips from before this
## existed; its import turns them off, so there is one source and not two.
##
## ## Every source file says `mixamo.com`
##
## The exporter names every take after itself, so all eleven files import an
## animation called `mixamo_com`. The slot name is therefore the **file name**,
## and this class is where that is turned from a coincidence into a rule.
##
## ## The rigs do not match, and the importer is what reconciles them
##
## The clips are authored on a 65-bone Mixamo rig in a T-pose; the character is a
## 27-bone rig in an A-pose with a stylised build — shorter legs, a much larger
## head. Applied as they arrive the arms fold into the chest and the body floats
## a quarter of a metre off the ground. `mixamo_humanoid.tres` maps both rigs
## onto `SkeletonProfileHumanoid` and the import-time rest fixer rewrites both to
## the profile's axes, after which a clip addresses `%GeneralSkeleton` and lands
## on any character imported the same way. Decision 0074 records why that is done
## at import rather than in a pipeline outside the repository or in the runtime.

## Where the clips are. A file dropped here becomes reachable by naming it below
## and nowhere else — the folder is not scanned, because a slot nothing plays is
## an asset somebody forgot rather than a feature.
const SOURCE_FOLDER: String = "res://game/assets/characters/humanoid_animations"

## What the exporter calls every take it writes.
const TAKE: String = "mixamo_com"

# --- the vocabulary -----------------------------------------------------------

## Standing still, and the gaits. What the walker plays as a function of speed.
const IDLE: String = "idle"
const WALK: String = "walk"
const RUN: String = "run"

## Turning on the spot. Four clips, and the angle each was authored for is
## **measured** rather than assumed — `WalkerGait` carries the numbers and the
## reason they are not 90 and 180.
const TURN_LEFT_90: String = "turn_left_90"
const TURN_RIGHT_90: String = "turn_right_90"
const TURN_LEFT_180: String = "turn_left_180"
const TURN_RIGHT_180: String = "turn_right_180"

## Throwing a ball. One shot, and the ball leaves the hand part way through
## rather than at the end (`WalkerGait.THROW_RELEASE`).
const THROW: String = "throw_ball"

## Held clips that nothing asks for yet.
##
## `FISHING_IDLE` is a stance around a rod the character has not got, so it reads
## as holding an invisible object and must not stand in for the ordinary idle. It
## is here so that a fishing spot can play it by name the day there is one.
##
## The two stair loops carry real root motion — 0.41 m forward and 0.40 m up per
## cycle for the walk, a rise and nothing else for the run. The overworld is one
## storey (`VltWorldMap`: y is fixed), so there is nowhere to climb. They are kept
## named rather than deleted, for the same reason spec 16 keeps a species' extras.
const FISHING_IDLE: String = "fishing_idle"
const WALK_UP_STAIRS: String = "walk_up_stairs"
const RUN_UP_STAIRS: String = "run_up_stairs"

## Every slot, in the order a reader wants them.
const EVERY: Array[String] = [
	IDLE,
	WALK,
	RUN,
	TURN_LEFT_90,
	TURN_RIGHT_90,
	TURN_LEFT_180,
	TURN_RIGHT_180,
	THROW,
	FISHING_IDLE,
	WALK_UP_STAIRS,
	RUN_UP_STAIRS,
]

## The gaits, slowest first. Read by the arithmetic that picks one for a speed
## and by the tool that measures them, so neither can list them separately.
const GAITS: Array[String] = [WALK, RUN]

## The four turns, and nothing else that rotates the body.
const TURNS: Array[String] = [TURN_LEFT_90, TURN_RIGHT_90, TURN_LEFT_180, TURN_RIGHT_180]

## Slots that loop. Everything else holds on its last frame.
##
## **The loop is set in the `.import`, not here** (decision 0057): this list is
## what the import files are checked against, so a clip that lost its loop mode
## fails a test rather than stopping dead in front of a player.
const LOOPING: Array[String] = [IDLE, WALK, RUN, FISHING_IDLE, WALK_UP_STAIRS, RUN_UP_STAIRS]


## Where a slot's clip is imported from.
static func source_of(slot: String) -> String:
	return "%s/%s.fbx" % [SOURCE_FOLDER, slot]


static func loops(slot: String) -> bool:
	return LOOPING.has(slot)


## Every slot's clip, under its slot name, in one library.
##
## Eleven small loads rather than one built asset. A merged library committed to
## the repository would be the same information twice — the files and a copy of
## them — with a staleness check to write and a build step to remember, and these
## carry no mesh: the whole vocabulary is a few hundred kilobytes of tracks.
##
## A slot whose file is missing is left out rather than refused. This runs while
## a character is being instanced, and refusing there would be refusing in front
## of a player; `WalkerBody` reports what it did not find, and the tests are what
## keep the vocabulary and the folder equal.
static func library() -> AnimationLibrary:
	var built: AnimationLibrary = AnimationLibrary.new()

	for slot: String in EVERY:
		var path: String = source_of(slot)
		if not ResourceLoader.exists(path):
			push_warning("no animation at %s — %s will not play" % [path, slot])
			continue

		var source: AnimationLibrary = ResourceLoader.load(path) as AnimationLibrary
		if source == null or not source.has_animation(TAKE):
			push_warning("%s carries no %s take" % [path, TAKE])
			continue

		built.add_animation(slot, source.get_animation(TAKE))

	return built

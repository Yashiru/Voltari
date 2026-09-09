class_name VltRandomSource
extends RefCounted

## The one generator behind every seeded decider.
##
## Identical seed and identical call sequence give identical answers.
##
## The generator is written here rather than taken from the engine, for two
## reasons. The purity rule bars `RandomNumberGenerator` from the core, and more
## importantly a committed fuzz regression case must still reproduce years later
## — which an engine implementation free to change between Godot versions cannot
## promise.
##
## xorshift32: small, integer-only, and entirely adequate for choosing damage
## rolls, coin flips and encounter slots. It is an implementation detail behind
## the decider interfaces, so replacing it if fuzzing ever needs more is a
## contained change.
##
## **It is held, not inherited.** Four decision vocabularies now need randomness
## and GDScript has single inheritance, so a generator that was a base class
## could serve only one of them. Decision 0029 anticipated this — one seeded
## generator may back several interfaces — and it is why the alternative, a
## xorshift copied into each seeded decider, was refused: a bias fixed in one
## copy would leave the others wrong.

const MASK_32: int = 0xFFFFFFFF

## splitmix32's finalising constants. Used to scatter the seed, never to
## generate: one round of avalanche, then xorshift does the work.
const MIX_A: int = 0x85EBCA6B
const MIX_B: int = 0xC2B2AE35

## Any non-zero constant would do; this one is the golden ratio's 32-bit form,
## which is what the mixing literature uses for the same purpose.
const NON_ZERO_STATE: int = 0x9E3779B9

var _state: int = 0


func _init(seed_value: int) -> void:
	_state = _scatter(seed_value & MASK_32)
	# Zero is a fixed point of xorshift, so it would emit nothing but zero.
	if _state == 0:
		_state = NON_ZERO_STATE


## Spreads a seed across all 32 bits before it becomes generator state.
##
## Without this, xorshift32's first output is a simple function of its seed, so
## consecutive seeds give correlated first draws — measurably so: the first speed
## tie alternated with the seed's low bit, seed after seed. The fuzzer walks
## seeds 1, 2, 3…, so half its ties were decided by the case number rather than
## explored. Seeding is where that is fixed; the generator itself is fine.
static func _scatter(value: int) -> int:
	var mixed: int = value
	mixed = (mixed ^ (mixed >> 16)) & MASK_32
	mixed = (mixed * MIX_A) & MASK_32
	mixed = (mixed ^ (mixed >> 13)) & MASK_32
	mixed = (mixed * MIX_B) & MASK_32
	return (mixed ^ (mixed >> 16)) & MASK_32


## State stays inside [0, 2^32), which keeps `>>` logical: GDScript integers are
## signed, and a sign-extending shift would break the generator.
func _next() -> int:
	_state ^= (_state << 13) & MASK_32
	_state ^= _state >> 17
	_state ^= (_state << 5) & MASK_32
	return _state


## Uniform over [0, bound). The modulo bias is on the order of 2^-32 for the
## small bounds used here, which is far below anything a battle can express.
func below(bound: int) -> int:
	assert(bound > 0, "bound must be positive")
	return _next() % bound


func happens(numerator: int, denominator: int) -> bool:
	assert(denominator > 0, "denominator must be positive")
	if numerator <= 0:
		return false
	if numerator >= denominator:
		return true
	return below(denominator) < numerator


## Exposed so a battle can be saved and resumed without losing its sequence.
func state() -> int:
	return _state


func restore(value: int) -> void:
	_state = value & MASK_32
	if _state == 0:
		_state = NON_ZERO_STATE

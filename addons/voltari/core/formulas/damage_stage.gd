class_name VltDamageStage
extends RefCounted

## Ordered stages of the Gen 4 damage pipeline.
##
## Modifiers attach to a stage and never move across stages (spec 06). Priority
## orders modifiers within a stage; it never moves one to another stage.
##
## This sequence is not a design choice. It is extracted from the oracle — see
## tools/oracle/gen4-damage-stages.md for the extraction and its provenance.
## Changing the order here without a matching oracle change is a fidelity defect.
##
## Declaration order is pipeline order. Nothing may depend on the numeric values
## themselves, only on their relative order.

enum Stage {
	## Physical damage halved when the attacker is burned, unless suppressed.
	BURN,
	## Screens and comparable effects.
	MODIFIER_PHASE_1,
	## Multi-target reduction in doubles.
	SPREAD,
	WEATHER,
	## Constant +2. Sits here, not in the base damage — see the extraction note.
	PLUS_TWO,
	## Doubling in Gen 4.
	CRITICAL,
	## Followed immediately by flooring.
	MODIFIER_PHASE_2,
	## The 85-100 roll. A decision, not a modifier: it is answered by the
	## decision interface of spec 03, never computed inline.
	RANDOM_ROLL,
	## x1.5, itself modifiable.
	STAB,
	## Repeated integer doubling or halving, exponent clamped to [-6, +6].
	TYPE_EFFECTIVENESS,
	FINAL_MODIFIER,
	## Flooring, with a minimum of 1.
	FLOOR_MINIMUM,
}

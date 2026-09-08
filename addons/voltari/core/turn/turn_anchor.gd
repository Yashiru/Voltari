class_name VltTurnAnchor
extends RefCounted

## The points at which the turn machine consults effects.
##
## This enumeration is the ONLY coupling between the turn machine and the effect
## system (spec 04). The machine names no individual effect, branches on none,
## and does not know which exist; effects name no phase except through an anchor
## here.
##
## Nothing binds to these yet — the effect system is spec 06. They are declared
## now because the machine is written around them, and retrofitting anchor points
## into finished control flow is how a turn machine turns into spaghetti.

enum Anchor {
	TURN_START,

	## Before an action runs: can the actor act at all? Sleep, flinch, confusion
	## and the rest are ordered effects at this anchor, never `if` branches.
	BEFORE_ACTION,

	## Guards the move: protect, immunity, semi-invulnerability. Vetoes, not
	## modifiers returning zero (spec 06).
	MOVE_VETO,

	BEFORE_ACCURACY,
	AFTER_HIT,
	ON_FAINT,

	## End-of-turn residuals, in a long and fidelity-critical order that lives as
	## per-effect declared priority rather than as calls in the machine.
	RESIDUAL,

	TURN_END,
	SWITCH_OUT,
	SWITCH_IN,
}

class_name VltVeto
extends VltEffectComponent

## Blocks something before it happens.
##
## Not a modifier returning zero. A veto stops the work upstream, and that is
## observably different: no damage is computed, no secondary rolls, and the log
## records a block rather than a zero (spec 06).
##
## The first veto that blocks ends evaluation at that anchor — the question is
## already answered, and consulting the rest would only invite one of them to
## have side effects.

var anchor: VltTurnAnchor.Anchor = VltTurnAnchor.Anchor.MOVE_VETO


func _init(at: VltTurnAnchor.Anchor, order: int = 0) -> void:
	super(order)
	anchor = at


func blocks(_context: VltEffectContext) -> bool:
	assert(false, "VltVeto is abstract")
	return false

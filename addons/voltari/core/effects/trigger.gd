class_name VltTrigger
extends VltEffectComponent

## Does something at a turn anchor.
##
## Triggers mutate state and emit log events. Every mutation must emit, or
## invariant 8 fails — which is the mechanism that stops an effect quietly
## changing a battle without the UI or the replay ever knowing.
##
## Triggers never call one another. Cascades go through the event queue, so
## their depth and ordering are controlled rather than emergent (spec 06).

var anchor: VltTurnAnchor.Anchor = VltTurnAnchor.Anchor.RESIDUAL


func _init(at: VltTurnAnchor.Anchor, order: int = 0) -> void:
	super(order)
	anchor = at


func run(_context: VltEffectContext) -> void:
	assert(false, "VltTrigger is abstract")

class_name VltEffectContext
extends RefCounted

## What a component is handed when it runs.
##
## Everything a component may read or write goes through here, so the set of
## things an effect can reach is a closed list rather than whatever it can find.

## The battle, mutable. Components change it; the turn boundary already took a
## copy (decision 0011).
var state: VltBattleState = null

## The instance this component belongs to, carrying its own duration and
## counters. Definitions are shared, so this is the only place an effect may
## keep state.
var instance: VltEffectInstance = null

## Where the effect is attached. Null for field-scoped effects.
var owner: VltSlotRef = null

## The action under way, when there is one.
var actor: VltSlotRef = null
var target: VltSlotRef = null
var move: VltMoveDefinition = null

var decider: VltDecider = null
var log: VltBattleLog = null


static func create(battle: VltBattleState, held: VltEffectInstance, at: VltSlotRef) -> VltEffectContext:
	var context: VltEffectContext = VltEffectContext.new()
	context.state = battle
	context.instance = held
	context.owner = at
	return context


func with_action(
	acting: VltSlotRef, targeted: VltSlotRef, used: VltMoveDefinition
) -> VltEffectContext:
	actor = acting
	target = targeted
	move = used
	return self


func owner_creature() -> VltBattleCreature:
	if owner == null:
		return null
	return state.creature_at(owner)

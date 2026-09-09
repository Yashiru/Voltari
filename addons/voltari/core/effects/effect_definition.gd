class_name VltEffectDefinition
extends RefCounted

## What an effect is: stateless, shared, and made of components.
##
## Scope, reset rule and stacking rule are three separate declarations because
## they answer three different questions. Fusing them breaks on the first
## awkward case — a badly-poisoned counter is creature-scoped yet resets on
## switching, which a single combined field cannot express (spec 03).

enum Scope {
	## Affects both sides.
	FIELD,
	## Attached to one side, independent of who occupies its slots.
	SIDE,
	## Attached to occupying a position; cleared when the occupant leaves.
	SLOT,
	## Intrinsic to a creature; follows it out of the battle.
	CREATURE,
}

enum ResetRule {
	## Lasts until it expires or is removed.
	PERSISTS,
	## Cleared when the holder leaves the field, even though it is not
	## slot-scoped.
	CLEARS_ON_SWITCH,
}

enum Stacking {
	## Reapplying does nothing.
	UNIQUE,
	## Reapplying restarts the duration.
	REFRESH,
	## Reapplying adds a layer.
	STACKING,
}

var id: String = ""
var scope: Scope = Scope.SLOT

## A major status — burn, freeze, paralysis, sleep, poison. Gen 4 allows a
## creature exactly one at a time, and this is what makes that a rule the engine
## enforces rather than a convention every effect has to remember.
##
## A marker rather than a separate kind of effect: a status is an ordinary effect
## in every other respect, and giving it its own type would duplicate the whole
## component system to express one exclusivity rule.
var is_major_status: bool = false
var reset_rule: ResetRule = ResetRule.PERSISTS
var stacking: Stacking = Stacking.UNIQUE

## Zero duration means it lasts until something removes it.
var default_duration: int = 0

var modifiers: Array[VltModifier] = []
var vetoes: Array[VltVeto] = []
var triggers: Array[VltTrigger] = []


static func create(
	effect_id: String,
	effect_scope: Scope,
	reset: ResetRule = ResetRule.PERSISTS,
	stack: Stacking = Stacking.UNIQUE,
	duration: int = 0
) -> VltEffectDefinition:
	var definition: VltEffectDefinition = VltEffectDefinition.new()
	definition.id = effect_id
	definition.scope = effect_scope
	definition.reset_rule = reset
	definition.stacking = stack
	definition.default_duration = duration
	return definition


## Marks this as the one status a creature may carry (see `is_major_status`).
func as_major_status() -> VltEffectDefinition:
	is_major_status = true
	return self


func with_modifier(modifier: VltModifier) -> VltEffectDefinition:
	modifiers.append(modifier)
	return self


func with_veto(veto: VltVeto) -> VltEffectDefinition:
	vetoes.append(veto)
	return self


func with_trigger(trigger: VltTrigger) -> VltEffectDefinition:
	triggers.append(trigger)
	return self

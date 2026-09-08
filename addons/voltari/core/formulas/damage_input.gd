class_name VltDamageInput
extends RefCounted

## Inputs to one damage computation.
##
## A plain typed carrier: it holds no logic and makes no decision. The caller
## fills it, VltDamage reads it. The same object serves as a test fixture and as
## a production input, so nothing has to be mirrored between the two.
##
## Modifiers arrive as ratios rather than as named conditions. The pipeline does
## not know what a burn is — which effect contributes which ratio at which stage
## is the effect system's business (spec 06), not the formula's.

## Base damage inputs.
var level: int = 1
var base_power: int = 0
var attack: int = 0
var defense: int = 1

## What each stage contributes. Effects fill this; the formula never learns what
## a burn or a screen is (spec 06).
var modifiers: VltDamageModifiers = VltDamageModifiers.new()

## Decided rather than contributed: one is answered by the decision interface,
## the other is intrinsic to the attacker.
var is_critical: bool = false
var has_stab: bool = false

## The forced damage roll, 85 to 100 inclusive (spec 03: a decision, not a draw).
var damage_roll: int = 100

## Doublings when positive, halvings when negative. Produced by the type chart,
## which is a separate procedure with its own vectors.
var type_effectiveness_exponent: int = 0

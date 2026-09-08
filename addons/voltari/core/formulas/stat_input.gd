class_name VltStatInput
extends RefCounted

## Inputs to one stat spread derivation.
##
## A plain typed carrier, holding no logic. Arrays are indexed by
## VltStats.Stat, so nothing has to agree on a separate ordering convention.

var base: PackedInt32Array = PackedInt32Array()
var ivs: PackedInt32Array = PackedInt32Array()
var evs: PackedInt32Array = PackedInt32Array()
var level: int = 1

## The stats a nature raises and lowers, or VltStats.NO_STAT. The nature table
## that maps an identifier to this pair is content; the core only needs the pair.
var nature_raised: int = VltStats.NO_STAT
var nature_lowered: int = VltStats.NO_STAT


func _init() -> void:
	base.resize(VltStats.STAT_COUNT)
	ivs.resize(VltStats.STAT_COUNT)
	evs.resize(VltStats.STAT_COUNT)

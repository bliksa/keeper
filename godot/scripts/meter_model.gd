class_name MeterModel
extends RefCounted
## The meter both the jackpot climb's hearts and the forest run's water use: `slots` ready
## units (hearts / drops; the abilities spend them) and a bar (0..100) that pickups fill. A
## full bar is one more ready unit; with every slot ready the bar stays full and refills the
## next one spent. Ready units may be fractional (the run's focus drains them per second).
## The climb keeps its own ints (Platformer.hearts / heart_bar) and calls `settle`; the
## run keeps an instance (ForestRunner.meter).

var slots := 4.0
## Ready units (0..slots).
var ready := 4.0
## The bar filling the next unit (0..100).
var bar := 0.0


func _init(n_slots := 4.0, n_ready := 4.0, n_bar := 0.0) -> void:
	slots = n_slots
	ready = clampf(n_ready, 0.0, n_slots)
	bar = clampf(n_bar, 0.0, 100.0)
	_apply(settle(ready, bar, slots))


## The bar turned into ready units: x = ready, y = bar, z = how many units it gave. A full
## bar (100) is one whole unit, given only once a whole slot is free (as the climb's int
## hearts): a part-used unit (the run's focus) waits with the bar full until it is used up.
static func settle(n_ready: float, n_bar: float, n_slots: float) -> Vector3:
	var gained := 0.0
	while n_bar >= 100.0 - 0.0001 and n_ready <= n_slots - 1.0 + 0.0001:
		n_ready += 1.0
		n_bar -= 100.0
		gained += 1.0
	return Vector3(n_ready, clampf(n_bar, 0.0, 100.0), gained)


## A pickup: the bar fills by `amount` (%); returns the units it made ready.
func fill(amount: float) -> float:
	var r := settle(ready, bar + amount, slots)
	_apply(r)
	return r.z


## Spends `n` ready units (a full bar refills them); false if there aren't enough.
func spend(n: float) -> bool:
	if ready < n - 0.001:
		return false
	ready = maxf(0.0, ready - n)
	_apply(settle(ready, bar, slots))
	return true


## Takes up to `n` (a hit, the focus drain per frame): never below zero, never fails.
func drain(n: float) -> void:
	ready = maxf(0.0, ready - n)
	_apply(settle(ready, bar, slots))


func _apply(r: Vector3) -> void:
	ready = r.x
	bar = r.y

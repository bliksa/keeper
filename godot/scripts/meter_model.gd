class_name MeterModel
extends RefCounted
## The meter both the jackpot climb's hearts and the forest run's water use, like a gun's
## magazine in a shooter:
## - the magazine `mag`: `slots` (4) units the abilities spend (fractional: the run's
##   focus drains it per second, a slot fills part by part);
## - the reserve `reserve` (0..`reserve_max`): the line round the pill.
## A pickup goes into the magazine first (the part-filled slot fills); only a full
## magazine sends it on into the reserve. The reserve reloads the magazine: at once when
## the magazine is empty, otherwise after RELOAD_DELAY s without spending; one unit leaves
## the reserve every RELOAD_GAP s and flies RELOAD_FLY s into its slot (`flyers`), so a
## reload takes a moment and can be watched. Spending stops a reload (the units already
## on their way still land) and starts the wait again.
## The run keeps one (ForestRunner.meter), the climb another (Platformer.meter); both call
## `update(dt)` every frame of play and draw it with MeterHud.

## Seconds without spending before a part-empty magazine reloads.
const RELOAD_DELAY := 1.2
## Seconds between two units leaving the reserve, and the flight of one into its slot.
const RELOAD_GAP := 0.45
const RELOAD_FLY := 0.38
## How long a pickup's flash on its slot / on the reserve line lasts (s).
const FLASH := 0.5
const EPS := 0.0001

var slots := 4.0
var reserve_max := 4.0
## Units in the magazine (0..slots), what the abilities spend.
var mag := 4.0
## Units in the reserve (0..reserve_max).
var reserve := 0.0
## Seconds since the last spending.
var idle := 99.0
## Units are moving from the reserve into the magazine.
var reloading := false
## The reload under way began with an empty magazine: like a shooter's, it runs to the end
## (spending meanwhile doesn't stop it).
var reload_from_empty := false
## The slot the last fill() went into (the caller's own flash when fill(…, false)).
var last_slot := 0
## Units on their way into the magazine: [{t: 0..1, amount, from (0..1 on the line), slot}].
var flyers: Array = []
## Seconds until the next unit leaves the reserve.
var _gap := 0.0
## Visual state (MeterHud): a pickup's flash on its slot / on the reserve line, a unit
## that just landed (its slot pops), the reserve as drawn (eases after the real one),
## the reload's shimmer (0..1).
var slot_flash := 0.0
var slot_flash_i := 0
var reserve_flash := 0.0
var land_flash := 0.0
var land_i := 0
var shown_reserve := 0.0
var reload_glow := 0.0


func _init(n_slots := 4.0, n_mag := 4.0, n_reserve := 0.0, n_reserve_max := 4.0) -> void:
	slots = n_slots
	reserve_max = n_reserve_max
	reset(n_mag, n_reserve)


## Sets both stores at once (a level's start, dev shortcuts, tests): no reload under way,
## no flashes.
func reset(n_mag: float, n_reserve := 0.0) -> void:
	mag = clampf(n_mag, 0.0, slots)
	reserve = clampf(n_reserve, 0.0, reserve_max)
	shown_reserve = reserve
	flyers.clear()
	reloading = false
	reload_from_empty = false
	idle = 99.0
	_gap = 0.0
	slot_flash = 0.0
	reserve_flash = 0.0
	land_flash = 0.0
	reload_glow = 0.0


## Whole units ready in the magazine.
func whole() -> int:
	return int(floorf(mag + EPS))


## Everything the meter holds: the magazine, the reserve and the units on their way.
func total() -> float:
	return mag + reserve + in_flight()


func in_flight() -> float:
	var s := 0.0
	for f in flyers:
		s += float(f.amount)
	return s


## A pickup of `amount` % of a unit: into the magazine first, the rest into the reserve
## (a full meter takes nothing). Returns Vector2(units into the magazine, into the reserve).
## `flash` = false: no slot / reserve flash now (the caller flashes when its pickup lands).
func fill(amount: float, flash := true) -> Vector2:
	var u := maxf(0.0, amount / 100.0)
	var room := maxf(0.0, slots - mag - in_flight())
	var to_mag := minf(u, room)
	mag = _snap(mag + to_mag)
	var to_res := minf(u - to_mag, reserve_max - reserve)
	to_res = maxf(0.0, to_res)
	reserve = _snap(reserve + to_res)
	if to_mag > EPS:
		last_slot = clampi(int(ceilf(mag - EPS)) - 1, 0, int(slots) - 1)
		if flash:
			slot_flash = FLASH
			slot_flash_i = last_slot
	if to_res > EPS and flash:
		reserve_flash = FLASH
	return Vector2(to_mag, to_res)


## Spends `n` units from the magazine; false (nothing spent) if it holds fewer.
func spend(n: float) -> bool:
	if mag < n - 0.001:
		return false
	mag = _snap(maxf(0.0, mag - n))
	hold()
	return true


## Takes up to `n` from the magazine (a hit, the focus drain per frame): never below zero.
func drain(n: float) -> void:
	if n <= 0.0:
		return
	mag = _snap(maxf(0.0, mag - n))
	hold()


## Something is being spent (also a continuous burn): the reload waits again (stops if
## under way; the units in the air still land), unless the magazine is empty or the reload
## began from an empty magazine (that one runs to the end, as in a shooter).
func hold() -> void:
	idle = 0.0
	if mag > EPS and not reload_from_empty:
		reloading = false


## The reload and the visuals; returns how many units landed in the magazine this frame
## (the caller plays a click for each).
func update(dt: float) -> int:
	slot_flash = maxf(0.0, slot_flash - dt)
	reserve_flash = maxf(0.0, reserve_flash - dt)
	land_flash = maxf(0.0, land_flash - dt)
	idle += dt
	var landed := 0
	for f in flyers.duplicate():
		f.t += dt / RELOAD_FLY
		if f.t >= 1.0:
			flyers.erase(f)
			mag = _snap(minf(slots, mag + float(f.amount)))
			land_flash = FLASH
			land_i = int(f.slot)
			landed += 1
	var level := mag + in_flight()
	var room := slots - level
	if room <= EPS or reserve <= EPS:
		reloading = false
		reload_from_empty = false
	elif not reloading and (level <= EPS or idle >= RELOAD_DELAY):
		reloading = true
		reload_from_empty = level <= EPS
		_gap = 0.0
	if reloading:
		_gap -= dt
		if _gap <= 0.0:
			# The part-filled slot is topped up first, then whole units (a reload from empty
			# brings whole units even while she spends, so it gets ahead of a steady drain).
			var part := level - floorf(level + EPS)
			var a := 1.0 - part if part > EPS and not reload_from_empty else 1.0
			a = minf(a, minf(reserve, room))
			# "from": where the reserve line ended (0..1 of it) when the unit left.
			var from := reserve / maxf(0.001, reserve_max)
			reserve = _snap(reserve - a)
			flyers.append({"t": 0.0, "amount": a, "from": from, "slot": clampi(int(ceilf(level + a - EPS)) - 1, 0, int(slots) - 1)})
			_gap = RELOAD_GAP
	shown_reserve = move_toward(shown_reserve, reserve, dt * 4.0)
	reload_glow = move_toward(reload_glow, 1.0 if reloading or not flyers.is_empty() else 0.0, dt * 4.0)
	return landed


static func _snap(v: float) -> float:
	var r := roundf(v)
	return r if absf(v - r) < EPS else v

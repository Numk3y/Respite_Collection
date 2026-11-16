extends RefCounted
## Placeholder sound effects made in code (16-bit mono, 22.05 kHz), used by Sound when Audio/sfx/ has no file of
## that name. make(name) returns the samples, already scaled to the sound's loudness; to_wav() packs them.

const RATE := 22050

static func make(name: String) -> PackedFloat32Array:
	match name:
		"swing": return _swing(0.2, 700.0, 2600.0, 0.5)  # a melee lunge
		"miss": return _swing(0.16, 1600.0, 4200.0, 0.28)  # a whiff past the target
		"shoot": return _shoot()  # a back-row bolt
		"hit": return _hit(false)
		"crit": return _hit(true)
		"heal": return _heal()
		"knockout": return _knockout()
		"ultimate": return _ultimate()  # under the Ultimate / combo cut-in
		"wave": return _wave()  # a new wave's banner
		"jumpscare": return _jumpscare()  # a boss wave's lights-out entrance
		"puke": return _puke()
		"victory": return _victory()
		"defeat": return _defeat()
		"crystal": return _crystal()  # a recruit crystal landing in the x10 lineup
		"claim": return _claim()  # a daily reward or chest collected
		"toast": return _toast()  # a "mission complete" notice sliding in
		# Interface (UiSound plays these for every button, tab and popup)
		"click": return _tick(1700.0, 0.045, 0.16)  # a button pressed
		"hover": return _tick(2600.0, 0.03, 0.06)  # the pointer onto a Home tile or big button
		"tab": return _sweep(850.0, 1500.0, 0.09, 0.15)  # a tab switched
		"open": return _whoosh(0.2, 600.0, 4200.0, 0.16)  # a window opening
		"error": return _error()  # a disabled button clicked / not enough currency
		"coin": return _coin()  # Money or a reward coming in
		# Progress
		"level_up": return _arpeggio([523.25, 659.25, 783.99, 1046.5], 0.06, 0.8, 0.3)  # a friend levels up
		"account_up": return _fanfare()  # the account levels up
		"forge": return _forge()  # gear upgraded or crafted
		"scrap": return _scrap()  # gear broken down into Parts
		"equip": return _clink()  # gear put on
		"star": return _tick(2093.0, 0.25, 0.22)  # a map star popping in on the results
		# Casino
		"card": return _card()  # a card dealt
		"flip": return _flip()  # a face-down card turned over
		"chips": return _chips()  # a bet placed
		"cylinder": return _cylinder()  # the revolver's cylinder spun
		"dry_click": return _dry_click()  # an empty chamber
		"gunshot": return _gunshot()  # a loaded one
		"win": return _arpeggio([1046.5, 1318.5, 1567.98, 2093.0, 2637.0], 0.07, 0.9, 0.32)  # a hand or round won
		"lose": return _lose()  # a hand or round lost
		# Recruiting
		"charge": return _charge()  # a crystal charging before the reveal (pitch it down to lengthen it)
		"reveal_sr": return _reveal(false)
		"reveal_ssr": return _reveal(true)
	return PackedFloat32Array()

## A short pure ping, fading fast (clicks, hovers, stars)
static func _tick(freq: float, seconds: float, peak: float) -> PackedFloat32Array:
	var s := _buffer(seconds)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.01 * t)) * exp(-t * 6.0 / seconds) * minf(t * 2000.0, 1.0)
	return _normalize(s, peak)

## A quick pitch glide (the tab switch)
static func _sweep(from: float, to: float, seconds: float, peak: float) -> PackedFloat32Array:
	var s := _buffer(seconds)
	var phase := 0.0
	for i in s.size():
		var p := float(i) / s.size()
		phase += TAU * lerpf(from, to, p * p) / RATE
		s[i] = sin(phase) * sin(PI * p)
	return _normalize(s, peak)

## Air rising through a filter (a window opening)
static func _whoosh(seconds: float, low: float, high: float, peak: float) -> PackedFloat32Array:
	var s := _buffer(seconds)
	var y := 0.0
	for i in s.size():
		var p := float(i) / s.size()
		y += _lp(lerpf(low, high, p)) * (randf_range(-1.0, 1.0) - y)
		s[i] = y * sin(PI * p) + sin(TAU * lerpf(440.0, 880.0, p) * float(i) / RATE) * 0.15 * sin(PI * p)
	return _normalize(s, peak)

## Two low buzzes: "no"
static func _error() -> PackedFloat32Array:
	var s := _buffer(0.22)
	for i in s.size():
		var t := float(i) / RATE
		var gate := 1.0 if t < 0.08 or (t > 0.11 and t < 0.2) else 0.0
		s[i] = signf(sin(TAU * 170.0 * t)) * 0.5 * gate + sin(TAU * 85.0 * t) * 0.5 * gate
	return _normalize(s, 0.2)

## One coin: a bright two-note ding
static func _coin() -> PackedFloat32Array:
	var s := _buffer(0.3)
	for i in s.size():
		var t := float(i) / RATE
		var f := 1975.5 if t < 0.05 else 2637.0
		var nt := t if t < 0.05 else t - 0.05
		s[i] = (sin(TAU * f * t) + 0.25 * signf(sin(TAU * f * t))) * exp(-nt * (30.0 if t < 0.05 else 9.0)) * minf(t * 1500.0, 1.0)
	return _normalize(s, 0.2)

## Notes one after another, each ringing on (level ups, wins)
static func _arpeggio(notes: Array, gap: float, seconds: float, peak: float) -> PackedFloat32Array:
	var s := _buffer(seconds)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var nt: float = t - gap * k
			if nt >= 0.0:
				var f: float = notes[k]
				v += (sin(TAU * f * nt) + 0.25 * sin(TAU * f * 2.0 * nt) + 0.12 * signf(sin(TAU * f * nt))) \
					* exp(-nt * (3.0 if k == notes.size() - 1 else 7.0)) * minf(nt * 600.0, 1.0)
		s[i] = v
	return _normalize(s, peak)

## Brass: G C E, then a held G major chord on top
static func _fanfare() -> PackedFloat32Array:
	var s := _buffer(1.5)
	var notes := [[0.0, 392.0, 0.1], [0.1, 523.25, 0.1], [0.2, 659.25, 0.1],
		[0.32, 783.99, 1.1], [0.32, 987.77, 1.1], [0.32, 1174.66, 1.1], [0.32, 392.0, 1.1]]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for n in notes:
			var nt: float = t - n[0]
			if nt >= 0.0:
				var env := minf(nt * 70.0, 1.0) * (exp(-nt * 1.4) if n[2] > 0.5 else exp(-maxf(nt - n[2] * 0.6, 0.0) * 30.0))
				v += _brass(TAU * n[1] * nt * (1.0 + 0.003 * sin(TAU * 5.5 * nt))) * env
		var st := t - 0.32
		if st >= 0.0:
			v += sin(TAU * 4186.0 * st) * 0.15 * exp(-st * 5.0) * (0.5 + 0.5 * sin(TAU * 18.0 * st))
		s[i] = v
	return _normalize(s, 0.42)

## Hammer on metal: inharmonic ringing partials over a thump, then a sparkle
static func _forge() -> PackedFloat32Array:
	var s := _buffer(0.7)
	var partials := [[520.0, 1.0], [1347.0, 0.6], [2210.0, 0.45], [3170.0, 0.3]]
	for i in s.size():
		var t := float(i) / RATE
		var v := randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.8 + sin(TAU * 90.0 * t) * exp(-t * 25.0)
		for p in partials:
			v += sin(TAU * p[0] * t) * p[1] * exp(-t * (6.0 + p[0] / 600.0))
		var st := t - 0.12
		if st >= 0.0:
			v += sin(TAU * 3951.0 * st) * 0.3 * exp(-st * 10.0) + sin(TAU * 5274.0 * st) * 0.2 * exp(-st * 14.0)
		s[i] = tanh(v * 0.9)
	return _normalize(s, 0.42)

## A crunch: noise falling in pitch over a low knock
static func _scrap() -> PackedFloat32Array:
	var s := _buffer(0.32)
	var y := 0.0
	var grain := 1.0
	for i in s.size():
		var t := float(i) / RATE
		var p := float(i) / s.size()
		if i % 160 == 0:
			grain = randf_range(0.3, 1.0)
		y += _lp(lerpf(5000.0, 400.0, p)) * (randf_range(-1.0, 1.0) - y)
		s[i] = y * 2.5 * grain * (1.0 - p) + sin(TAU * 70.0 * t) * exp(-t * 20.0) * 0.7
	return _normalize(s, 0.38)

## Two light metallic pings
static func _clink() -> PackedFloat32Array:
	var s := _buffer(0.28)
	for i in s.size():
		var t := float(i) / RATE
		var v := (sin(TAU * 1530.0 * t) + 0.6 * sin(TAU * 3890.0 * t)) * exp(-t * 22.0)
		var t2 := t - 0.07
		if t2 >= 0.0:
			v += (sin(TAU * 2210.0 * t2) + 0.5 * sin(TAU * 5110.0 * t2)) * exp(-t2 * 18.0) * 0.8
		s[i] = v * minf(t * 3000.0, 1.0)
	return _normalize(s, 0.24)

## A card snapping onto felt: a brief bright noise burst
static func _card() -> PackedFloat32Array:
	var s := _buffer(0.08)
	var y := 0.0
	var prev := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := randf_range(-1.0, 1.0)
		y += _lp(6000.0) * (n - y)
		var high := y - prev  # a crude high-pass keeps it papery
		prev = y
		s[i] = (high * 6.0 + y) * exp(-t * 55.0)
	return _normalize(s, 0.3)

## Two quick paper ticks
static func _flip() -> PackedFloat32Array:
	var s := _buffer(0.12)
	var y := 0.0
	for i in s.size():
		var t := float(i) / RATE
		y += _lp(4500.0) * (randf_range(-1.0, 1.0) - y)
		var env := exp(-t * 90.0) + (exp(-(t - 0.06) * 90.0) if t > 0.06 else 0.0)
		s[i] = y * env
	return _normalize(s, 0.24)

## Poker chips clacking: three hard little knocks
static func _chips() -> PackedFloat32Array:
	var s := _buffer(0.24)
	var hits := [0.0, 0.045, 0.1]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in hits.size():
			var ht: float = t - hits[k]
			if ht >= 0.0:
				var f := 2600.0 + 400.0 * k
				v += (sin(TAU * f * ht) + 0.7 * sin(TAU * f * 1.48 * ht) + randf_range(-1.0, 1.0) * exp(-ht * 300.0)) * exp(-ht * 70.0)
		s[i] = v
	return _normalize(s, 0.3)

## A revolver cylinder spinning down: ratchet clicks, fast and then slowing (about 1.1 s, like the animation)
static func _cylinder() -> PackedFloat32Array:
	var s := _buffer(1.15)
	var t := 0.0
	var gap := 0.025
	var length := int(RATE * 0.03)
	while t < 1.05:
		var start := int(t * RATE)
		for j in mini(length, s.size() - start):  # each click only touches its own 30 ms
			var ct := float(j) / RATE
			s[start + j] += (sin(TAU * 3200.0 * ct) * 0.6 + randf_range(-1.0, 1.0) * 0.5) * exp(-ct * 220.0)
		t += gap
		gap *= 1.11
	return _normalize(s, 0.3)

## The hammer falling on an empty chamber: a hard dry click with a low knock
static func _dry_click() -> PackedFloat32Array:
	var s := _buffer(0.18)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = randf_range(-1.0, 1.0) * exp(-t * 400.0) + sin(TAU * 2900.0 * t) * exp(-t * 90.0) * 0.6 \
			+ sin(TAU * 140.0 * t) * exp(-t * 40.0) * 0.6
	return _normalize(s, 0.5)

## A gunshot: a saturated burst whose filter closes fast, a deep thump, and a short room tail
static func _gunshot() -> PackedFloat32Array:
	var s := _buffer(0.9)
	var y := 0.0
	for i in s.size():
		var t := float(i) / RATE
		y += _lp(300.0 + 9000.0 * exp(-t * 18.0)) * (randf_range(-1.0, 1.0) - y)
		var v := y * 3.0 * (exp(-t * 9.0) + 0.15 * exp(-t * 2.5)) + sin(TAU * (55.0 + 80.0 * exp(-t * 30.0)) * t) * exp(-t * 12.0) * 1.2
		s[i] = tanh(v * 2.0) * minf(t * 4000.0, 1.0)
	return _normalize(s, 0.85)

## A sad "wah wah": two falling notes, the second sagging
static func _lose() -> PackedFloat32Array:
	var s := _buffer(0.8)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		if t < 0.28:
			v = asin(sin(TAU * 311.13 * t)) * minf(t * 60.0, 1.0) * minf((0.28 - t) * 40.0, 1.0)
		else:
			var nt := t - 0.28
			v = asin(sin(TAU * 293.66 * (1.0 - 0.03 * minf(nt, 0.5)) * nt)) * minf(nt * 60.0, 1.0) * exp(-nt * 3.0) \
				* (0.75 + 0.25 * sin(TAU * 6.0 * nt))
		s[i] = v
	return _normalize(s, 0.3)

## A rising hum and hiss (1 s at pitch 1; slower and deeper at a lower pitch)
static func _charge() -> PackedFloat32Array:
	var s := _buffer(1.0)
	var phase := 0.0
	var y := 0.0
	for i in s.size():
		var p := float(i) / s.size()
		phase += TAU * (180.0 * pow(6.0, p)) / RATE
		y += _lp(400.0 + 7000.0 * p) * (randf_range(-1.0, 1.0) - y)
		s[i] = (sin(phase) * 0.5 + sin(phase * 1.5) * 0.25 + y * 0.9) * p * p * (0.85 + 0.15 * sin(TAU * 14.0 * p))
	return _normalize(s, 0.35)

## The crystal bursting into a friend: a shimmering chord (SR), or a crash, a big major chord and sparkles (SSR)
static func _reveal(ssr: bool) -> PackedFloat32Array:
	var seconds := 2.2 if ssr else 1.0
	var s := _buffer(seconds)
	var chord := [523.25, 659.25, 783.99, 1046.5, 261.63] if ssr else [659.25, 830.61, 987.77]
	var y := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in chord.size():
			var f: float = chord[k]
			v += (_brass(TAU * f * t) if ssr else sin(TAU * f * t)) * exp(-t * (1.2 if ssr else 3.0)) * minf(t * 200.0, 1.0)
		if ssr:
			y += _lp(lerpf(9000.0, 1500.0, minf(t, 1.0))) * (randf_range(-1.0, 1.0) - y)
			v += y * 2.0 * exp(-t * 4.0)
		var sparkle := 0.5 + 0.5 * sin(TAU * (12.0 if ssr else 20.0) * t)
		v += sin(TAU * 4186.0 * t) * 0.3 * exp(-t * 2.5) * sparkle + sin(TAU * 3136.0 * t) * 0.2 * exp(-t * 4.0)
		s[i] = tanh(v * 0.7)
	return _normalize(s, 0.55 if ssr else 0.38)

## A coin pickup: two quick bright notes, the second one ringing out with a sparkle
static func _claim() -> PackedFloat32Array:
	var s := _buffer(0.5)
	var notes := [[0.0, 987.77, 0.07], [0.07, 1318.5, 0.45]]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for n in notes:
			var nt: float = t - n[0]
			if nt >= 0.0 and nt < n[2]:
				var square := signf(sin(TAU * n[1] * nt)) * 0.35 + sin(TAU * n[1] * nt)
				v += square * exp(-nt * (6.0 if n[2] > 0.1 else 2.0)) * minf(nt * 800.0, 1.0) * minf((n[2] - nt) * 200.0, 1.0)
		var st := t - 0.07
		if st >= 0.0:
			v += sin(TAU * 3951.0 * st) * 0.25 * exp(-st * 12.0)
		s[i] = v
	return _normalize(s, 0.32)

## A soft two-note chime
static func _toast() -> PackedFloat32Array:
	var s := _buffer(0.55)
	var notes := [[0.0, 1046.5], [0.09, 1567.98]]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for n in notes:
			var nt: float = t - n[0]
			if nt >= 0.0:
				v += (sin(TAU * n[1] * nt) + 0.15 * sin(TAU * n[1] * 2.0 * nt)) * exp(-nt * 7.0) * minf(nt * 300.0, 1.0)
		s[i] = v
	return _normalize(s, 0.22)

## A short glassy ping
static func _crystal() -> PackedFloat32Array:
	var s := _buffer(0.4)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (sin(TAU * 2093.0 * t) + 0.5 * sin(TAU * 3136.0 * t) * exp(-t * 6.0) + 0.25 * sin(TAU * 5274.0 * t) * exp(-t * 14.0)) \
			* exp(-t * 9.0) * minf(t * 600.0, 1.0)
	return _normalize(s, 0.35)

static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

static func _buffer(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(RATE * seconds))
	return s

## Scales the samples so the loudest one is `peak`, with a 3 ms fade-out so nothing ends on a click
static func _normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0001
	for v in s:
		top = maxf(top, absf(v))
	var fade := int(RATE * 0.003)
	for i in s.size():
		s[i] = s[i] / top * peak * minf(float(s.size() - 1 - i) / fade, 1.0)
	return s

## One-pole low-pass coefficient for a cutoff frequency
static func _lp(cutoff: float) -> float:
	return 1.0 - exp(-TAU * cutoff / RATE)

## Brassy tone (odd harmonics) for the fanfares
static func _brass(phase: float) -> float:
	return sin(phase) + 0.33 * sin(phase * 3.0) + 0.15 * sin(phase * 5.0)

## Air rushing past: noise through a low-pass whose cutoff swells from `low` to `high` and back
static func _swing(seconds: float, low: float, high: float, peak: float) -> PackedFloat32Array:
	var s := _buffer(seconds)
	var y1 := 0.0
	var y2 := 0.0
	for i in s.size():
		var p := float(i) / s.size()
		var a := _lp(lerpf(low, high, sin(PI * p)))
		y1 += a * (randf_range(-1.0, 1.0) - y1)
		y2 += a * (y1 - y2)
		s[i] = y2 * pow(sin(PI * minf(p * 1.4, 1.0)), 1.5)
	return _normalize(s, peak)

## A falling "pew" with a little crackle at the start
static func _shoot() -> PackedFloat32Array:
	var s := _buffer(0.2)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * (300.0 + 1300.0 * exp(-t * 22.0)) / RATE
		var env := exp(-t * 13.0) * minf(t * 500.0, 1.0)
		s[i] = (sin(phase) + 0.25 * sin(phase * 2.0)) * env + randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.4
	return _normalize(s, 0.42)

## A punch: a low thump falling in pitch plus a noise crack. A crit is longer and heavier and rings metallically.
static func _hit(crit: bool) -> PackedFloat32Array:
	var s := _buffer(0.45 if crit else 0.22)
	var phase := 0.0
	var noise := 0.0
	var a := _lp(3200.0 if crit else 2400.0)
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * ((45.0 + 170.0 * exp(-t * 28.0)) if crit else (60.0 + 130.0 * exp(-t * 32.0))) / RATE
		noise += a * (randf_range(-1.0, 1.0) - noise)
		var v := sin(phase) * exp(-t * (10.0 if crit else 17.0)) + noise * 1.6 * exp(-t * (30.0 if crit else 45.0))
		if crit:
			v += (sin(TAU * 1250.0 * t) + 0.7 * sin(TAU * 1870.0 * t) + 0.5 * sin(TAU * 2950.0 * t)) * 0.18 * exp(-t * 9.0)
		s[i] = tanh(v * 1.4)
	return _normalize(s, 0.85 if crit else 0.7)

## Three soft bell notes rising, with a shimmer
static func _heal() -> PackedFloat32Array:
	var s := _buffer(0.7)
	var notes := [880.0, 1318.5, 1760.0]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var nt := t - 0.07 * k
			if nt >= 0.0:
				var f: float = notes[k] * (1.0 + 0.004 * sin(TAU * 6.0 * nt))
				v += (sin(TAU * f * nt) + 0.2 * sin(TAU * f * 2.0 * nt)) * exp(-nt * 5.0) * minf(nt * 120.0, 1.0)
		s[i] = v
	return _normalize(s, 0.38)

## A falling groan that crumbles away
static func _knockout() -> PackedFloat32Array:
	var s := _buffer(0.65)
	var phase := 0.0
	var noise := 0.0
	var a := _lp(1100.0)
	var grain := 1.0
	for i in s.size():
		var t := float(i) / RATE
		var p := float(i) / s.size()
		phase += TAU * (60.0 + 340.0 * pow(1.0 - p, 2.0)) / RATE
		if i % 300 == 0:
			grain = randf_range(0.2, 1.0)
		noise += a * (randf_range(-1.0, 1.0) - noise)
		var tone := asin(sin(phase)) * 0.9  # triangle
		s[i] = (tone * 0.8 + noise * 2.2 * grain) * pow(1.0 - p, 2.0) * minf(t * 300.0, 1.0)
	return _normalize(s, 0.6)

## A rising rush that bursts into a bright "shing"
static func _ultimate() -> PackedFloat32Array:
	const RISE := 0.55
	var s := _buffer(1.0)
	var phase := 0.0
	var noise := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		if t < RISE:
			var p := t / RISE
			phase += TAU * (180.0 * pow(5.0, p)) / RATE
			noise += _lp(500.0 + 6000.0 * p) * (randf_range(-1.0, 1.0) - noise)
			v = (fposmod(phase / TAU, 1.0) * 2.0 - 1.0) * 0.35 * p * p + noise * 1.4 * pow(p, 1.5)
		var hit := t - RISE
		if hit >= 0.0:
			v += (sin(TAU * 2093.0 * hit) + 0.7 * sin(TAU * 3136.0 * hit) + 0.4 * sin(TAU * 4186.0 * hit)) * 0.5 * exp(-hit * 5.0)
			v += randf_range(-1.0, 1.0) * 0.6 * exp(-hit * 30.0)
		s[i] = v
	return _normalize(s, 0.6)

## Two quick drum hits and a big one
static func _wave() -> PackedFloat32Array:
	var s := _buffer(0.9)
	var hits := [[0.0, 0.6], [0.14, 0.6], [0.3, 1.0]]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for h in hits:
			var ht: float = t - h[0]
			if ht >= 0.0:
				var f := 65.0 + 70.0 * exp(-ht * 25.0)
				v += (sin(TAU * f * ht) + randf_range(-1.0, 1.0) * 0.3 * exp(-ht * 40.0)) * exp(-ht * (9.0 if h[1] < 1.0 else 4.5)) * h[1]
		s[i] = tanh(v * 1.5)
	return _normalize(s, 0.7)

## A harsh, wobbling stab of clashing notes
static func _jumpscare() -> PackedFloat32Array:
	var s := _buffer(1.3)
	var notes := [98.0, 103.8, 138.6, 146.8, 207.7, 220.0]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for f in notes:
			v += fposmod(f * t, 1.0) * 2.0 - 1.0
		v = v / notes.size() * (1.0 + 0.5 * sin(TAU * 11.0 * t)) + randf_range(-1.0, 1.0) * 0.5 * exp(-t * 12.0)
		s[i] = tanh(v * 3.0) * exp(-t * 2.2) * minf(t * 400.0, 1.0)
	return _normalize(s, 0.75)

## A wet, wobbling gurgle
static func _puke() -> PackedFloat32Array:
	var s := _buffer(0.5)
	var phase := 0.0
	var noise := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var p := float(i) / s.size()
		var wobble := sin(TAU * 32.0 * t)
		phase += TAU * (110.0 + 40.0 * wobble) / RATE
		noise += _lp(700.0 + 400.0 * wobble) * (randf_range(-1.0, 1.0) - noise)
		s[i] = (sin(phase) * 0.6 + noise * 2.5) * sin(PI * minf(p * 1.6, 1.0)) * (1.0 - p * 0.5)
	return _normalize(s, 0.5)

## Rising brass: C E G, then a held C chord
static func _victory() -> PackedFloat32Array:
	var s := _buffer(1.6)
	var notes := [[0.0, 523.25, 0.12], [0.12, 659.25, 0.12], [0.24, 783.99, 0.12],
		[0.4, 1046.5, 1.2], [0.4, 659.25, 1.2], [0.4, 783.99, 1.2]]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for n in notes:
			var nt: float = t - n[0]
			if nt >= 0.0:
				var env := minf(nt * 80.0, 1.0) * (exp(-nt * 1.6) if n[2] > 0.5 else exp(-maxf(nt - n[2] * 0.6, 0.0) * 25.0))
				v += _brass(TAU * n[1] * nt * (1.0 + 0.003 * sin(TAU * 5.0 * nt))) * env
		s[i] = v
	return _normalize(s, 0.45)

## Four slow falling notes, the last one sagging
static func _defeat() -> PackedFloat32Array:
	var s := _buffer(1.8)
	var notes := [[0.0, 392.0], [0.3, 370.0], [0.6, 349.2], [0.9, 329.6]]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var nt: float = t - notes[k][0]
			var last := k == notes.size() - 1
			if nt >= 0.0 and (last or nt < 0.34):
				var f: float = notes[k][1] * (1.0 - (0.02 * minf(nt, 0.8) if last else 0.0))
				var env := minf(nt * 60.0, 1.0) * (exp(-nt * 1.8) if last else exp(-nt * 4.0)) * (1.0 if last else minf((0.34 - nt) * 40.0, 1.0))
				v += asin(sin(TAU * f * nt)) * env
		s[i] = v
	return _normalize(s, 0.42)

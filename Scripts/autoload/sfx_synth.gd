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
	return PackedFloat32Array()

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

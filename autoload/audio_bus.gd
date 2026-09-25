extends Node
## AudioBus (SYSTEMS_EXPANSION §13): `AudioBus.event(name)` announces a game event. Listeners get
## the `fired` signal; the bus itself plays a tiny synthesized cue for it — restrained, short,
## generated at startup (no asset files) and rate-limited so frequent events never chatter. No
## per-packet sounds. The master volume is Settings → Sound (GameSettings).
##
## Events: usb_insert, usb_remove, wire_connect, wire_disconnect, machine_place, machine_delete,
## job_accept, job_reject, job_complete, fan_start, thermal_warning, power_overload, unlock.

signal fired(name: String)

const RATE := 22050
const VOICES := 6
## name -> [[freq Hz, dur s, start s, wave], ...], volume dB, min gap s
const CUES := {
	"usb_insert": [[[1320.0, 0.03, 0.0, "tick"], [880.0, 0.05, 0.035, "sine"]], -16.0, 0.05],
	"usb_remove": [[[880.0, 0.04, 0.0, "sine"], [620.0, 0.05, 0.04, "sine"]], -18.0, 0.05],
	"wire_connect": [[[1500.0, 0.025, 0.0, "tick"]], -18.0, 0.04],
	"wire_disconnect": [[[520.0, 0.04, 0.0, "tick"]], -20.0, 0.04],
	"machine_place": [[[220.0, 0.07, 0.0, "thunk"], [1800.0, 0.015, 0.0, "tick"]], -14.0, 0.05],
	"machine_delete": [[[300.0, 0.09, 0.0, "down"]], -18.0, 0.05],
	"job_accept": [[[1760.0, 0.02, 0.0, "sine"]], -30.0, 0.25],
	"job_reject": [[[330.0, 0.06, 0.0, "buzz"]], -24.0, 0.5],
	"job_complete": [[[523.25, 0.09, 0.0, "sine"], [659.25, 0.09, 0.09, "sine"], [783.99, 0.16, 0.18, "sine"]], -14.0, 1.0],
	"desk_bump": [[[240.0, 0.035, 0.0, "thunk"], [2100.0, 0.01, 0.0, "tick"]], -24.0, 0.07],
	"desk_tap": [[[170.0, 0.06, 0.0, "thunk"]], -20.0, 0.08],
	"quest_ready": [[[783.99, 0.07, 0.0, "sine"], [1046.5, 0.12, 0.07, "sine"]], -18.0, 1.0],
	"fan_start": [[[180.0, 0.35, 0.0, "whoosh"]], -24.0, 2.0],
	"thermal_warning": [[[660.0, 0.07, 0.0, "sine"], [550.0, 0.09, 0.08, "sine"]], -20.0, 2.0],
	"power_overload": [[[110.0, 0.18, 0.0, "buzz"]], -18.0, 2.0],
	"unlock": [[[659.25, 0.07, 0.0, "sine"], [987.77, 0.07, 0.07, "sine"], [1318.5, 0.14, 0.14, "sine"]], -16.0, 1.0],
}

var _streams := {}  # name -> AudioStreamWAV
var _last := {}  # name -> msec of the last play
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for n in CUES:
		_streams[n] = _synth(CUES[n][0])


## Announce `name`; plays its cue unless the same cue just played.
func event(name: String) -> void:
	fired.emit(name)
	if not CUES.has(name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -100000)) < int(float(CUES[name][2]) * 1000.0):
		return
	_last[name] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = float(CUES[name][1])
	p.play()


## Build a mono 16-bit clip from tone segments (freq, duration, start, waveform).
static func _synth(parts: Array) -> AudioStreamWAV:
	var total := 0.0
	for s in parts:
		total = maxf(total, float(s[2]) + float(s[1]))
	var n := int(total * RATE) + 64
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # the noise in ticks / whooshes is the same every run
	for s in parts:
		var f: float = s[0]
		var dur: float = s[1]
		var st := int(float(s[2]) * RATE)
		var len := int(dur * RATE)
		var ph := 0.0
		for i in len:
			var t := float(i) / RATE
			var env := minf(1.0, t / 0.004) * exp(-t / (dur * 0.35))  # 4 ms attack, fast decay
			var freq := f
			match str(s[3]):
				"down": freq = f * (1.0 - 0.5 * t / dur)
				"thunk": freq = f * (1.0 - 0.35 * t / dur)
			ph += TAU * freq / RATE
			var v := 0.0
			match str(s[3]):
				"tick": v = sin(ph) * 0.6 + rng.randf_range(-0.4, 0.4) * exp(-t / 0.004)
				"buzz": v = (1.0 if sin(ph) >= 0.0 else -1.0) * 0.35
				"whoosh": v = rng.randf_range(-1.0, 1.0) * 0.5 * sin(PI * t / dur)
				_: v = sin(ph)
			var k := st + i
			if k < n:
				buf[k] += v * env * 0.8
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

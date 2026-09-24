extends SceneTree
## AudioBus smoke:  timeout 60 godot --headless --path . -s tools/audio_smoke.gd
## Every cue synthesizes a non-empty clip; event() fires the signal every time but plays a cue
## at most once per its gap. Prints "AUDIO PASS".

var _fired := 0


func _process(_d: float) -> bool:
	var ab = root.get_node("/root/AudioBus")
	var fail := ""
	for n in ab.CUES:
		var st: AudioStreamWAV = ab._streams[n]
		if st == null or st.data.size() < 200:
			fail = "cue %s did not synthesize" % n
	ab.fired.connect(func(_n): _fired += 1)
	var before: int = ab._next
	for i in 5:
		ab.event("job_accept")
	if _fired != 5:
		fail = "the signal fired %d times for 5 events" % _fired
	if (ab._next - before + ab._players.size()) % ab._players.size() != 1:
		fail = "job_accept is rate-limited to one cue per burst"
	ab.event("not_a_cue")
	if fail != "":
		printerr("AUDIO FAIL: " + fail)
		quit(1)
	else:
		print("AUDIO PASS")
		quit(0)
	return true

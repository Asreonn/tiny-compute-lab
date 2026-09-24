class_name GameSettings
extends RefCounted
## Player settings (title screen → Settings), stored in SaveStore prefs and applied at launch:
## master volume (0–100 %), reduced motion (HudKit.REDUCED_MOTION), fullscreen, and whether the
## laptop intro plays.

const DEFAULTS := {"volume": 80, "reduced_motion": false, "fullscreen": false, "intro": true}


static func get_value(key: String) -> Variant:
	var p := SaveStore.load_prefs()
	return p.get(key, DEFAULTS[key])


static func set_value(key: String, value: Variant) -> void:
	SaveStore.save_prefs({key: value})
	apply()


## Apply every setting to the running game (safe to call any time).
static func apply() -> void:
	HudKit.REDUCED_MOTION = bool(get_value("reduced_motion"))
	var vol := clampi(int(get_value("volume")), 0, 100)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, vol == 0)
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(get_value("fullscreen")) else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and (want == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
			DisplayServer.window_set_mode(want)

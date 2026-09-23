class_name CameraRig
extends Camera2D

const HUD_LEFT := 336.0
const HUD_TOP := 68.0
## Slice A4a part 2 camera: pan with middle/right drag and WASD/arrows, wheel zoom in steps
## inside [0.5, 2.5], defaulting to a fit-to-board view. Emits zoom_tier_changed(tier)
## with "far" below Palette.ZOOM_FAR_BELOW, "close" above Palette.ZOOM_CLOSE_ABOVE and
## "normal" in between (VISUAL_SYSTEM §13).

signal zoom_tier_changed(tier: String)

const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.5
## Wheel zoom ladder; the wheel snaps to the nearest step inside [MIN_ZOOM, MAX_ZOOM].
const ZOOM_STEPS: Array[float] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.5]
const PAN_SPEED := 900.0  # world px/s at zoom 1.0

var _fit_rect := Rect2()
var _following_fit := true  # true until the player zooms/pans away from the fitted view
var _dragging := false
var _tier := ""


func _ready() -> void:
	_update_tier()


## Frame the given world rect: position on its centre, zoom so the whole rect is visible
## (clamped to the zoom ladder range). Called by World whenever the board changes.
func fit_board(rect: Rect2) -> void:
	_fit_rect = rect
	_following_fit = true
	_apply_fit()


## Explicit zoom (tools/shot.gd uses it). Clamps to [MIN_ZOOM, MAX_ZOOM] and leaves
## fit mode.
func set_zoom_level(z: float) -> void:
	_following_fit = false
	_zoom_to(z)


func _zoom_to(z: float) -> void:
	var c := clampf(z, MIN_ZOOM, MAX_ZOOM)
	if absf(c - zoom.x) > 0.0001:
		zoom = Vector2.ONE * c
		_update_tier()


func zoom_level() -> float:
	return zoom.x


func _apply_fit() -> void:
	if _fit_rect.size.x <= 0.0 or _fit_rect.size.y <= 0.0:
		return
	var vs := get_viewport_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	# Fit into the area the HUD leaves free: left panels (ToolRail + BuildPalette / MissionSummary)
	# end at 336 px, the TopBar at 52 (+16 margin); 16 px margins elsewhere.
	var safe := Rect2(Vector2(HUD_LEFT, HUD_TOP), vs - Vector2(HUD_LEFT + 16.0, HUD_TOP + 16.0))
	var z := minf(safe.size.x / _fit_rect.size.x, safe.size.y / _fit_rect.size.y) * 0.96
	_zoom_to(z)
	z = zoom.x
	position = _fit_rect.get_center() - (safe.get_center() - vs / 2.0) / z


func _process(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if not pan.is_zero_approx():
		_following_fit = false
		position += pan * PAN_SPEED * delta / zoom.x
	elif _following_fit:
		_apply_fit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel(1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel(-1)
	elif event is InputEventMouseMotion and _dragging:
		_following_fit = false
		position -= (event as InputEventMouseMotion).relative / zoom.x


func _wheel(direction: int) -> void:
	set_zoom_level(ZOOM_STEPS[clampi(_nearest_step(zoom.x) + direction, 0, ZOOM_STEPS.size() - 1)])


func _nearest_step(z: float) -> int:
	var best := 0
	var best_d := INF
	for i in ZOOM_STEPS.size():
		var d := absf(ZOOM_STEPS[i] - z)
		if d < best_d:
			best_d = d
			best = i
	return best


func _update_tier() -> void:
	var tier := "normal"
	if zoom.x < Palette.ZOOM_FAR_BELOW:
		tier = "far"
	elif zoom.x > Palette.ZOOM_CLOSE_ABOVE:
		tier = "close"
	if tier != _tier:
		_tier = tier
		zoom_tier_changed.emit(tier)
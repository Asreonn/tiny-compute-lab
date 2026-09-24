class_name CameraRig
extends Camera2D

const HUD_LEFT := 336.0
const HUD_TOP := 68.0
## Board camera (SYSTEMS_EXPANSION §9): pan with middle / right drag or Space + drag (with
## inertia) and the arrow keys; the wheel zooms smoothly towards the cursor in steps inside
## [0.5, 2.5]; defaulting to a fit-to-board view. A Space tap toggles play / pause. Emits zoom_tier_changed(tier)
## with "far" below Palette.ZOOM_FAR_BELOW, "close" above Palette.ZOOM_CLOSE_ABOVE and
## "normal" in between (VISUAL_SYSTEM §13).

signal zoom_tier_changed(tier: String)

const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.5
## Wheel zoom ladder; the wheel snaps to the nearest step inside [MIN_ZOOM, MAX_ZOOM].
const ZOOM_STEPS: Array[float] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.5]
const PAN_SPEED := 900.0  # world px/s at zoom 1.0

const INERTIA_DAMP := 8.0  # 1/s, exponential decay of the pan velocity after a drag
const ZOOM_SMOOTH := 14.0  # 1/s, exponential approach of the wheel zoom target

var _fit_rect := Rect2()
var _following_fit := true  # true until the player zooms/pans away from the fitted view
var _dragging := false
var _tier := ""
var _vel := Vector2.ZERO  # world px/s, pan inertia
var _frame_pan := Vector2.ZERO  # world px panned by the drag this frame
var _zoom_target := -1.0  # wheel zoom target (smooth), < 0 = none
var _zoom_anchor := Vector2.ZERO  # screen px the wheel zoom keeps fixed (the cursor)
var _space_down := false
var _space_panned := false  # a Space hold that panned is not a play/pause tap


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
	_zoom_target = -1.0
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
		_vel = Vector2.ZERO
		position += pan * PAN_SPEED * delta / zoom.x
	# drag inertia: measure while dragging, glide with exponential damping after release
	if _dragging:
		if delta > 0.0:
			_vel = _vel.lerp(_frame_pan / delta, 0.5)
		_frame_pan = Vector2.ZERO
	elif _vel.length() > 4.0:
		position += _vel * delta
		_vel *= exp(-INERTIA_DAMP * delta)
	else:
		_vel = Vector2.ZERO
	# smooth wheel zoom towards the cursor: the world point under it stays put
	if _zoom_target > 0.0:
		var z0 := zoom.x
		var z1 := lerpf(z0, _zoom_target, 1.0 - exp(-ZOOM_SMOOTH * delta))
		if absf(z1 - _zoom_target) < 0.002:
			z1 = _zoom_target
			_zoom_target = -1.0
		var half := get_viewport_rect().size * 0.5
		var world := position + (_zoom_anchor - half) / z0
		_zoom_to(z1)
		position = world - (_zoom_anchor - half) / zoom.x
	if pan.is_zero_approx() and not _dragging and _vel == Vector2.ZERO and _zoom_target < 0.0 and _following_fit:
		_apply_fit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if k.pressed:
			_space_down = true
			_space_panned = false
		elif _space_down:
			_space_down = false
			if not _space_panned:
				SimulationManager.toggle()  # a tap
			_dragging = false
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var space_pan := mb.button_index == MOUSE_BUTTON_LEFT and _space_down
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT or space_pan:
			_dragging = mb.pressed
			if mb.pressed:
				_vel = Vector2.ZERO
				_frame_pan = Vector2.ZERO
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel(1, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel(-1, mb.position)
	elif event is InputEventMouseMotion and _dragging:
		_following_fit = false
		var d := (event as InputEventMouseMotion).relative / zoom.x
		position -= d
		_frame_pan -= d
		if _space_down:
			_space_panned = true


func _wheel(direction: int, at: Vector2) -> void:
	_following_fit = false
	var from := _zoom_target if _zoom_target > 0.0 else zoom.x
	_zoom_target = ZOOM_STEPS[clampi(_nearest_step(from) + direction, 0, ZOOM_STEPS.size() - 1)]
	_zoom_anchor = at


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
@icon("res://addons/godot_texture_atlas/icon_atlas_sprite.svg")
@tool
## Plays Adobe Animate sprite atlases in Godot.
class_name AtlasSprite
extends Node2D

# Base key mapping from Adobe Animate JSON
const NAMES_BASE = {
	"ANIMATION": "AN",
	"SYMBOL_DICTIONARY": "SD",
	"TIMELINE": "TL",
	"LAYERS": "L",
	"Frames": "FR",
	"Symbols": "S",
	"name": "N",
	"SYMBOL_name": "SN",
	"elements": "E",
	"Layer_name": "LN",
	"index": "I",
	"duration": "DU",
	"ATLAS_SPRITE_instance": "ASI",
	"Instance_Name": "IN",
	"symbolType": "ST",
	"movieclip": "MC",
	"graphic": "G",
	"firstFrame": "FF",
	"loop": "LP",
	"Matrix3D": "M3D",
	"metadata": "MD",
	"framerate": "FRT"
}

# Inspector properties
@export var animations: Array[AtlasAnimInfo] = [] ## Array of animations this sprite can play
@export var animation: int = 0: ## Active animation index
	set(value):
		animation = value
		_load_current_animation()

@export var frame: int = 0: ## Current frame of the active animation
	set(value):
		frame = value
		queue_redraw()
		
@export var fps: int = 24 ## Frames per second
@export_tool_button("Reload Atlas") var reload_atlas = _load_current_animation ## Reload atlas button
@export_tool_button("Create Animation Player") var create_animplayer = _create_animation_player ## Create animations in child AnimationPlayer

# Internal variables
var _animation_json: Dictionary
var spritemap_tex: Texture2D
var spritemap_json: JSON
var symbols: Dictionary[String, Array] = {}
var limbs: Dictionary[String, Rect2i] = {}
var NAMES: Dictionary
var timeline_length: int = 0
var is_optimized: bool = false
var _current_animation: AtlasAnimInfo = null
var _loaded_json: JSON = null

func _ready() -> void:
	_update_current_animation()
	_load_current_animation()

# Set active animation by index
func set_current_anim(index: int) -> void:
	if index < 0 or index >= animations.size():
		push_warning("Invalid animation index ", index)
		return
	animation = index
	_update_current_animation()
	_load_current_animation(false)
	queue_redraw()

# Update reference to current animation
func _update_current_animation() -> void:
	if animations.size() == 0:
		_current_animation = null
	else:
		_current_animation = animations[animation]

# Load JSON and texture atlas for current animation
func _load_current_animation(reset_frame: bool=true) -> void:
	_update_current_animation()
	
	if _current_animation == null or _current_animation.animation_json == null:
		return

	if _current_animation.animation_json == _loaded_json:
		pass

	var dir = _current_animation.animation_json.resource_path.get_base_dir()
	spritemap_tex = load(dir.path_join("spritemap1.png"))
	spritemap_json = load(dir.path_join("spritemap1.json"))
	_animation_json = _current_animation.animation_json.data.duplicate(true)
	
	is_optimized = _animation_json.has("AN")
	NAMES = NAMES_BASE.duplicate()
	limbs.clear()
	symbols.clear()
	
	if not is_optimized:
		for key in NAMES:
			NAMES[key] = key
	
	# Build limbs from texture atlas
	for _sprite in spritemap_json.data["ATLAS"]["SPRITES"]:
		var sprite = _sprite["SPRITE"]
		limbs[sprite["name"]] = Rect2i(int(sprite["x"]), int(sprite["y"]), int(sprite["w"]), int(sprite["h"]))
	
	# Build symbols from JSON
	if _animation_json.has(NAMES["SYMBOL_DICTIONARY"]):
		for symbol_data in _animation_json[NAMES["SYMBOL_DICTIONARY"]][NAMES["Symbols"]]:
			symbols[symbol_data[NAMES["SYMBOL_name"]]] = symbol_data[NAMES["TIMELINE"]][NAMES["LAYERS"]]
			symbols[symbol_data[NAMES["SYMBOL_name"]]].reverse()
	
	# Ensure top-level timeline exists
	symbols["_top"] = _animation_json[NAMES["ANIMATION"]][NAMES["TIMELINE"]][NAMES["LAYERS"]]
	symbols["_top"].reverse()
	
	timeline_length = get_timeline_length(_get_layers())
	
	if reset_frame:
		frame = 0
	
	_loaded_json = _current_animation.animation_json
	queue_redraw()

# Draw
func _draw() -> void:
	if symbols.size() > 0:
		_draw_timeline(_get_layers(), frame)

# Get layers for current animation
func _get_layers() -> Array:
	if _current_animation == null:
		return symbols["_top"]
	return symbols["_top"]

# Compute total timeline length
func get_timeline_length(layers: Array) -> int:
	var longest_length = 0
	for layer in layers:
		var total_duration: int = 0
		for frame_data in layer[NAMES["Frames"]]:
			total_duration += frame_data[NAMES["duration"]]
		if total_duration > longest_length:
			longest_length = total_duration
	return longest_length

# Get frame and its index at a specific timeline frame
func _get_frame_and_index(target_frame: int, frames: Array) -> Dictionary:
	var accumulated_frames = 0
	for i in range(frames.size()):
		accumulated_frames += frames[i][NAMES["duration"]]
		if target_frame <= accumulated_frames:
			return {"frame": frames[i], "index": i}
	return {"frame": {}, "index": 0}

# Draw timeline recursively
func _draw_timeline(layers: Array, starting_frame: int, transformation: Transform2D = Transform2D()) -> void:
	for layer in layers:
		var frame_data = _get_frame_and_index(starting_frame, layer[NAMES["Frames"]])
		var frame_dict = frame_data["frame"]
		var frame_index = frame_data["index"]
		
		if frame_dict.size() == 0:
			continue
		
		for element_type in frame_dict[NAMES["elements"]]:
			var type = element_type.keys()[0]
			var element = element_type[type]
			var transform_2d = transformation * _m3d_to_transform2d(element[NAMES["Matrix3D"]])
			
			match type:
				"ATLAS_SPRITE_instance", "ASI":
					var limb = limbs[element[NAMES["name"]]]
					draw_set_transform_matrix(transform_2d)
					draw_texture_rect_region(spritemap_tex, Rect2i(0, 0, limb.size.x, limb.size.y), limb)
				"SYMBOL_Instance", "SI":
					var new_starting_frame = 0
					if element[NAMES["symbolType"]] == NAMES["movieclip"]:
						new_starting_frame = frame_index
					else:
						new_starting_frame = element[NAMES["firstFrame"]] + 1
					_draw_timeline(symbols[element[NAMES["SYMBOL_name"]]], new_starting_frame, transform_2d)
				_:
					push_warning("Unsupported type ", type, "!")

# Convert 3D matrix to 2D transform
func _m3d_to_transform2d(matrix) -> Transform2D:
	var x_axis: Vector2
	var y_axis: Vector2
	var translation: Vector2
	
	if is_optimized:
		x_axis = Vector2(matrix[0], matrix[1])
		y_axis = Vector2(matrix[4], matrix[5])
		translation = Vector2(matrix[12], matrix[13])
	else:
		x_axis = Vector2(matrix["m00"], matrix["m01"])
		y_axis = Vector2(matrix["m10"], matrix["m11"])
		translation = Vector2(matrix["m30"], matrix["m31"])
	
	return Transform2D(x_axis, y_axis, translation)

# Create AnimationPlayer tracks for all animations
func _create_animation_player() -> void:
	var anim_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
	if anim_player == null:
		push_error("Must have an AnimationPlayer as a child!")
		return
	
	for anim_info in animations:
		if anim_info.symbol_name == "":
			continue
		
		var layers = symbols.get(anim_info.symbol_name, symbols["_top"])
		var total_frames = get_timeline_length(layers)
		if total_frames <= 0:
			continue
		
		var anim = Animation.new()
		anim.length = float(total_frames) / fps
		anim.loop_mode = anim_info.loop_mode
		
		# Track animation index
		var track_anim_index = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_anim_index, ".:animation")
		anim.value_track_set_update_mode(track_anim_index, Animation.UPDATE_DISCRETE)
		anim.track_insert_key(track_anim_index, 0.0, animations.find(anim_info))
		
		# Track frame
		var track_frame = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_frame, ".:frame")
		anim.track_insert_key(track_frame, 0, 0)
		anim.track_insert_key(track_frame, anim.length, total_frames)
		
		# Animation name
		var anim_name = anim_info.symbol_name.replace("/", "_").replace(" ", "_")
		
		var lib: AnimationLibrary
		if not anim_player.has_animation_library("AtlasSymbols"):
			lib = AnimationLibrary.new()
			anim_player.add_animation_library("AtlasSymbols", lib)
		else:
			lib = anim_player.get_animation_library("AtlasSymbols")
		
		lib.add_animation(anim_name, anim)

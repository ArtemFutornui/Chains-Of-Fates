extends Node3D

var chunkManager:Node3D

var terminated:= false
var threadGenerate: Thread

var is_generated:= true
var mapGenerator: MapGenerator
var chunks_for_generate: Array[Vector2i]

var map_size: int
var worldImage: ImageTexture
var worldName: String
var worldSeed: String

func _ready() -> void:
	if get_children().size() == 0:
		return
	Globals.spawn_ready = false
	var spawn_timer := Timer.new()
	spawn_timer.one_shot = true
	spawn_timer.wait_time = 0.8
	add_child(spawn_timer)
	spawn_timer.timeout.connect(func(): Globals.spawn_ready = true)
	spawn_timer.start()
	chunkManager = get_child(0)
	if Globals.generateDuringLoading:
		is_generated = false
		mapGenerator = Globals.mapGenerator
		chunks_for_generate = Globals.all_chunks_coords.duplicate()
		threadGenerate = Thread.new()
		threadGenerate.start(generate_remaining_chunks)
	var chunks := Globals.chunks
	for chunk_pos in chunks.keys():
		chunkManager.add_chunk(chunk_pos,chunks[chunk_pos])
	
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	var color_rect = ColorRect.new()
	color_rect.color = Color.BLACK
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(color_rect)
	
	map_size = Globals.map_size
	_draw_border_lines(map_size)
	worldImage = Globals.imageTexture
	worldName = Globals.worldName
	worldSeed = Globals.worldSeed
	Globals.clear_data()
	
	await get_tree().process_frame
	await get_tree().process_frame
	var camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("snap_to_target"):
		camera.snap_to_target()
	
	var tween = create_tween()
	tween.tween_property(color_rect, "modulate:a", 0.0, 0.5)
	tween.tween_callback(canvas_layer.queue_free)

func _process(delta: float) -> void:
	if is_terminated():
		return
		
	if has_node("/root/TimeManager") and has_node("DirectionalLight3D"):
		var tm = get_node("/root/TimeManager")
		var time = tm.get_time_of_day()
		update_day_night_cycle(time)


func generate_remaining_chunks() -> void:
	while chunks_for_generate.size() != 0:
		if is_terminated():
			return
		var coord := chunks_for_generate[0]
		var chunk := mapGenerator.generate_chunk(coord.x,coord.y)
		chunkManager.add_chunk(coord, chunk)
		chunks_for_generate.remove_at(0)
	chunks_for_generate.clear()
	mapGenerator.clear_data()
	mapGenerator.queue_free()
	is_generated = true
	print("Map ready")

func is_terminated() -> bool:
	return terminated

func _draw_border_lines(map_size: int):
	var mesh = ImmediateMesh.new()
	var line_width: float = 0.05

	var half_x = map_size / 2.0
	var half_z = map_size / 2.0

	var points = [
		Vector3(-half_x, 0, -half_z),
		Vector3(half_x, 0, -half_z),
		Vector3(half_x, 0, half_z),
		Vector3(-half_x, 0, half_z),
		Vector3(-half_x, 0, -half_z) # Замкнути контур
	]

	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var shader = load("res://materials/border_lines.gdshader")
	var material = ShaderMaterial.new()
	material.shader = shader
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.material_override = material
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunkManager.add_child.call_deferred(mesh_instance)

func close_scene() -> void:
	terminated = true
	if threadGenerate and threadGenerate.is_started():
		threadGenerate.wait_to_finish()
	threadGenerate = null
	if mapGenerator:
		mapGenerator.clear_data()
		mapGenerator.queue_free()
	chunks_for_generate.clear()
	worldImage = null
	chunkManager.remove_chunks()
	
func update_day_night_cycle(time: float) -> void:
	# Sun Rotation
	# 00:00 -> 90 deg (down), 06:00 -> 0 deg (horizon), 12:00 -> -90 deg (up)
	var angle = 90.0 - (time * 15.0)
	$DirectionalLight3D.rotation_degrees.x = angle

	# Sun Visibility & Intensity (Fix artifacts)
	if time > 5.5 and time < 18.5:
		$DirectionalLight3D.visible = true
		var fade = 1.0
		if time < 7.0:
			fade = (time - 5.5) / 1.5
		elif time > 17.0:
			fade = (18.5 - time) / 1.5
		
		# Clamp fade
		fade = clamp(fade, 0.0, 1.0)
		
		$DirectionalLight3D.light_energy = fade
		# Reduce shadow opacity near horizon to prevent artifacts
		$DirectionalLight3D.shadow_opacity = fade * 0.7 
	else:
		$DirectionalLight3D.visible = false

	# Sky Colors
	if not has_node("WorldEnvironment"): return
	var env = $WorldEnvironment.environment
	if not env or not env.sky: return
	var sky_mat = env.sky.sky_material
	if not sky_mat: return
	
	var top_color: Color
	var horizon_color: Color
	
	# Colors
	var night_top = Color(0.02, 0.02, 0.05)
	var night_horizon = Color(0.05, 0.05, 0.1)
	
	var dawn_top = Color(0.1, 0.2, 0.4)
	var dawn_horizon = Color(1.0, 0.4, 0.2)
	
	var day_top = Color(0.36, 0.62, 0.91)
	var day_horizon = Color(0.47, 0.83, 0.93)
	
	var dusk_top = Color(0.1, 0.1, 0.3)
	var dusk_horizon = Color(0.8, 0.2, 0.1)
	
	if time >= 0 and time < 5:
		top_color = night_top
		horizon_color = night_horizon
	elif time >= 5 and time < 7:
		var t = (time - 5.0) / 2.0
		top_color = night_top.lerp(dawn_top, t)
		horizon_color = night_horizon.lerp(dawn_horizon, t)
	elif time >= 7 and time < 9: # Transition Dawn -> Day
		var t = (time - 7.0) / 2.0
		top_color = dawn_top.lerp(day_top, t)
		horizon_color = dawn_horizon.lerp(day_horizon, t)
	elif time >= 9 and time < 16: # Full Day
		top_color = day_top
		horizon_color = day_horizon
	elif time >= 16 and time < 18: # Day -> Dusk
		var t = (time - 16.0) / 2.0
		top_color = day_top.lerp(dusk_top, t)
		horizon_color = day_horizon.lerp(dusk_horizon, t)
	elif time >= 18 and time < 20: # Dusk -> Night
		var t = (time - 18.0) / 2.0
		top_color = dusk_top.lerp(night_top, t)
		horizon_color = dusk_horizon.lerp(night_horizon, t)
	else: # Night
		top_color = night_top
		horizon_color = night_horizon
		
	sky_mat.sky_top_color = top_color
	sky_mat.sky_horizon_color = horizon_color
	sky_mat.ground_bottom_color = top_color
	sky_mat.ground_horizon_color = horizon_color

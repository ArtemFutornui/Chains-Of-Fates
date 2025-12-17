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
	# Ensure MoonLight exists
	var moon_light = get_node_or_null("MoonLight")
	if not moon_light:
		moon_light = DirectionalLight3D.new()
		moon_light.name = "MoonLight"
		moon_light.light_color = Color(0.6, 0.7, 0.9) # Cold blue moon
		moon_light.light_energy = 0.0
		moon_light.shadow_enabled = true
		add_child(moon_light)

	# Sun Rotation (06:00 = 0 deg horizon)
	# We want Sun up roughly 05:00 - 22:00 based on user phases, but physically 
	# it needs to rotate. Let's map 06:00 to 0 (rise) and 18:00 to 180 (set) normally.
	# But user wants specific phases: Morning 5-11, Day 11-16, Evening 16-22, Night 22-5.
	# This implies a very long "day" (5 to 22 = 17 hours of light).
	# We can slow down the sun rotation to fit this.
	
	var sun_angle = -90.0 # Default noon
	if time >= 5.0 and time <= 22.0:
		# Map 5..22 range to -10 (rise) .. 190 (set) degrees roughly
		var t = (time - 5.0) / (22.0 - 5.0) # 0.0 to 1.0
		sun_angle = 10.0 - (t * 200.0) # Start at 10 (just above horizon?) No, 0 is horizon.
		# Standard: 0 = Horizon East (Left?), -90 = Top, 180 = Horizon West.
		# Godot: 0 is horizon. -90 is Zenith.
		# Let's map 0.0 -> 0 deg (Rise), 0.5 -> -90 deg (Noon), 1.0 -> -180 deg (Set)
		sun_angle = 0.0 - (t * 180.0)
	else:
		# Night time rotation
		sun_angle = 90.0 # Down

	$DirectionalLight3D.rotation_degrees.x = sun_angle
	moon_light.rotation_degrees.x = sun_angle + 180.0 # Opposite to sun

	# Sun Intensity
	if time >= 5.0 and time <= 22.0:
		$DirectionalLight3D.visible = true
		var fade = 1.0
		# Fade in morning (5-7)
		if time < 7.0:
			fade = (time - 5.0) / 2.0
		# Fade out evening (20-22)
		elif time > 20.0:
			fade = (22.0 - time) / 2.0
		
		fade = clamp(fade, 0.0, 1.0)
		$DirectionalLight3D.light_energy = fade
		$DirectionalLight3D.shadow_opacity = fade * 0.8
		moon_light.visible = false
		moon_light.light_energy = 0.0
	else:
		$DirectionalLight3D.visible = false
		$DirectionalLight3D.light_energy = 0.0
		
		# Moon Intensity
		moon_light.visible = true
		var fade = 1.0
		# Fade in (22-23)
		if time >= 22.0 and time < 23.0:
			fade = time - 22.0
		# Fade out (4-5)
		elif time >= 4.0 and time < 5.0:
			fade = 5.0 - time
			
		moon_light.light_energy = fade * 0.3 # Moon is dimmer
		moon_light.shadow_opacity = fade * 0.5

	# Sky Colors & Fog
	if not has_node("WorldEnvironment"): return
	var env = $WorldEnvironment.environment
	if not env or not env.sky: return
	var sky_mat = env.sky.sky_material
	if not sky_mat: return
	
	var top_color: Color
	var horizon_color: Color
	
	var night_top = Color(0.02, 0.02, 0.08)
	var night_horizon = Color(0.05, 0.05, 0.15)
	
	var dawn_top = Color(0.2, 0.4, 0.7)
	var dawn_horizon = Color(1.0, 0.5, 0.3) # Orange/Red
	
	var day_top = Color(0.36, 0.62, 0.91)
	var day_horizon = Color(0.6, 0.85, 0.95)
	
	var dusk_top = Color(0.15, 0.2, 0.4)
	var dusk_horizon = Color(0.8, 0.3, 0.1) # Red/Purple
	
	# Phases based on user request:
	# Morning: 5-11
	# Day: 11-16
	# Evening: 16-22
	# Night: 22-5
	
	if time >= 5.0 and time < 11.0: # Morning
		if time < 7.0: # 5-7: Night -> Dawn
			var t = (time - 5.0) / 2.0
			top_color = night_top.lerp(dawn_top, t)
			horizon_color = night_horizon.lerp(dawn_horizon, t)
		else: # 7-11: Dawn -> Day
			var t = (time - 7.0) / 4.0
			top_color = dawn_top.lerp(day_top, t)
			horizon_color = dawn_horizon.lerp(day_horizon, t)
			
	elif time >= 11.0 and time < 16.0: # Day
		top_color = day_top
		horizon_color = day_horizon
		
	elif time >= 16.0 and time < 22.0: # Evening
		if time < 19.0: # 16-19: Day -> Dusk
			var t = (time - 16.0) / 3.0
			top_color = day_top.lerp(dusk_top, t)
			horizon_color = day_horizon.lerp(dusk_horizon, t)
		else: # 19-22: Dusk -> Night
			var t = (time - 19.0) / 3.0
			top_color = dusk_top.lerp(night_top, t)
			horizon_color = dusk_horizon.lerp(night_horizon, t)
			
	else: # Night (22 - 5)
		top_color = night_top
		horizon_color = night_horizon
		
	sky_mat.sky_top_color = top_color
	sky_mat.sky_horizon_color = horizon_color
	sky_mat.ground_bottom_color = top_color
	sky_mat.ground_horizon_color = horizon_color
	
	# Fog & Ambient Adaptation
	env.fog_enabled = true
	env.fog_light_color = horizon_color
	env.fog_density = 0.0002 # Default light fog
	
	# Adjust fog density for atmosphere
	if time >= 5.0 and time < 8.0: # Morning mist
		env.fog_density = 0.0015
	elif time >= 20.0 or time < 5.0: # Night haze
		env.fog_density = 0.0008
		
	# Ambient light to prevent "no shadows" flat look (provides fill)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = top_color
	
	# Intensity of ambient light
	if time >= 11.0 and time < 16.0:
		env.ambient_light_energy = 0.2 # Day: sun is main source
	elif time >= 22.0 or time < 5.0:
		env.ambient_light_energy = 0.05 # Night: very dark ambient, rely on MoonLight
	else:
		env.ambient_light_energy = 0.1 # Transition

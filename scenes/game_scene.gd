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

	# --- Rotation Logic (Continuous) ---
	# Day: 5:00 - 22:00 (17h). Angle: 0 (Rise) -> -180 (Set)
	# Night: 22:00 - 5:00 (7h). Angle: -180 (Set) -> -360 (Rise)
	
	var sun_angle_x: float = 0.0
	
	if time >= 5.0 and time <= 22.0:
		var t = (time - 5.0) / 17.0
		sun_angle_x = 0.0 - (t * 180.0)
	else:
		# Night mapping
		var t_night = 0.0
		if time > 22.0:
			t_night = time - 22.0
		else:
			t_night = (24.0 - 22.0) + time # 2h + time
			
		var t = t_night / 7.0
		sun_angle_x = -180.0 - (t * 180.0)

	# Apply rotation
	# Y = -90 ensures X rotation moves East -> Up -> West
	$DirectionalLight3D.rotation_degrees = Vector3(sun_angle_x, -90.0, 0.0)
	moon_light.rotation_degrees = Vector3(sun_angle_x + 180.0, -90.0, 0.0)

	# --- Sun Intensity & Color ---
	var sun_color_day = Color(1.0, 1.0, 1.0)
	var sun_color_horizon = Color(1.0, 0.7, 0.4)
	
	# Default to hidden/off, enable based on time
	$DirectionalLight3D.visible = false
	$DirectionalLight3D.light_energy = 0.0
	moon_light.visible = false
	moon_light.light_energy = 0.0

	if time >= 5.0 and time <= 22.0:
		$DirectionalLight3D.visible = true
		var fade = 1.0
		
		# Morning Fade In (5:00 - 7:00)
		if time < 7.0:
			fade = (time - 5.0) / 2.0
			var color_mix = 1.0 - fade
			$DirectionalLight3D.light_color = sun_color_day.lerp(sun_color_horizon, color_mix)
			
		# Evening Fade Out (20:30 - 22:00) - Start LATER as requested
		elif time > 20.5:
			# 20:30 -> 1.0, 22:00 -> 0.0
			fade = (22.0 - time) / 1.5
			
			# Color Transition (starts at 20:00)
			# 20:00 -> White, 22:00 -> Orange
			var t_color = clamp((time - 20.0) / 2.0, 0.0, 1.0)
			$DirectionalLight3D.light_color = sun_color_day.lerp(sun_color_horizon, t_color)
			
		else:
			# Mid Day
			$DirectionalLight3D.light_color = sun_color_day
			
			# Slight color tint during late afternoon (18:00 - 20:00) - Golden Hour
			if time > 18.0:
				var t_gold = (time - 18.0) / 2.5 
				t_gold = clamp(t_gold, 0.0, 1.0)
				var gold_color = Color(1.0, 0.9, 0.8)
				$DirectionalLight3D.light_color = sun_color_day.lerp(gold_color, t_gold)

		fade = clamp(fade, 0.0, 1.0)
		$DirectionalLight3D.light_energy = fade
		# Quadratic fade for shadows to prevent "sharp" appearance at low angles
		$DirectionalLight3D.shadow_opacity = fade * fade * 0.8
		
		# Moon logic during day (only visible very late?)
		if time > 21.5:
			moon_light.visible = true
			var moon_fade = (time - 21.5) * 2.0
			moon_light.light_energy = moon_fade * 0.3
			moon_light.shadow_opacity = moon_fade * 0.5

	else:
		# Night
		moon_light.visible = true
		var fade = 1.0
		
		# Fade out morning (4:00 - 5:00)
		if time >= 4.0 and time < 5.0:
			fade = 5.0 - time
		
		moon_light.light_energy = fade * 0.3 
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
	
	var dusk_top = Color(0.1, 0.15, 0.3)
	var dusk_horizon = Color(0.7, 0.4, 0.2)
	
	# Fog Density Targets
	var target_fog_density = 0.0002
	
	if time >= 5.0 and time < 11.0: # Morning
		if time < 7.0: # 5-7: Night -> Dawn
			var t = (time - 5.0) / 2.0
			top_color = night_top.lerp(dawn_top, t)
			horizon_color = night_horizon.lerp(dawn_horizon, t)
			target_fog_density = lerpf(0.0008, 0.0015, t) # Night haze -> Morning mist
		else: # 7-11: Dawn -> Day
			var t = (time - 7.0) / 4.0
			top_color = dawn_top.lerp(day_top, t)
			horizon_color = dawn_horizon.lerp(day_horizon, t)
			target_fog_density = lerpf(0.0015, 0.0002, t) # Mist -> Clear
			
	elif time >= 11.0 and time < 16.0: # Day
		top_color = day_top
		horizon_color = day_horizon
		target_fog_density = 0.0002
		
	elif time >= 16.0 and time < 22.0: # Evening
		if time < 20.0: # 16-20: Day -> Golden Hour
			var t = (time - 16.0) / 4.0
			var golden_top = day_top.darkened(0.05)
			var golden_horizon = day_horizon.lerp(Color(1.0, 0.9, 0.6), 0.6)
			
			top_color = day_top.lerp(golden_top, t)
			horizon_color = day_horizon.lerp(golden_horizon, t)
			target_fog_density = 0.0002
			
		else: # 20-22: Golden -> Dusk -> Night (Sunset Phase)
			var t = (time - 20.0) / 2.0 # 0.0 to 1.0
			
			# 20:00 is Golden/Start Sunset
			var start_top = day_top.darkened(0.05)
			var start_horizon = Color(1.0, 0.9, 0.6)
			
			if t < 0.75: # 20:00 - 21:30 (Sunset)
				var sub_t = t / 0.75
				top_color = start_top.lerp(dusk_top, sub_t)
				horizon_color = start_horizon.lerp(dusk_horizon, sub_t)
				target_fog_density = lerpf(0.0002, 0.0005, sub_t)
			else: # 21:30 - 22:00 (Dusk -> Night)
				var sub_t = (t - 0.75) / 0.25
				top_color = dusk_top.lerp(night_top, sub_t)
				horizon_color = dusk_horizon.lerp(night_horizon, sub_t)
				target_fog_density = lerpf(0.0005, 0.0008, sub_t)
			
	else: # Night (22 - 5)
		top_color = night_top
		horizon_color = night_horizon
		target_fog_density = 0.0008
		
	sky_mat.sky_top_color = top_color
	sky_mat.sky_horizon_color = horizon_color
	sky_mat.ground_bottom_color = top_color
	sky_mat.ground_horizon_color = horizon_color
	
	# Fog & Ambient Adaptation
	env.fog_enabled = true
	env.fog_light_color = horizon_color
	env.fog_density = target_fog_density # Use smooth target
	
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

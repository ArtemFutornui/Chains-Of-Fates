@tool
extends Node3D

@export_tool_button("Update")
var update = func():
	generate_map()
@export var map_seed :int = 0
@export var map_size :int = 4096


var chunkManager
var grass
@export var terminated := true

var block_mask_image : Image
var block_mask_tex : ImageTexture

func _ready() -> void:
	generate_map()

var thread: Thread
var thread2: Thread

func generate_map() -> void:
	if get_children().size() != 0 and !terminated:
		print("start")
		chunkManager = get_child(0)
		chunkManager.remove_chunks()
		grass = get_child(-1)
		thread = Thread.new()
		thread.start(genaration_chunks)
	
func genaration_chunks() -> void:
	var map_generator = MapGenerator.new(map_seed,map_size)
	map_generator.pregen_chunks()
	for point in get_children():
		if point.is_in_group("test"):
			point.queue_free()
	for point in map_generator.test_arr:
		var meshinst = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		meshinst.mesh = mesh
		mesh.radius = 5.0
		mesh.height = 10.0
		meshinst.position = Vector3(point.x, 10, point.y)
		meshinst.add_to_group("test")
		add_child.call_deferred(meshinst)
	
	#thread2 = Thread.new()
	#thread2.start(generate_textures.bind(map_generator))
	
	var chunks_per_axis = map_size / map_generator.chunk_size
	var half_chunks = chunks_per_axis/2
	var chunk_coords := []
	var existing_coords := {}
	# Центр мапи знаходиться між чанками, тобто між (0,0), (-1,0), (0,-1), (-1,-1)
	# Тому центр координат зміщуємо на півчанка
	var center_offset = Vector2(0.5, 0.5)
	
	#Зберігаємо всі координати чанків
	for x in range(-half_chunks, half_chunks):
		for z in range(-half_chunks, half_chunks):
			var coord = Vector2i(x, z)
			chunk_coords.append(coord)
			existing_coords[coord] = true

	#Сортуємо їх за відстанню до центру (0,0)
	chunk_coords.sort_custom(func(a, b):
		var a_dist = (Vector2(a) + center_offset).length_squared()
		var b_dist = (Vector2(b) + center_offset).length_squared()
		return a_dist < b_dist
	)

	#Генеруємо чанки в порядку наближеності до центру
	for coord in chunk_coords:
		if is_terminated():
			return
		var final_chunk := map_generator.generate_chunk(coord.x, coord.y)
		chunkManager.add_chunk(coord, final_chunk)
	
	_draw_border_lines(map_size)
	# Далі генеруємо чанки за межами мапи
	var extra_layers = map_generator.layers_from_border  # кількість шарів
	for layer in range(1, extra_layers + 1):
		var new_half_chunks = half_chunks + layer
		var layer_coords := []

		for x in range(-new_half_chunks, new_half_chunks):
			for z in range(-new_half_chunks, new_half_chunks):
				# Периметр — пропускаємо внутрішні координати
				if x == -new_half_chunks or x == new_half_chunks - 1 or z == -new_half_chunks or z == new_half_chunks - 1:
					continue

				var coord = Vector2i(x, z)
				if coord in existing_coords:
					continue  # не дублюємо вже існуючі

				layer_coords.append(coord)
				existing_coords[coord] = true

		# --- Генеруємо нові чанки за допомогою іншої функції ---
		for coord in layer_coords:
			if is_terminated():
				return
			var final_chunk := map_generator.generate_chunk(coord.x, coord.y)
			chunkManager.add_chunk(coord, final_chunk)
			
	print("finish")
	thread.call_deferred("wait_to_finish")
	terminated = true
	
func generate_textures(map_generator: MapGenerator) -> void:
	map_generator.generate_height_and_normal_textures(2)
	var material = grass.process_material
	block_mask_image = Image.create(map_size, map_size, false, Image.FORMAT_RF)
	block_mask_image.fill(Color(0, 0, 0)) # 0 = трава дозволена, 1 = заборонена
	block_mask_tex = ImageTexture.create_from_image(block_mask_image)
	material.set_shader_parameter("block_mask", block_mask_tex)
	material.set_shader_parameter("height_map", map_generator.heights)
	material.set_shader_parameter("normal_map", map_generator.normals)
	material.set_shader_parameter("map_size", float(map_size))
	grass.noise.seed = map_seed
	print("load grass finish")
	thread2.call_deferred("wait_to_finish")

func _exit_tree() -> void:
	if thread:
		thread.wait_to_finish()
	if thread2:
		thread2.wait_to_finish()

func is_terminated() -> bool:
	return terminated

func _draw_border_lines(map_size: int):
	var mesh = ImmediateMesh.new()
	var line_color: Color = Color(1.0, 0, 0, 1.0)
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
	var material = StandardMaterial3D.new()
	material.albedo_color = line_color
	material.no_depth_test = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.material_override = material
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunkManager.add_child.call_deferred(mesh_instance)

func block_unblock_grass_area_world(rect: Rect2, block:int): #якщо block > 0 то забороняється трава на піскселі, якщо < 0, то дозволяється
	if block < 0:
		block = 0
	elif block > 1:
		block = 1
	var tex_width = block_mask_image.get_width()
	var tex_height = block_mask_image.get_height()

	var world_to_pixel := func(pos: Vector2) -> Vector2i:
		var uv = (pos + Vector2(map_size * 0.5, map_size * 0.5)) / map_size
		uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
		return Vector2i(uv.x * tex_width, uv.y * tex_height)

	var from_px: Vector2i = world_to_pixel.call(rect.position)
	var to_px: Vector2i = world_to_pixel.call(rect.position + rect.size)

	for x in range(from_px.x, to_px.x):
		for y in range(from_px.y, to_px.y):
			if x >= 0 and y >= 0 and x < tex_width and y < tex_height:
				block_mask_image.set_pixel(x, y, Color(block, 0, 0)) # 1 = блок
	block_mask_tex.update(block_mask_image)

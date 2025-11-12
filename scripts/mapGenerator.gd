extends Node

class_name MapGenerator

var map_size:int = 4096

var resolution:int = 1024

var center_radius := 384.0

var chunk_size: int = 256

var max_height := 512.0
var min_height := 96.0
var threshold_height := 100.0
var hill_growth_rate := 0.8

var river_width: float = 70.0
var river_waving_offset: float = 1.0 # for large map = 1.0 - 1.5, other Map sizes = 3.0 or higher
var river_size_step: float = 1.0
var river_depth: float = 2.5
var river_resolution: int = 3
var river_point_distance: float = 30.0

var lake_scale: float = 250.0
var lake_depth: float = 2.5

var forest_min_count:int = 12
var forest_max_count:int = 24
var forest_min_radius:float = 350.0
var forest_max_radius:float = 700.0
var trees_min_spacing:float = 6.0
var trees_max_spacing:float = 9.0
var trees_random_offset_spacing:float = 3.0

var resolution_reduction_threshold:int = 2
var layers_from_border: int = 8 

var map_texture_resolution_per_chunk := 64

var noise: FastNoiseLite


var _lake_data: Array = []
var _river_data: Array = []
var _forest_data: Array = []
var _river_chunks: Dictionary[Vector2,Array] = {}
var _lake_chunks: Dictionary[Vector2,Array] = {}
var _forest_chunks: Dictionary[Vector2,Array] = {}

var heights :ImageTexture
var normals :ImageTexture

var test_arr : Array

var _map_size_with_layers :int
var chunks_per_axis :int
var half_chunks :int

####for chunks
var _forest_decorations := []
var _objectsList : Array[ChunkObject]
var _tree: ChunkObject
var _terrain_material
var _forest_noise : FastNoiseLite
var _chunk_scene
var _chunk_resolution : int
var _water: MeshInstance3D

func _init(map_seed:int, map_size: int, resolution := 1024) -> void:
	seed(map_seed)
	self.map_size = map_size
	self.resolution = resolution
	noise = FastNoiseLite.new()
	noise.seed = map_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.001
	noise.fractal_lacunarity = 1.7
	
	update_map_params()

func update_map_params() -> void:
	_map_size_with_layers = map_size + (layers_from_border * 2 * chunk_size)
	chunks_per_axis = map_size / chunk_size
	half_chunks = chunks_per_axis/2

func pregen_chunks() -> void:
	_lake_data.clear()
	_river_data.clear()
	_forest_data.clear()
	_lake_chunks.clear()
	_river_chunks.clear()
	_forest_chunks.clear()
	
	if randi_range(0,1) == 1:
		_generate_river()
	else:
		_generate_lake()
	
	_generate_forests()
	
	##Готуємо мапи для трави
	#var height_normals = generate_height_and_normal_textures(2)
	#heights = height_normals["height"]
	#normals = height_normals["normal"]
	_chunk_resolution = resolution/(map_size / chunk_size)
	var chunk_data = load("res://resources/chunkObjects.tres")
	_objectsList = chunk_data.objectsList.duplicate()
	_chunk_scene = load("res://objects/chunks/chunk.tscn")
	var not_found := true
	for obj in _objectsList:
		if not_found:
			_tree = obj
			if obj.object_name == "tree":
				not_found = false
		if obj.procent_in_forest != 0:
			_forest_decorations.append(obj)
	
	var noise_texture := NoiseTexture2D.new()
	var noise_material := FastNoiseLite.new()
	noise_texture.seamless = true
	noise_texture.color_ramp = load("res://materials/for_terrain.tres")
	noise_material.seed = randi()
	noise_material.frequency = 0.02
	noise_material.fractal_lacunarity = 1.5
	noise_texture.noise = noise_material
	_terrain_material = load("res://materials/terrain/terrain.tres").duplicate()
	_terrain_material.set_shader_parameter("noise_texture",noise_texture)
	
	#вода для чанка
	_water = MeshInstance3D.new()
	var new_mesh = QuadMesh.new()
	new_mesh.size = Vector2(chunk_size,chunk_size)
	new_mesh.center_offset = Vector3(0,-3.0,0)
	new_mesh.orientation = PlaneMesh.FACE_Y
	_water.mesh = new_mesh
	var water_material := load("res://materials/terrain/water.tres")
	_water.set_surface_override_material(0, water_material)
	
	_forest_noise = FastNoiseLite.new()
	_forest_noise.seed = randi()
	_forest_noise.fractal_lacunarity = 1.0
	_forest_noise.fractal_gain = 5.0
	
func generate_chunk(x:int, z: int) -> Node:
	var chunk = _chunk_scene.instantiate()
	var chunk_pos := Vector2i(x, z)
	chunk.position = Vector3(x * chunk_size, 0, z * chunk_size)
	var chunk_pos2D := Vector2(chunk.position.x,chunk.position.z)
	
	chunk.chunk_size = float(chunk_size)
	chunk.set_visibleOnScreenNotifier3D()
	
	var layer := _get_layer_fast(chunk_pos)
	chunk.chunk_layer = layer
	var border_layer := layer - resolution_reduction_threshold
	#Створюємо terrain для чанка
	#if border_layer > 0:
		#chunk_res = max(_chunk_resolution/pow(2,border_layer),4)
	var terrain := MeshInstance3D.new()
	terrain.mesh = _update_mesh(chunk_pos2D, _chunk_resolution)
	terrain.lod_bias = 0.2
	terrain.material_override = _terrain_material
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(terrain)
	chunk.terrain_meshes.append(terrain)
	terrain.position += Vector3(chunk_size/2,0,chunk_size/2)
	
	#Створюємо воду для чанка
	if _river_chunks.has(Vector2(x,z)) or _lake_chunks.has(Vector2(x,z)):
		var water := _water.duplicate()
		chunk.add_child(water)
		chunk.terrain_meshes.append(water)
		water.position += Vector3(chunk_size/2,0,chunk_size/2)
	
	if border_layer > resolution_reduction_threshold:
		return chunk
	chunk.create_sub_chunks()
	
	# Далі об'єкти в чанкі
	var objects_data_list: Array[Dictionary] = []
	for obj in _objectsList:
		var obj_data_list: Array[Dictionary] = []
		var count_objects = randi() % obj.max_single_objects_per_chunk
		if _check_chance(obj.empty_chunk_chance):
			continue
		var to_exit = 0
		while obj_data_list.size() <= count_objects:
			var tx = randf() * chunk_size
			var tz = randf() * chunk_size
			var world_x = chunk_pos2D.x + tx
			var world_y = chunk_pos2D.y + tz
			var world_pos := Vector2(world_x,world_y)
			var object_type := _choose_weighted_object(obj.object_types)
			var obj_type = obj.object_types[object_type]
			var object_scale = obj_type.scale
			var obj_data = _add_object(object_type,object_scale, obj.object_size_offset, world_pos,tx,tz,obj.chance_at_height, obj.multimesh_height)
			if obj_data.size() == 0:
				if to_exit > 100:
					break
				to_exit +=1
				continue
			obj_data_list.append(obj_data)
			if obj_type.group:
				var objects_group := _add_group_objects(world_pos,obj_type.group,chunk_pos2D,object_type, object_scale, obj.object_size_offset, obj.chance_at_height,obj.multimesh_height)
				objects_data_list.append_array(objects_group)
				
		objects_data_list.append_array(obj_data_list)
	###Forests
	if _forest_chunks.size() != 0:
		var xz = Vector2(x,z)
		if _forest_chunks.has(xz):
			var min_p = _forest_chunks[xz].min()
			var max_p = _forest_chunks[xz].max()
			var start_index = max(min_p, 0)
			var end_index = min(max_p, _forest_data.size()-1)
			var points_group := _forest_data.slice(start_index,end_index+1)# Потім беремо точки в цьому діапазоні
			for forest in points_group:
				var forest_center = forest.pos
				var forest_radius = forest.radius
				var spacing = forest.spacing
				if !_circle_intersects_chunk(forest_center,forest_radius, chunk_pos2D):
					continue
				for fx in range(-forest_radius, forest_radius, spacing):
					for fy in range(-forest_radius, forest_radius, spacing):
						var rand_offset_x = randf_range(-trees_random_offset_spacing,trees_random_offset_spacing) # Оффсети для того щоб дерева не стояли рівно в лінію
						var rand_offset_y = randf_range(-trees_random_offset_spacing,trees_random_offset_spacing)
						var pos = Vector2(fx, fy) + forest_center + Vector2(rand_offset_x,rand_offset_y)
						var n = _forest_noise.get_noise_2d(pos.x, pos.y) # Шум дає значення від -1 до 1
						if pos.distance_to(forest_center) > forest_radius * (0.6 + n * 0.4): # Перевіряємо чи входить точка до радіусу, який змінюється шумом для випадкових форм.
							continue
						if !_is_point_in_chunk(pos,chunk_pos2D):
							continue
							# Можна додати шум або рандомну густоту
						if randf() > 0.75: # 75% шанс що тут дерево
							continue
						var tx = pos.x - chunk_pos2D.x
						var tz = pos.y - chunk_pos2D.y
						var object_type = _choose_weighted_object(_tree.object_types)
						var obj_type = _tree.object_types[object_type]
						var object_scale = obj_type.scale
						var tree_data = _add_object(object_type,object_scale,_tree.object_size_offset,pos,tx,tz,_tree.chance_at_height,_tree.multimesh_height)
						if tree_data.size() == 0:
							continue
						objects_data_list.append(tree_data)
						if obj_type.group:
							var objects_group := _add_group_objects(pos,obj_type.group,chunk_pos2D,object_type, object_scale, _tree.object_size_offset, _tree.chance_at_height, _tree.multimesh_height)
							objects_data_list.append_array(objects_group)
						var forest_decors := _add_forest_decorations(pos, chunk_pos2D)
						objects_data_list.append_array(forest_decors)
	chunk.objects_data = objects_data_list
	return chunk

func generate() -> Dictionary:
	pregen_chunks()
	# Створюємо чанки
	var chunks := {}
	for x in range(-half_chunks, half_chunks):
		for z in range(-half_chunks, half_chunks):
			var final_chunk := generate_chunk(x,z)
			chunks[Vector2i(x,z)] = final_chunk
	return chunks

func get_height(x:float,y:float) -> float:
	var xy = Vector2(x,y)
	var dist_to_center := Vector2.ZERO.distance_to(xy)
	if dist_to_center <= center_radius: # якщо точка в центрі = 0
		return 0.0
	var height := noise.get_noise_2d(x,y) * max_height - min_height
	if height < 0.0: 
		height = 0.0
	
	# Чи належить точка річці
	if _river_chunks.size() != 0:
		var get_chunk := _get_chunk_position_from_point(xy)
		if _river_chunks.has(get_chunk):
			# Знаходимо початкову та кінцеву точки в цьому чанку та збільшуємо діапазон між ними 
			var min_p = _river_chunks[get_chunk].min() - 5
			var max_p = _river_chunks[get_chunk].max() + 5
			var start_index = max(min_p, 0)
			var end_index = min(max_p, _river_data.size()-1)
			# Потім беремо точки в цьому діапазоні
			var points_group := _river_data.slice(start_index,end_index+1)
			for p in range(points_group.size()-1):
				var a = points_group[p].pos
				var b = points_group[p+1].pos
				var width1 = points_group[p].width
				var width2 = points_group[p+1].width
				# проекція точки на відрізок
				var ab = b - a
				var ap = xy - a
				var t = clamp(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
				var closest = a + ab * t
				var dist = xy.distance_to(closest)
				var width = lerp(width1, width2,0.5)
				var double_width = width * 3.0
				if dist < width:
					if height > 0.0:
						height = 0.0
					var river_influence = (1.0 + cos(dist / width * PI))  # згладження країв.
					height -= river_influence * river_depth  # сила впливу річки
				elif dist < double_width and height > 0.0:
					var fade = pow(smoothstep(width, double_width, dist), 0.5)  # чим вище ступінь — тим стрімкіше згасання
					height *= fade
			
	#Чи належить точка озеру.
	if _lake_chunks.size() != 0:
		var get_chunk := _get_chunk_position_from_point(xy)
		if _lake_chunks.has(get_chunk):
			for lake_point in _lake_data:
				var pos = lake_point.pos
				var width = lake_point.width
				var double_width = width * 3.0
				var dist = xy.distance_to(pos)
				if dist < width:
					if height > 0.0:
						height = 0.0
					var influence = (1.0 + cos(dist / width * PI))  # м’яке заглиблення
					height -= influence * lake_depth # сила впливу
				elif dist < double_width and height > 0.0:
					var fade = pow(smoothstep(width, double_width, dist), 0.5)  # чим вище ступінь — тим стрімкіше згасання
					height *= fade
	if height < threshold_height and height > 0.0: # якщо висоти меньше порога, то вона зменшується,
		#чим меньше висота, тим швидше вона зменшується
		var t = clamp(height / threshold_height, 0.0, 1.0)
		var boosted = pow(t, hill_growth_rate)
		height = boosted * threshold_height
	
	var second_radius := center_radius * 1.5
	if dist_to_center < second_radius and height > 0.0: # Якщо точка не далеко від центру, її висота зменшується
		# Згасання: чим ближче до center_radius, тим швидше вниз
		var fade = pow(smoothstep(center_radius, second_radius, dist_to_center), 1.5)  # чим вище ступінь — тим стрімкіше згасання біля center_radius
		height *= fade
	
	return height

func _get_normal(x:float,y:float) -> Vector3:
	var epsilon = map_size / resolution
	var normal := Vector3(
		(get_height(x + epsilon, y) - get_height(x - epsilon, y)) / (2.0 * epsilon),
		1.0,
		(get_height(x, y + epsilon) - get_height(x, y - epsilon)) / (2.0 * epsilon),
	)
	return normal.normalized()

func _get_normal_from_cache(x_idx: int, z_idx: int, height_map: Array, step_size: float) -> Vector3:
	var h_center = height_map[z_idx][x_idx]
	var grid_size_x = height_map[0].size()
	var grid_size_z = height_map.size()

	var h_x_plus = h_center
	if x_idx + 1 < grid_size_x:
		h_x_plus = height_map[z_idx][x_idx + 1]

	var h_x_minus = h_center
	if x_idx - 1 >= 0:
		h_x_minus = height_map[z_idx][x_idx - 1]

	var h_z_plus = h_center
	if z_idx + 1 < grid_size_z:
		h_z_plus = height_map[z_idx + 1][x_idx]

	var h_z_minus = h_center
	if z_idx - 1 >= 0:
		h_z_minus = height_map[z_idx - 1][x_idx]

	var dx = (h_x_plus - h_x_minus) / (2.0 * step_size)
	var dz = (h_z_plus - h_z_minus) / (2.0 * step_size)

	# Нормаль, що дивиться вгору (Y=1.0), а XZ компоненти залежать від градієнта
	var normal_vec = Vector3(-dx, 1.0, -dz) 
	
	return normal_vec.normalized()

func _update_mesh(chunk_pos: Vector2, chunk_resolution: int) -> Mesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var step_size = chunk_size / float(chunk_resolution)
	
	# Розмір розширеної карти висот (resolution + 1 для чанка + 2 для бордюрів)
	var extended_map_size = chunk_resolution + 3 
	
	# Обчислюємо світову координату початку розширеного діапазону для get_height
	# Це буде на 1 "крок" поза лівим/нижнім краєм поточного чанка
	var start_world_x_extended = chunk_pos.x - step_size
	var start_world_z_extended = chunk_pos.y - step_size

	var height_map : Array = []
	height_map.resize(extended_map_size)
	for z_idx_extended in range(extended_map_size): # Цикл для розширеної карти
		height_map[z_idx_extended] = PackedFloat32Array()
		height_map[z_idx_extended].resize(extended_map_size)
		for x_idx_extended in range(extended_map_size): # Цикл для розширеної карти
			# Розраховуємо світові координати для get_height з урахуванням розширення
			var world_x = start_world_x_extended + x_idx_extended * step_size
			var world_z = start_world_z_extended + z_idx_extended * step_size
			
			height_map[z_idx_extended][x_idx_extended] = get_height(world_x, world_z)

	# Тепер генеруємо ВЕРШИНИ, UV та ІНДЕКСИ ТІЛЬКИ ДЛЯ ПОТОЧНОГО ЧАНКА
	# Індекси для цих циклів будуть від 0 до chunk_resolution
	for z_idx in range(chunk_resolution + 1):
		for x_idx in range(chunk_resolution + 1):
			# Локальні координати вершин відносно центру чанка
			var local_x = x_idx * step_size - chunk_size / 2.0
			var local_z = z_idx * step_size - chunk_size / 2.0
			
			# Використовуємо висоту з height_map, враховуючи зміщення на +1 для "бордюру"
			vertices.append(Vector3(local_x, height_map[z_idx + 1][x_idx + 1], local_z)) 
			
			uvs.append(Vector2(float(x_idx) / chunk_resolution, float(z_idx) / chunk_resolution))
			# Нормалі розрахуємо пізніше, використовуючи _get_normal_from_cache
			normals.append(Vector3.UP) 

	for z_idx in range(chunk_resolution):
		for x_idx in range(chunk_resolution):
			var p0_idx = z_idx * (chunk_resolution + 1) + x_idx
			var p1_idx = p0_idx + 1
			var p2_idx = (z_idx + 1) * (chunk_resolution + 1) + x_idx
			var p3_idx = p2_idx + 1

			# Висоти для вибору триангуляції також беремо з кешу з урахуванням зміщення +1
			var h0 = height_map[z_idx + 1][x_idx + 1]
			var h1 = height_map[z_idx + 1][x_idx + 1 + 1]
			var h2 = height_map[z_idx + 1 + 1][x_idx + 1]
			var h3 = height_map[z_idx + 1 + 1][x_idx + 1 + 1]

			var diag1_diff = abs(h0 - h3) 
			var diag2_diff = abs(h1 - h2) 

			if diag1_diff < diag2_diff:
				indices.append(p0_idx)
				indices.append(p3_idx)
				indices.append(p2_idx)

				indices.append(p0_idx)
				indices.append(p1_idx)
				indices.append(p3_idx)
			else:
				indices.append(p0_idx)
				indices.append(p1_idx)
				indices.append(p2_idx)

				indices.append(p1_idx)
				indices.append(p3_idx)
				indices.append(p2_idx)
				
	# Перерахунок нормалей, використовуючи розширену карту висот
	for z_idx in range(chunk_resolution + 1):
		for x_idx in range(chunk_resolution + 1):
			var current_vertex_index = z_idx * (chunk_resolution + 1) + x_idx
			# Тут передаємо в _get_normal_from_cache індекси, що враховують зміщення для бордюру
			normals[current_vertex_index] = _get_normal_from_cache(x_idx + 1, z_idx + 1, height_map, step_size)

	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_NORMAL] = normals
	arrays[ArrayMesh.ARRAY_TEX_UV] = uvs
	arrays[ArrayMesh.ARRAY_INDEX] = indices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh

func _generate_river() -> void:
	var side_from = randi() % 4
	var side_to = (side_from + randi() % 3 + 1) % 4  # інша випадкова сторона
	
	var from = _get_edge_point(side_from)
	var to = _get_edge_point(side_to)
	
	if from.distance_to(to) < 1000:
		return _generate_river()  # рекурсивно перегенерувати, якщо маленька відстань
	
	var center_pos = Vector2(0, 0)
	var control_points := []
	var dist_between_points = 100.0
	var num_points = roundi(from.distance_to(to)/dist_between_points)
	# Обчислюємо амплітуду відхилення
	var max_waving_amplitude = map_size * 0.05
	num_points = clamp(num_points,2,num_points)
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var point = from.lerp(to, t)
		# Це створить плавне зменшення амплітуди до країв.
		var waving_attenuation = sin(t * PI)
		
		# хвилясте відхилення
		var offset = Vector2(- (to - from).y, (to - from).x).normalized()  # перпендикуляр
		point += offset * sin(t * TAU + randf() * river_waving_offset) * max_waving_amplitude * waving_attenuation
		
		if point.distance_to(center_pos) < center_radius:
			return _generate_river()  # рекурсивно перегенерувати, якщо зачепили центр

		control_points.append(point)
	#Далі робимо продовження річки за межами ігрової області
	var control_points_from := []
	var control_points_to := []
	var far_from := _get_edge_point(side_from,true)
	var far_to := _get_edge_point(side_to,true)
	# тут йде перевірка на те щоб річка сильно не змінювала вектор
	while !_are_vectors_similar(to,from,from,far_from,30) or !_are_vectors_similar(from,to,to,far_to,30):
		far_from = _get_edge_point(side_from,true)
		far_to = _get_edge_point(side_to,true)
	var num_points_from = roundi(from.distance_to(far_from)/dist_between_points)
	var num_points_to = roundi(to.distance_to(far_to)/dist_between_points)
	for i in range(max(num_points_from+1,num_points_to+1)):
		if i < num_points_from+1:
			var t = float(i) / float(num_points_from)
			var waving_attenuation = sin(t * PI)
			var point_from = from.lerp(far_from, t)
			var offset_from = Vector2(- (far_from - from).y, (far_from - from).x).normalized()  # перпендикуляр
			point_from += offset_from * sin(t * TAU + randf() * river_waving_offset) * max_waving_amplitude * waving_attenuation
			control_points_from.append(point_from)
		if i < num_points_to+1:
			var t = float(i) / float(num_points_to)
			var waving_attenuation = sin(t * PI)
			var point_to = to.lerp(far_to, t)
			var offset_to = Vector2(- (far_to - to).y, (far_to - to).x).normalized()  # перпендикуляр
			point_to += offset_to * sin(t * TAU + randf() * river_waving_offset) * max_waving_amplitude * waving_attenuation
			control_points_to.append(point_to)
	
	control_points_from.append(far_from)
	control_points_from.append(far_from)
	control_points_to.append(far_to)
	control_points_to.append(far_to)
	control_points_from.reverse()
	control_points_from.append_array(control_points)
	control_points_from.append_array(control_points_to)
	test_arr = control_points_from
	control_points = control_points_from
	#Далі йде згладження річки
	if control_points.size() < 4: # Catmull-Rom потребує мінімум 4 точки (p0, p1, p2, p3)
		print("Недостатньо контрольних точок для Catmull-Rom.")
		return
	
	var baked_curve_points: Array = []
	var current_river_segment_index = 0
	
	# Крок 1: "Випікаємо" (baked) криву в щільний масив точок
	# Ми пройдемо по Catmull-Rom сегментах і збережемо дуже багато точок,
	# щоб потім рівномірно їх семплювати.
	var segments_to_process = control_points.size() - 3
	for i in range(segments_to_process):
		var p0 = control_points[i]
		var p1 = control_points[i + 1]
		var p2 = control_points[i + 2]
		var p3 = control_points[i + 3]
		
		for j in range(river_resolution):
			var t = float(j) / float(river_resolution)
			var pos = _catmull_rom(p0, p1, p2, p3, t)
			baked_curve_points.append(pos)
		
		# Додаємо останню точку сегмента (t=1.0) для безперервності між сегментами
		# Вона буде першою точкою наступного сегмента.
		if i == segments_to_process - 1: # Додати останню точку останнього сегмента
			var pos_at_end = _catmull_rom(p0, p1, p2, p3, 1.0)
			baked_curve_points.append(pos_at_end)

	# Крок 2: Рівномірне семплювання "випеченої" кривої

	var current_length = 0.0
	var last_baked_pos = baked_curve_points[0]

	_river_data.append({"pos": baked_curve_points[0], "width": randf_range(river_width/1.2, river_width*1.2)})
	var current_num_point = 1 # Кількість точок, доданих до river_data

	for i in range(1, baked_curve_points.size()):
		var current_baked_pos = baked_curve_points[i]
		var segment_dist = last_baked_pos.distance_to(current_baked_pos)
		
		current_length += segment_dist
		
		# Додаємо точки, коли досягаємо цільової довжини сегмента
		while current_length >= river_point_distance:
			current_length -= river_point_distance
			
			# Обчислюємо інтерпольовану позицію
			var t_interp = current_length / segment_dist # Скільки залишилося від попереднього сегмента
			var new_pos = current_baked_pos.lerp(last_baked_pos, t_interp) # Інтерполюємо назад
			
			# Перевірка на вже існуючі точки, щоб уникнути дублювання
			if _river_data.size() > 0 and _river_data.back().pos.distance_to(new_pos) < 0.1:
				continue
			
			# Розрахунок river_w залишається як є
			var current_river_w = clamp(randf_range(_river_data.back().width - river_size_step, _river_data.back().width + river_size_step), river_width/1.2, river_width*1.2)
			
			var chunks = _get_chunks_in_circle(new_pos, current_river_w * 3.1)
			var data := {
				"pos": new_pos,
				"width": current_river_w
			}
			for chunk in chunks:
				_river_chunks.get_or_add(chunk, []).append(current_num_point)
			_river_data.append(data)
			current_num_point += 1
		
		last_baked_pos = current_baked_pos

func _generate_lake() -> void:
	var min_dist = 0.0
	var max_dist = 0.0
	var lake_center = Vector2(0,0)
	
	var count = randi_range(4,6)
	var num := 0
	while _lake_data.size() < count:
		var lake_pos: Vector2
		var lake_radius: float
		if _lake_data.size() == 0:
			lake_pos = Vector2(
				randf_range(-map_size/2 , map_size/2),
				randf_range(-map_size/2 , map_size/2)
			)
			lake_radius = randf_range(lake_scale/1.5, lake_scale*1.5)
			if Vector2(0,0).distance_to(lake_pos) <= center_radius + lake_radius:
				continue
			var chunks = _get_chunks_in_circle(lake_pos, lake_radius * 3.1) # Знаходимо чанки, в яких знаходиться озеро
			var data := {
					"pos":lake_pos,
					"width":lake_radius
				}
			for chunk in chunks:
				_lake_chunks.get_or_add(chunk, []).append(num)
			_lake_data.append(data)
			min_dist = lake_radius / 3
			max_dist = lake_radius / 2
			lake_center = lake_pos
			num += 1
			continue
		lake_pos = Vector2(
			lake_center.x + _double_rand_range(min_dist,max_dist),
			lake_center.y + _double_rand_range(min_dist,max_dist)
		)
		lake_radius = randf_range(lake_scale/1.5, lake_scale*1.5)
		if Vector2(0,0).distance_to(lake_pos) <= center_radius + lake_radius:
			continue
		var chunks = _get_chunks_in_circle(lake_pos, lake_radius * 3.1) # Знаходимо чанки, в яких знаходиться озеро
		var data := {
				"pos":lake_pos,
				"width":lake_radius
			}
		for chunk in chunks:
			_lake_chunks.get_or_add(chunk, []).append(num)
		_lake_data.append(data)
		num += 1

func _generate_forests() -> void:
	var total_chunks_per_axis = chunks_per_axis + (layers_from_border * 2)
	var initial_chunks = chunks_per_axis * chunks_per_axis
	var total_chunks = total_chunks_per_axis * total_chunks_per_axis
	var scale_factor = total_chunks / initial_chunks

	var forest_count = randi_range(int(forest_min_count*scale_factor),(forest_max_count*scale_factor))
	var to_exit = 0
	var current_num_point = 0
	while _forest_data.size() <= forest_count:
		var center = Vector2(
			randf_range(-_map_size_with_layers/2, _map_size_with_layers/2),
			randf_range(-_map_size_with_layers/2, _map_size_with_layers/2)
		)
		var radius = randf_range(forest_min_radius, forest_max_radius)
		var overlap = false
		for forest in _forest_data:
			if forest.pos.distance_to(center) <= radius + forest.radius/1.5:
				overlap = true
				break
		if overlap:
			if to_exit > 100:
				break
			to_exit += 1
			continue
		var chunks = _get_chunks_in_circle(center, radius)
		var main_forest = {
			"pos": center,
			"radius": radius,
			"spacing": randf_range(trees_min_spacing, trees_max_spacing)
		}
		for chunk in chunks:
			_forest_chunks.get_or_add(chunk, []).append(current_num_point)
		_forest_data.append(main_forest)
		current_num_point += 1
		# Додаємо від 0 до 3 дочірніх лісів
		var child_forest_count = randi_range(1, 3)
		var potential_parents = [main_forest]
		var child_forests = []
		for i in child_forest_count:
			var attempts = 0
			while attempts < 10:
				# Випадковий "батьківський" ліс: головний або вже створений дочірній
				var parent_forest = potential_parents[randi_range(0, potential_parents.size() - 1)]
				var angle = randf() * PI * 2
				var parent_radius = parent_forest["radius"]
				var child_radius = randf_range(forest_min_radius/2, parent_radius)

				# Генерація точки на межі
				var offset = Vector2(cos(angle), sin(angle)) * parent_radius
				var child_pos = parent_forest["pos"] + offset

				# Перевірка на колізії з усіма іншими лісами
				var valid = true
				for forest in _forest_data + child_forests:
					if forest["pos"].distance_to(child_pos) <= forest["radius"]/2.5 + child_radius/2.5:
						valid = false
						break

				if valid:
					var child = {
						"pos": child_pos,
						"radius": child_radius,
						"spacing": randf_range(trees_min_spacing, trees_max_spacing)
					}
					var childs_chunks = _get_chunks_in_circle(child_pos, child_radius)
					for chunk in childs_chunks:
						_forest_chunks.get_or_add(chunk, []).append(current_num_point)
					current_num_point += 1
					child_forests.append(child)
					potential_parents.append(child)
					break
				attempts += 1

		_forest_data.append_array(child_forests)

#========================================Допоміжні функції==================================

func _get_edge_point(side: int, outside_border: bool = false) -> Vector2:
	var size_map := map_size
	if outside_border:
		size_map = _map_size_with_layers
	match side:
		0: return Vector2(randf_range(-size_map/2, size_map/2), -size_map/2) # top
		1: return Vector2(size_map/2, randf_range(-size_map/2, size_map/2)) # right
		2: return Vector2(randf_range(-size_map/2, size_map/2), size_map/2) # bottom
		3: return Vector2(-size_map/2, randf_range(-size_map/2 , size_map/2)) # left
		_: return Vector2.ZERO

func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 = t * t
	var t3 = t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _double_rand_range(a: float, b: float) -> float:
	var range_choice = randf_range(0, 1)
	var random_value = 0
	if range_choice < 0.5:
		random_value = randf_range(-b, -a)
	else:
		random_value = randf_range(a, b)

	return random_value

func _add_object(object_type: String, object_scale: float,size_offset: float, 
world_pos: Vector2,tx:float,tz:float, object_heights: Dictionary[Array,float], multimesh_height:float) -> Dictionary:
	var dist_to_centr = Vector2.ZERO.distance_to(world_pos)
	if dist_to_centr < 20.0: # Ближче чим 20 до центра вже нічого не спавниться
		return {}
	if dist_to_centr < center_radius:
		var chance = pow(smoothstep(0.0, center_radius, dist_to_centr), 1.3) # Чим ближче до центра тим меньше шанс
		if !_check_chance(dist_to_centr * chance):
			return {}
	var normal = _get_normal(world_pos.x, world_pos.y) # Щоб на спавнилося на крутому схилі
	if normal.y < 0.75:
		return {}
	var height = get_height(world_pos.x, world_pos.y)
	var skip = true
	for h in object_heights.keys():
		if height >= h[0] and height <= h[1]:
			if !_check_chance(object_heights[h]):
				return {}
			skip = false
			break
	if skip:
		return {}
	var size = (1.0  - randf() * (1.0 - size_offset)) * object_scale
	var object_data = { # object_types[object_type].scale використовується тому, що у кожного об'єкта індивідуальний стандартний розмір і також його зміна впливає на розташування
		#"position": Vector3(tx - chunk_size/2, height, tz - chunk_size/2) * (1/size),
		"position": Vector3(tx, height-multimesh_height, tz),
		"type": object_type,
		"rotation": randf() * TAU,
		"size": size
	}
	return object_data

func _add_forest_decorations(pos : Vector2, chunk_pos: Vector2) -> Array:
	var decors := []
	for dec in _forest_decorations:
		if !_check_chance(dec.procent_in_forest):
			continue
		var rand_offset_x = randf_range(-trees_random_offset_spacing,trees_random_offset_spacing)
		var rand_offset_y = randf_range(-trees_random_offset_spacing,trees_random_offset_spacing)
		var dec_pos := pos + Vector2(rand_offset_x,rand_offset_y)
		if !_is_point_in_chunk(dec_pos,chunk_pos):
			continue
		var tx = dec_pos.x - chunk_pos.x
		var tz = dec_pos.y - chunk_pos.y
		var object_type = _choose_weighted_object(dec.object_types)
		var obj_type = dec.object_types[object_type]
		var object_scale = obj_type.scale
		var dec_data := _add_object(object_type,object_scale,dec.object_size_offset,dec_pos,tx,tz,dec.chance_at_height, dec.multimesh_height)
		if dec_data.size() == 0:
			continue
		decors.append(dec_data)
		if obj_type.group:
			var objects_group := _add_group_objects(dec_pos,obj_type.group,chunk_pos,object_type,object_scale,dec.object_size_offset,dec.chance_at_height, dec.multimesh_height)
			decors.append_array(objects_group)
	return decors

func _add_group_objects(pos: Vector2,group: chunkGroupObjects, chunk_pos: Vector2, object_type: String, 
object_scale: float, size_offset: float, object_heights: Dictionary[Array,float], mm_height: float) -> Array:
	var objects := []
	var count := randi_range(group.min_group_size,group.max_group_size)
	if count < 2:
		return objects
	for i in count:
		var rand_offset_x = randf_range(group.min_objects_distance,group.max_objects_distance)
		var rand_offset_y = randf_range(group.min_objects_distance,group.max_objects_distance)
		var object_pos := pos + Vector2(rand_offset_x,rand_offset_y)
		if !_is_point_in_chunk(object_pos,chunk_pos):
			continue
		var tx = object_pos.x - chunk_pos.x
		var tz = object_pos.y - chunk_pos.y
		var object_data := _add_object(object_type,object_scale,size_offset,object_pos,tx,tz,object_heights,mm_height)
		if object_data.size() == 0:
			continue
		objects.append(object_data)
	return objects

func _choose_weighted_object(object_weights: Dictionary) -> String:
	var total_weight = 0
	for weight in object_weights.values():
		total_weight += weight.chance
	
	var rnd = randi() % total_weight
	var current = 0
	
	for object_type in object_weights.keys():
		current += object_weights[object_type].chance
		if rnd < current:
			return object_type
	
	return object_weights.keys()[0] # fallback

func _is_point_in_chunk(point: Vector2, chunk_position: Vector2) -> bool:
	return (
		point.x >= chunk_position.x and
		point.x < chunk_position.x + chunk_size and
		point.y >= chunk_position.y and
		point.y < chunk_position.y + chunk_size
	)

func _get_chunk_position_from_point(point: Vector2) -> Vector2:
	var chunk_x = floor(point.x / chunk_size)
	var chunk_y = floor(point.y / chunk_size)
	return Vector2(chunk_x, chunk_y) 

func _circle_intersects_chunk(circle_center: Vector2, radius: float, chunk_position: Vector2) -> bool:
	var closest_point = Vector2(
		clamp(circle_center.x, chunk_position.x, chunk_position.x + chunk_size),
		clamp(circle_center.y, chunk_position.y, chunk_position.y + chunk_size)
	)
	
	var distance_squared = circle_center.distance_squared_to(closest_point)
	return distance_squared <= radius * radius

func _get_chunks_in_circle(center: Vector2, radius: float) -> Array:
	var chunks = []

	# Обчислюємо AABB (прямокутник) довкола кола
	var min_x = floor((center.x - radius) / chunk_size)
	var max_x = floor((center.x + radius) / chunk_size)
	var min_y = floor((center.y - radius) / chunk_size)
	var max_y = floor((center.y + radius) / chunk_size)

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var chunk_position = Vector2(x * chunk_size, y * chunk_size)
			if _circle_intersects_chunk(center, radius, chunk_position):
				chunks.append(Vector2(x, y))  # Повертаємо координати чанку в системі чанків (а не в пікселях)

	return chunks

func _check_chance(chance: float) -> bool:
	return randf() * 100 < chance

func _are_vectors_similar(p1_a: Vector2, p1_b: Vector2, p2_a: Vector2, p2_b: Vector2, max_angle_degrees: float) -> bool:
	var v1 = p1_b - p1_a
	var v2 = p2_b - p2_a

	# Якщо хоча б один вектор нульовий — не можна порівнювати напрям
	if v1.length_squared() == 0 or v2.length_squared() == 0:
		return false

	var angle_rad = v1.angle_to(v2)
	var angle_deg = abs(rad_to_deg(angle_rad))

	return angle_deg <= max_angle_degrees

func generate_height_and_normal_textures(resolution_scale:int = 1) -> Dictionary:
	var bigger_resolution = resolution * resolution_scale
	var img := Image.create(bigger_resolution + 1, bigger_resolution + 1, false, Image.FORMAT_RF)

	# Спочатку знайти мін/макс для нормалізації
	for y in range(bigger_resolution + 1):
		for x in range(bigger_resolution + 1):
			var world_x = float(x) / bigger_resolution * map_size - map_size / 2.0
			var world_z = float(y) / bigger_resolution * map_size - map_size / 2.0
			var height = get_height(world_x, world_z)
			img.set_pixel(x,y,Color(height,0,0))

	img.generate_mipmaps()
	var height_tex := ImageTexture.create_from_image(img)
	var normalmap := _heightmap_to_normalmap(img)
	var normal_tex := ImageTexture.create_from_image(normalmap)
	heights = height_tex
	normals = normal_tex
	return {
		"height": height_tex,
		"normal": normal_tex,
	}

func _heightmap_to_normalmap(height_img: Image, strength: float = 1.0) -> Image:
	var width = height_img.get_width()
	var height = height_img.get_height()

	var normal_img = Image.create(width, height, false, Image.FORMAT_RGB8)

	# Make sure heightmap is in grayscale format (single channel)
	height_img.convert(Image.FORMAT_RF)

	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var hL = height_img.get_pixel(x - 1, y).r
			var hR = height_img.get_pixel(x + 1, y).r
			var hU = height_img.get_pixel(x, y - 1).r
			var hD = height_img.get_pixel(x, y + 1).r

			var dx = (hR - hL) * strength
			var dy = (hD - hU) * strength

			var normal = Vector3(-dx, -dy, 1.0).normalized()
			var color = Color(
				normal.x * 0.5 + 0.5,
				normal.y * 0.5 + 0.5,
				normal.z * 0.5 + 0.5
			)
			normal_img.set_pixel(x, y, color)

	normal_img.generate_mipmaps()
	return normal_img
	
func generate_chunk_map_texture_direct(chunk_grid_x: int, chunk_grid_z: int) -> Image:
	
	var texture_image = Image.create(map_texture_resolution_per_chunk, map_texture_resolution_per_chunk, false, Image.FORMAT_RGBA8)
	var forests := []
	if _forest_chunks.size() != 0:
		var xz = Vector2(chunk_grid_x,chunk_grid_z)
		if _forest_chunks.has(xz):
			var min_p = _forest_chunks[xz].min()
			var max_p = _forest_chunks[xz].max()
			var start_index = max(min_p, 0)
			var end_index = min(max_p, _forest_data.size()-1)
			forests = _forest_data.slice(start_index,end_index+1)
	for y_pixel in range(map_texture_resolution_per_chunk):
		for x_pixel in range(map_texture_resolution_per_chunk):
			# Обчислення світових координат для поточного пікселя текстури
			# Це ВАЖЛИВО для безшовності та коректного відображення
			var world_x = (chunk_grid_x * chunk_size) + (float(x_pixel) / map_texture_resolution_per_chunk) * chunk_size
			var world_z = (chunk_grid_z * chunk_size) + (float(y_pixel) / map_texture_resolution_per_chunk) * chunk_size
			var current_pixel_world_pos = Vector2(world_x, world_z)

			# Прямий виклик get_height для кожного пікселя
			var height = get_height(world_x, world_z) 

			var terrain_type = 0 # За замовчуванням: суша

			# Перевірка на ліс для кожного пікселя
			# Використовуємо той самий алгоритм перевірки, що і в generate_chunk
			for forest in forests:
				var forest_center = forest.pos
				var forest_radius = forest.radius
				# Використовуйте _forest_noise з вашого MapGenerator або інстанс шуму з forest
				var forest_noise_instance = _forest_noise
				var n = forest_noise_instance.get_noise_2d(current_pixel_world_pos.x, current_pixel_world_pos.y) 
				
				if current_pixel_world_pos.distance_to(forest_center) < forest_radius * (0.6 + n * 0.4):
					terrain_type = 3 # Ліс
					break # Якщо вже ліс, далі не перевіряємо
			
			# Отримання стилізованого кольору
			var pixel_color = _get_stylized_pixel_color(
				height, 
				terrain_type, 
				current_pixel_world_pos
			)

			texture_image.set_pixel(x_pixel, y_pixel, pixel_color)
			
	return texture_image

func _get_stylized_pixel_color(height: float, terrain_type: int, world_pos: Vector2) -> Color:
	
	var base_color: Color

	# Логіка визначення кольору,(wegukhfrkshbufbsr)від найнижчих до найвищих областей
	if height <= -0.2: # Вода: висота <= -3
		base_color = Color.ROYAL_BLUE # Глибока вода
	elif height < 0.0: # Берег: висота між -3 та 0 (виключно 0)
		base_color = Color.TAN # Пісочний колір берега
	elif terrain_type == 3: # Ліс (якщо не вода і не берег)
		base_color = Color.WEB_GREEN # Темно-зелений для лісу
	elif height == 0: # Рівнина: висота = 0
		base_color = Color.FOREST_GREEN # Світло-зелений для рівнин
	elif height > 0.0 and height < 256.0: # Пагорби
		base_color = Color.DARK_GREEN # Колір пагорбів (коричневий)
	else: # Високі пагорби / гори
		base_color = Color.DIM_GRAY # Колір гір (сірий)

	return base_color

func _get_layer_fast(c: Vector2i) -> int:
	var r = max(abs(c.x + 0.5), abs(c.y + 0.5))
	var layer = int(ceil(r)) - half_chunks
	return max(layer, 0)

func clear_data() -> void:
	_lake_data.clear()
	_river_data.clear()
	_forest_data.clear()
	_river_chunks.clear()
	_lake_chunks.clear()
	_forest_chunks.clear()

	heights = null
	normals = null

	test_arr.clear()
	
	_forest_decorations.clear()
	_objectsList.clear()
	_tree = null
	_terrain_material = null
	_forest_noise = null
	_chunk_scene = null
	_water.queue_free()

#func generate() -> Dictionary:
	#_lake_data.clear()
	#_river_data.clear()
	#_square_lake.clear()
	#_square_river.clear()
	#if randi_range(0,1) == 1:
		#_generate_river()
	#else:
		#_generate_lake()
	#var forests := _generate_forests()
	#
	#var objectsList : Array[ChunkObject] = chunkObjects.new().objectsList
	#var tree: ChunkObject
	#for obj in objectsList:
		#tree = obj
		#if obj.object_name == "tree":
			#break
	#
	##Створюємо шум для terrain
	#var noise_texture := NoiseTexture2D.new()
	#noise_texture.seamless = true
	#noise_texture.color_ramp = preload("res://materials/for_terrain.tres")
	#var noise_material := FastNoiseLite.new()
	#noise_material.seed = randi()
	#noise_material.frequency = 0.02
	#noise_material.fractal_lacunarity = 1.5
	#noise_texture.noise = noise_material
	#var terrain_material := preload("res://materials/terrain/terrain.tres").duplicate()
	#terrain_material.set_shader_parameter("noise_texture",noise_texture)
	#
	##Створюємо шум для лісів
	#var forest_noise = FastNoiseLite.new()
	#forest_noise.seed = randi()
	#forest_noise.fractal_lacunarity = 1.0
	#forest_noise.fractal_gain = 5.0
	#
	## Створюємо чанки
	#var chunks_per_axis = map_size / chunk_size
	#var half_chunks = chunks_per_axis/2
	#var chunk_scene := preload("res://objects/chunks/chunk.tscn")
	#var chunks := {}
	#for x in range(-half_chunks, half_chunks):
		#for z in range(-half_chunks, half_chunks):
			#var chunk = chunk_scene.instantiate()
			#var chunk_pos = Vector2i(x, z)
			#chunk.position = Vector3(x * chunk_size, 0, z * chunk_size)
			#var chunk_pos2D = Vector2(chunk.position.x,chunk.position.z)
			#var terrain := MeshInstance3D.new()
			#terrain.add_to_group("chunk_terrain")
			#terrain.mesh = _update_mesh(chunk_pos2D, resolution/chunks_per_axis)
			#terrain.material_override = terrain_material
			#chunk.add_child(terrain)
			## Далі об'єкти в чанкі
			#var objects_data_list: Array[Dictionary] = []
			#for obj in objectsList:
				#var obj_data_list: Array[Dictionary] = []
				#var empty_chunk = randi() % obj.empty_chunk_chance
				#var count_objects = randi() % obj.max_single_objects_per_chunk
				#var to_exit = 0
				#while obj_data_list.size() <= count_objects:
					#if empty_chunk == 0:
						#break
					#var tx = randf() * chunk_size
					#var tz = randf() * chunk_size
					#var world_x = chunk_pos2D.x + tx
					#var world_y = chunk_pos2D.y + tz
					#var height = get_height(world_x, world_y)
					#
					#var obj_data = _add_object(obj.object_types, obj.object_size_offset, world_x,world_y,tx,tz,0,0,height)
					#if obj_data.size() == 0:
						#if to_exit > 100:
							#break
						#to_exit +=1
						#continue
					#obj_data_list.append(obj_data)
				#objects_data_list.append_array(obj_data_list)
			####Forest tree
			#for forest in forests:
				#var forest_center = forest.pos
				#var forest_radius = forest.radius
				#var spacing = forest.spacing
				#if !_circle_intersects_chunk(forest_center,forest_radius, chunk_pos2D, float(chunk_size)):
					#continue
				#for fx in range(-forest_radius, forest_radius, spacing):
					#for fy in range(-forest_radius, forest_radius, spacing):
						#var rand_offset_x = randf_range(-trees_random_offset_spacing,trees_random_offset_spacing) # Оффсети для того щоб дерева не стояли рівно в лінію
						#var rand_offset_y = randf_range(-trees_random_offset_spacing,trees_random_offset_spacing)
						#var pos = Vector2(fx, fy) + forest_center + Vector2(rand_offset_x,rand_offset_y)
						#var n = forest_noise.get_noise_2d(pos.x, pos.y) # Шум дає значення від -1 до 1
						#if pos.distance_to(forest_center) > forest_radius * (0.6 + n * 0.4): # Перевіряємо чи входить точка до радіусу, який змінюється шумом для випадкових форм.
							#continue
						#if !_is_point_in_chunk(pos,chunk_pos2D, float(chunk_size)):
							#continue
							## Можна додати шум або рандомну густоту
						#if randf() > 0.75: # 75% шанс що тут дерево
							#continue
						#var tx = pos.x - chunk_pos2D.x
						#var tz = pos.y - chunk_pos2D.y
						#var height = get_height(pos.x, pos.y)
						#var tree_data = _add_object(tree.object_types,tree.object_size_offset,pos.x,pos.y,tx,tz,0,0,height)
						#if tree_data.size() == 0:
							#continue
						#objects_data_list.append(tree_data)
			#chunk.objects_data = objects_data_list
			#chunks[chunk_pos] = chunk
	#return chunks

#func _update_mesh(chunk_pos: Vector2, chunk_resolution: int) -> Mesh:
	#var plane := PlaneMesh.new()
	#plane.subdivide_depth = chunk_resolution
	#plane.subdivide_width = chunk_resolution
	#plane.size = Vector2(chunk_size, chunk_size)
	#
	#var plane_arrays := plane.get_mesh_arrays()
	#var vertex_array : PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_VERTEX]
	#var normal_array : PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_NORMAL]
	#var tangent_array: PackedFloat32Array = plane_arrays[ArrayMesh.ARRAY_TANGENT]
	#
	#for i:int in vertex_array.size():
		#var vertex := vertex_array[i]
		#var normal := Vector3.UP
		#var tangent := Vector3.RIGHT
		#
		#var chunk_offset_x := chunk_pos.x + chunk_size/2
		#var chunk_offset_y := chunk_pos.y + chunk_size/2
		#
		#if noise:
			#vertex.y = get_height(vertex.x + chunk_offset_x,vertex.z + chunk_offset_y)
			#normal = _get_normal(vertex.x + chunk_offset_x,vertex.z + chunk_offset_y)
			#tangent = normal.cross(Vector3.UP)
		#
		#vertex_array[i] = vertex
		#normal_array[i] = normal
		#tangent_array[4 * i] = tangent.x
		#tangent_array[4 * i + 1] = tangent.y
		#tangent_array[4 * i + 2] = tangent.z
	#
	#var array_mesh := ArrayMesh.new()
	#array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	#return array_mesh
	##$Terrain.mesh = array_mesh


#func _update_mesh(chunk_pos: Vector2, chunk_resolution: int) -> Mesh:
	#var plane := PlaneMesh.new()
	#plane.subdivide_depth = chunk_resolution
	#plane.subdivide_width = chunk_resolution
	#plane.size = Vector2(chunk_size, chunk_size)
	#
	#var plane_arrays := plane.get_mesh_arrays()
	#var vertex_array : PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_VERTEX]
	#var normal_array : PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_NORMAL]
	#var tangent_array: PackedFloat32Array = plane_arrays[ArrayMesh.ARRAY_TANGENT]
	#
	## Структура для кешу нормалей і висот
	#var vertex_data := []
	#for y in range(chunk_resolution + 1):
		#vertex_data.append([])
	#for i:int in vertex_array.size():
		#var vertex := vertex_array[i]
		#var normal := Vector3.UP
		#var tangent := Vector3.RIGHT
		#
		#var chunk_offset_x := chunk_pos.x + chunk_size/2
		#var chunk_offset_y := chunk_pos.y + chunk_size/2
		#
		#if noise:
			#vertex.y = get_height(vertex.x + chunk_offset_x,vertex.z + chunk_offset_y)
			#normal = _get_normal(vertex.x + chunk_offset_x,vertex.z + chunk_offset_y)
			#tangent = normal.cross(Vector3.UP)
			#
			#var color = _encode_normal_for_texture(normal)
			#var correct_x = int(((vertex.x + chunk_offset_x + map_size / 2.0) / map_size) * resolution)
			#var correct_y = int(((vertex.z + chunk_offset_y + map_size / 2.0) / map_size) * resolution)
			#_heights_img.set_pixel(correct_x , correct_y , Color(vertex.y,0,0))
			#_normals_img.set_pixel(correct_x, correct_y, color)
		#vertex_array[i] = vertex
		#normal_array[i] = normal
		#tangent_array[4 * i] = tangent.x
		#tangent_array[4 * i + 1] = tangent.y
		#tangent_array[4 * i + 2] = tangent.z
	#
	#_heights_img.generate_mipmaps.call_deferred()
	#_normals_img.generate_mipmaps.call_deferred()
	#heights.update.call_deferred(_heights_img)
	#normals.update.call_deferred(_normals_img)
	#
	#var array_mesh := ArrayMesh.new()
	#array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	#return array_mesh


#func _update_mesh(chunk_pos: Vector2, chunk_resolution: int) -> Mesh:
	#var plane := PlaneMesh.new()
	#plane.subdivide_depth = chunk_resolution
	#plane.subdivide_width = chunk_resolution
	#plane.size = Vector2(chunk_size, chunk_size)
	#
	#var plane_arrays := plane.get_mesh_arrays()
	#var vertex_array : PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_VERTEX]
	#var normal_array : PackedVector3Array = plane_arrays[ArrayMesh.ARRAY_NORMAL]
	##var tangent_array: PackedFloat32Array = plane_arrays[ArrayMesh.ARRAY_TANGENT]
	#
	#for i:int in vertex_array.size():
		#var vertex := vertex_array[i]
		#var normal := Vector3.UP
		##var tangent := Vector3.RIGHT
		#
		#var chunk_offset_x := chunk_pos.x + chunk_size/2
		#var chunk_offset_y := chunk_pos.y + chunk_size/2
		#
		#if noise:
			#var world_x = vertex.x + chunk_offset_x
			#var world_z = vertex.z + chunk_offset_y
			#vertex.y = get_height(world_x,world_z)
			#normal = _get_normal(world_x,world_z)
			##tangent = normal.cross(Vector3.UP)
#
		#vertex_array[i] = vertex
		#normal_array[i] = normal
		##tangent_array[4 * i] = tangent.x
		##tangent_array[4 * i + 1] = tangent.y
		##tangent_array[4 * i + 2] = tangent.z
	#
	#var array_mesh := ArrayMesh.new()
	#array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_arrays)
	#return array_mesh

#func _encode_normal_for_texture(n: Vector3) -> Color:
	#var corrected = Vector3(-n.x, -n.z, n.y)
	#corrected = corrected.normalized()
	#return Color(
		#corrected.x * 0.5 + 0.5,
		#corrected.y * 0.5 + 0.5,
		#corrected.z * 0.5 + 0.5
	#)

#func generate_chunk_map_texture(chunk_grid_x: int, chunk_grid_z: int, sample_grid_res: int) -> Image:
	#
	#var texture_image = Image.create(map_texture_resolution_per_chunk, map_texture_resolution_per_chunk, false, Image.FORMAT_RGBA8)
#
	#var sample_step_meters = float(chunk_size) / (sample_grid_res - 1)
	#
	## 1. Створення сітки вибірки висот та масок лісів (низька роздільна здатність)
	#var sampled_heights := []
	#sampled_heights.resize(sample_grid_res * sample_grid_res)
	#
	#var sampled_terrain_types := [] # 0: суша, 3: ліс (вода визначається висотою)
	#sampled_terrain_types.resize(sample_grid_res * sample_grid_res)
#
	#for sy in range(sample_grid_res):
		#for sx in range(sample_grid_res):
			#var world_x_sample = (chunk_grid_x * chunk_size) + sx * sample_step_meters
			#var world_z_sample = (chunk_grid_z * chunk_size) + sy * sample_step_meters
			#var sample_world_pos = Vector2(world_x_sample, world_z_sample)
#
			#var height = get_height(world_x_sample, world_z_sample)
			#sampled_heights[sy * sample_grid_res + sx] = height
			#
			#var terrain_type = 0 # За замовчуванням: суша
#
			## Перевірка на ліс
			#for forest in _forest_data:
				#var forest_center = forest.pos
				#var forest_radius = forest.radius
				## Важливо: використовуйте той самий об'єкт FastNoiseLite, 
				## що і для генерації лісів, щоб форми лісів збігалися.
				## Якщо forest.noise не існує, використовуйте _forest_noise з вашого MapGenerator.
				#var forest_noise_instance = _forest_noise 
				#var n = forest_noise_instance.get_noise_2d(sample_world_pos.x, sample_world_pos.y) 
				#
				#if sample_world_pos.distance_to(forest_center) < forest_radius * (0.6 + n * 0.4):
					#terrain_type = 3 # Ліс
					#break 
#
			#sampled_terrain_types[sy * sample_grid_res + sx] = terrain_type
#
	## 2. Заповнення пікселів текстури, використовуючи інтерполяцію та процедурні деталі
	#for y_pixel in range(map_texture_resolution_per_chunk):
		#for x_pixel in range(map_texture_resolution_per_chunk):
			#var world_x = (chunk_grid_x * chunk_size) + (float(x_pixel) / map_texture_resolution_per_chunk) * chunk_size
			#var world_z = (chunk_grid_z * chunk_size) + (float(y_pixel) / map_texture_resolution_per_chunk) * chunk_size
			#var current_pixel_world_pos = Vector2(world_x, world_z)
#
			## Обчислення координат в сітці вибірки та інтерполяція висоти
			#var sample_x_float = float(x_pixel) / map_texture_resolution_per_chunk * (sample_grid_res - 1)
			#var sample_y_float = float(y_pixel) / map_texture_resolution_per_chunk * (sample_grid_res - 1)
			#
			#var sx0 = int(floor(sample_x_float))
			#var sy0 = int(floor(sample_y_float))
			#var sx1 = int(ceil(sample_x_float))
			#var sy1 = int(ceil(sample_y_float))
			#
			#sx0 = clampi(sx0, 0, sample_grid_res - 1)
			#sy0 = clampi(sy0, 0, sample_grid_res - 1)
			#sx1 = clampi(sx1, 0, sample_grid_res - 1)
			#sy1 = clampi(sy1, 0, sample_grid_res - 1)
#
			#var h00 = sampled_heights[sy0 * sample_grid_res + sx0]
			#var h01 = sampled_heights[sy0 * sample_grid_res + sx1]
			#var h10 = sampled_heights[sy1 * sample_grid_res + sx0]
			#var h11 = sampled_heights[sy1 * sample_grid_res + sx1]
			#
			#var fx = fmod(sample_x_float, 1.0)
			#var fy = fmod(sample_y_float, 1.0)
			#var interpolated_height = lerp(lerp(h00, h01, fx), lerp(h10, h11, fx), fy)
#
			## Визначення типу місцевості для пікселя: просто беремо найближчу точку для типу
			## або можна зробити більш складну логіку, якщо ліс/вода займає значну частину 4 сусідніх семплів
			#var terrain_type_for_pixel = sampled_terrain_types[sy0 * sample_grid_res + sx0]
			#
			#var pixel_color = _get_stylized_pixel_color(
				#interpolated_height, 
				#terrain_type_for_pixel, # Тепер передаємо лише тип суші/лісу
				#current_pixel_world_pos
			#)
#
			#texture_image.set_pixel(x_pixel, y_pixel, pixel_color)
	#return texture_image

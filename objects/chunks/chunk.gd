@tool
extends Node3D

var chunk_layer := 0
var chunk_size := 256.0
var terrain_meshes := []
var sub_chunk_grid_size := 2 
var sub_chunk_size : float # Розраховується динамічно: chunk_size / sub_chunk_grid_size

@export var objects_data: Array[Dictionary] = []:
	set(new_objects_data):
		objects_data = new_objects_data
		#count_objects.clear()
		#for data in objects_data:
			#var type = data["type"]
			#count_objects[type] = count_objects.get(type, 0) + 1
#
#var count_objects: Dictionary[String,int]

var sub_chunk_nodes: Dictionary[Vector2, Node3D] = {}

func set_visibleOnScreenNotifier3D():
	#var scaled_chunk_size = chunk_size * 2
	#var scales_chunk_pos = -chunk_size
	#var pos := Vector3(scales_chunk_pos,scales_chunk_pos,scales_chunk_pos)
	#var size := Vector3(scaled_chunk_size,scaled_chunk_size,scaled_chunk_size)
	var pos := Vector3.ZERO
	var size := Vector3(chunk_size,chunk_size,chunk_size)
	var aabb:= AABB(pos,size)
	var notifier = get_child(0)
	notifier.aabb = aabb
	#notifier.position += Vector3(chunk_size/2,0,chunk_size/2)

func create_sub_chunks() -> void:
	sub_chunk_size = chunk_size / sub_chunk_grid_size
	var sub_chunk = preload("res://objects/chunks/subChunk.tscn")
	# Створюємо вузли під-чанків у сітці.
	for x in range(sub_chunk_grid_size):
		for z in range(sub_chunk_grid_size):
			var sub_chunk_coords = Vector2(x * sub_chunk_size, z * sub_chunk_size)
			var sub_chunk_node = sub_chunk.instantiate()
			sub_chunk_node.sub_chunk_size = sub_chunk_size
			sub_chunk_node.position = Vector3(sub_chunk_coords.x, 0, sub_chunk_coords.y)
			add_child(sub_chunk_node)
			sub_chunk_nodes[sub_chunk_coords] = sub_chunk_node
			sub_chunk_node.create_meshes()

func update_objects_data() -> void:
	var temp_sub_chunk_transforms: Dictionary[Vector2, Dictionary]# Dictionary[Vector2, Dictionary[String, Array]]
	
	for data in objects_data:
		var type_name = data["type"]
		var object_size = data["size"]
		var object_position = data["position"]
		var sub_chunk_x = floor(object_position.x / sub_chunk_size) * sub_chunk_size
		var sub_chunk_y = floor(object_position.z / sub_chunk_size) * sub_chunk_size
		var sub_chunk_position := Vector3(sub_chunk_x,0,sub_chunk_y)
		
		var position_offset = (object_position - sub_chunk_position - Vector3(sub_chunk_size/2,0,sub_chunk_size/2)) / object_size
		# Ці всі розрахунки в position_offset треба щоб об'єкт стояв на своєму місці, 
		# так як початкові координати орієнтовані на позицію в чанкі, 
		# але позиції під-чанка і мультимеша зміщають позицію об'єкта. 
		# Також scale також впливає на позицію об'єкта.
		var basis = Basis().rotated(Vector3.UP, data["rotation"])
		var transform = Transform3D(basis, position_offset).scaled(object_size * Vector3.ONE)
		
		var sub_chunk_coords := Vector2(sub_chunk_x,sub_chunk_y)
		temp_sub_chunk_transforms.get_or_add(sub_chunk_coords, {}).get_or_add(type_name, []).append(transform)
	
	for key in temp_sub_chunk_transforms.keys():
		sub_chunk_nodes[key].update_multimeshes(temp_sub_chunk_transforms[key])

func show_chunk() -> void:
	# Показати terrain
	for mesh in terrain_meshes:
		mesh.show()

	for sub_chunk in sub_chunk_nodes.values():
		sub_chunk.show()

func hide_chunk() -> void:
	# Приховати terrain
	for mesh in terrain_meshes:
		mesh.hide()

	for sub_chunk in sub_chunk_nodes.values():
		sub_chunk.hide()

func _on_visible_on_screen_notifier_3d_screen_entered() -> void:
	show_chunk()


func _on_visible_on_screen_notifier_3d_screen_exited() -> void:
	hide_chunk()

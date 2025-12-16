@tool
extends Node3D

var MAP_SIZE: int
@export var CHUNK_SIZE: int = 256
@export var LOAD_RADIUS = 2048  # в радіусі яких метрів від камери завантажувати чанки
@onready var camera = get_viewport().get_camera_3d()

signal create_collision_for_chunk(chunk: Node)

var chunks := {}

func add_chunks(chunksDic: Dictionary) ->void:
	for c in chunksDic.keys():
		var chunk = chunksDic[c]
		add_child(chunk)
		chunk.update_objects_data()
		chunks[c] = {
			"node": chunk,
		}
		if chunk.chunk_layer <= 0:
			var notifier: VisibleOnScreenNotifier3D = chunk.get_child(0) as VisibleOnScreenNotifier3D
			if notifier != null:
				notifier.screen_entered.connect(func():
					_on_create_collision_for_chunk(chunk)
				)

func add_chunk(chunkPos: Vector2i,chunk:Node) -> void:
	add_child.call_deferred(chunk)
	chunk.call_deferred("update_objects_data")
	chunks[chunkPos] = {
		"node": chunk,
	}
	if chunk.chunk_layer <= 0:
		var notifier: VisibleOnScreenNotifier3D = chunk.get_child(0) as VisibleOnScreenNotifier3D
		if notifier != null:
			notifier.screen_entered.connect(func():
				_on_create_collision_for_chunk(chunk)
			)


func remove_chunks() -> void:
	if chunks.size() == 0:
		return
	
	for chunk in chunks.keys():
		chunks[chunk].node.queue_free()
	chunks.clear()
	
func _on_create_collision_for_chunk(chunk: Node) -> void:
	# Avoid duplicate collision bodies
	for child in chunk.get_children():
		if child is StaticBody3D:
			return
	var chunk_size:int = chunk.chunk_size
	var terrain :MeshInstance3D = chunk.terrain_meshes[0]
	var coll_area = StaticBody3D.new()
	var coll_shape := CollisionShape3D.new()
	coll_area.add_child.call_deferred(coll_shape)
	var collision_shape = terrain.mesh.create_trimesh_shape()
	coll_shape.shape = collision_shape
	chunk.add_child.call_deferred(coll_area)
	coll_area.position += Vector3(chunk_size/2,0,chunk_size/2)

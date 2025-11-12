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
	map_size = Globals.map_size
	_draw_border_lines(map_size)
	worldImage = Globals.imageTexture.duplicate()
	worldName = Globals.worldName
	worldSeed = Globals.worldSeed
	Globals.clear_data()

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
	if threadGenerate.is_started():
		threadGenerate.wait_to_finish()
	threadGenerate = null
	if mapGenerator:
		mapGenerator.clear_data()
		mapGenerator.queue_free()
	chunks_for_generate.clear()
	worldImage = null
	chunkManager.remove_chunks()
	

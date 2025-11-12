@tool
extends Node3D

var sub_chunk_size : float

var multimesh_instances : Dictionary[String,Array] = {}


func create_meshes() -> void:
	var chunk_data = preload("res://resources/chunkObjects.tres")
	var objectsList : Array[ChunkObject] = chunk_data.objectsList
	for obj in objectsList:
		for type in obj.object_types.values():
			multimesh_instances[type.type_name] = []
			for type_mesh in type.meshes.keys():
				
				var multimesh := MultiMesh.new()
				multimesh.transform_format = MultiMesh.TRANSFORM_3D
				multimesh.mesh = type_mesh
				multimesh.instance_count
				var multimesh_instance :=  MultiMeshInstance3D.new()
				multimesh_instance.multimesh = multimesh
				multimesh_instance.material_override = type.meshes[type_mesh]
				if type.mesh_range.size() != 0:
					var range = type.mesh_range[type_mesh]
					multimesh_instance.visibility_range_begin = range[0]
					multimesh_instance.visibility_range_end = range[1]
					multimesh_instance.lod_bias = 0.2
				multimesh_instance.position = Vector3(sub_chunk_size/2,obj.multimesh_height,sub_chunk_size/2)
				multimesh_instances[type.type_name].append(multimesh_instance)
				add_child(multimesh_instance)

func update_multimeshes(transforms: Dictionary) -> void:
	for type in transforms.keys():
		for mm in multimesh_instances[type]:
			var transforms_array : Array = transforms[type]
			var mmesh :MultiMesh = mm.multimesh
			mmesh.instance_count = transforms_array.size()
			for i in transforms_array.size():
				mmesh.set_instance_transform(i,transforms_array[i])

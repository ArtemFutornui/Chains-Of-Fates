@tool
extends Node3D

var sub_chunk_size : float

var multimesh_instances : Dictionary[String,Array] = {}

var _range_scale_end : float = 0.7
var _lod_bias_value : float = 0.9


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
					var begin : float = range[0]
					var end : float = range[1]
					if obj.object_name == "trees":
						end *= _range_scale_end
					# Розширюємо діапазон з урахуванням радіуса субчанка, щоб уникнути різких зникань
					var radius := sqrt(2.0) * sub_chunk_size * 0.5
					begin = max(0.0, begin - radius)
					end += radius
					multimesh_instance.lod_bias = _lod_bias_value
					multimesh_instance.visibility_range_begin = begin
					multimesh_instance.visibility_range_end = end
					var mesh_path : String = type_mesh.resource_path
					if mesh_path.find("leaves") != -1 and end >= 800.0:
						multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				else:
					# Fallback visibility/LOD for types without explicit mesh_range
					var fb_begin : float = 0.0
					var fb_end : float = 1100.0
					var fb_lod : float = _lod_bias_value
					match obj.object_name:
						"Deposit":
							fb_end = 1000.0
							fb_lod = 0.7
						"rocks":
							fb_end = 1200.0
							fb_lod = 0.7
						"mushrooms":
							fb_end = 800.0
							fb_lod = 0.9
						_:
							fb_end = 1100.0
							fb_lod = _lod_bias_value
					var radius2 := sqrt(2.0) * sub_chunk_size * 0.5
					fb_begin = max(0.0, fb_begin - radius2)
					fb_end += radius2
					multimesh_instance.visibility_range_begin = fb_begin
					multimesh_instance.visibility_range_end = fb_end
					multimesh_instance.lod_bias = fb_lod
					if fb_end >= 800.0 and obj.object_name != "trees":
						multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				multimesh_instance.position = Vector3(sub_chunk_size/2,obj.multimesh_height,sub_chunk_size/2)
				multimesh_instances[type.type_name].append(multimesh_instance)
				add_child(multimesh_instance)

func update_multimeshes(transforms: Dictionary) -> void:
	for type in transforms.keys():
		var transforms_array : Array = transforms[type]
		for mm in multimesh_instances[type]:
			var mmesh :MultiMesh = mm.multimesh
			var count := transforms_array.size()
			if count == 0:
				mmesh.instance_count = 0
				continue
			mmesh.instance_count = count
			for i in range(count):
				mmesh.set_instance_transform(i, transforms_array[i])

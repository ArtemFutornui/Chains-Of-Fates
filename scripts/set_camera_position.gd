extends MultiMeshInstance3D

@onready var camera = get_viewport().get_camera_3d()

func _process(delta: float) -> void:
	if camera:
		var mat = material_override
		if mat and mat is ShaderMaterial:
			material_override.set_shader_parameter("camera_world_position",camera.global_position)

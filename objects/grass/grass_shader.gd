extends GPUParticles3D

@onready var camera = get_viewport().get_camera_3d()
#@onready var cameraTarget = get_tree().get_first_node_in_group("CameraTarget")
@export var noise: FastNoiseLite
@export var distance_from_camera:float = 80.0

func _process(delta: float) -> void:
	if camera:
		var camera_transform: Transform3D = camera.global_transform
		var forward_vector: Vector3 = -camera_transform.basis.z
		var point_in_3d: Vector3 = camera.global_position + (forward_vector * distance_from_camera)
		position = point_in_3d

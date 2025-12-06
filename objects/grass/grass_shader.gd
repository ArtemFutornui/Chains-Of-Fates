extends GPUParticles3D

@onready var camera = get_viewport().get_camera_3d()
@onready var cameraTarget = get_tree().get_first_node_in_group("CameraTarget")
@export var noise: FastNoiseLite
@export var distance_from_camera:float = 80.0
@export var height_disable_threshold: float = 200.0
@export var height_enable_threshold: float = 150.0
@export var coverage_range: float = 100.0
@export var spacing: float = 1.6
@export var rows: int = 128

var _last_visible: bool = true

func _ready() -> void:
	var pm: Material = process_material
	if pm != null and pm is ShaderMaterial:
		var sm: ShaderMaterial = pm as ShaderMaterial
		sm.set_shader_parameter("instance_rows", float(rows))
		sm.set_shader_parameter("instance_spacing", spacing)
		sm.set_shader_parameter("_coverage_range", coverage_range)
		sm.set_shader_parameter("instance_orient_to_normal", true)
		if Globals != null and Globals.mapGenerator != null:
			sm.set_shader_parameter("map_size", float(Globals.map_size))
			if Globals.mapGenerator.heights != null:
				sm.set_shader_parameter("height_map", Globals.mapGenerator.heights)
			if Globals.mapGenerator.normals != null:
				sm.set_shader_parameter("normal_map", Globals.mapGenerator.normals)
			if Globals.imageTexture != null:
				sm.set_shader_parameter("map_noise", Globals.imageTexture)

func _process(delta: float) -> void:
	if camera:
		var pos: Vector3 = camera.global_position
		if cameraTarget:
			pos = cameraTarget.global_position
		position = pos
		var h: float = camera.global_position.y
		var pm2: Material = process_material
		if pm2 != null and pm2 is ShaderMaterial:
			var sm: ShaderMaterial = pm2 as ShaderMaterial
			if h < height_enable_threshold:
				sm.set_shader_parameter("_coverage_range", coverage_range)
				if !_last_visible:
					visible = true
					_last_visible = true
			elif h > height_disable_threshold:
				if _last_visible:
					visible = false
					_last_visible = false

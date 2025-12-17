extends Camera3D

var touch_points := {}  # Словник для зберігання активних дотиків
var last_distance := -1.0
var last_angle := 0.0
# Обмеження для масштабування
@export var min_zoom := 5.0
@export var max_zoom := 200.0
@export_range(0.01,1.0,0.01) var min_zoom_percent := 0.2
# Обмеження для переміщення
@export var map_end_radius = 2048.0

# Точка, навколо якої обертається камера
var target := Vector3()
var target_zoom_y := max_zoom
var tilt_angle_x := -45.0
var current_target_y := 0.0
var desired_target_y := 0.0

# Прапор для відстеження, чи відбувається масштабування або обертання
var is_scaling := false
var is_rotating := false

#Миша
var mouse_rotate_active := false
var last_mouse_position := Vector2()

# Швидкість переміщення та обертання
var min_move_speed := 40.0
var max_move_speed := 300.0
var rotate_speed := 0.01
var zoom_speed := 2.0

var target_zoom_percent = (target_zoom_y - min_zoom) / (max_zoom - min_zoom)
var camera_angle_y := 0.0  # Кут навколо осі Y
var max_tilt_angle := -45.0  # Коли камера далеко
var min_tilt_angle := 0.0  # Коли камера близько



func _process(delta: float) -> void:
	# Переміщення клавішами WASD
	var input_vec = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input_vec.z -= 1
	if Input.is_action_pressed("move_back"):
		input_vec.z += 1
	if Input.is_action_pressed("move_left"):
		input_vec.x -= 1
	if Input.is_action_pressed("move_right"):
		input_vec.x += 1

	if input_vec != Vector3.ZERO:
		input_vec = input_vec.normalized()
		var forward = transform.basis.z
		var right = transform.basis.x
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()

		var move_speed = lerp(min_move_speed, max_move_speed, target_zoom_percent)

		var move = (right * input_vec.x + forward * input_vec.z) * move_speed * delta
		target += move

		# Обмеження target по межах карти
		target.x = clamp(target.x, -map_end_radius, map_end_radius)
		target.z = clamp(target.z, -map_end_radius, map_end_radius)
	
	if current_target_y != desired_target_y or input_vec != Vector3.ZERO:
		# Оновлення target.y (вгору/вниз залежно від зуму)
		update_target_y()
	
	if position.y != target_zoom_y or input_vec != Vector3.ZERO:
		update_camera_position()


func rotate_around_target(angle: float):
	camera_angle_y += angle
	update_camera_position()


func _unhandled_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position  # Додаємо новий дотик
		else:
			touch_points.erase(event.index)  # Видаляємо дотик, якщо він відпущений
		if touch_points.size() < 2:
			last_distance = -1.0  # Скидаємо дистанцію, якщо менше двох пальців
			last_angle = 0.0  # Скидаємо значення кута
			
			# Скидаємо прапор, якщо пальці відпущені
			is_scaling = false
			is_rotating = false

	elif event is InputEventScreenDrag:
		touch_points[event.index] = event.position  # Оновлюємо позицію дотику
		if touch_points.size() == 1:  # Переміщення камери одним пальцем
			var delta = event.relative * 0.05  # Чутливість
			
			# Отримуємо локальні вектори напрямку камери
			var forward = global_transform.basis.z  # Вперед
			var right = global_transform.basis.x  # Право
			
			# Вимикаємо вісь Y (щоб не було руху вгору-вниз)
			forward.y = 0
			right.y = 0
			
			# Нормалізуємо вектори (щоб рух був рівномірним)
			forward = forward.normalized()
			right = right.normalized()
			
			# Обчислюємо зміщення камери
			var move_speed = lerp(min_move_speed, max_move_speed, target_zoom_percent)
			var move = right * -delta.x + forward * -delta.y
			move *= move_speed
			target += move
			
			# Обмеження target по межах карти
			target.x = clamp(target.x, -map_end_radius, map_end_radius)
			target.z = clamp(target.z, -map_end_radius, map_end_radius)
			update_camera_position()
			# Оновлення target.y (вгору/вниз залежно від зуму)
			update_target_y()
		
		elif touch_points.size() == 2:  # Масштабування та обертання
			var keys = touch_points.keys()
			var pos1 = touch_points[keys[0]]
			var pos2 = touch_points[keys[1]]
			
			var distance = pos1.distance_to(pos2)
			var current_angle = rad_to_deg((pos2 - pos1).angle())
			
			if last_distance > 0:
				if !is_rotating and !is_scaling:
					# Визначаємо, чи ми робимо масштабування або обертання
					if abs(distance - last_distance) > 10.0:  # Якщо зміна відстані велика, то це масштабування
						is_scaling = true
					else:  # Якщо зміна кута велика, то це обертання
						is_rotating = true
				
				if is_scaling:
					# Масштабування
					var zoom_factor = (distance - last_distance) * 0.01
					#target_zoom_y = clamp(target_zoom_y + zoom_factor * zoom_speed, min_zoom, max_zoom)
					mouse_zoom(zoom_factor * zoom_speed)
				
				if is_rotating:
					# Обертання
					var angle_diff = current_angle - last_angle
					rotate_around_target(deg_to_rad(angle_diff))
			
			last_distance = distance
			last_angle = current_angle
	# Обробка обертання мишкою
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			mouse_rotate_active = event.pressed
			last_mouse_position = event.position
		
		# Масштабування колесиком
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			mouse_zoom(-zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			mouse_zoom(zoom_speed)
	
	elif event is InputEventMouseMotion:
		if mouse_rotate_active:
			var delta = event.relative
			rotate_around_target(-delta.x * rotate_speed)
			
func mouse_zoom(amount):
	target_zoom_y = clamp(target_zoom_y + amount, min_zoom, max_zoom)
	target_zoom_percent = (target_zoom_y - min_zoom) / (max_zoom - min_zoom)


func update_target_y():
	var ground := get_ground_height(target)
	desired_target_y = 0.0
	var lerp_speed := 5.0
	if ground > 0.1:
		desired_target_y = ground
		var move_speed = lerp(min_move_speed, max_move_speed, target_zoom_percent)
		move_speed = clamp(move_speed, 0.0, 80.0)
		lerp_speed *= sqrt(move_speed)

	if target_zoom_percent < min_zoom_percent:
		var local_percent = target_zoom_percent / min_zoom_percent
		desired_target_y += lerp(min_zoom, 0.0, local_percent)
	current_target_y = lerp(current_target_y, desired_target_y, lerp_speed * get_process_delta_time())
	target.y = current_target_y


func _ready() -> void:
	rotation_degrees.x = tilt_angle_x
	snap_to_target()

func snap_to_target() -> void:
	update_target_y()
	current_target_y = desired_target_y
	target.y = current_target_y
	update_camera_position(100.0) # Force instant update

func update_camera_position(delta: float = -1.0):
	if delta < 0:
		delta = get_process_delta_time()

	# Обчислюємо бажаний нахил
	var desired_tilt_x = max_tilt_angle  # звичайний кут (-45°)
	if target_zoom_percent < min_zoom_percent:
		var local_percent = target_zoom_percent / min_zoom_percent
		desired_tilt_x = lerp(min_tilt_angle, max_tilt_angle, local_percent)

	# Плавне оновлення кута
	tilt_angle_x = lerp(tilt_angle_x, desired_tilt_x, 5.0 * delta)

	# Плавне оновлення дистанції (зуму)
	var current_distance := position.distance_to(target)
	var desired_distance = clamp(target_zoom_y, min_zoom, max_zoom)
	var distance = lerp(current_distance, desired_distance, 30.0 * delta)

	# Мінімальна відстань до target
	var min_camera_distance := 10.0
	distance = max(distance, min_camera_distance)

	# Обчислюємо позицію камери
	var tilt_rad = deg_to_rad(tilt_angle_x)
	var y_rotation = Basis(Vector3.UP, camera_angle_y)
	var offset = Vector3(
		0,
		sin(-tilt_rad),
		cos(-tilt_rad)
	).normalized()
	
	var final_offset = y_rotation * offset * distance

	position = target + final_offset
	look_at(target, Vector3.UP)
	# Для відображення в редакторі
	rotation_degrees.x = tilt_angle_x
	
	var ground_height = get_ground_height(position)
	if position.y - min_zoom < ground_height:
		distance = max(desired_distance, min_camera_distance)
		var new_offset = y_rotation * offset * distance
		position = target + new_offset
		var diff = ground_height - position.y
		position.y += diff + min_zoom
		target_zoom_y = diff + min_zoom
		#target_zoom_percent = (target_zoom_y - min_zoom) / (max_zoom - min_zoom)
	
	$"../CameraTarget".position = target

func get_ground_height(point: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	var from = point + Vector3.UP * 500.0	
	var to = point + Vector3.DOWN * 1000.0
	var result = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if result:
		return result.position.y
	
	return 0.0

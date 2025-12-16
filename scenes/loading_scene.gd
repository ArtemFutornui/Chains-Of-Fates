extends Control

var terminated := false
var threadGenerateImages: Thread
var threadGenerateChunks: Thread
var _start_ms: int
var _delay_done := false
var _delay_timer: Timer
var _post_delay_done := false
var _post_timer: Timer

func _ready() -> void:
	ResourceLoader.load_threaded_request(Globals.next_scene)
	_start_ms = Time.get_ticks_msec()
	_delay_timer = Timer.new()
	_delay_timer.one_shot = true
	_delay_timer.wait_time = 7.0
	add_child(_delay_timer)
	_delay_timer.timeout.connect(_on_delay_timeout)
	_delay_timer.start()
	_post_timer = Timer.new()
	_post_timer.one_shot = true
	_post_timer.wait_time = 1.0
	add_child(_post_timer)
	_post_timer.timeout.connect(_on_post_timeout)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	if Globals.generateDuringLoading:
		threadGenerateImages = Thread.new()
		if Globals.imageTexture == null:
			threadGenerateImages.start(create_chunk_image)
		threadGenerateChunks = Thread.new()
		var preload_ms := int(_delay_timer.wait_time * 1000.0) + int(_post_timer.wait_time * 1000.0)
		threadGenerateChunks.start(generate_some_chunks_during_loading.bind(preload_ms))

func _process(delta: float) -> void:
	var elapsed_ms := Time.get_ticks_msec() - _start_ms
	var wait_ms := int(_delay_timer.wait_time * 1000.0)
	var percent: int = clamp(int(roundi(float(elapsed_ms) / float(wait_ms) * 100.0)), 1, 100)
	$VBoxContainer/Progress_number.text = str(percent) + "%"
	# Перехід у гру виконується у _on_post_timeout рівно після 8 секунд

func _on_delay_timeout() -> void:
	_delay_done = true
	_post_timer.start()
	
func _on_post_timeout() -> void:
	_post_delay_done = true
	terminated = true
	var packed = ResourceLoader.load_threaded_get(Globals.next_scene)
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(Globals.next_scene)
	
func generate_some_chunks_during_loading(preload_ms: int) -> void:
	var gen = Globals.mapGenerator
	if gen == null:
		return
	var start_ms = Time.get_ticks_msec()
	while Globals.all_chunks_coords.size() != 0 and (Time.get_ticks_msec() - start_ms) < preload_ms:
		if is_terminated():
			return
		var coord = Globals.all_chunks_coords[0]
		var chunk = gen.generate_chunk(coord.x, coord.y)
		if is_terminated():
			return
		Globals.chunks[coord] = chunk
		Globals.all_chunks_coords.remove_at(0)


func create_chunk_image() -> void:
	var chunks_coords = Globals.chunks_coords
	var mapGenerator = Globals.mapGenerator
	var map_images = Globals.imagesArray
	var texture : ImageTexture
	while chunks_coords.size() != 0:
		if is_terminated():
			return
		var coord = chunks_coords[0]
		var chunk_image = mapGenerator.generate_chunk_map_texture_direct(coord.x, coord.y)
		map_images[coord] = chunk_image
		texture = combine_all_chunk_textures_from_dict(map_images)
		chunks_coords.remove_at(0)
	Globals.chunks_coords.clear()
	Globals.imagesArray.clear()
	Globals.imageTexture = texture
	print("Image ready")



func combine_all_chunk_textures_from_dict(generated_chunk_images_dict: Dictionary[Vector2i,Image]) -> ImageTexture:
	var texture_resolution_per_chunk := Globals.mapGenerator.map_texture_resolution_per_chunk
	var chunks_per_axis := Globals.mapGenerator.chunks_per_axis
	var total_width = chunks_per_axis * texture_resolution_per_chunk
	var total_height = chunks_per_axis * texture_resolution_per_chunk

	var full_map_image = Image.create(total_width, total_height, false, Image.FORMAT_RGBA8)
	var half_chunks = chunks_per_axis/2
	for chunk_x in range(chunks_per_axis):
		for chunk_z in range(chunks_per_axis):
			var chunk_coords = Vector2i(chunk_x - half_chunks, chunk_z - half_chunks)
			
			if generated_chunk_images_dict.has(chunk_coords):
				var chunk_img = generated_chunk_images_dict[chunk_coords]
				
				# Визначаємо позицію, куди треба "блітувати" це зображення чанка
				var dest_x = chunk_x * texture_resolution_per_chunk
				var dest_y = chunk_z * texture_resolution_per_chunk
				
				# 'blit_rect' копіює прямокутник з одного зображення в інше
				# Перший аргумент: джерельне зображення (Image чанка)
				# Другий аргумент: прямокутник джерела (весь чанк, Rect2i(0,0,роздільна_здатність,роздільна_здатність))
				# Третій аргумент: позиція призначення в цільовому зображенні (Vector2i)
				full_map_image.blit_rect(
					chunk_img, 
					Rect2i(0, 0, texture_resolution_per_chunk, texture_resolution_per_chunk), 
					Vector2i(dest_x, dest_y)
				)
			# Якщо чанк відсутній у словнику, він залишиться чорним, як і потрібно
	
	# Створюємо ImageTexture з готового зображення
	var final_texture = ImageTexture.create_from_image(full_map_image)
	return final_texture

func is_terminated() -> bool:
	return terminated

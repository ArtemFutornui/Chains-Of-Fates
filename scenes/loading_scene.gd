extends Control

var terminated := false
var threadGenerateImages: Thread
var threadGenerateChunks: Thread

func _ready() -> void:
	ResourceLoader.load_threaded_request(Globals.next_scene)
	threadGenerateImages = Thread.new()
	threadGenerateChunks = Thread.new()
	if Globals.generateDuringLoading:
		if Globals.imageTexture == null:
			threadGenerateImages.start(create_chunk_image)
		threadGenerateChunks.start(generate_chunks)

func _process(delta: float) -> void:
	var progress := []
	ResourceLoader.load_threaded_get_status(Globals.next_scene, progress)
	$VBoxContainer/Progress_number.text = str(roundi(progress[0]*100)) + "%"
	if progress[0] == 1:
		var scene = ResourceLoader.load_threaded_get(Globals.next_scene)
		if threadGenerateImages.is_started():
			threadGenerateImages.wait_to_finish()
		terminated = true
		if threadGenerateChunks.is_started():
			threadGenerateChunks.wait_to_finish()
		get_tree().change_scene_to_packed(scene)



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


func generate_chunks() -> void:
	var all_chunks_coords = Globals.all_chunks_coords
	var mapGenerator = Globals.mapGenerator
	var chunks = Globals.chunks
	while all_chunks_coords.size() != 0:
		if is_terminated():
			return
		var coord = all_chunks_coords[0]
		var chunk := mapGenerator.generate_chunk(coord.x,coord.y)
		chunks[coord] = chunk
		all_chunks_coords.remove_at(0)
	Globals.generateDuringLoading = false
		
	print("Map ready")

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
				
				# Визначаємо позицію, куди "блітувати" це зображення чанка
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

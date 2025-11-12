extends Control

var threadImage : Thread
var threadChunks : Thread
var terminated := false

var last_text : String
var mapGenerator : MapGenerator
var map_size := 4096

var map_images : Dictionary[Vector2i,Image]
var chunks_coords :Array[Vector2i]

var chunks : Dictionary[Vector2i,Node]
var all_chunks_coords :Array[Vector2i]

var textureImage

func _ready() -> void:
	textureImage = $MarginContainer2/TextureRect
	randomize()
	var new_seed := str(randi())
	$MarginContainer/VBoxContainer/Seed/LineEdit.text = new_seed
	last_text = new_seed
	threadImage = Thread.new()
	threadChunks = Thread.new()
	create_new_image_from_seed(new_seed.hash())

func _on_back_pressed() -> void:
	terminated = true
	if threadImage.is_started():
		threadImage.wait_to_finish()
	if threadChunks.is_started():
		threadChunks.wait_to_finish()
	for chunk in chunks.values():
		chunk.queue_free()
	mapGenerator.clear_data()
	mapGenerator.queue_free()
	get_tree().change_scene_to_file("res://scenes/mainMenu.tscn")

func create_chunk_image() -> void:
	map_images.clear()
	while chunks_coords.size() != 0:
		if is_terminated():
			return
		var coord := chunks_coords[0]
		var chunk_image := mapGenerator.generate_chunk_map_texture_direct(coord.x, coord.y)
		map_images[coord] = chunk_image
		var texture := combine_all_chunk_textures_from_dict(map_images)
		textureImage.set_deferred("texture",texture)
		chunks_coords.remove_at(0)
	print("Image ready")


func generate_chunks() -> void:
	for chunk in chunks.values():
		chunk.queue_free()
	chunks.clear()
	while all_chunks_coords.size() != 0:
		if is_terminated():
			return
		var coord := all_chunks_coords[0]
		var chunk := mapGenerator.generate_chunk(coord.x,coord.y)
		chunks[coord] = chunk
		all_chunks_coords.remove_at(0)
		
	print("Map ready")

func create_new_image_from_seed(map_seed: int) -> void:
	terminated = true
	if threadImage.is_started():
		threadImage.wait_to_finish()
	if threadChunks.is_started():
		threadChunks.wait_to_finish()
	terminated = false
	if mapGenerator:
		mapGenerator.clear_data()
		mapGenerator.queue_free()
	mapGenerator = MapGenerator.new(map_seed,map_size)
	mapGenerator.pregen_chunks()
	all_chunks_coords.clear()
	chunks_coords.clear()
	var half_chunks = mapGenerator.half_chunks
	var bigger_half_chunks = half_chunks + mapGenerator.layers_from_border * 2
	#Зберігаємо всі координати чанків
	for x in range(-bigger_half_chunks, bigger_half_chunks):
		for z in range(-bigger_half_chunks, bigger_half_chunks):
			var pos = Vector2i(x, z)
			if x >= -half_chunks and x < half_chunks and z >= -half_chunks and z < half_chunks:
				chunks_coords.append(pos)
			all_chunks_coords.append(pos)
	#Сортуємо чанки за відстанню до центру (0,0)
	var center_offset = Vector2(0.5, 0.5)
	chunks_coords.sort_custom(func(a, b):
		var a_dist = (Vector2(a) + center_offset).length_squared()
		var b_dist = (Vector2(b) + center_offset).length_squared()
		return a_dist < b_dist
	)
	all_chunks_coords.sort_custom(func(a, b):
		var a_dist = (Vector2(a) + center_offset).length_squared()
		var b_dist = (Vector2(b) + center_offset).length_squared()
		return a_dist < b_dist
	)
	
	threadImage.start(create_chunk_image)
	threadChunks.start(generate_chunks)


func _exit_tree() -> void:
	chunks.clear()
	map_images.clear()
	all_chunks_coords.clear()
	chunks_coords.clear()
	threadChunks = null
	threadImage = null
	textureImage = null
	$MarginContainer2/TextureRect.queue_free()

func is_terminated() -> bool:
	return terminated

func _on_line_edit_editing_toggled(toggled_on: bool) -> void:
	if toggled_on:
		return
	var text :String = $MarginContainer/VBoxContainer/Seed/LineEdit.text
	if text == "":
		var new_text := str(randi())
		$MarginContainer/VBoxContainer/Seed/LineEdit.text = new_text
		text = new_text
	if text != last_text:
		last_text = text
		var map_seed := text.hash()
		print(map_seed)
		create_new_image_from_seed(map_seed)

func combine_all_chunk_textures_from_dict(generated_chunk_images_dict: Dictionary[Vector2i,Image]) -> ImageTexture:
	var texture_resolution_per_chunk := mapGenerator.map_texture_resolution_per_chunk
	var chunks_per_axis:= mapGenerator.chunks_per_axis
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

func _on_create_pressed() -> void:
	terminated = true
	if threadImage.is_started():
		threadImage.wait_to_finish()
	if threadChunks.is_started():
		threadChunks.wait_to_finish()
	
	if all_chunks_coords.size() != 0 or chunks_coords.size() != 0:
		Globals.generateDuringLoading = true
		Globals.mapGenerator = mapGenerator
		Globals.all_chunks_coords = all_chunks_coords.duplicate()
	if chunks_coords.size() != 0:
		Globals.chunks_coords = chunks_coords.duplicate()
		Globals.imagesArray = map_images.duplicate()
	else:
		Globals.imageTexture = $MarginContainer2/TextureRect.texture.duplicate()
	
	Globals.worldName = $MarginContainer/VBoxContainer/WorldName/LineEdit.text
	if $MarginContainer/VBoxContainer/WorldName/LineEdit.text == "":
		Globals.worldName = "New world"
	Globals.worldSeed = $MarginContainer/VBoxContainer/Seed/LineEdit.text
	Globals.map_size = map_size
	Globals.chunks = chunks.duplicate()
	
	Globals.next_scene = "res://scenes/gameScene.tscn"
	get_tree().change_scene_to_file(Globals.loading_scene)
		

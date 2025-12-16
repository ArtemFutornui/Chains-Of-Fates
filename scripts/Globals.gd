extends Node

var next_scene: String = "res://scenes/mainMenu.tscn"
var loading_scene: String = "res://scenes/loadingScene.tscn"


#Передати в сцену гри
var generateDuringLoading := false
var mapGenerator: MapGenerator
var map_size:int

var chunks:Dictionary[Vector2i,Node]
var all_chunks_coords:Array[Vector2i]

var imageTexture:ImageTexture
var imagesArray:Dictionary[Vector2i,Image]
var chunks_coords:Array[Vector2i]

var worldName:String
var worldSeed:String
var spawn_ready := false

func clear_data() -> void:
	generateDuringLoading = false
	mapGenerator = null
	map_size = 0
	#for chunk in chunks.values():
		#chunk.queue_free()
	chunks.clear()
	all_chunks_coords.clear()
	imageTexture = null
	imagesArray.clear()
	chunks_coords.clear()
	worldName = ""
	worldSeed = ""
	spawn_ready = false

@tool
extends Node3D

@export var map_seed := 0

@export_tool_button("Update")
var update = func():
	seed(map_seed)
	print(randi() % 100)

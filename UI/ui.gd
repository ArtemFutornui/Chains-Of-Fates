extends CanvasLayer


func _on_menu_button_pressed() -> void:
	$MenuButtonContainer.hide()
	$Menu.show()
	get_tree().paused = true


func _on_resume_pressed() -> void:
	$MenuButtonContainer.show()
	$Menu.hide()
	get_tree().paused = false


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	var gameScene := get_tree().current_scene
	if gameScene.name == "GameScene":
		gameScene.close_scene()
	get_tree().change_scene_to_file("res://scenes/mainMenu.tscn")

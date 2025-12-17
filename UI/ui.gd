extends CanvasLayer
class_name UI

func _ready() -> void:
	if has_node("/root/TimeManager"):
		var tm = get_node("/root/TimeManager")
		_update_date_label(tm.current_day, tm.current_season, tm.current_year)
		tm.time_tick.connect(_on_time_tick)
	else:
		printerr("TimeManager autoload not found!")

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

func _on_pause_pressed() -> void:
	if has_node("/root/TimeManager"):
		get_node("/root/TimeManager").pause_game()

func _on_speed_1x_pressed() -> void:
	if has_node("/root/TimeManager"):
		get_node("/root/TimeManager").set_speed(1.0)

func _on_speed_2x_pressed() -> void:
	if has_node("/root/TimeManager"):
		get_node("/root/TimeManager").set_speed(2.0)

func _on_speed_5x_pressed() -> void:
	if has_node("/root/TimeManager"):
		get_node("/root/TimeManager").set_speed(5.0)

func _on_time_tick(day: int, season: int, year: int, _hour: int, _minute: int) -> void:
	_update_date_label(day, season, year)

func _update_date_label(day: int, season: int, year: int) -> void:
	if has_node("TimeControlContainer/VBoxContainer/DateLabel"):
		$TimeControlContainer/VBoxContainer/DateLabel.text = "Year %d, Season %d, Day %d" % [year, season, day]

extends CanvasLayer

@onready var console_panel: Panel = $ConsolePanel
@onready var output_box: RichTextLabel = $ConsolePanel/VBoxContainer/Output
@onready var input_line: LineEdit = $ConsolePanel/VBoxContainer/Input

var is_open: bool = false
var command_history: Array[String] = []
var history_index: int = -1

func _ready() -> void:
	console_panel.hide()
	process_mode = Node.PROCESS_MODE_ALWAYS # Console works even when paused

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_console"):
		var current_scene = get_tree().current_scene
		# Relaxed check: works if scene file is GameScene or if root node is GameScene
		if current_scene and (current_scene.scene_file_path == "res://scenes/gameScene.tscn" or current_scene.name == "GameScene"):
			toggle_console()

func toggle_console() -> void:
	is_open = !is_open
	console_panel.visible = is_open
	
	if is_open:
		input_line.grab_focus()
		# Optionally pause game when console is open
		# get_tree().paused = true 
	else:
		input_line.release_focus()
		# get_tree().paused = false

func _on_input_text_submitted(new_text: String) -> void:
	if new_text.strip_edges() == "":
		return
		
	input_line.clear()
	# Print command to history first (grey)
	print_to_console("> " + new_text, Color.LIGHT_GRAY)
	
	command_history.append(new_text)
	history_index = command_history.size()
	
	parse_command(new_text)

func print_to_console(text: String, color: Color = Color.WHITE) -> void:
	output_box.push_color(color)
	output_box.append_text(text + "\n")
	output_box.pop()

func parse_command(input: String) -> void:
	var parts = input.split(" ", false)
	if parts.size() == 0:
		return
		
	var command = parts[0].to_lower()
	
	match command:
		"info":
			print_to_console("Available commands:", Color.CYAN)
			print_to_console("  info - Show this help message", Color.WHITE)
			print_to_console("  skip [unit] [amount] - Skip time. Units: day, season, year", Color.WHITE)
			
		"skip":
			# Re-print the command with syntax highlighting
			# Note: We already printed the raw command, but this adds the colored breakdown
			# To match the request exactly ("when written, it marks blue..."), we simulate the parsed output
			
			if parts.size() < 3:
				print_to_console("ERROR: Usage: skip [day/season/year] [amount]", Color.RED)
				return
				
			var unit = parts[1].to_lower()
			var amount_str = parts[2]
			
			if unit not in ["day", "season", "year"]:
				print_to_console("ERROR: Invalid unit. Use 'day', 'season', or 'year'", Color.RED)
				return
				
			if not amount_str.is_valid_int():
				print_to_console("ERROR: Amount must be an integer", Color.RED)
				return
			
			# Visual feedback of parsed command
			output_box.push_color(Color.CYAN)
			output_box.add_text("Executed: skip ")
			output_box.pop()
			
			output_box.push_color(Color.GREEN)
			output_box.add_text(unit + " ")
			output_box.pop()
			
			output_box.push_color(Color.WHITE)
			output_box.add_text(amount_str + "\n")
			output_box.pop()
			
			var amount = amount_str.to_int()
			
			# Execute Logic
			if has_node("/root/TimeManager"):
				get_node("/root/TimeManager").skip_time(amount, unit)
				print_to_console("Time advanced successfully.", Color.LIGHT_GRAY)

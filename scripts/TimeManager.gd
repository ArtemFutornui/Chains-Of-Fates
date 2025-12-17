extends Node

signal time_tick(day: int, season: int, year: int, hour: int, minute: int)

# Configuration
const REAL_SECONDS_PER_DAY: float = 360.0 # 6 minutes = 360 seconds
const GAME_HOURS_PER_DAY: int = 24
const GAME_MINUTES_PER_HOUR: int = 60
const DAYS_PER_SEASON: int = 15
const SEASONS_PER_YEAR: int = 4

# Derived constants
# Total game minutes in a day = 24 * 60 = 1440
# Real seconds per game minute = 360 / 1440 = 0.25 seconds
var _real_seconds_per_game_minute: float

# State
var current_minute: int = 0
var current_hour: int = 9
var current_day: int = 1
var current_season: int = 1
var current_year: int = 1

var time_scale: float = 1.0
var is_paused: bool = false
var _accumulator: float = 0.0

func _ready() -> void:
	_real_seconds_per_game_minute = REAL_SECONDS_PER_DAY / (float(GAME_HOURS_PER_DAY) * float(GAME_MINUTES_PER_HOUR))
	
func _process(delta: float) -> void:
	if is_paused:
		return
		
	_accumulator += delta * time_scale
	
	while _accumulator >= _real_seconds_per_game_minute:
		_accumulator -= _real_seconds_per_game_minute
		_advance_minute()

func _advance_minute() -> void:
	current_minute += 1
	
	if current_minute >= GAME_MINUTES_PER_HOUR:
		current_minute = 0
		current_hour += 1
		
		if current_hour >= GAME_HOURS_PER_DAY:
			current_hour = 0
			current_day += 1
			
			if current_day > DAYS_PER_SEASON:
				current_day = 1
				current_season += 1
				
				if current_season > SEASONS_PER_YEAR:
					current_season = 1
					current_year += 1
	
	time_tick.emit(current_day, current_season, current_year, current_hour, current_minute)

func get_time_of_day() -> float:
	return float(current_hour) + float(current_minute) / float(GAME_MINUTES_PER_HOUR)

func set_speed(speed: float) -> void:
	time_scale = speed
	is_paused = false

func pause_game() -> void:
	is_paused = true

func resume_game() -> void:
	is_paused = false

func get_date_string() -> String:
	return "Year %d, Season %d, Day %d" % [current_year, current_season, current_day]



func skip_time(amount: int, unit: String) -> void:
	match unit:
		"day":
			current_day += amount
		"season":
			current_season += amount
		"year":
			current_year += amount
			
	# Normalize date overflow
	while current_day > DAYS_PER_SEASON:
		current_day -= DAYS_PER_SEASON
		current_season += 1
		
	while current_season > SEASONS_PER_YEAR:
		current_season -= SEASONS_PER_YEAR
		current_year += 1
		
	time_tick.emit(current_day, current_season, current_year, current_hour, current_minute)

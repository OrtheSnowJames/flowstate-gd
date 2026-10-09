extends Node3D

@onready var red_score: Label3D = get_node("red_score")
@onready var blue_score: Label3D = get_node("blue_score")
@onready var red_goal: Label3D = get_node_or_null("red_goal")
@onready var blue_goal: Label3D = get_node_or_null("blue_goal")

var _red_score := 0
var _blue_score := 0
var _red_goal := 0
var _blue_goal := 0


func _ready() -> void:
	_apply_labels()


func set_scores(red: int, blue: int) -> void:
	_red_score = red
	_blue_score = blue
	_apply_labels()


func set_goals(red: int, blue: int) -> void:
	_red_goal = red
	_blue_goal = blue
	_apply_labels()


func set_round_progress(red_points: int, blue_points: int, red_goal_points: int, blue_goal_points: int) -> void:
	_red_score = red_points
	_blue_score = blue_points
	_red_goal = red_goal_points
	_blue_goal = blue_goal_points
	_apply_labels()


func change_red_score(to: int) -> void:
	_red_score = to
	_apply_labels()


func increment_red_score(by: int = 1) -> void:
	change_red_score(_red_score + by)


func change_blue_score(to: int) -> void:
	_blue_score = to
	_apply_labels()


func increment_blue_score(by: int = 1) -> void:
	change_blue_score(_blue_score + by)


func _apply_labels() -> void:
	if red_score:
		red_score.text = str(_red_score)
	if blue_score:
		blue_score.text = str(_blue_score)
	if red_goal:
		red_goal.text = _goal_text(_red_goal)
	if blue_goal:
		blue_goal.text = _goal_text(_blue_goal)


func _goal_text(points: int) -> String:
	var unit := "point" if points == 1 else "points"
	return "Goal: %d %s" % [points, unit]

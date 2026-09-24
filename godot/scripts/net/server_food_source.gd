# 伺服器食物來源：食物位置由伺服器決定（food_spawned），吃到時送 food_eaten_request（同 Flutter game_controller _tick()）。
# game_session.gd 收到 food_spawned 時呼叫 spawn()。
extends "res://scripts/food_source.gd"

var net: Node   # net_client.gd

func spawn(food_id: String, cell: Vector2i) -> void:
	food_spawned.emit(food_id, cell)

func report_eaten(food_id: String, head_cell: Vector2i) -> void:
	net.send("food_eaten_request", {"foodId": food_id, "headPos": {"x": head_cell.x, "y": head_cell.y}})

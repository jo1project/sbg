# 食物（寶石）來源介面。畫面端（food_manager.gd）只認這個介面，不管食物是誰產生的。
# 對應 Flutter/伺服器協定：
#   S2C food_spawned       { foodId: String, position: {x, y} }  -> 發出 food_spawned 信號
#   C2S food_eaten_request { foodId: String, headPos: {x, y} }  <- report_eaten() 送出
# 伺服器沒有「食物消失」訊息：吃到判定跟 Flutter 一樣在 client 端（蛇頭走進食物格），
# client 自己先移除、再回報；伺服器驗證後補一個新的 food_spawned（場上恆定 3 個）。
# 之後接伺服器時，寫一個 ServerFoodSource 繼承這個類別：收到 food_spawned 訊息就 emit，
# report_eaten() 裡送 food_eaten_request，其他檔案都不用改。
extends Node

signal food_spawned(food_id: String, cell: Vector2i)
signal food_removed(food_id: String)   # 保留給「伺服器強制清掉食物」之類的情況（例如重新開局）

# 對戰開始時呼叫（本地產生器在這裡放初始的 3 個；伺服器版什麼都不用做，等訊息進來）
func start() -> void:
	pass

# client 判定吃到後呼叫
func report_eaten(_food_id: String, _head_cell: Vector2i) -> void:
	pass

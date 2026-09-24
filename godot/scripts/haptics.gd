# 震動回饋。對應 Flutter 的 HapticFeedback.heavyImpact()（被攻擊時，見規格 9.3）：
# 一下短而重的觸感，不是持續的嗡嗡聲，所以用很短的時間 + 最大強度。
# 注意：Android 匯出時要在 export preset 勾 VIBRATE 權限；電腦上不會有任何反應。
extends RefCounted

const HEAVY_MS := 40

static func heavy_impact() -> void:
	Input.vibrate_handheld(HEAVY_MS, 1.0)
	if OS.is_debug_build() and not OS.has_feature("mobile"):
		print("[haptics] heavy_impact (%dms)" % HEAVY_MS)

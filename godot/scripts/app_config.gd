# 執行模式與伺服器網址的預設值（對應 Flutter config.dart 的 --dart-define=SERVER_URL）。
#
# 伺服器網址（優先順序由高到低）：
#   1. 命令列 --sbg-server=ws://...
#   2. 環境變數 SBG_SERVER_URL
#   3. 建置時產生的 res://build_config.gd 的 SERVER_URL（tools/write_build_config.sh，不進版控——
#      這個 repo 是 public，正式站網址不寫在原始碼裡；CI 用 repo secret SERVER_URL 產生）
#   4. debug build：ws://localhost:8080；release build：沒有（連線模式會顯示「沒有設定伺服器網址」）
#
# 模式：release build 預設線上模式；debug build（編輯器、debug 匯出）預設本地單機模式。
#   強制線上：--online 或 SBG_ONLINE=1；強制本地：--local 或 SBG_ONLINE=0。
#   --sbg-release-defaults（只在 debug build 有效）：用 release 的預設值跑，方便在編輯器裡測試。
extends RefCounted

const BUILD_CONFIG := "res://build_config.gd"
const DEV_SERVER_URL := "ws://localhost:8080"

static func _args() -> PackedStringArray:
	return OS.get_cmdline_user_args() + OS.get_cmdline_args()

static func is_release_defaults() -> bool:
	return not OS.is_debug_build() or "--sbg-release-defaults" in _args()

# 建置時寫進去的網址（沒有 build_config.gd 就是空字串）
static func build_server_url() -> String:
	if not ResourceLoader.exists(BUILD_CONFIG):
		return ""
	var s: Script = load(BUILD_CONFIG)
	return str(s.get_script_constant_map().get("SERVER_URL", "")) if s else ""

static func server_url() -> String:
	for a in _args():
		if a.begins_with("--sbg-server="):
			return a.trim_prefix("--sbg-server=")
	var env := OS.get_environment("SBG_SERVER_URL")
	if env != "":
		return env
	var built := build_server_url()
	if built != "":
		return built
	return "" if is_release_defaults() else DEV_SERVER_URL

# 本地模式改用別張地圖（例如測大地圖效能）：--sbg-map=<地圖 JSON 路徑，res:// 或絕對路徑>；沒給 = ""
static func local_map_override() -> String:
	for a in _args():
		if a.begins_with("--sbg-map="):
			return a.trim_prefix("--sbg-map=")
	return ""

static func online_default() -> bool:
	var args := _args()
	if "--local" in args or OS.get_environment("SBG_ONLINE") == "0":
		return false
	if "--online" in args or OS.get_environment("SBG_ONLINE") == "1":
		return true
	return is_release_defaults()

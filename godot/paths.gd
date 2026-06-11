class_name Paths
# 安裝路徑的單一出處：根目錄＝Godot 專案(res://)的上一層，全部路徑由它推出，
# 不寫死 → 整包可搬到任意位置。給 cmd.exe 用的反斜線版用 ROOT_WIN。

static var ROOT: String = ProjectSettings.globalize_path("res://..").rstrip("/")
static var ROOT_WIN: String = ROOT.replace("/", "\\")
static var APP_DIR: String = ROOT + "/app"
static var SESSIONS_DIR: String = ROOT + "/runtime/sessions"
static var USAGE_FILE: String = ROOT + "/runtime/usage.json"
static var REHIRE_FILE: String = ROOT + "/runtime/rehire.json"
static var REHIRE_HIDDEN_FILE: String = ROOT + "/runtime/rehire_hidden.json"
static var UI_STATE_FILE: String = ROOT + "/runtime/ui_state.json"
static var TILED_DIR: String = ROOT + "/assets/tiled/"
static var ICON_FILE: String = ROOT + "/assets/icon.png"
static var CHARACTERS_DIR: String = ROOT + "/assets/characters"
static var SHOT_FILE: String = ROOT + "/runtime/_shot.png"
static var SHOT_BOARD_FILE: String = ROOT + "/runtime/_shot_board.png"

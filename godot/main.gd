extends Node2D
# FunAI Robot Map — 階段 2b
# 輪詢 runtime/sessions/*.json → 每個 session 一隻角色，依狀態播動畫、依專案分區。
# 素材從 assets 絕對路徑載入，不需 import。

# BOT 角色表（16×32 幀，方向序 右0 上1 左2 正3；每方向 6 格）
const ROW_IDLE := 1    # 第2列：站著待機（4 向×6）
const ROW_WALK := 2    # 第3列：走路（4 向×6）
const ROW_PHONE := 6   # 第7列：等待滑手機（12 格，正面）
const ROW_READ := 7    # 第8列：休息看書（12 格，正面）
const SESSIONS_DIR := "D:/Work/FunAI/runtime/sessions"
const USAGE_FILE := "D:/Work/FunAI/runtime/usage.json"
const TILED_DIR := "D:/Work/FunAI/assets/tiled/"

# 工作看板（獨立視窗，遊戲化呈現：負荷量表 + LV + 產出/閱讀/回合 + 人才庫）
const USAGE_W := 260            # 看板視窗寬
const USAGE_MIN_H := 220        # 看板最小高（拉高把手的下限）
const CONTEXT_MAX := 200000.0   # 負荷量表的分母（context 上限；超過=超出負荷）
const USAGE_REFRESH := 1.0      # 看板多久刷新一次（秒）
const DEPARTED_FILE := "D:/Work/FunAI/runtime/departed.json"
const DEPARTED_MAX := 8         # 人才庫（離職名單）最多記幾筆
# 負荷比例 → 遊戲字眼（由低到高，取第一個達標的）
const LOAD_WORDS := [
	[0.30, "游刃有餘", Color(0.55, 0.85, 0.60)],
	[0.55, "漸入佳境", Color(0.70, 0.85, 0.55)],
	[0.75, "全神貫注", Color(0.95, 0.85, 0.45)],
	[0.90, "火力全開", Color(1.00, 0.65, 0.35)],
	[1.00, "瀕臨極限", Color(1.00, 0.45, 0.35)],
]
const LOAD_OVER := ["⚠ 工作量超出負荷", Color(1.0, 0.35, 0.30)]

# 時間衰減（秒）：沒有「中斷」hook，靠 ts 變舊自我修正
const DONE_DECAY := 5.0       # done 顯示一下就回 idle
const ACTIVE_FRESH := 6.0     # transcript 這秒數內有更新 → 正在輸出 = working（主要活躍訊號）
const ACTIVE_IDLE := 120.0    # 沒在輸出超過這秒數 → 回 idle（容忍長回合/長工具空檔）
const ACTIVE_DECAY := 180.0   # 安全網：沒 transcript 路徑時靠事件 ts 退回 idle
const WAIT_DECAY := 180.0     # waiting 超過這秒數沒動作 → 視為閒置（避免卡死在等待）
const ZOMBIE_SEC := 1800.0    # transcript 超過這秒數沒動且事件也舊 → 死掉的 session，隱藏

const FRAME_W := 16
const FRAME_H := 32
const SCALE := 1.2
const NAMEPLATE_SIZE := 13       # 名牌字體大小
const POLL_SEC := 0.4          # 多久掃一次 sessions 資料夾
const FRAME_DUR := 0.14        # 每幀動畫秒數
const WALK_SPEED := 120.0      # 走動速度 px/s
const PLAYER_SPEED := 95.0     # 玩家角色走動速度 px/s

# 工作座位（來自 Tiled 地圖的格座標 col,row；face=面向 down/up）
const SEATS := [
	{"col": 9, "row": 5, "face": "down"},   # room1
	{"col": 12, "row": 5, "face": "down"},
	{"col": 9, "row": 9, "face": "up"},
	{"col": 12, "row": 9, "face": "up"},
	{"col": 18, "row": 5, "face": "down"},  # room2
	{"col": 21, "row": 5, "face": "down"},
	{"col": 18, "row": 9, "face": "up"},
	{"col": 21, "row": 9, "face": "up"},
]
# 休息點（座位序對應；前 4=左休息室、後 4=右休息室；散開不擠在一起，皆在 nav 可走格）
const LOUNGE_TILES := [[2, 3], [4, 3], [2, 7], [4, 9], [27, 3], [29, 3], [27, 7], [29, 9]]
# 等待位置（座位序對應；前 4 個=room1，後 4 個=room2）
const WAIT_TILES := [[8, 3], [11, 2], [15, 3], [13, 3], [17, 3], [20, 2], [24, 3], [22, 3]]
# 通道開口（強制可走，連通各模組）
const PASSAGE_TILES := [[6, 4], [6, 5], [6, 6], [25, 4], [25, 5], [25, 6]]
# 座位人物上下位移（格，正值=往上移動的格數）— 微調坐姿位置用
const SEAT_UP_DY := 1.5
const SEAT_DOWN_DY := 0.5

# 狀態 → 名牌顏色提示
const STATE_COLOR := {
	"idle": Color(0.7, 0.7, 0.7),
	"thinking": Color(0.6, 0.8, 1.0),
	"working": Color(0.7, 1.0, 0.7),
	"waiting": Color(1.0, 0.85, 0.3),
	"done": Color(0.6, 1.0, 0.6),
	"error": Color(1.0, 0.5, 0.5),
}

var _robots := {}            # session_id -> 角色狀態 dict
var _project_slots := {}     # session_id -> 座位 index
var _next_slot := 0
var _poll_t := 0.0
var _shot := false
var _shot_t := 0.0
var _debug_mode := false
var _map_w := 17
var _map_h := 11
var _astar: AStarGrid2D
var _bot_tex := {}   # 角色名 -> Texture2D（BOT1~BOT9）
var _dragging := false
var _drag_off := Vector2i()
var _player := {}        # 玩家可控角色（WASD/方向鍵走動）
var _selected := ""           # 被點選顯示進度的 session
var _detail_win: Window       # 大型進度視窗（獨立 OS 視窗）
var _detail_text: RichTextLabel
var _detail_header: Label
var _detail_t := 0.0          # 刷新計時
var _detail_dragging := false
var _detail_drag_off := Vector2i()
var _file_dialog: FileDialog   # 點空椅 → 選資料夾 → 開新 PowerShell+claude
var _usage_win: Window         # 工作看板（獨立 OS 視窗：可分開釘選/拖曳/拉高）
var _usage_box: VBoxContainer  # 看板的卡片容器（每次刷新重建內容）
var _usage_t := 0.0            # 看板刷新計時
var _usage_dragging := false
var _usage_drag_off := Vector2i()
var _usage_resizing := false   # 拖底部把手調整高度中
var _departed: Array = []      # 人才庫：離職 session [{project, cwd}]，可重新雇用

func _input(event: InputEvent) -> void:
	# 左鍵：點機器人→顯示進度氣泡；點空白→拖曳整個視窗
	if _debug_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _robot_at(get_viewport().get_mouse_position())
			if hit != "":
				_on_robot_click(hit)           # 點機器人 = 把它的終端叫到最前
				_dragging = false
			elif _empty_seat_at(get_viewport().get_mouse_position()):
				_file_dialog.popup_centered(Vector2i(780, 540))   # 點空椅 = 開新 session
			else:
				_dragging = true               # 點空白 = 拖視窗
				_drag_off = DisplayServer.mouse_get_position() - get_window().position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		get_window().position = DisplayServer.mouse_get_position() - _drag_off

func _robot_at(mp: Vector2) -> String:
	for sid in _robots:
		var p: Vector2 = _robots[sid].pos
		if abs(mp.x - p.x) < FRAME_W * SCALE * 0.6 and mp.y > p.y - FRAME_H * SCALE * 0.7 and mp.y < p.y + FRAME_H * SCALE * 0.5:
			return sid
	return ""

func _on_robot_click(sid: String) -> void:
	# 點機器人 → 開對話框（最近一輪 Q&A）；對話框底部按鈕才呼叫終端
	if sid == _selected and _detail_win.visible:
		_selected = ""
		_detail_win.hide()
	else:
		_open_detail(sid)

func _focus_selected_terminal() -> void:
	if _selected == "" or not _robots.has(_selected):
		return
	var hw := int(_robots[_selected].get("hwnd", 0))
	if hw != 0:
		OS.create_process("py", ["D:/Work/FunAI/app/winfocus.py", str(hw)])
	_on_detail_close()   # 叫出終端後對話卡就功成身退，自動關閉

func _build_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "選擇專案資料夾 → 開新 PowerShell 跑 claude"
	_file_dialog.use_native_dialog = true
	_file_dialog.dir_selected.connect(_on_folder_selected)
	add_child(_file_dialog)

func _on_folder_selected(path: String) -> void:
	# 在選的資料夾開一個新 PowerShell 視窗並啟動 claude（引號處理交給 .cmd，最穩）
	OS.create_process("cmd.exe", ["/c", "D:\\Work\\FunAI\\app\\launch_claude.cmd", path])

func _empty_seat_at(mp: Vector2) -> bool:
	# 點到「沒有機器人佔用的座位」→ 觸發開新 session
	var occupied := {}
	for sid in _robots:
		occupied[int(_robots[sid].seat_idx)] = true
	for i in range(SEATS.size()):
		if occupied.has(i):
			continue
		var p := _seat_px(i)
		if abs(mp.x - p.x) < FRAME_W * SCALE * 0.7 and mp.y > p.y - FRAME_H * SCALE * 0.7 and mp.y < p.y + FRAME_H * SCALE * 0.5:
			return true
	return false

func _ready() -> void:
	# 透明背景（多管齊下，確保 Windows 上生效）
	get_tree().root.transparent_bg = true
	get_window().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	var w := get_window()
	w.borderless = true
	w.always_on_top = false
	_build_detail_window()
	_shot = OS.get_cmdline_args().has("--shot")
	for i in range(1, 10):   # 載入 BOT1~BOT9（缺檔就略過）
		var nm := "BOT%d" % i
		var p := "D:/Work/FunAI/assets/characters/%s.png" % nm
		if not FileAccess.file_exists(p):
			continue
		var img := Image.load_from_file(p)
		if img != null:
			_bot_tex[nm] = ImageTexture.create_from_image(img)
	if OS.get_cmdline_args().has("--bot"):
		get_window().size = Vector2i(720, 420)
		RenderingServer.set_default_clear_color(Color(0.5, 0.5, 0.5, 1))
		_debug_mode = true
		_debug_bot()
		_shot = true
		return
	_load_map()
	if OS.get_cmdline_args().has("--grid"):
		_debug_mode = true       # 持續顯示座標格線（不自動關），供讀座位/休息室座標
		_draw_grid()
		return
	_make_player()
	_load_departed()
	_build_usage_window()
	_make_pin_button()
	_build_file_dialog()
	_scan()   # 立即掃一次
	_refresh_usage()

func _process(delta: float) -> void:
	_poll_t += delta
	if not _debug_mode and _poll_t >= POLL_SEC:
		_poll_t = 0.0
		_scan()
	if _shot:
		_shot_t += delta
		if _shot_t > 1.0:
			get_viewport().get_texture().get_image().save_png("D:/Work/FunAI/runtime/_shot.png")
			if _usage_win != null and _usage_win.visible:   # 看板是獨立視窗，另存一張
				_usage_win.get_texture().get_image().save_png("D:/Work/FunAI/runtime/_shot_board.png")
			get_tree().quit()
			return
	# 行為（移動）+ 動畫
	for sid in _robots:
		_update_robot(_robots[sid], delta)
	_update_player(delta)
	# 對話框拖曳：按住標題後每幀跟著滑鼠移動，放開即停（不依賴 motion 事件）
	if _detail_dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_detail_win.position = DisplayServer.mouse_get_position() - _detail_drag_off
		else:
			_detail_dragging = false
	# 大型進度視窗：開著就定期刷新內容
	if _selected != "" and _robots.has(_selected) and _detail_win.visible:
		_detail_t -= delta
		if _detail_t <= 0.0:
			_detail_t = 1.0
			_refresh_detail()
	elif _detail_win.visible and (_selected == "" or not _robots.has(_selected)):
		_detail_win.hide()
	# 工作看板：拖曳 / 拉高 / 定期刷新（讀 usage.json）
	if _usage_dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_usage_win.position = DisplayServer.mouse_get_position() - _usage_drag_off
		else:
			_usage_dragging = false
	if _usage_resizing:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var maxh := DisplayServer.screen_get_size(_usage_win.current_screen).y
			var h := DisplayServer.mouse_get_position().y - _usage_win.position.y + 10
			_usage_win.size = Vector2i(USAGE_W, clampi(h, USAGE_MIN_H, maxh))
		else:
			_usage_resizing = false
	if not _debug_mode and _usage_box != null and _usage_win.visible:
		_usage_t -= delta
		if _usage_t <= 0.0:
			_usage_t = USAGE_REFRESH
			_refresh_usage()

func _build_detail_window() -> void:
	_detail_win = Window.new()
	_detail_win.title = "FunAI 對話"
	_detail_win.size = Vector2i(540, 520)
	_detail_win.visible = false
	_detail_win.borderless = true       # 移除原始 OS 視窗邊框，改用卡片自己的關閉鈕
	_detail_win.unresizable = true
	_detail_win.transparent_bg = true   # 去背：卡片外透明，只露出圓角卡片
	add_child(_detail_win)
	_detail_win.set_flag(Window.FLAG_TRANSPARENT, true)
	_detail_win.close_requested.connect(_on_detail_close)
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(m, 14)
	_detail_win.add_child(outer)
	# 卡片（圓角面板）
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.12, 0.13, 0.18, 1.0)
	csb.set_corner_radius_all(16)
	csb.set_border_width_all(1)
	csb.border_color = Color(0.26, 0.30, 0.42, 1.0)
	csb.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", csb)
	outer.add_child(card)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)
	# 標題列：標題（可拖曳移動視窗）+ 自己的關閉鈕
	var headrow := HBoxContainer.new()
	vbox.add_child(headrow)
	_detail_header = Label.new()
	_detail_header.add_theme_font_size_override("font_size", 17)
	_detail_header.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	_detail_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_header.gui_input.connect(_on_header_drag)
	headrow.add_child(_detail_header)
	var xbtn := Button.new()
	xbtn.text = "✕"
	xbtn.focus_mode = Control.FOCUS_NONE
	xbtn.add_theme_font_size_override("font_size", 15)
	var xsb := StyleBoxFlat.new()
	xsb.bg_color = Color(0.24, 0.11, 0.13, 1.0)
	xsb.set_corner_radius_all(8)
	xsb.set_content_margin_all(7)
	var xhsb := xsb.duplicate()
	xhsb.bg_color = Color(0.62, 0.20, 0.22, 1.0)
	xbtn.add_theme_stylebox_override("normal", xsb)
	xbtn.add_theme_stylebox_override("hover", xhsb)
	xbtn.add_theme_stylebox_override("pressed", xsb)
	xbtn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	xbtn.pressed.connect(_on_detail_close)
	headrow.add_child(xbtn)
	# 聊天內容（內嵌一張稍深的卡片）
	var inner := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.09, 0.10, 0.14, 1.0)
	isb.set_corner_radius_all(10)
	isb.set_content_margin_all(12)
	inner.add_theme_stylebox_override("panel", isb)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(inner)
	_detail_text = RichTextLabel.new()
	_detail_text.bbcode_enabled = true
	_detail_text.scroll_active = true
	_detail_text.scroll_following = true
	_detail_text.selection_enabled = true
	_detail_text.add_theme_font_size_override("normal_font_size", 15)
	_detail_text.add_theme_constant_override("line_separation", 3)
	inner.add_child(_detail_text)
	# 底部：呼叫對應終端（給 TAB 聚焦不到時用）
	var fbtn := Button.new()
	fbtn.text = "▸ 呼叫這個 session 的終端視窗"
	fbtn.add_theme_font_size_override("font_size", 15)
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(0.20, 0.34, 0.52, 1.0)
	nsb.set_corner_radius_all(9)
	nsb.set_content_margin_all(10)
	var hsb := nsb.duplicate()
	hsb.bg_color = Color(0.26, 0.42, 0.62, 1.0)
	fbtn.add_theme_stylebox_override("normal", nsb)
	fbtn.add_theme_stylebox_override("hover", hsb)
	fbtn.add_theme_stylebox_override("pressed", nsb)
	fbtn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	fbtn.pressed.connect(_focus_selected_terminal)
	vbox.add_child(fbtn)

func _on_detail_close() -> void:
	_selected = ""
	_detail_win.hide()

func _on_header_drag(event: InputEvent) -> void:
	# 按下標題列 = 開始拖曳；實際移動在 _process 每幀輪詢（拖出標題範圍也不斷線）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_detail_dragging = true
		_detail_drag_off = DisplayServer.mouse_get_position() - _detail_win.position

func _open_detail(sid: String) -> void:
	_selected = sid
	_refresh_detail()
	# 置中於螢幕
	var scr := get_window().current_screen
	var sp := DisplayServer.screen_get_size(scr)
	var so := DisplayServer.screen_get_position(scr)
	_detail_win.position = so + (sp - _detail_win.size) / 2
	_detail_win.visible = true

func _refresh_detail() -> void:
	if _selected == "" or not _robots.has(_selected):
		return
	var r = _robots[_selected]
	_detail_win.title = "FunAI 對話 — %s" % str(r.project)
	var col: Color = STATE_COLOR.get(str(r.state), Color.WHITE)
	_detail_header.text = "💬 %s   ·   %s" % [str(r.project), str(r.state)]
	_detail_header.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.3))
	var body := _transcript_log(str(r.get("transcript", "")))
	if body == "":
		body = "[color=#888888](尚無對話記錄)[/color]"
	_detail_text.text = body

func _transcript_log(path: String) -> String:
	# 讀 transcript 尾端（位元組對齊換行，避免 Unicode/NUL 警告），組出最近對話/工具
	if path == "" or not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var flen := f.get_length()
	var start: int = max(0, flen - 200000)
	f.seek(start)
	var bytes := f.get_buffer(flen - start)
	f.close()
	if start > 0:
		var nl := bytes.find(10)
		if nl >= 0:
			bytes = bytes.slice(nl + 1)
	var endnl := bytes.rfind(10)
	if endnl >= 0:
		bytes = bytes.slice(0, endnl + 1)
	var events: Array = []
	for ln in bytes.get_string_from_utf8().split("\n"):
		var s: String = ln.strip_edges()
		if s == "" or not s.begins_with("{"):
			continue
		var j = JSON.parse_string(s)
		if typeof(j) != TYPE_DICTIONARY:
			continue
		var t := str(j.get("type", ""))
		var msg = j.get("message", {})
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		var content = msg.get("content", null)
		if t == "user":
			var up := ""
			if content is String:
				up = content
			elif content is Array:
				for b in content:
					if typeof(b) == TYPE_DICTIONARY and str(b.get("type", "")) == "text":
						up = str(b.get("text", ""))
			if up.strip_edges() != "":
				events.append("[color=#7fb3ff]▌ 你[/color]\n" + _clip(up, 800))
		elif t == "assistant" and content is Array:
			for b in content:
				if typeof(b) != TYPE_DICTIONARY:
					continue
				if str(b.get("type", "")) == "text" and str(b.get("text", "")).strip_edges() != "":
					events.append("[color=#cfcfcf]▌ Claude[/color]\n" + _clip(str(b.get("text", "")), 2000))
				elif str(b.get("type", "")) == "tool_use":
					events.append("[color=#e8b35a]   🔧 " + str(b.get("name", "")) + "[/color]  [color=#9a9a9a]" + _clip(_tool_hint(b.get("input", {})), 100) + "[/color]")
	# 只顯示「最近一次使用者提問」之後（最近一輪 Q&A）
	var last_user := -1
	for i in range(events.size()):
		if str(events[i]).begins_with("[color=#7fb3ff]"):
			last_user = i
	if last_user >= 0:
		events = events.slice(last_user)
	elif events.size() > 12:
		events = events.slice(events.size() - 12)
	return "\n\n".join(events)

func _clip(s: String, n: int) -> String:
	s = s.replace("[", "(").replace("]", ")")   # 避免 BBCode 衝突
	return s if s.length() <= n else s.substr(0, n) + "…"

func _tool_hint(inp) -> String:
	if typeof(inp) != TYPE_DICTIONARY:
		return ""
	for k in ["file_path", "command", "pattern", "query", "path", "url", "description"]:
		if inp.has(k):
			return str(inp[k])
	return ""

func _update_robot(r, delta: float) -> void:
	# 1) 決定目標：idle/done → 休息室休息；其他 → 長桌座位工作
	var resting: bool = r.state == "idle" or r.state == "done"
	if r.state == "waiting":
		r.resting_now = false                       # 等待 → 移到等待區滑手機
		var wt = WAIT_TILES[int(r.seat_idx) % WAIT_TILES.size()]
		r.target = _tile_px(wt[0], wt[1])
	elif resting:
		r.resting_now = false                       # 休息 → 依座位序到固定休息點（不重疊）
		var lt = LOUNGE_TILES[int(r.seat_idx) % LOUNGE_TILES.size()]
		r.target = _tile_px(lt[0], lt[1])
	else:
		r.resting_now = false
		r.target = r.home                           # 回座位工作
	# 2) 路徑規劃：目標變了就重算繞牆路徑
	if r.target != r.last_target:
		r.last_target = r.target
		r.path = _compute_path(r.pos, r.target)
		r.path_i = 0
	# 緊貼路徑點：朝目前路徑點走，到了才換下一個（嚴格沿格子走道，不抄近路）
	var step: Vector2 = r.target
	if r.path_i < r.path.size():
		step = r.path[r.path_i]
		if r.pos.distance_to(step) < 2.0:
			r.path_i += 1
			step = r.path[r.path_i] if r.path_i < r.path.size() else r.target
	# 3) 朝即時目標移動（用最終目標距離判斷是否到達）
	var to: Vector2 = step - r.pos
	if r.pos.distance_to(r.target) > 3.0 and to.length() > 0.5:
		r.pos += to.normalized() * min(WALK_SPEED * delta, to.length())
		r.moving = true
		if abs(to.x) > abs(to.y):
			r.dir = 0 if to.x > 0.0 else 2   # 右 / 左
		else:
			r.dir = 1 if to.y < 0.0 else 3   # 上 / 下
	else:
		r.pos = r.target
		r.moving = false
		# 靜止面向：上排座位朝上、其餘朝下
		r.dir = 1 if (not resting and r.home_facing == "up") else 3
	r.node.position = r.pos
	# 角色在家具之上(1000+)、overlay 之下；角色間仍依腳底 Y 互相排序
	r.node.z_index = 1000 + int(r.pos.y + FRAME_H * SCALE * 0.5)
	# 3) 選角色貼圖 + BOT 列 + 幀
	var ctex = _bot_tex.get(str(r.character), null)
	if ctex != null:
		r.sprite.texture = ctex
	var row := ROW_IDLE
	var frames := 6
	var dir_based := true
	if r.moving:
		row = ROW_WALK                       # 走路（4 向×6）
	elif resting:
		row = ROW_READ                        # 休息看書（12 格正面）
		frames = 12
		dir_based = false
	elif r.state == "waiting":
		row = ROW_PHONE                       # 等待滑手機（12 格正面）
		frames = 12
		dir_based = false
	r.anim_t += delta
	var frame := int(r.anim_t / FRAME_DUR) % frames
	var col: int = (int(r.dir) * 6 + frame) if dir_based else frame
	r.sprite.region_rect = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)

func _scan() -> void:
	var seen := {}
	var dir := DirAccess.open(SESSIONS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				var data = _read_json(SESSIONS_DIR + "/" + fname)
				if data != null and data.has("session"):
					seen[data.session] = true
					_upsert(data)
			fname = dir.get_next()
		dir.list_dir_end()
	# 移除已離場（檔案消失）的角色 → 記入人才庫供重新雇用
	for sid in _robots.keys():
		if not seen.has(sid):
			_record_departed(_robots[sid])
			_robots[sid].node.queue_free()
			_robots.erase(sid)

func _upsert(data: Dictionary) -> void:
	var sid: String = str(data.session)
	var state: String = str(data.get("state", "idle"))
	var now := Time.get_unix_time_from_system()
	var age := now - float(data.get("ts", 0))
	# transcript 修改時間 = 主要活躍訊號（沒有 PreToolUse 心跳，靠這個修正狀態）
	var tp := str(data.get("transcript", ""))
	var t_age := 1.0e9
	if tp != "" and FileAccess.file_exists(tp):
		t_age = now - float(FileAccess.get_modified_time(tp))
	# 殭屍：transcript 很久沒動、事件也舊 → session 已死，移除機器人（記入人才庫）
	if t_age > ZOMBIE_SEC and age > ZOMBIE_SEC:
		if _robots.has(sid):
			_record_departed(_robots[sid])
			_robots[sid].node.queue_free()
			_robots.erase(sid)
		return
	var has_tx := t_age < 1.0e8
	var ref := t_age if has_tx else age   # 沒 transcript 路徑時退而用事件 age
	if t_age < ACTIVE_FRESH:
		state = "working"                # 正在輸出 = 工作中（覆蓋過時的 waiting/thinking）
	elif state == "done":
		if age > DONE_DECAY:
			state = "idle"
	elif state == "waiting":
		if ref > WAIT_DECAY:             # 等太久沒任何動作 → 視為閒置，避免卡死
			state = "idle"
	elif state == "thinking" or state == "working":
		if ref > ACTIVE_IDLE or age > ACTIVE_DECAY:
			state = "idle"
	var character: String = str(data.get("character", "Adam"))
	var project: String = str(data.get("project", "?"))
	var si := _assign_seat(sid)              # 每個 session 配一個座位（繞回循環）
	var seat := _seat_px(si)
	var seat_face: String = SEATS[si].face

	var r
	if _robots.has(sid):
		r = _robots[sid]
	else:
		# 新角色進場（坐在自己工位）
		var node := Node2D.new()
		var spr := Sprite2D.new()
		spr.region_enabled = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(SCALE, SCALE)
		node.add_child(spr)
		var lbl := Label.new()
		lbl.position = Vector2(-16, -FRAME_H * SCALE * 0.5 - 16)   # 角色頭上名牌
		lbl.z_index = 4000        # 名牌永遠在 overlay 之上
		lbl.z_as_relative = false
		lbl.add_theme_font_size_override("font_size", NAMEPLATE_SIZE)
		node.add_child(lbl)
		add_child(node)
		node.position = seat
		r = {
			"node": node, "sprite": spr, "label": lbl, "anim_t": 0.0,
			"pos": seat, "target": seat, "home": seat,
			"moving": false, "dir": 3, "wander_t": 0.0,
			"resting_now": false, "home_facing": seat_face, "seat_idx": si,
			"path": PackedVector2Array(), "path_i": 0, "last_target": Vector2(-9999, -9999),
		}
		_robots[sid] = r

	r.state = state
	r.character = character
	r.home = seat
	r.home_facing = seat_face
	r.seat_idx = si
	r.project = project
	r.tool = str(data.get("tool", ""))
	r.message = str(data.get("message", ""))
	r.transcript = str(data.get("transcript", ""))
	r.cwd = str(data.get("cwd", ""))
	r.hwnd = int(data.get("hwnd", 0))
	_unrecord_departed(r.cwd)   # 回來上班了 → 從人才庫移除
	r.label.text = project
	r.label.add_theme_color_override("font_color", STATE_COLOR.get(state, Color.WHITE))
	r.label.add_theme_stylebox_override("normal", _name_bg())
	r.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var _lf: Font = r.label.get_theme_font("font")
	if _lf != null:
		r.label.position.x = -_lf.get_string_size(project, HORIZONTAL_ALIGNMENT_LEFT, -1, NAMEPLATE_SIZE).x * 0.5 - 2

func _make_pin_button() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var b := Button.new()
	b.text = "釘選"
	b.toggle_mode = true
	b.tooltip_text = "釘選：地圖永遠置頂（再按取消）"
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(48, 26)
	b.position = Vector2(get_window().size.x - 52, 4)
	b.add_theme_font_size_override("font_size", 13)
	b.toggled.connect(_on_pin_toggled)
	cl.add_child(b)
	# 看板開關（看板被關掉後從這裡叫回來）
	var ub := Button.new()
	ub.text = "看板"
	ub.tooltip_text = "顯示/隱藏工作看板"
	ub.focus_mode = Control.FOCUS_NONE
	ub.size = Vector2(48, 26)
	ub.position = Vector2(get_window().size.x - 104, 4)
	ub.add_theme_font_size_override("font_size", 13)
	ub.pressed.connect(_toggle_usage_win)
	cl.add_child(ub)

func _toggle_usage_win() -> void:
	if _usage_win.visible:
		_usage_win.hide()
	else:
		# 重新打開時拉回地圖右側（避免飄到看不到的地方）
		_usage_win.position = get_window().position + Vector2i(get_window().size.x + 8, 0)
		_usage_win.show()
		_refresh_usage()

func _on_pin_toggled(on: bool) -> void:
	get_window().always_on_top = on

# ── 工作看板（獨立視窗：分開釘選、拖曳、拉高、透明背景）──────────
func _build_usage_window() -> void:
	_usage_win = Window.new()
	_usage_win.title = "FunAI 工作看板"
	_usage_win.size = Vector2i(USAGE_W, 380)
	_usage_win.borderless = true       # 無邊框，把手/按鈕都自己畫
	_usage_win.unresizable = true      # OS 縮放關掉，改用底部把手拉高
	_usage_win.transparent_bg = true   # 卡片外全透明
	_usage_win.always_on_top = false
	add_child(_usage_win)
	_usage_win.set_flag(Window.FLAG_TRANSPARENT, true)
	_usage_win.close_requested.connect(func(): _usage_win.hide())
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(m, 6)
	_usage_win.add_child(outer)
	# 半透明圓角卡片
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.10, 0.11, 0.15, 0.86)
	csb.set_corner_radius_all(14)
	csb.set_border_width_all(1)
	csb.border_color = Color(0.26, 0.30, 0.42, 0.9)
	csb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", csb)
	outer.add_child(card)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)
	# 標題列：標題（拖曳）+ 釘選 + 關閉
	var headrow := HBoxContainer.new()
	headrow.add_theme_constant_override("separation", 6)
	vbox.add_child(headrow)
	var title := Label.new()
	title.text = "⚒ 工作看板"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.gui_input.connect(_on_usage_header_drag)
	headrow.add_child(title)
	var pin := Button.new()
	pin.text = "📌"
	pin.toggle_mode = true
	pin.tooltip_text = "釘選看板：永遠置頂（與地圖分開）"
	pin.focus_mode = Control.FOCUS_NONE
	pin.add_theme_font_size_override("font_size", 12)
	pin.toggled.connect(func(on): _usage_win.always_on_top = on)
	headrow.add_child(pin)
	var xbtn := Button.new()
	xbtn.text = "✕"
	xbtn.focus_mode = Control.FOCUS_NONE
	xbtn.add_theme_font_size_override("font_size", 12)
	xbtn.pressed.connect(func(): _usage_win.hide())
	headrow.add_child(xbtn)
	# 內容捲動（拉高視窗 = 一次看到更多卡片）
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_usage_box = VBoxContainer.new()
	_usage_box.add_theme_constant_override("separation", 8)
	_usage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_usage_box)
	# 底部拉高把手
	var grip := Label.new()
	grip.text = "··· 拖此調整高度 ···"
	grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grip.add_theme_font_size_override("font_size", 10)
	grip.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	grip.gui_input.connect(_on_usage_grip)
	vbox.add_child(grip)
	# 預設開在地圖右側
	_usage_win.position = get_window().position + Vector2i(get_window().size.x + 8, 0)
	_usage_win.visible = true

func _on_usage_header_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_usage_dragging = true
		_usage_drag_off = DisplayServer.mouse_get_position() - _usage_win.position

func _on_usage_grip(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_usage_resizing = true

func _refresh_usage() -> void:
	if _usage_box == null:
		return
	var usage = _read_json(USAGE_FILE)
	if usage == null:
		usage = {}
	for c in _usage_box.get_children():
		c.queue_free()
	# 依座位序排在場 session，畫面穩定不跳動
	var sids := _robots.keys()
	sids.sort_custom(func(a, b): return int(_robots[a].seat_idx) < int(_robots[b].seat_idx))
	var t_in := 0; var t_out := 0; var t_cache := 0; var t_turns := 0
	var shown := 0
	for sid in sids:
		var r = _robots[sid]
		var u = usage.get(sid, null)
		var col: Color = STATE_COLOR.get(str(r.state), Color.WHITE)
		_usage_box.add_child(_usage_card(str(sid), str(r.project), col, u))
		shown += 1
		if u != null:
			t_in += int(u.get("in", 0))
			t_out += int(u.get("out", 0))
			t_cache += int(u.get("cache", 0))
			t_turns += int(u.get("turns", 0))
	if shown == 0:
		var empty := Label.new()
		empty.text = "辦公室空無一人…"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
		_usage_box.add_child(empty)
	else:
		# 全公司合計列
		_usage_box.add_child(HSeparator.new())
		var tot := VBoxContainer.new()
		tot.add_theme_constant_override("separation", 1)
		var h := Label.new()
		h.text = "🏢 全公司 · %d 人上工" % shown
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
		tot.add_child(h)
		var l := Label.new()
		l.text = "⚒ 產出 %s   📖 閱讀 %s" % [_fmt_tok(t_out), _fmt_tok(t_in + t_cache)]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		tot.add_child(l)
		var l2 := Label.new()
		l2.text = "🔁 共 %d 回合" % t_turns
		l2.add_theme_font_size_override("font_size", 12)
		l2.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		tot.add_child(l2)
		_usage_box.add_child(tot)
	# 人才庫：離職的 session，一鍵重新雇用（claude -c 接續上次對話）
	if _departed.size() > 0:
		_usage_box.add_child(HSeparator.new())
		var dh := Label.new()
		dh.text = "📋 人才庫 · 點擊重新雇用"
		dh.add_theme_font_size_override("font_size", 12)
		dh.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
		_usage_box.add_child(dh)
		for d in _departed:
			_usage_box.add_child(_rehire_row(d))

func _on_usage_card_input(event: InputEvent, sid: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _robots.has(sid):
			_on_robot_click(sid)   # 與點機器人一致：開/關該 session 對話卡
			_refresh_usage()       # 立即更新卡片高亮

func _usage_card(sid: String, project: String, col: Color, u) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# 被點選的 session 卡片高亮邊框，呼應對話框正在看的對象
	sb.bg_color = Color(0.17, 0.20, 0.28, 1.0) if sid == _selected else Color(0.14, 0.15, 0.20, 1.0)
	if sid == _selected:
		sb.set_border_width_all(1)
		sb.border_color = Color(0.45, 0.6, 0.95, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	# 點卡片 = 跳到對應 session（同點機器人：開/關該 session 的對話卡）
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e): _on_usage_card_input(e, sid))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	# 標題列：狀態色點 + 專案名
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)
	var name := Label.new()
	name.text = project
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name)
	if u != null:
		# LV 徽章：依產出量成長（sqrt 曲線，前期升得快後期慢）
		var lv := 1 + int(sqrt(float(int(u.get("out", 0))) / 10000.0))
		var lvl := Label.new()
		lvl.text = "LV %d" % lv
		lvl.add_theme_font_size_override("font_size", 11)
		lvl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		hb.add_child(lvl)
	vb.add_child(hb)
	if u == null:
		var dash := Label.new()
		dash.text = "統計中…"
		dash.add_theme_font_size_override("font_size", 12)
		dash.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
		vb.add_child(dash)
		return card
	# 負荷量表（context 佔用 → 遊戲字眼）
	var ctx := int(u.get("context_now", 0))
	var frac: float = float(ctx) / CONTEXT_MAX
	var word: String = LOAD_OVER[0]
	var wcol: Color = LOAD_OVER[1]
	for lw in LOAD_WORDS:
		if frac < float(lw[0]):
			word = lw[1]
			wcol = lw[2]
			break
	var clab := Label.new()
	clab.text = "負荷 %d%%  ·  %s" % [int(frac * 100.0), word]
	clab.add_theme_font_size_override("font_size", 11)
	clab.add_theme_color_override("font_color", wcol)
	vb.add_child(clab)
	var pb := ProgressBar.new()
	pb.max_value = CONTEXT_MAX
	pb.value = clamp(float(ctx), 0.0, CONTEXT_MAX)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 1.0)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	# 負荷越高越偏紅
	fill.bg_color = Color(0.35, 0.7, 0.45).lerp(Color(0.9, 0.4, 0.35), clamp(frac, 0.0, 1.0))
	fill.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	vb.add_child(pb)
	# 戰績：產出（out）/ 閱讀（in+cache）/ 回合
	var stats := Label.new()
	stats.text = "⚒ %s   📖 %s   🔁 %d" % [
		_fmt_tok(int(u.get("out", 0))),
		_fmt_tok(int(u.get("in", 0)) + int(u.get("cache", 0))),
		int(u.get("turns", 0)),
	]
	stats.add_theme_font_size_override("font_size", 12)
	stats.add_theme_color_override("font_color", Color(0.68, 0.72, 0.8))
	vb.add_child(stats)
	return card

func _fmt_tok(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)

# ── 人才庫（離職名單 + 重新雇用）────────────────────────────────
func _rehire_row(d: Dictionary) -> Control:
	var btn := Button.new()
	btn.text = "↻ %s" % str(d.get("project", "?"))
	btn.tooltip_text = "重新雇用：在 %s 開新終端、接續上次對話 (claude -c)" % str(d.get("cwd", ""))
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(0.16, 0.22, 0.30, 1.0)
	nsb.set_corner_radius_all(7)
	nsb.set_content_margin_all(7)
	var hsb := nsb.duplicate()
	hsb.bg_color = Color(0.22, 0.32, 0.44, 1.0)
	btn.add_theme_stylebox_override("normal", nsb)
	btn.add_theme_stylebox_override("hover", hsb)
	btn.add_theme_stylebox_override("pressed", nsb)
	btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	var cwd := str(d.get("cwd", ""))
	btn.pressed.connect(func(): _rehire(cwd))
	return btn

func _rehire(cwd: String) -> void:
	# 重新雇用 = 在原資料夾開新 PowerShell、claude -c 接續上次對話
	if cwd == "":
		return
	OS.create_process("cmd.exe", ["/c", "D:\\Work\\FunAI\\app\\launch_claude.cmd", cwd, "-c"])

func _record_departed(r) -> void:
	# 機器人離場（SessionEnd / 殭屍）→ 記入人才庫；同資料夾只留最新一筆
	var cwd := str(r.get("cwd", ""))
	if cwd == "":
		return
	for i in range(_departed.size()):
		if str(_departed[i].get("cwd", "")) == cwd:
			_departed.remove_at(i)
			break
	_departed.insert(0, {"project": str(r.get("project", "?")), "cwd": cwd})
	while _departed.size() > DEPARTED_MAX:
		_departed.pop_back()
	_save_departed()

func _unrecord_departed(cwd: String) -> void:
	# 同資料夾的 session 回來上班了 → 從人才庫移除
	if cwd == "":
		return
	for i in range(_departed.size()):
		if str(_departed[i].get("cwd", "")) == cwd:
			_departed.remove_at(i)
			_save_departed()
			return

func _save_departed() -> void:
	var f := FileAccess.open(DEPARTED_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_departed))
		f.close()

func _load_departed() -> void:
	var f := FileAccess.open(DEPARTED_FILE, FileAccess.READ)
	if f == null:
		return
	var j = JSON.parse_string(f.get_as_text())
	f.close()
	if j is Array:
		_departed = j

func _make_player() -> void:
	var node := Node2D.new()
	var spr := Sprite2D.new()
	spr.region_enabled = true
	spr.texture = _bot_tex.get("BOT1", null)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(SCALE, SCALE)
	node.add_child(spr)
	var lbl := Label.new()
	lbl.text = "你"
	lbl.add_theme_font_size_override("font_size", NAMEPLATE_SIZE)
	lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	lbl.add_theme_stylebox_override("normal", _name_bg())
	lbl.position = Vector2(-7, -FRAME_H * SCALE * 0.5 - 22)
	lbl.z_index = 4000
	lbl.z_as_relative = false
	node.add_child(lbl)
	add_child(node)
	var start := _tile_px(6, 5)   # 通道，保證可走
	node.position = start
	_player = {"node": node, "sprite": spr, "pos": start, "dir": 3, "t": 0.0}

func _update_player(delta: float) -> void:
	if _player.is_empty():
		return
	var v := Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D): v.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A): v.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S): v.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W): v.y -= 1
	var moving: bool = v != Vector2.ZERO
	if moving:
		v = v.normalized()
		var step: Vector2 = v * PLAYER_SPEED * delta
		var p: Vector2 = _player.pos
		if _walkable_px(Vector2(p.x + step.x, p.y)):  # 分軸判斷，可沿牆滑行
			p.x += step.x
		if _walkable_px(Vector2(p.x, p.y + step.y)):
			p.y += step.y
		_player.pos = p
		if abs(v.x) > abs(v.y):
			_player.dir = 0 if v.x > 0 else 2
		else:
			_player.dir = 1 if v.y < 0 else 3
	_player.node.position = _player.pos
	_player.node.z_index = 1000 + int(_player.pos.y + FRAME_H * SCALE * 0.5)
	var row := ROW_WALK if moving else ROW_IDLE
	_player.t += delta
	var frame := int(_player.t / FRAME_DUR) % 6
	_player.sprite.region_rect = Rect2((int(_player.dir) * 6 + frame) * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)

func _walkable_px(pos: Vector2) -> bool:
	if _astar == null:
		return true
	var foot := pos + Vector2(0, FRAME_H * SCALE * 0.25)   # 用腳底判斷格子
	return not _astar.is_point_solid(_world_to_cell(foot))

func _name_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)   # 名字半透明深色底，好讀
	sb.set_content_margin_all(2)
	sb.set_corner_radius_all(2)
	return sb

func _tile_px(col: float, row: float) -> Vector2:
	# 格座標 → 螢幕像素（格中心，已含 4x 縮放）
	return Vector2(col * 16.0 + 8.0, row * 16.0 + 8.0) * SCALE

func _assign_seat(sid: String) -> int:
	if not _project_slots.has(sid):
		_project_slots[sid] = _next_slot
		_next_slot += 1
	return _project_slots[sid] % SEATS.size()

func _seat_px(i: int) -> Vector2:
	var s = SEATS[i]
	var p := _tile_px(s.col, s.row)
	if s.face == "up":
		p.y -= SEAT_UP_DY * 16 * SCALE     # 座位 3、4（正值往上）
	else:
		p.y -= SEAT_DOWN_DY * 16 * SCALE   # 座位 1、2（正值往上）
	return p

func _load_map() -> void:
	# 讀 bake_map.py 烘焙好的 map_baked.json，照圖層渲染整間辦公室
	var f := FileAccess.open(TILED_DIR + "map_baked.json", FileAccess.READ)
	if f == null:
		push_error("找不到 map_baked.json，請先跑 bake_map.py")
		return
	var m = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(m) != TYPE_DICTIONARY:
		return
	var tw := int(m["tilewidth"])
	_map_w = int(m["width"])
	_map_h = int(m["height"])
	get_window().size = Vector2i(int(_map_w * tw * SCALE), int(_map_h * tw * SCALE))
	# 載入 tileset 紋理
	var tsets := []
	for ts in m["tilesets"]:
		var img := Image.load_from_file(TILED_DIR + str(ts["image"]))
		if img != null:
			tsets.append({"firstgid": int(ts["firstgid"]), "columns": int(ts["columns"]),
				"tex": ImageTexture.create_from_image(img)})
	# 逐格畫；地板永遠最底，其餘家具依「列 Y」排序、與角色腳底 Y 比前後
	var li := 0
	for L in m["layers"]:
		var data = L["data"]
		for idx in range(data.size()):
			var gid := int(data[idx])
			if gid <= 0:
				continue
			var col := idx % _map_w
			@warning_ignore("integer_division")
			var row := idx / _map_w
			var ts = _pick_tileset(tsets, gid)
			if ts == null:
				continue
			var local := gid - int(ts["firstgid"])
			var cols := int(ts["columns"])
			@warning_ignore("integer_division")
			var sy := (local / cols) * tw
			var spr := Sprite2D.new()
			spr.texture = ts["tex"]
			spr.region_enabled = true
			spr.region_rect = Rect2((local % cols) * tw, sy, tw, tw)
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(SCALE, SCALE)
			spr.position = Vector2(col * tw, row * tw) * SCALE
			# 無 Y-Sort：家具固定在角色之後，依圖層順序疊（z 0~8）
			spr.z_index = li
			add_child(spr)
		li += 1
	# overlay：使用者標記「永遠畫在角色前面」的層；多層依序疊（後面的更前面）
	var ovls = m.get("overlays", [])
	var ovz := 3000
	for ovl in ovls:
		for idx in range(ovl.size()):
			var gid := int(ovl[idx])
			if gid <= 0:
				continue
			var ts = _pick_tileset(tsets, gid)
			if ts == null:
				continue
			var local := gid - int(ts["firstgid"])
			var cols := int(ts["columns"])
			@warning_ignore("integer_division")
			var sy := (local / cols) * tw
			@warning_ignore("integer_division")
			var row := idx / _map_w
			var spr := Sprite2D.new()
			spr.texture = ts["tex"]
			spr.region_enabled = true
			spr.region_rect = Rect2((local % cols) * tw, sy, tw, tw)
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(SCALE, SCALE)
			spr.position = Vector2((idx % _map_w) * tw, row * tw) * SCALE
			spr.z_index = ovz
			add_child(spr)
		ovz += 1
	# 障礙格用 bake_map.py 算好的 solid（含地板層的牆 + 上層家具）
	var solid := {}
	var sgrid = m.get("solid", [])
	for idx in range(sgrid.size()):
		if int(sgrid[idx]) == 1:
			@warning_ignore("integer_division")
			var row := idx / _map_w
			solid[Vector2i(idx % _map_w, row)] = true
	_build_astar(solid)

func _build_astar(solid: Dictionary) -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, _map_w, _map_h)
	_astar.cell_size = Vector2(16 * SCALE, 16 * SCALE)
	_astar.offset = Vector2(8 * SCALE, 8 * SCALE)   # 對齊格中心
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER   # 只走上下左右，嚴格沿格子走道
	_astar.update()
	for c in solid:
		_astar.set_point_solid(c, true)
	# 座位與休息點一定要可走（否則機器人到不了）
	for s in SEATS:
		_astar.set_point_solid(Vector2i(int(s.col), int(s.row)), false)
	for t in WAIT_TILES:
		_astar.set_point_solid(Vector2i(int(t[0]), int(t[1])), false)
	for t in PASSAGE_TILES:
		_astar.set_point_solid(Vector2i(int(t[0]), int(t[1])), false)

func _world_to_cell(p: Vector2) -> Vector2i:
	var c := Vector2i(int(p.x / (16 * SCALE)), int(p.y / (16 * SCALE)))
	c.x = clampi(c.x, 0, _map_w - 1)
	c.y = clampi(c.y, 0, _map_h - 1)
	return c

func _compute_path(fromp: Vector2, top: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array([top])
	var fc := _world_to_cell(fromp)
	var tc := _world_to_cell(top)
	if _astar.is_point_solid(fc):
		_astar.set_point_solid(fc, false)   # 角色當前格暫時放行，避免起點卡死
	var p := _astar.get_point_path(fc, tc)
	if p.size() == 0:
		return PackedVector2Array([top])
	return p

func _pick_tileset(tsets: Array, gid: int):
	var best = null
	for ts in tsets:
		if int(ts["firstgid"]) <= gid and (best == null or int(ts["firstgid"]) > int(best["firstgid"])):
			best = ts
	return best

func _debug_bot() -> void:
	var img := Image.load_from_file("D:/Work/FunAI/assets/characters/BOT1.png")
	if img == null:
		return
	var tex := ImageTexture.create_from_image(img)
	_bot_strip(tex, 16, 32, 4.0, 40, "16x32")
	_bot_strip(tex, 32, 64, 2.0, 230, "32x64")

func _bot_strip(tex: Texture2D, fw: int, fh: int, sc: float, y: int, tag: String) -> void:
	var lbl := Label.new()
	lbl.text = "%s 幀, 第1列前 10 格" % tag
	lbl.add_theme_color_override("font_color", Color.BLACK)
	lbl.position = Vector2(16, y - 20)
	add_child(lbl)
	for c in range(10):
		var s := Sprite2D.new()
		s.texture = tex
		s.region_enabled = true
		s.region_rect = Rect2(c * fw, 0, fw, fh)
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.scale = Vector2(sc, sc)
		s.position = Vector2(16 + c * 70, y)
		add_child(s)

func _draw_grid() -> void:
	# debug：在每格標 (col,row)，方便讀出座位/休息室座標
	var tw := int(16 * SCALE)
	for row in range(_map_h):
		for col in range(_map_w):
			var lbl := Label.new()
			lbl.text = "%d,%d" % [col, row]
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", Color(1, 1, 0))
			lbl.position = Vector2(col * tw + 2, row * tw + 1)
			lbl.z_index = 4096
			add_child(lbl)

func _placeholder(pos: Vector2, size: Vector2, col: Color, tag: String) -> void:
	var rect := ColorRect.new()
	rect.color = col
	rect.position = pos
	rect.size = size
	rect.z_index = int(pos.y + size.y)
	add_child(rect)
	var lbl := Label.new()
	lbl.text = tag
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.position = pos + Vector2(2, 2)
	lbl.z_index = int(pos.y + size.y) + 1
	add_child(lbl)

func _wall_strip(tex: Texture2D, pos: Vector2, w_tiles: float, h_tiles: float) -> void:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.position = pos
	tr.size = Vector2(w_tiles, h_tiles)
	tr.scale = Vector2(SCALE, SCALE)
	tr.z_index = -999
	add_child(tr)

func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var res = JSON.parse_string(txt)
	return res if res is Dictionary else null

extends Node2D
# Deskbots — Claude Code 桌面機器人辦公室（主迴圈）
# 輪詢 runtime/sessions/*.json → 每個 session 一隻角色，依狀態播動畫、依專案分區。
# 素材從 assets 絕對路徑載入，不需 import。
#
# 模組分工：
#   paths.gd            — 安裝路徑單一出處（整包可搬到任意位置）
#   util.gd             — JSON 讀寫、樣式、格式化等共用小工具
#   office_map.gd       — 地圖載入、A* 走格、座位/休息點地理
#   drag_window.gd      — 無邊框透明卡片視窗共用底座（拖曳/卡片）
#   detail_window.gd    — 對話卡（最近一輪 Q&A、送訊息/指令）
#   usage_board.gd      — 工作看板（負荷/LV/戰績 + 人才庫）
#   settings_window.gd  — 設定卡（置頂/看板開關、離開遊戲）
# 本檔只留：session 掃描與狀態機、角色行為與動畫、玩家、視窗訊號接線。

# BOT 角色表（16×32 幀，方向序 右0 上1 左2 正3；每方向 6 格）
const ROW_IDLE := 1    # 第2列：站著待機（4 向×6）
const ROW_WALK := 2    # 第3列：走路（4 向×6）
const ROW_PHONE := 6   # 第7列：等待滑手機（12 格，正面）
const ROW_READ := 7    # 第8列：休息看書（12 格，正面）
const FRAME_W := 16
const FRAME_H := 32
const SCALE := OfficeMap.SCALE

# 時間衰減（秒）：沒有「中斷」hook，靠 ts 變舊自我修正
const DONE_DECAY := 5.0       # done 顯示一下就回 idle
const ACTIVE_FRESH := 6.0     # transcript 這秒數內有更新 → 正在輸出 = working（主要活躍訊號）
const ACTIVE_IDLE := 120.0    # 沒在輸出超過這秒數 → 回 idle（容忍長回合/長工具空檔）
const ACTIVE_DECAY := 180.0   # 安全網：沒 transcript 路徑時靠事件 ts 退回 idle
const WAIT_DECAY := 180.0     # waiting 超過這秒數沒動作 → 視為閒置（避免卡死在等待）
const ZOMBIE_SEC := 1800.0    # transcript 超過這秒數沒動且事件也舊 → 死掉的 session，隱藏

const NAMEPLATE_SIZE := 13     # 名牌字體大小
const POLL_SEC := 0.4          # 多久掃一次 sessions 資料夾
const FRAME_DUR := 0.14        # 每幀動畫秒數
const WALK_SPEED := 120.0      # 走動速度 px/s
const PLAYER_SPEED := 95.0     # 玩家角色走動速度 px/s
const USAGE_REFRESH := 1.0     # 看板多久刷新一次（秒）
const UI_SAVE_SEC := 2.0       # UI 狀態（視窗位置等）多久檢查一次、有變才寫檔

var _robots := {}            # session_id -> 角色狀態 dict
var _project_slots := {}     # session_id -> 座位 index
var _next_slot := 0
var _poll_t := 0.0
var _shot := false
var _shot_t := 0.0
var _debug_mode := false
var _bot_tex := {}           # 角色名 -> Texture2D（BOT1~BOT9）
var _dragging := false       # 拖曳地圖視窗中
var _drag_off := Vector2i()
var _player := {}            # 玩家可控角色（WASD/方向鍵走動）
var _selected := ""          # 被點選顯示進度的 session
var _detail_t := 0.0         # 對話卡刷新計時
var _usage_t := 0.0          # 看板刷新計時
var _ui_t := 0.0             # UI 狀態儲存計時
var _ui_last := ""           # 上次寫入的 UI 狀態快照（JSON 字串，變了才寫檔）
var _map: OfficeMap
var _detail: DetailWindow
var _board: UsageBoard
var _settings: SettingsWindow
var _file_dialog: FileDialog   # 點空椅 → 選資料夾 → 開新 PowerShell+claude
var _pin_btn: Button           # 右上角釘選鈕（與設定卡的置頂開關同步）


func _ready() -> void:
	# 透明背景（多管齊下，確保 Windows 上生效）
	get_tree().root.transparent_bg = true
	get_window().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	var w := get_window()
	w.borderless = true
	w.always_on_top = false
	_set_app_icon()
	_shot = _has_arg("--shot")
	for i in range(1, 10):   # 載入 BOT1~BOT9（缺檔就略過）
		var nm := "BOT%d" % i
		var p := Paths.CHARACTERS_DIR + ("/%s.png" % nm)
		if not FileAccess.file_exists(p):
			continue
		var img := Image.load_from_file(p)
		if img != null:
			_bot_tex[nm] = ImageTexture.create_from_image(img)
	if _has_arg("--bot"):
		get_window().size = Vector2i(720, 420)
		RenderingServer.set_default_clear_color(Color(0.5, 0.5, 0.5, 1))
		_debug_mode = true
		_debug_bot()
		_shot = true
		return
	_map = OfficeMap.new()
	add_child(_map)
	_map.load_map()
	get_window().size = _map.window_px_size()
	if _has_arg("--grid"):
		_debug_mode = true       # 持續顯示座標格線（不自動關），供讀座位/休息室座標
		_map.draw_grid()
		return
	_make_player()
	_build_windows()
	_make_corner_buttons()
	_restore_ui_state()   # 還原上次的視窗位置/置頂/看板狀態（runtime/ui_state.json）
	_build_file_dialog()
	_scan()   # 立即掃一次
	_board.refresh(_robots, _selected)


static func _has_arg(name: String) -> bool:
	# debug 旗標兩種寫法都認：`godot --path … --shot` 與 `godot --path … -- --shot`
	# （`--` 之後的參數只會出現在 get_cmdline_user_args，不在 get_cmdline_args）
	return OS.get_cmdline_args().has(name) or OS.get_cmdline_user_args().has(name)


func _build_windows() -> void:
	# 三張卡片視窗：對話卡 / 工作看板 / 設定卡。先 add_child 再 build（旗標需要視窗存在）
	_detail = DetailWindow.new()
	add_child(_detail)
	_detail.build()
	_detail.send_requested.connect(_send_to_selected)
	_detail.focus_requested.connect(_focus_selected_terminal)
	_detail.closed.connect(func(): _selected = "")
	_board = UsageBoard.new()
	add_child(_board)
	_board.build()
	_board.card_clicked.connect(_on_board_card)
	_board.rehire_requested.connect(_rehire)
	# 位置與是否顯示由 _restore_ui_state 決定（首次啟動預設開在地圖右側）
	_settings = SettingsWindow.new()
	add_child(_settings)
	_settings.build()
	_settings.pin_toggled.connect(_on_pin_toggled)
	_settings.board_toggle_requested.connect(_toggle_board)
	_settings.quit_requested.connect(func():
		_save_ui_state()   # 離開前把最終視窗狀態寫進 ui_state.json
		get_tree().quit())


func _make_corner_buttons() -> void:
	# 地圖右上角常駐小鈕：設定 / 看板 / 釘選
	var cl := CanvasLayer.new()
	add_child(cl)
	_pin_btn = Button.new()
	_pin_btn.text = "釘選"
	_pin_btn.toggle_mode = true
	_pin_btn.tooltip_text = "釘選：地圖永遠置頂（再按取消）"
	_pin_btn.focus_mode = Control.FOCUS_NONE
	_pin_btn.size = Vector2(48, 26)
	_pin_btn.position = Vector2(get_window().size.x - 52, 4)
	_pin_btn.add_theme_font_size_override("font_size", 13)
	_pin_btn.toggled.connect(_on_pin_toggled)
	cl.add_child(_pin_btn)
	var ub := Button.new()
	ub.text = "看板"
	ub.tooltip_text = "顯示/隱藏工作看板"
	ub.focus_mode = Control.FOCUS_NONE
	ub.size = Vector2(48, 26)
	ub.position = Vector2(get_window().size.x - 104, 4)
	ub.add_theme_font_size_override("font_size", 13)
	ub.pressed.connect(_toggle_board)
	cl.add_child(ub)
	var sb := Button.new()
	sb.text = "設定"
	sb.tooltip_text = "設定：置頂/看板開關、離開遊戲"
	sb.focus_mode = Control.FOCUS_NONE
	sb.size = Vector2(48, 26)
	sb.position = Vector2(get_window().size.x - 156, 4)
	sb.add_theme_font_size_override("font_size", 13)
	sb.pressed.connect(_toggle_settings)
	cl.add_child(sb)


func _process(delta: float) -> void:
	_poll_t += delta
	if not _debug_mode and _poll_t >= POLL_SEC:
		_poll_t = 0.0
		_scan()
	if _shot:
		_shot_t += delta
		if _shot_t > 1.0:
			get_viewport().get_texture().get_image().save_png(Paths.SHOT_FILE)
			if _board != null and _board.visible:   # 看板是獨立視窗，另存一張
				_board.get_texture().get_image().save_png(Paths.SHOT_BOARD_FILE)
			get_tree().quit()
			return
	# 行為（移動）+ 動畫
	for sid in _robots:
		_update_robot(_robots[sid], delta)
	_update_player(delta)
	# 對話卡：開著就定期刷新內容；對象消失就收起來
	if _detail != null:
		if _selected != "" and _robots.has(_selected) and _detail.visible:
			_detail_t -= delta
			if _detail_t <= 0.0:
				_detail_t = 1.0
				_detail.refresh(_robots[_selected])
		elif _detail.visible and (_selected == "" or not _robots.has(_selected)):
			_detail.hide()
	# 工作看板：定期刷新（讀 usage.json / rehire.json）
	if not _debug_mode and _board != null and _board.visible:
		_usage_t -= delta
		if _usage_t <= 0.0:
			_usage_t = USAGE_REFRESH
			_board.refresh(_robots, _selected)
	# UI 狀態：定期檢查、有變才寫檔（拖視窗/開關看板等馬上被記住，崩潰也不丟）
	if not _debug_mode and not _shot and _board != null:
		_ui_t -= delta
		if _ui_t <= 0.0:
			_ui_t = UI_SAVE_SEC
			_save_ui_state()


# ── 輸入：點機器人/空椅/空白，拖曳地圖視窗 ──────────────────────
func _input(event: InputEvent) -> void:
	if _debug_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _robot_at(get_viewport().get_mouse_position())
			if hit != "":
				_on_robot_click(hit)           # 點機器人 = 開/關對話卡
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


func _empty_seat_at(mp: Vector2) -> bool:
	# 點到「沒有機器人佔用的座位」→ 觸發開新 session
	var occupied := {}
	for sid in _robots:
		occupied[int(_robots[sid].seat_idx)] = true
	for i in range(_map.seat_count()):
		if occupied.has(i):
			continue
		var p := _map.seat_px(i)
		if abs(mp.x - p.x) < FRAME_W * SCALE * 0.7 and mp.y > p.y - FRAME_H * SCALE * 0.7 and mp.y < p.y + FRAME_H * SCALE * 0.5:
			return true
	return false


func _on_robot_click(sid: String) -> void:
	# 點機器人 → 開對話卡（最近一輪 Q&A）；再點一次（或點 ✕）關閉
	if sid == _selected and _detail.visible:
		_selected = ""
		_detail.hide()
	else:
		_selected = sid
		_detail.refresh(_robots[sid])
		_detail.open_centered(get_window().current_screen)


func _on_board_card(sid: String) -> void:
	if _robots.has(sid):
		_on_robot_click(sid)                    # 與點機器人一致：開/關該 session 對話卡
		_board.refresh(_robots, _selected)      # 立即更新卡片高亮


# ── 視窗動作（對話卡/看板/設定卡發出的 signal 在這裡落地）────────
func _send_to_selected(text: String) -> void:
	# 聚焦該 session 的終端 → 鍵盤注入文字 + Enter（送訊息或 /clear 等斜線指令）
	if _selected == "" or not _robots.has(_selected) or text == "":
		return
	var hw := int(_robots[_selected].get("hwnd", 0))
	if hw == 0:
		_detail.flash_hint()
		return
	OS.create_process("py", [Paths.APP_DIR + "/winfocus.py", str(hw), "--send", text])


func _focus_selected_terminal() -> void:
	if _selected == "" or not _robots.has(_selected):
		return
	var hw := int(_robots[_selected].get("hwnd", 0))
	if hw == 0:
		_detail.flash_hint()
		return
	OS.create_process("py", [Paths.APP_DIR + "/winfocus.py", str(hw)])
	# 不自動關對話卡：叫出終端後通常還要繼續送訊息／下指令


func _rehire(cwd: String) -> void:
	# 重新雇用 = 在原資料夾開新 PowerShell、claude -c 接續上次對話
	if cwd == "":
		return
	OS.create_process("cmd.exe", ["/c", Paths.ROOT_WIN + "\\app\\launch_claude.cmd", cwd, "-c"])


func _toggle_board() -> void:
	if _board.visible:
		_board.hide()
	else:
		# 沿用上次位置；只有飄到螢幕外才拉回地圖右側
		if not _pos_on_screen(_board.position, _board.size):
			_board.position = get_window().position + Vector2i(get_window().size.x + 8, 0)
		_board.show()
		_board.refresh(_robots, _selected)


func _toggle_settings() -> void:
	if _settings.visible:
		_settings.hide()
	else:
		var pos := get_window().position + (get_window().size - _settings.size) / 2
		_settings.open_at(pos, get_window().always_on_top)


func _on_pin_toggled(on: bool) -> void:
	get_window().always_on_top = on
	# 右上角釘選鈕和設定卡的開關是同一個狀態，兩邊都同步（no_signal 不會迴圈）
	if _pin_btn != null:
		_pin_btn.set_pressed_no_signal(on)
	if _settings != null:
		_settings.set_pin_state(on)


# ── UI 狀態記憶（runtime/ui_state.json）：視窗位置/置頂/看板高度與顯示 ──
func _restore_ui_state() -> void:
	var j = Util.read_json(Paths.UI_STATE_FILE)
	var st: Dictionary = j if j != null else {}
	var w := get_window()
	# 地圖：位置 + 置頂
	var mp: Dictionary = st.get("map", {})
	if mp.has("x"):
		var p := Vector2i(int(mp.get("x", 0)), int(mp.get("y", 0)))
		if _pos_on_screen(p, w.size):
			w.position = p
	if bool(mp.get("pin", false)):
		_on_pin_toggled(true)
	# 看板：位置/高度/置頂/是否顯示（首次啟動：預設開在地圖右側）
	var bd: Dictionary = st.get("board", {})
	var bp := Vector2i(int(bd.get("x", -99999)), int(bd.get("y", 0)))
	if bp.x == -99999 or not _pos_on_screen(bp, _board.size):
		bp = w.position + Vector2i(w.size.x + 8, 0)
	_board.position = bp
	var bh := int(bd.get("h", _board.size.y))
	_board.size = Vector2i(UsageBoard.USAGE_W, clampi(bh, UsageBoard.USAGE_MIN_H, DisplayServer.screen_get_size(w.current_screen).y))
	_board.set_pin_state(bool(bd.get("pin", false)))
	if bool(bd.get("visible", true)):
		_board.show()
	# 對話卡 / 設定卡：記住上次位置，之後開啟原地出現（不再置中）
	var dt: Dictionary = st.get("detail", {})
	if dt.has("x"):
		var dp := Vector2i(int(dt.get("x", 0)), int(dt.get("y", 0)))
		if _pos_on_screen(dp, _detail.size):
			_detail.restore_position(dp)
	var sg: Dictionary = st.get("settings", {})
	if sg.has("x"):
		var sp := Vector2i(int(sg.get("x", 0)), int(sg.get("y", 0)))
		if _pos_on_screen(sp, _settings.size):
			_settings.restore_position(sp)
	# _ui_last 留空 → 啟動後第一次檢查一定寫一次檔（之後有變才寫）


func _ui_snapshot() -> Dictionary:
	var w := get_window()
	var st := {
		"map": {"x": w.position.x, "y": w.position.y, "pin": w.always_on_top},
		"board": {"x": _board.position.x, "y": _board.position.y, "h": _board.size.y,
			"pin": _board.always_on_top, "visible": _board.visible},
	}
	# 對話卡/設定卡只在位置已知後才記（避免存到從未開過的預設原點）
	if _detail.placed:
		st["detail"] = {"x": _detail.position.x, "y": _detail.position.y}
	if _settings.placed:
		st["settings"] = {"x": _settings.position.x, "y": _settings.position.y}
	return st


func _save_ui_state() -> void:
	var snap := _ui_snapshot()
	var s := JSON.stringify(snap)
	if s == _ui_last:
		return
	_ui_last = s
	Util.write_json(Paths.UI_STATE_FILE, snap)


func _pos_on_screen(p: Vector2i, sz: Vector2i) -> bool:
	# 記下的位置必須仍落在任一螢幕上（螢幕配置可能變），否則不用
	for i in DisplayServer.get_screen_count():
		var r := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		if r.intersection(Rect2i(p, sz)).has_area():
			return true
	return false


func _notification(what: int) -> void:
	# Alt+F4 等 OS 關閉路徑也把最終狀態寫進去（平常每 2s 已存，這是保險）
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _board != null and not _shot:
		_save_ui_state()


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
	OS.create_process("cmd.exe", ["/c", Paths.ROOT_WIN + "\\app\\launch_claude.cmd", path])


func _set_app_icon() -> void:
	# 視窗 / 工作列圖示用 Deskbots LOGO（素材在 res:// 外，走絕對路徑載入）
	var img := Image.load_from_file(Paths.ICON_FILE)
	if img != null:
		DisplayServer.set_icon(img)


# ── session 掃描與狀態機 ─────────────────────────────────────────
func _scan() -> void:
	var seen := {}
	var dir := DirAccess.open(Paths.SESSIONS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				var data = Util.read_json(Paths.SESSIONS_DIR + "/" + fname)
				if data != null and data.has("session"):
					seen[data.session] = true
					_upsert(data)
			fname = dir.get_next()
		dir.list_dir_end()
	# 移除已離場（檔案消失）的角色
	for sid in _robots.keys():
		if not seen.has(sid):
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
	# 殭屍：transcript 很久沒動、事件也舊 → session 已死，移除機器人
	if t_age > ZOMBIE_SEC and age > ZOMBIE_SEC:
		if _robots.has(sid):
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
	var seat := _map.seat_px(si)
	var seat_face := _map.seat_face(si)

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
	r.label.text = project
	r.label.add_theme_color_override("font_color", Util.STATE_COLOR.get(state, Color.WHITE))
	r.label.add_theme_stylebox_override("normal", Util.name_bg())
	r.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var _lf: Font = r.label.get_theme_font("font")
	if _lf != null:
		r.label.position.x = -_lf.get_string_size(project, HORIZONTAL_ALIGNMENT_LEFT, -1, NAMEPLATE_SIZE).x * 0.5 - 2


func _assign_seat(sid: String) -> int:
	if not _project_slots.has(sid):
		_project_slots[sid] = _next_slot
		_next_slot += 1
	return _project_slots[sid] % _map.seat_count()


# ── 角色行為與動畫 ───────────────────────────────────────────────
func _update_robot(r, delta: float) -> void:
	# 1) 決定目標：idle/done → 休息室休息；其他 → 長桌座位工作
	var resting: bool = r.state == "idle" or r.state == "done"
	if r.state == "waiting":
		r.resting_now = false                       # 等待 → 移到等待區滑手機
		r.target = _map.wait_px(int(r.seat_idx))
	elif resting:
		r.resting_now = false                       # 休息 → 依座位序到固定休息點（不重疊）
		r.target = _map.lounge_px(int(r.seat_idx))
	else:
		r.resting_now = false
		r.target = r.home                           # 回座位工作
	# 2) 路徑規劃：目標變了就重算繞牆路徑
	if r.target != r.last_target:
		r.last_target = r.target
		r.path = _map.compute_path(r.pos, r.target)
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
	# 4) 選角色貼圖 + BOT 列 + 幀
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


# ── 玩家角色（WASD/方向鍵走動）──────────────────────────────────
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
	lbl.add_theme_stylebox_override("normal", Util.name_bg())
	lbl.position = Vector2(-7, -FRAME_H * SCALE * 0.5 - 22)
	lbl.z_index = 4000
	lbl.z_as_relative = false
	node.add_child(lbl)
	add_child(node)
	var start := _map.tile_px(6, 5)   # 通道，保證可走
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
	var foot := pos + Vector2(0, FRAME_H * SCALE * 0.25)   # 用腳底判斷格子
	return _map.is_walkable(foot)


# ── debug：--bot 看角色表 ────────────────────────────────────────
func _debug_bot() -> void:
	var img := Image.load_from_file(Paths.CHARACTERS_DIR + "/BOT1.png")
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

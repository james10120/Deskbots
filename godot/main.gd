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
#   usage_board.gd      — 工作看板（負荷/LV/戰績 + 人才庫 + 卡片快速指令）
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
# 趣味性：想法泡泡 / 事件反應 / 摸頭轉圈 / 日夜光線
const BUBBLE_SHOW := 3.0       # 一則想法泡泡顯示秒數
const BUBBLE_GAP_MIN := 9.0    # 兩則想法泡泡的最短間隔
const BUBBLE_GAP_MAX := 18.0   # 最長間隔
const SPIN_DUR := 0.45         # 摸頭轉一圈的秒數
const DAYNIGHT_SEC := 30.0     # 多久更新一次日夜色調

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
var _selected := ""          # 最近一次互動（聚焦/送指令）的 session，看板用來高亮
var _usage_t := 0.0          # 看板刷新計時
var _ui_t := 0.0             # UI 狀態儲存計時
var _last_hover := ""        # 上一幀滑鼠停在哪隻機器人（摸頭反應用，只在進入時觸發）
var _daynight: CanvasModulate # 日夜色調（依真實時鐘 modulate 整個地圖）
var _daynight_t := 0.0       # 日夜更新計時
var _ui_last := ""           # 上次寫入的 UI 狀態快照（JSON 字串，變了才寫檔）
var _map: OfficeMap
var _board: UsageBoard
var _settings: SettingsWindow
var _file_dialog: FileDialog   # 點空椅 → 選資料夾 → 開新 PowerShell+claude
var _pin_btn: Button           # 右上角釘選鈕（與設定卡的置頂開關同步）
var _board_btn: Button         # 右上角「看板」鈕（換語言時更新文字）
var _settings_btn: Button      # 右上角「設定」鈕
var _hook_hint: Label          # hook 未安裝時的畫面提示（有 session 就自動隱藏）
var _hooks_ok := true          # 啟動時偵測：~/.claude/settings.json 是否含本工具的 hook
var _managed := false          # 被 run_deskbots.ps1 託管（外部已裝 hook/起背景）→ 不自管生命週期
var _bg_pids: Array = []       # 自管模式啟動的背景行程（usage_poll / ssh_bridge）


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
	for i in range(1, 10):   # 角色來源優先序：外部 PNG > 內嵌加密包 > 程式生成備援
		var nm := "BOT%d" % i
		var p := Paths.CHARACTERS_DIR + ("/%s.png" % nm)
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img != null:
				_bot_tex[nm] = ImageTexture.create_from_image(img)
		if not _bot_tex.has(nm):
			var im = AssetStore.image("characters/%s.png" % nm)
			if im != null:
				_bot_tex[nm] = ImageTexture.create_from_image(im)
		if not _bot_tex.has(nm):
			_bot_tex[nm] = FallbackArt.bot_sheet(i)
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
	_load_locale()   # 建任何 UI 前先定語言（讀 ui_state.json 的 lang；首次依 OS 語系）
	# 日夜光線：CanvasModulate 只染預設層（地圖/角色），不影響 CanvasLayer 上的鈕/提示
	_daynight = CanvasModulate.new()
	_daynight.color = _daynight_tint(Time.get_time_dict_from_system().hour)
	add_child(_daynight)
	_make_player()
	_build_windows()
	_make_corner_buttons()
	# 直接雙擊 exe（非託管、非截圖）→ 自己管理生命週期：裝 hook、起背景、退出還原
	_managed = _has_arg("--managed")
	if not _shot and not _managed:
		get_tree().set_auto_accept_quit(false)   # 攔截關閉 → 先還原再退出
		_bootstrap()
	_make_hook_hint()     # hook 未安裝 → 畫面提示（_bootstrap 後通常已裝好）
	_restore_ui_state()   # 還原上次的視窗位置/置頂/看板狀態（runtime/ui_state.json）
	_build_file_dialog()
	_scan()   # 立即掃一次
	_board.refresh(_robots, _selected)


static func _has_arg(name: String) -> bool:
	# debug 旗標兩種寫法都認：`godot --path … --shot` 與 `godot --path … -- --shot`
	# （`--` 之後的參數只會出現在 get_cmdline_user_args，不在 get_cmdline_args）
	return OS.get_cmdline_args().has(name) or OS.get_cmdline_user_args().has(name)


func _build_windows() -> void:
	# 兩張卡片視窗：工作看板 / 設定卡。先 add_child 再 build（旗標需要視窗存在）
	_board = UsageBoard.new()
	add_child(_board)
	_board.build()
	_board.focus_requested.connect(_focus_terminal)        # 點卡片本體 → 聚焦該終端（遠端開 VS Code）
	_board.command_requested.connect(_send_command)        # 卡片快速指令鈕 → 注入該終端
	_board.rehire_requested.connect(_rehire)
	# 位置與是否顯示由 _restore_ui_state 決定（首次啟動預設開在地圖右側）
	_settings = SettingsWindow.new()
	add_child(_settings)
	_settings.build()
	_settings.pin_toggled.connect(_on_pin_toggled)
	_settings.board_toggle_requested.connect(_toggle_board)
	_settings.add_server_requested.connect(_add_server)
	_settings.vscode_requested.connect(_open_vscode)
	_settings.remove_server_requested.connect(_remove_server)
	_settings.lang_change_requested.connect(_apply_lang)
	_settings.quit_requested.connect(_quit)


func _make_hook_hint() -> void:
	# 偵測 hook 是否已裝進 ~/.claude/settings.json；沒裝就在畫面中央給明確指引。
	_hooks_ok = _hook_installed()
	var cl := CanvasLayer.new()
	add_child(cl)
	_hook_hint = Label.new()
	_hook_hint.text = Lang.t("hook_hint")
	_hook_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hook_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hook_hint.add_theme_font_size_override("font_size", 15)
	_hook_hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.07, 0.86)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.8, 0.6, 0.3, 0.7)
	_hook_hint.add_theme_stylebox_override("normal", sb)
	var hint_size := Vector2(380, 130)
	_hook_hint.size = hint_size
	_hook_hint.position = (Vector2(get_window().size) - hint_size) * 0.5
	_hook_hint.visible = not _hooks_ok
	cl.add_child(_hook_hint)


func _hook_installed() -> bool:
	# 讀全域 settings.json，看 hooks 裡有沒有任一 command 指向 emit.py（不限安裝位置）
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	if home == "":
		return true   # 拿不到家目錄就不誤報
	var j = Util.read_json(home + "/.claude/settings.json")
	if typeof(j) != TYPE_DICTIONARY:
		return false
	var hooks = j.get("hooks", {})
	if typeof(hooks) != TYPE_DICTIONARY:
		return false
	for ev in hooks:
		if typeof(hooks[ev]) != TYPE_ARRAY:
			continue
		for grp in hooks[ev]:
			if typeof(grp) != TYPE_DICTIONARY:
				continue
			for h in grp.get("hooks", []):
				if typeof(h) == TYPE_DICTIONARY and str(h.get("command", "")).contains("emit.py"):
					return true
	return false


func _make_corner_buttons() -> void:
	# 地圖右上角常駐小鈕：設定 / 看板 / 釘選
	var cl := CanvasLayer.new()
	add_child(cl)
	_pin_btn = Button.new()
	_pin_btn.text = Lang.t("c_pin")
	_pin_btn.toggle_mode = true
	_pin_btn.tooltip_text = Lang.t("c_pin_tip")
	_pin_btn.focus_mode = Control.FOCUS_NONE
	_pin_btn.size = Vector2(48, 26)
	_pin_btn.position = Vector2(get_window().size.x - 52, 4)
	_pin_btn.add_theme_font_size_override("font_size", 13)
	_pin_btn.toggled.connect(_on_pin_toggled)
	cl.add_child(_pin_btn)
	_board_btn = Button.new()
	_board_btn.text = Lang.t("c_board")
	_board_btn.tooltip_text = Lang.t("c_board_tip")
	_board_btn.focus_mode = Control.FOCUS_NONE
	_board_btn.size = Vector2(48, 26)
	_board_btn.position = Vector2(get_window().size.x - 104, 4)
	_board_btn.add_theme_font_size_override("font_size", 13)
	_board_btn.pressed.connect(_toggle_board)
	cl.add_child(_board_btn)
	_settings_btn = Button.new()
	_settings_btn.text = Lang.t("c_settings")
	_settings_btn.tooltip_text = Lang.t("c_settings_tip")
	_settings_btn.focus_mode = Control.FOCUS_NONE
	_settings_btn.size = Vector2(48, 26)
	_settings_btn.position = Vector2(get_window().size.x - 156, 4)
	_settings_btn.add_theme_font_size_override("font_size", 13)
	_settings_btn.pressed.connect(_toggle_settings)
	cl.add_child(_settings_btn)


func _process(delta: float) -> void:
	_poll_t += delta
	if not _debug_mode and _poll_t >= POLL_SEC:
		_poll_t = 0.0
		_scan()
	# hook 未安裝的提示：一旦有機器人（hook 顯然有效）就收起來
	if _hook_hint != null:
		_hook_hint.visible = not _hooks_ok and _robots.is_empty()
	if _shot:
		_shot_t += delta
		if _shot_t > 1.0:
			get_viewport().get_texture().get_image().save_png(Paths.SHOT_FILE)
			if _board != null and _board.visible:   # 看板是獨立視窗，另存一張
				_board.get_texture().get_image().save_png(Paths.SHOT_BOARD_FILE)
			if _settings != null and _settings.visible:   # 設定卡開著也存一張
				_settings.get_texture().get_image().save_png(Paths.ROOT + "/runtime/_shot_settings.png")
			get_tree().quit()
			return
	# 行為（移動）+ 動畫
	for sid in _robots:
		_update_robot(_robots[sid], delta)
	_update_player(delta)
	# 摸頭反應：滑鼠移到某機器人上（進入時觸發一次）→ 冒愛心 + 轉一圈
	if not _debug_mode and not _shot:
		var hov := _robot_at(get_viewport().get_mouse_position())
		if hov != "" and hov != _last_hover and _robots.has(hov):
			_set_bubble(_robots[hov], "💗", 1.4)
			_robots[hov].spin_t = SPIN_DUR
		_last_hover = hov
		# 日夜光線：依真實時鐘調整地圖色調
		_daynight_t -= delta
		if _daynight_t <= 0.0:
			_daynight_t = DAYNIGHT_SEC
			if _daynight != null:
				_daynight.color = _daynight_tint(Time.get_time_dict_from_system().hour)
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
				_focus_terminal(hit)           # 點機器人 = 聚焦該 session 終端（遠端開 VS Code）
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


# ── 視窗動作（看板/設定卡發出的 signal 在這裡落地）──────────────
func _focus_terminal(sid: String) -> void:
	# 點機器人或看板卡片本體 → 把該 session 的終端叫到最前；遠端改開 VS Code Remote
	if not _robots.has(sid):
		return
	_selected = sid
	var r = _robots[sid]
	var host := str(r.get("host", ""))
	if host != "":
		# 遠端 session：開 VS Code Remote-SSH 到該機該資料夾（code 是 .cmd shim，要走 cmd /c）
		OS.create_process("cmd.exe", ["/c", "code", "--remote", "ssh-remote+" + host, str(r.get("cwd", ""))])
	else:
		var hw := int(r.get("hwnd", 0))
		if hw != 0:
			OS.create_process("py", [Paths.APP_DIR + "/winfocus.py", str(hw)])
		# hwnd=0 時看板卡片已顯示「抓不到終端」提示，這裡不做事
	if _board != null and _board.visible:
		_board.refresh(_robots, _selected)      # 立即更新卡片高亮


func _send_command(sid: String, text: String) -> void:
	# 卡片快速指令鈕 → 聚焦該 session 終端 → 鍵盤注入文字 + Enter（/clear /compact；<ESC> 只送 ESC）
	if not _robots.has(sid) or text == "":
		return
	_selected = sid
	var hw := int(_robots[sid].get("hwnd", 0))
	if hw == 0:
		return
	OS.create_process("py", [Paths.APP_DIR + "/winfocus.py", str(hw), "--send", text])
	if _board != null and _board.visible:
		_board.refresh(_robots, _selected)


func _rehire(cwd: String, host: String) -> void:
	if cwd == "":
		return
	if host != "":
		# 遠端專案：開 VS Code Remote-SSH 直達該機該資料夾（在裡面開終端跑 claude）
		OS.create_process("cmd.exe", ["/c", "code", "--remote", "ssh-remote+" + host, cwd])
		return
	# 本地專案：重新雇用 = 在原資料夾開新 PowerShell、claude -c 接續上次對話
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


func _add_server(host: String, label: String) -> void:
	# 開新終端視窗跑首次設定（金鑰/密碼互動在那邊完成）；bridge 熱載入，裝完機器人自動出現
	OS.create_process("cmd.exe", ["/c", Paths.ROOT_WIN + "\\app\\add_server.cmd", host, label])


func _open_vscode(host: String) -> void:
	# code 是 .cmd shim，要經 cmd /c；不帶資料夾 = 開該機的 VS Code Remote 視窗
	OS.create_process("cmd.exe", ["/c", "code", "--remote", "ssh-remote+" + host])


func _remove_server(host: String) -> void:
	# 從 servers.json 拿掉這台；bridge 熱載入後會斷線、清掉該台的鏡像（機器人離場）
	var servers = Util.read_json_any(Paths.SERVERS_FILE)
	if not (servers is Array):
		return
	var keep := []
	for sv in servers:
		if typeof(sv) != TYPE_DICTIONARY or str(sv.get("host", "")) != host:
			keep.append(sv)
	Util.write_json(Paths.SERVERS_FILE, keep)


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
	# 設定卡：記住上次位置，之後開啟原地出現（不再置中）
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
	# 設定卡只在位置已知後才記（避免存到從未開過的預設原點）
	if _settings.placed:
		st["settings"] = {"x": _settings.position.x, "y": _settings.position.y}
	st["lang"] = Lang.locale
	return st


# ── 介面語言（zh/en）─────────────────────────────────────────────
func _load_locale() -> void:
	# 建任何 UI 前呼叫：有存檔用存檔，否則依 OS 語系猜一次
	var j = Util.read_json(Paths.UI_STATE_FILE)
	var st: Dictionary = j if j != null else {}
	var loc := str(st.get("lang", ""))
	Lang.set_locale(loc if loc != "" else Lang.detect())


func _apply_lang(loc: String) -> void:
	if Lang.locale == loc:
		return
	Lang.set_locale(loc)
	# 各視窗靜態文字即時換；動態內容（卡片/伺服器列）由各自 relocalize/刷新跟上
	if _board != null:
		_board.relocalize()
	if _settings != null:
		_settings.relocalize()
	_relabel_chrome()
	_save_ui_state()   # 立刻把語言寫進 ui_state.json


func _relabel_chrome() -> void:
	# 右上角小鈕 / hook 提示 / 選資料夾對話框 / 玩家名牌
	if _pin_btn != null:
		_pin_btn.text = Lang.t("c_pin")
		_pin_btn.tooltip_text = Lang.t("c_pin_tip")
	if _board_btn != null:
		_board_btn.text = Lang.t("c_board")
		_board_btn.tooltip_text = Lang.t("c_board_tip")
	if _settings_btn != null:
		_settings_btn.text = Lang.t("c_settings")
		_settings_btn.tooltip_text = Lang.t("c_settings_tip")
	if _hook_hint != null:
		_hook_hint.text = Lang.t("hook_hint")
	if _file_dialog != null:
		_file_dialog.title = Lang.t("filedialog_title")
	if _player.has("label"):
		_player.label.text = Lang.t("player_name")


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
	# 視窗關閉鈕 / Alt+F4 → 走統一退出流程（存狀態 + 自管模式還原環境）
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _board != null and not _shot:
		_quit()


# ── 自管生命週期（直接雙擊 Deskbots.exe）──────────────────────────
func _bootstrap() -> void:
	# 裝 hook（同步，要在使用者開 session 前完成）+ 清殭屍 + 起背景輪詢
	OS.execute("py", [Paths.APP_DIR + "/apply_settings.py"], [])
	OS.execute("py", [Paths.APP_DIR + "/clean_sessions.py"], [])
	for script in ["usage_poll.py", "ssh_bridge.py"]:
		var pid := OS.create_process("py", [Paths.APP_DIR + "/" + script])
		if pid > 0:
			_bg_pids.append(pid)
	_hooks_ok = true   # 剛裝好，畫面不顯示「未安裝」提示


func _quit() -> void:
	_save_ui_state()
	# 停背景行程（py.exe 會生 python 子行程，taskkill /T 連子帶孫清乾淨）
	for pid in _bg_pids:
		OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"])
	_bg_pids.clear()
	if not _managed:
		# 還原全域設定 + 清自己的 runtime 暫存（與 run_deskbots.ps1 的 finally 一致）
		OS.execute("py", [Paths.APP_DIR + "/apply_settings.py", "--remove"], [])
		var d := DirAccess.open(Paths.SESSIONS_DIR)
		if d != null:
			d.list_dir_begin()
			var f := d.get_next()
			while f != "":
				if f.ends_with(".json"):
					d.remove(Paths.SESSIONS_DIR + "/" + f)
				f = d.get_next()
		DirAccess.remove_absolute(Paths.USAGE_FILE)
	get_tree().quit()


func _build_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = Lang.t("filedialog_title")
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
			if sid == _selected:
				_selected = ""   # 高亮對象離場 → 清掉，免得看板留著對不上的高亮


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
		# 想法泡泡（名牌上方，平時藏著）
		var bub := Label.new()
		bub.position = Vector2(0, -FRAME_H * SCALE * 0.5 - 32)
		bub.z_index = 4001
		bub.z_as_relative = false
		bub.add_theme_font_size_override("font_size", NAMEPLATE_SIZE)
		bub.add_theme_color_override("font_color", Color(1.0, 0.98, 0.85))
		bub.add_theme_stylebox_override("normal", Util.name_bg())
		bub.visible = false
		node.add_child(bub)
		add_child(node)
		node.position = seat
		r = {
			"node": node, "sprite": spr, "label": lbl, "anim_t": 0.0,
			"pos": seat, "target": seat, "home": seat,
			"moving": false, "dir": 3, "wander_t": 0.0,
			"resting_now": false, "home_facing": seat_face, "seat_idx": si,
			"path": PackedVector2Array(), "path_i": 0, "last_target": Vector2(-9999, -9999),
			"bubble": bub, "bubble_t": 0.0, "bubble_next": randf_range(BUBBLE_GAP_MIN, BUBBLE_GAP_MAX), "spin_t": 0.0,
		}
		_robots[sid] = r

	# 事件小反應：狀態切換時冒個 emoji（done 讚、error 汗、waiting 驚嘆）
	var prev_state: String = str(r.get("state", ""))
	if state != prev_state and r.has("bubble"):
		if state == "done":
			_set_bubble(r, "👍", 1.8)
		elif state == "error":
			_set_bubble(r, "💧", 1.8)
		elif state == "waiting":
			_set_bubble(r, "❗", 2.0)
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
	r.host = str(data.get("host", ""))   # 非空 = SSH 遠端 session（ssh_bridge 鏡像）
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
	_update_bubble(r, delta)
	# 摸頭轉一圈
	if float(r.get("spin_t", 0.0)) > 0.0:
		r.spin_t = float(r.spin_t) - delta
		r.sprite.rotation = (1.0 - clampf(float(r.spin_t) / SPIN_DUR, 0.0, 1.0)) * TAU
		if float(r.spin_t) <= 0.0:
			r.sprite.rotation = 0.0


func _update_bubble(r, delta: float) -> void:
	# 想法泡泡：顯示中倒數收起；沒在顯示就等下一則、依當下狀態挑句
	var bub = r.get("bubble")
	if bub == null:
		return
	if float(r.bubble_t) > 0.0:
		r.bubble_t = float(r.bubble_t) - delta
		if float(r.bubble_t) <= 0.0:
			bub.visible = false
		return
	r.bubble_next = float(r.bubble_next) - delta
	if float(r.bubble_next) <= 0.0:
		r.bubble_next = randf_range(BUBBLE_GAP_MIN, BUBBLE_GAP_MAX)
		_set_bubble(r, Lang.bubble(str(r.state)), BUBBLE_SHOW)


func _set_bubble(r, text: String, dur: float) -> void:
	var bub = r.get("bubble")
	if bub == null or text == "":
		return
	bub.text = text
	bub.visible = true
	r.bubble_t = dur
	# 約略置中於頭頂
	var f: Font = bub.get_theme_font("font")
	if f != null:
		bub.position.x = -f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAMEPLATE_SIZE).x * 0.5


func _daynight_tint(hour: int) -> Color:
	# 依真實時鐘給地圖色調（純 modulate 濾鏡，零素材）
	if hour >= 22 or hour < 6:
		return Color(0.55, 0.60, 0.85)   # 深夜：冷藍偏暗
	elif hour < 9:
		return Color(1.0, 0.92, 0.82)    # 清晨：微暖
	elif hour < 17:
		return Color(1.0, 1.0, 1.0)      # 白天：正常
	elif hour < 20:
		return Color(1.0, 0.84, 0.66)    # 傍晚：橘調
	return Color(0.78, 0.74, 0.90)       # 入夜：紫藍


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
	lbl.text = Lang.t("player_name")
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
	_player = {"node": node, "sprite": spr, "label": lbl, "pos": start, "dir": 3, "t": 0.0}


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

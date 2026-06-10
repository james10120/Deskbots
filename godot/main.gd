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
const TILED_DIR := "D:/Work/FunAI/assets/tiled/"

# 時間衰減（秒）：沒有「中斷」hook，靠 ts 變舊自我修正
const DONE_DECAY := 4.0      # done 顯示一下就回 idle
const ACTIVE_IDLE := 15.0    # thinking/working：transcript 超過這秒數沒更新 → 判定中斷/結束 → idle
const ACTIVE_DECAY := 120.0  # 安全網：沒有 transcript 路徑時，靠事件 ts 變舊退回 idle

const FRAME_W := 16
const FRAME_H := 32
const SCALE := 1.5
const POLL_SEC := 0.4          # 多久掃一次 sessions 資料夾
const FRAME_DUR := 0.14        # 每幀動畫秒數
const WALK_SPEED := 120.0      # 走動速度 px/s

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
# 休息點（座位序對應；前 4 個=左休息室，後 4 個=右休息室）
const LOUNGE_TILES := [[4, 6], [2, 8], [3, 3], [4, 3], [29, 6], [27, 8], [28, 3], [29, 3]]
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
var _selected := ""           # 被點選顯示進度的 session
var _detail_win: Window       # 大型進度視窗（獨立 OS 視窗）
var _detail_text: RichTextLabel
var _detail_input: LineEdit
var _detail_t := 0.0          # 刷新計時

func _input(event: InputEvent) -> void:
	# 左鍵：點機器人→顯示進度氣泡；點空白→拖曳整個視窗
	if _debug_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _robot_at(get_viewport().get_mouse_position())
			if hit != "":
				if hit == _selected and _detail_win.visible:
					_selected = ""
					_detail_win.hide()         # 再點同一隻 = 關閉
				else:
					_open_detail(hit)          # 點機器人 = 開獨立大視窗
				_dragging = false
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
		if abs(mp.x - p.x) < 14.0 and mp.y > p.y - 28.0 and mp.y < p.y + 26.0:
			return sid
	return ""

func _ready() -> void:
	# 透明背景（多管齊下，確保 Windows 上生效）
	get_tree().root.transparent_bg = true
	get_window().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	var w := get_window()
	w.borderless = true
	w.always_on_top = true
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
	_scan()   # 立即掃一次

func _process(delta: float) -> void:
	_poll_t += delta
	if not _debug_mode and _poll_t >= POLL_SEC:
		_poll_t = 0.0
		_scan()
	if _shot:
		_shot_t += delta
		if _shot_t > 1.0:
			get_viewport().get_texture().get_image().save_png("D:/Work/FunAI/runtime/_shot.png")
			get_tree().quit()
			return
	# 行為（移動）+ 動畫
	for sid in _robots:
		_update_robot(_robots[sid], delta)
	# 大型進度視窗：開著就定期刷新內容
	if _selected != "" and _robots.has(_selected) and _detail_win.visible:
		_detail_t -= delta
		if _detail_t <= 0.0:
			_detail_t = 1.0
			_refresh_detail()
	elif _detail_win.visible and (_selected == "" or not _robots.has(_selected)):
		_detail_win.hide()

func _build_detail_window() -> void:
	_detail_win = Window.new()
	_detail_win.title = "FunAI 進度"
	_detail_win.size = Vector2i(560, 600)
	_detail_win.visible = false
	add_child(_detail_win)
	_detail_win.close_requested.connect(_on_detail_close)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.13, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_win.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	_detail_win.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_detail_text = RichTextLabel.new()
	_detail_text.bbcode_enabled = true
	_detail_text.scroll_active = true
	_detail_text.scroll_following = true
	_detail_text.selection_enabled = true
	_detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_text.add_theme_font_size_override("normal_font_size", 15)
	vbox.add_child(_detail_text)
	var row := HBoxContainer.new()
	vbox.add_child(row)
	_detail_input = LineEdit.new()
	_detail_input.placeholder_text = "輸入指令送給這個 session（Enter 送出，實驗性）…"
	_detail_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_input.text_submitted.connect(_on_reply_submitted)
	row.add_child(_detail_input)
	var btn := Button.new()
	btn.text = "送出"
	btn.pressed.connect(_on_send_pressed)
	row.add_child(btn)

func _on_detail_close() -> void:
	_selected = ""
	_detail_win.hide()

func _open_detail(sid: String) -> void:
	_selected = sid
	_refresh_detail()
	# 置中於螢幕
	var scr := get_window().current_screen
	var sp := DisplayServer.screen_get_size(scr)
	var so := DisplayServer.screen_get_position(scr)
	_detail_win.position = so + (sp - _detail_win.size) / 2
	_detail_win.visible = true
	_detail_input.grab_focus()

func _on_send_pressed() -> void:
	_on_reply_submitted(_detail_input.text)

func _on_reply_submitted(text: String) -> void:
	text = text.strip_edges()
	if text == "" or _selected == "" or not _robots.has(_selected):
		return
	var cwd := str(_robots[_selected].get("cwd", ""))
	var safe := text.replace("\"", "'")
	var cmd := "claude --resume %s -p \"%s\"" % [_selected, safe]   # 接續該 session 跑一回合
	if cwd != "":
		cmd = "cd /d \"%s\" && %s" % [cwd, cmd]
	OS.create_process("cmd.exe", ["/c", cmd])
	_detail_input.clear()
	_detail_text.text += "\n\n[color=#88ccff]👤 你（送出）：[/color] " + _clip(text, 240)

func _refresh_detail() -> void:
	if _selected == "" or not _robots.has(_selected):
		return
	var r = _robots[_selected]
	_detail_win.title = "%s — %s" % [str(r.project), str(r.state)]
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
				events.append("[color=#88ccff]👤 你：[/color] " + _clip(up, 800))
		elif t == "assistant" and content is Array:
			for b in content:
				if typeof(b) != TYPE_DICTIONARY:
					continue
				if str(b.get("type", "")) == "text" and str(b.get("text", "")).strip_edges() != "":
					events.append("[color=#dddddd]🤖[/color] " + _clip(str(b.get("text", "")), 2000))
				elif str(b.get("type", "")) == "tool_use":
					events.append("[color=#ffcc66]🔧 " + str(b.get("name", "")) + "[/color] " + _clip(_tool_hint(b.get("input", {})), 100))
	if events.size() > 30:
		events = events.slice(events.size() - 30)
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
	# 取下一個路徑點當即時目標
	var step: Vector2 = r.target
	while r.path_i < r.path.size():
		step = r.path[r.path_i]
		if r.pos.distance_to(step) < 8.0:
			r.path_i += 1
		else:
			break
	if r.path_i >= r.path.size():
		step = r.target
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
	# Y-Sort：角色依腳底 Y 與家具一起排前後（自動，免逐座位調圖層）
	r.node.z_index = int(r.pos.y + FRAME_H * SCALE * 0.5)
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
	if state == "done" and age > DONE_DECAY:
		state = "idle"
	elif state == "thinking" or state == "working":
		# 心跳：transcript 停止更新代表回合結束（自然完成或被中斷）
		var tp := str(data.get("transcript", ""))
		if tp != "" and FileAccess.file_exists(tp):
			if now - float(FileAccess.get_modified_time(tp)) > ACTIVE_IDLE:
				state = "idle"
		elif age > ACTIVE_DECAY:
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
		lbl.position = Vector2(-16, -FRAME_H * SCALE * 0.5 - 12)   # 角色頭上名牌
		lbl.add_theme_font_size_override("font_size", 8)
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
	r.label.text = project
	r.label.add_theme_color_override("font_color", STATE_COLOR.get(state, Color.WHITE))
	r.label.add_theme_stylebox_override("normal", _name_bg())
	r.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var _lf: Font = r.label.get_theme_font("font")
	if _lf != null:
		r.label.position.x = -_lf.get_string_size(project, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x * 0.5 - 2

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
	# 逐格畫；最底層當地板（永遠在後），其餘家具/牆依「列 Y」排序，跟機器人一起前後遮擋
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
			# Y-Sort：地板永遠最底；其餘家具依「格底 Y」排序，與角色腳底 Y 比前後
			spr.z_index = -4096 if li == 0 else int((row + 1) * 16 * SCALE)
			add_child(spr)
		li += 1
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
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for c in solid:
		_astar.set_point_solid(c, true)
	# 座位與休息點一定要可走（否則機器人到不了）
	for s in SEATS:
		_astar.set_point_solid(Vector2i(int(s.col), int(s.row)), false)
	for t in LOUNGE_TILES:
		_astar.set_point_solid(Vector2i(int(t[0]), int(t[1])), false)
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

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
	{"col": 3, "row": 5, "face": "down"},
	{"col": 6, "row": 5, "face": "down"},
	{"col": 3, "row": 9, "face": "up"},
	{"col": 6, "row": 9, "face": "up"},
]
# 休息室休息點（格座標）
const LOUNGE_TILES := [[15, 2], [13, 2], [14, 6], [11, 6]]
# 等待狀態移動到的位置（格座標）—— 依座位序對應
const WAIT_TILES := [[5, 3], [6, 3], [9, 3], [2, 3]]
# ── 圖層/座位微調（改完重啟 start_map.cmd 生效）──
# 角色插入的圖層深度＝Tiled 裡的空白圖層當插入點（index = Tiled 層號 - 1）。
# 在該層以下的圖層畫在角色之後，以上的畫在角色之前。
const CHAR_LAYER_DEFAULT := 3   # Tiled 第4層(空白)：走動/待機/座位1、2 等大多數情況
const CHAR_LAYER_UPSEAT := 9    # Tiled 第10層(空白)：座位 3、4（面向上）
# 座位人物上下位移（格，正值=往上移動的格數）
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

func _input(event: InputEvent) -> void:
	# 整個視窗可拖曳（無邊框，靠滑鼠左鍵拖移視窗位置）
	if _debug_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_off = DisplayServer.mouse_get_position() - get_window().position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		get_window().position = DisplayServer.mouse_get_position() - _drag_off

func _ready() -> void:
	# 透明背景（多管齊下，確保 Windows 上生效）
	get_tree().root.transparent_bg = true
	get_window().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	var w := get_window()
	w.borderless = true
	w.always_on_top = true
	_shot = OS.get_cmdline_args().has("--shot")
	for i in range(1, 10):   # 載入 BOT1~BOT9
		var nm := "BOT%d" % i
		var img := Image.load_from_file("D:/Work/FunAI/assets/characters/%s.png" % nm)
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
	# 夾在 CHAR_LAYER 之下、CHAR_LAYER-1 之上；同層內以列(腳底 Y)互相排序
	# 角色插在指定的空白圖層深度；座位 3、4 用更前面的插入層
	var clayer := CHAR_LAYER_DEFAULT
	if not r.moving and not resting and r.state != "waiting" and r.home_facing == "up":
		clayer = CHAR_LAYER_UPSEAT   # 只有座位 3、4 真正在工作時用第 10 層
	r.node.z_index = clayer * 100 + int(r.pos.y / (16.0 * SCALE))
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
			spr.z_index = li * 100 + row   # 按 Tiled 圖層深度（層為主、列為輔）
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

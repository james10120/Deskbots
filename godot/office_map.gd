class_name OfficeMap
extends Node2D
# 辦公室地圖與地理：載入 bake_map.py 烘焙的 map_baked.json、畫圖層/overlay、
# 建 A* 走格。座位/休息點/等待點由烘焙時依模組錨點動態算好（每座位含
# lounge/wait 配對），這裡只載入；任何 COMPOSITION 都不用改 GDScript。

const SCALE := 1.2
const TILE := 16

# 座位人物上下位移（格，正值=往上移動的格數）— 微調坐姿位置用
const SEAT_UP_DY := 1.5
const SEAT_DOWN_DY := 0.5

var map_w := 17
var map_h := 11
var _seats: Array = []   # [{col,row,face,lounge:[c,r],wait:[c,r]}]，bake_map.py 算好
var _astar: AStarGrid2D


func tile_px(col: float, row: float) -> Vector2:
	# 格座標 → 螢幕像素（格中心，已含縮放）
	return Vector2(col * TILE + TILE * 0.5, row * TILE + TILE * 0.5) * SCALE


func seat_count() -> int:
	return _seats.size()


func seat_face(i: int) -> String:
	return str(_seats[i % _seats.size()].get("face", "down"))


func seat_px(i: int) -> Vector2:
	var s: Dictionary = _seats[i % _seats.size()]
	var p := tile_px(float(s.col), float(s.row))
	if str(s.get("face", "down")) == "up":
		p.y -= SEAT_UP_DY * TILE * SCALE     # 正值往上
	else:
		p.y -= SEAT_DOWN_DY * TILE * SCALE
	return p


func lounge_px(seat_idx: int) -> Vector2:
	var t: Array = _seats[seat_idx % _seats.size()].lounge
	return tile_px(float(t[0]), float(t[1]))


func wait_px(seat_idx: int) -> Vector2:
	var t: Array = _seats[seat_idx % _seats.size()].wait
	return tile_px(float(t[0]), float(t[1]))


func window_px_size() -> Vector2i:
	return Vector2i(int(map_w * TILE * SCALE), int(map_h * TILE * SCALE))


func is_walkable(p: Vector2) -> bool:
	if _astar == null:
		return true
	return not _astar.is_point_solid(world_to_cell(p))


func world_to_cell(p: Vector2) -> Vector2i:
	var c := Vector2i(int(p.x / (TILE * SCALE)), int(p.y / (TILE * SCALE)))
	c.x = clampi(c.x, 0, map_w - 1)
	c.y = clampi(c.y, 0, map_h - 1)
	return c


func compute_path(fromp: Vector2, top: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array([top])
	var fc := world_to_cell(fromp)
	var tc := world_to_cell(top)
	if _astar.is_point_solid(fc):
		_astar.set_point_solid(fc, false)   # 角色當前格暫時放行，避免起點卡死
	var p := _astar.get_point_path(fc, tc)
	if p.size() == 0:
		return PackedVector2Array([top])
	return p


func load_map() -> void:
	# 讀 bake_map.py 烘焙好的 map_baked.json，照圖層渲染整間辦公室
	var f := FileAccess.open(Paths.TILED_DIR + "map_baked.json", FileAccess.READ)
	if f == null:
		push_warning("map_baked.json 不存在 → 使用內建預設佈局（不黑屏）")
		_default_layout()
		return
	var m = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(m) != TYPE_DICTIONARY:
		return
	var tw := int(m["tilewidth"])
	map_w = int(m["width"])
	map_h = int(m["height"])
	_seats = m.get("seats", [])
	if _seats.is_empty():
		# 沒有座位資料（舊烘焙檔/組裝裡沒有房間）：放一個地圖中央的保底座位
		push_error("map_baked.json 沒有 seats，請重跑 bake_map.py")
		@warning_ignore("integer_division")
		var cc := [map_w / 2, map_h / 2]
		_seats = [{"col": cc[0], "row": cc[1], "face": "down", "lounge": cc, "wait": cc}]
	# 載入 tileset 紋理（優先序：外部 PNG > 內嵌加密包 > 程式生成備援地圖）
	var tsets := []
	for ts in m["tilesets"]:
		var img: Image = null
		if FileAccess.file_exists(Paths.TILED_DIR + str(ts["image"])):
			img = Image.load_from_file(Paths.TILED_DIR + str(ts["image"]))
		if img == null:
			img = AssetStore.image("tiled/" + str(ts["image"]))
		if img != null:
			tsets.append({"firstgid": int(ts["firstgid"]), "columns": int(ts["columns"]),
				"tex": ImageTexture.create_from_image(img)})
	# 瓦片集缺檔（使用者尚未放入素材）→ 程式生成的簡約辦公室，開箱即用
	if tsets.is_empty():
		var solid0 := {}
		var sg = m.get("solid", [])
		for idx in range(sg.size()):
			if int(sg[idx]) == 1:
				@warning_ignore("integer_division")
				solid0[Vector2i(idx % map_w, idx / map_w)] = true
		_paint_fallback(solid0)
		_build_astar(solid0)
		return
	# 逐格畫；地板永遠最底，其餘家具依圖層順序疊（z 0~8），與角色腳底 Y 比前後
	var li := 0
	for L in m["layers"]:
		var data = L["data"]
		for idx in range(data.size()):
			var gid := int(data[idx])
			if gid <= 0:
				continue
			var col := idx % map_w
			@warning_ignore("integer_division")
			var row := idx / map_w
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
			var row := idx / map_w
			var spr := Sprite2D.new()
			spr.texture = ts["tex"]
			spr.region_enabled = true
			spr.region_rect = Rect2((local % cols) * tw, sy, tw, tw)
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(SCALE, SCALE)
			spr.position = Vector2((idx % map_w) * tw, row * tw) * SCALE
			spr.z_index = ovz
			add_child(spr)
		ovz += 1
	# 障礙格用 bake_map.py 算好的 solid（含地板層的牆 + 上層家具）
	var solid := {}
	var sgrid = m.get("solid", [])
	for idx in range(sgrid.size()):
		if int(sgrid[idx]) == 1:
			@warning_ignore("integer_division")
			var row := idx / map_w
			solid[Vector2i(idx % map_w, row)] = true
	_build_astar(solid)


func _default_layout() -> void:
	# 連 map_baked.json 都沒有時的最終保險：一間 17×11 預設辦公室（程式生成畫風）。
	# 永不黑屏；使用者跑過 bake_map.py（run_deskbots 會跑）後就改用正式佈局。
	map_w = 17
	map_h = 11
	_seats = [
		{"col": 6, "row": 5, "face": "down", "lounge": [2, 4], "wait": [6, 3]},
		{"col": 9, "row": 5, "face": "down", "lounge": [3, 4], "wait": [9, 3]},
		{"col": 6, "row": 8, "face": "up", "lounge": [2, 7], "wait": [7, 3]},
		{"col": 9, "row": 8, "face": "up", "lounge": [3, 7], "wait": [8, 3]},
	]
	var solid := {}
	for c in range(map_w):
		solid[Vector2i(c, 0)] = true
		solid[Vector2i(c, 1)] = true
		solid[Vector2i(c, 2)] = true
		solid[Vector2i(c, map_h - 1)] = true
	for r in range(map_h):
		solid[Vector2i(0, r)] = true
		solid[Vector2i(map_w - 1, r)] = true
	_paint_fallback(solid)
	_build_astar(solid)


func _paint_fallback(solid: Dictionary) -> void:
	# 簡約平面風辦公室：合成一張整圖（地板棋盤/牆/家具塊 + 椅子/沙發/地墊提示）
	var img := Image.create(map_w * TILE, map_h * TILE, false, Image.FORMAT_RGBA8)
	for r in range(map_h):
		for c in range(map_w):
			var rect := Rect2i(c * TILE, r * TILE, TILE, TILE)
			if solid.has(Vector2i(c, r)):
				if r < 3 or r >= map_h - 1 or c == 0 or c == map_w - 1:
					img.fill_rect(rect, Color(0.40, 0.36, 0.36))            # 牆
					img.fill_rect(Rect2i(rect.position.x, rect.position.y + TILE - 2, TILE, 2),
						Color(0.30, 0.27, 0.27))
				else:
					img.fill_rect(rect, Color(0.58, 0.47, 0.36))            # 家具（桌面等）
					img.fill_rect(Rect2i(rect.position.x, rect.position.y, TILE, 2),
						Color(0.66, 0.55, 0.43))
			else:
				var even := (c + r) % 2 == 0
				img.fill_rect(rect, Color(0.84, 0.82, 0.77) if even else Color(0.81, 0.79, 0.74))
	for s in _seats:
		var sc := Vector2i(int(s.col), int(s.row))
		img.fill_rect(Rect2i(sc.x * TILE + 3, sc.y * TILE + 4, 10, 9), Color(0.84, 0.45, 0.25))   # 椅子
		img.fill_rect(Rect2i(sc.x * TILE + 3, sc.y * TILE + 11, 10, 2), Color(0.62, 0.32, 0.18))
		var lc: Array = s.lounge
		img.fill_rect(Rect2i(int(lc[0]) * TILE + 1, int(lc[1]) * TILE + 4, 14, 10), Color(0.46, 0.55, 0.69))  # 沙發
		img.fill_rect(Rect2i(int(lc[0]) * TILE + 1, int(lc[1]) * TILE + 4, 14, 3), Color(0.56, 0.65, 0.78))
		var wc: Array = s.wait
		img.fill_rect(Rect2i(int(wc[0]) * TILE + 2, int(wc[1]) * TILE + 3, 12, 11), Color(0.76, 0.73, 0.66))  # 等待區地墊
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(SCALE, SCALE)
	spr.z_index = 0   # 永遠墊底，角色(1000+)在上
	add_child(spr)


func _build_astar(solid: Dictionary) -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, map_w, map_h)
	_astar.cell_size = Vector2(TILE * SCALE, TILE * SCALE)
	_astar.offset = Vector2(TILE * 0.5 * SCALE, TILE * 0.5 * SCALE)   # 對齊格中心
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER   # 只走上下左右，嚴格沿格子走道
	_astar.update()
	for c in solid:
		_astar.set_point_solid(c, true)
	# 錨點（座位/休息/等待）一定要可走——模組錨點標錯也不至於讓機器人卡死
	for s in _seats:
		_astar.set_point_solid(Vector2i(int(s.col), int(s.row)), false)
		_astar.set_point_solid(Vector2i(int(s.lounge[0]), int(s.lounge[1])), false)
		_astar.set_point_solid(Vector2i(int(s.wait[0]), int(s.wait[1])), false)


func _pick_tileset(tsets: Array, gid: int):
	var best = null
	for ts in tsets:
		if int(ts["firstgid"]) <= gid and (best == null or int(ts["firstgid"]) > int(best["firstgid"])):
			best = ts
	return best


func draw_grid() -> void:
	# debug：在每格標 (col,row)，並把烘焙的錨點標上 S=座位 W=等待 L=休息（同序號一組）
	var tw := int(TILE * SCALE)
	for row in range(map_h):
		for col in range(map_w):
			var lbl := Label.new()
			lbl.text = "%d,%d" % [col, row]
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", Color(1, 1, 0))
			lbl.position = Vector2(col * tw + 2, row * tw + 1)
			lbl.z_index = 4096
			add_child(lbl)
	for i in range(_seats.size()):
		var s: Dictionary = _seats[i]
		_anchor_mark("S%d" % i, int(s.col), int(s.row), Color(0.3, 1.0, 0.3))
		_anchor_mark("W%d" % i, int(s.wait[0]), int(s.wait[1]), Color(1.0, 0.8, 0.2))
		_anchor_mark("L%d" % i, int(s.lounge[0]), int(s.lounge[1]), Color(0.4, 0.8, 1.0))


func _anchor_mark(text: String, col: int, row: int, c: Color) -> void:
	var tw := int(TILE * SCALE)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", c)
	lbl.add_theme_stylebox_override("normal", Util.name_bg())
	lbl.position = Vector2(col * tw, row * tw + 7)
	lbl.z_index = 4097
	add_child(lbl)

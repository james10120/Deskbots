class_name OfficeMap
extends Node2D
# 辦公室地圖與地理：載入 bake_map.py 烘焙的 map_baked.json、畫圖層/overlay、
# 建 A* 走格。座位/休息點/等待點等「辦公室地理」集中在這裡，外界只問像素座標。

const SCALE := 1.2
const TILE := 16

# 工作座位（格座標 col,row；face=面向 down/up）
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

var map_w := 17
var map_h := 11
var _astar: AStarGrid2D


func tile_px(col: float, row: float) -> Vector2:
	# 格座標 → 螢幕像素（格中心，已含縮放）
	return Vector2(col * TILE + TILE * 0.5, row * TILE + TILE * 0.5) * SCALE


func seat_count() -> int:
	return SEATS.size()


func seat_face(i: int) -> String:
	return SEATS[i].face


func seat_px(i: int) -> Vector2:
	var s = SEATS[i]
	var p := tile_px(s.col, s.row)
	if s.face == "up":
		p.y -= SEAT_UP_DY * TILE * SCALE     # 正值往上
	else:
		p.y -= SEAT_DOWN_DY * TILE * SCALE
	return p


func lounge_px(seat_idx: int) -> Vector2:
	var t = LOUNGE_TILES[seat_idx % LOUNGE_TILES.size()]
	return tile_px(t[0], t[1])


func wait_px(seat_idx: int) -> Vector2:
	var t = WAIT_TILES[seat_idx % WAIT_TILES.size()]
	return tile_px(t[0], t[1])


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
		push_error("找不到 map_baked.json，請先跑 bake_map.py")
		return
	var m = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(m) != TYPE_DICTIONARY:
		return
	var tw := int(m["tilewidth"])
	map_w = int(m["width"])
	map_h = int(m["height"])
	# 載入 tileset 紋理
	var tsets := []
	for ts in m["tilesets"]:
		var img := Image.load_from_file(Paths.TILED_DIR + str(ts["image"]))
		if img != null:
			tsets.append({"firstgid": int(ts["firstgid"]), "columns": int(ts["columns"]),
				"tex": ImageTexture.create_from_image(img)})
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


func _build_astar(solid: Dictionary) -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, map_w, map_h)
	_astar.cell_size = Vector2(TILE * SCALE, TILE * SCALE)
	_astar.offset = Vector2(TILE * 0.5 * SCALE, TILE * 0.5 * SCALE)   # 對齊格中心
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


func _pick_tileset(tsets: Array, gid: int):
	var best = null
	for ts in tsets:
		if int(ts["firstgid"]) <= gid and (best == null or int(ts["firstgid"]) > int(best["firstgid"])):
			best = ts
	return best


func draw_grid() -> void:
	# debug：在每格標 (col,row)，方便讀出座位/休息室座標
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

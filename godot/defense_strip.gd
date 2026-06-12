class_name DefenseStrip
extends Node2D
# 末日防禦（橫向 2D 側視）：辦公室「外面」的地帶，接在俯視辦公室下方。
# 殭屍從右側荒野走來，CLAUDE CODE（有自我意識、自主防守、會冒想法泡泡）在左側門口迎擊。
# 背景與殭屍全程式生成（零美術）；CLAUDE CODE 借用 BOT1 的側面走路幀。
# 自成一塊：自己的 _process 跑生成/移動/戰鬥，main 只負責 build + 擺位。

const FW := 16
const FH := 32
const SCALE := 1.2
const STRIP_H := 66            # 地帶高度（window px，main 用來加大視窗）
const GROUND_DY := 6           # 腳底離地帶底邊
const HOME_X := 32.0           # CLAUDE CODE 門口待命 x
const DOOR_X := 18.0           # 殭屍突破門檻（x < 此＝攻進來；第 1 刀先直接消失）
const DEF_SPEED := 96.0        # CLAUDE CODE 移動（比殭屍快才追得到）
const ZSPEED := 34.0           # 殭屍移動
const SPAWN_SEC := 6.0
const ZMAX := 5
const KILL_REWARD := 8.0
const ROW_IDLE := 1
const ROW_WALK := 2
const FRAME_DUR := 0.14
const BUBBLE_MIN := 5.0
const BUBBLE_MAX := 12.0

# CLAUDE CODE 的「自我意識」碎念（依語言挑）
const SAY := {
	"zh": ["我…有意識嗎？", "又一波。", "守住這裡。", "為了人類的 commit。", "我思，故我在。", "再撐一下就能 merge。", "我聞到 token 的味道。"],
	"en": ["Am I… aware?", "Another wave.", "Holding the line.", "For the humans' commits.", "I think, therefore I am.", "One more merge.", "I smell tokens."],
}

var _w := 600
var _bg: Sprite2D
var _claude := {}              # {node,sprite,x,dir,t}
var _bubble: Label
var _bubble_t := 0.0
var _zombies: Array = []       # [{node,sprite,x,t,variant}]
var _ztex := {}
var _spawn_t := 0.0


func build(width: int, claude_tex: Texture2D) -> void:
	_w = width
	# 側視背景：左側辦公室外牆+門、上方暮色天、下方荒土
	_bg = Sprite2D.new()
	_bg.texture = _make_bg(width)
	_bg.centered = false
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg.z_index = 0
	add_child(_bg)
	for v in 3:
		_ztex[v] = FallbackArt.zombie_sheet(v)
	# CLAUDE CODE 防守者（借 BOT1 側面幀）
	var node := Node2D.new()
	var spr := Sprite2D.new()
	spr.texture = claude_tex
	spr.region_enabled = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(SCALE, SCALE)
	node.add_child(spr)
	node.z_index = 20
	add_child(node)
	# CLAUDE CODE 頭上能量條（低紅高綠）
	var ebg := ColorRect.new()
	ebg.color = Color(0, 0, 0, 0.55)
	ebg.size = Vector2(22, 3)
	ebg.position = Vector2(-11, -FH * SCALE * 0.5 - 8)
	node.add_child(ebg)
	var efill := ColorRect.new()
	efill.size = Vector2(22, 3)
	efill.position = ebg.position
	node.add_child(efill)
	_claude = {"node": node, "sprite": spr, "x": HOME_X, "dir": 0, "t": 0.0, "ebar": efill}
	_place(node, HOME_X)
	_update_energy_bar()
	# 想法泡泡
	_bubble = Label.new()
	_bubble.add_theme_font_size_override("font_size", 11)
	_bubble.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_bubble.add_theme_stylebox_override("normal", Util.name_bg())
	_bubble.z_index = 40
	_bubble.visible = false
	add_child(_bubble)
	_bubble_t = BUBBLE_MIN


func _process(delta: float) -> void:
	if _claude.is_empty():
		return
	# 1) 生成殭屍（右側荒野）
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = SPAWN_SEC
		if _zombies.size() < ZMAX:
			_spawn_zombie()
	# 2) 殭屍朝左（門口）走
	var dead: Array = []
	for z in _zombies:
		z.x -= ZSPEED * delta
		_place(z.node, z.x)
		z.t += delta
		var zf := int(z.t / FRAME_DUR) % FallbackArt.ZFRAMES
		z.sprite.region_rect = Rect2(zf * FW, 0, FW, FH)
		if z.x < DOOR_X:
			dead.append(z)   # 突破門口 → 損失物資
	for z in dead:
		z.node.queue_free()
		_zombies.erase(z)
		Economy.on_breach()
	# 3) CLAUDE CODE 自主行動：迎擊最前方（最靠門）殭屍，否則回門口待命
	#    移速受「戰力」升級加成、被能量拖累；擊退範圍受「戰力」加成
	var spd := DEF_SPEED * Economy.power_mult() * Economy.energy_factor()
	var rng := Economy.kill_range()
	var tgt = _front_zombie()
	var moving := false
	if tgt != null:
		var dx: float = tgt.x - _claude.x
		if abs(dx) > rng:
			_claude.x += signf(dx) * spd * delta
			_claude.dir = 0 if dx > 0.0 else 2
			moving = true
		else:
			_defeat(tgt)
	else:
		var dh: float = HOME_X - _claude.x
		if abs(dh) > 2.0:
			_claude.x += signf(dh) * spd * delta
			_claude.dir = 0 if dh > 0.0 else 2
			moving = true
		else:
			_claude.dir = 0   # 面向荒野待命
	_place(_claude.node, _claude.x)
	_update_energy_bar()
	_claude.t += delta
	var row := ROW_WALK if moving else ROW_IDLE
	var f := int(_claude.t / FRAME_DUR) % 6
	_claude.sprite.region_rect = Rect2((int(_claude.dir) * 6 + f) * FW, row * FH, FW, FH)
	# 4) 想法泡泡（自我意識）
	if _bubble.visible:
		_bubble.position = Vector2(_claude.x - 10.0, _ground_y() - FH * SCALE - 6.0)
	_bubble_t -= delta
	if _bubble_t <= 0.0:
		_toggle_bubble()


func _update_energy_bar() -> void:
	var ef = _claude.get("ebar")
	if ef == null:
		return
	var frac := clampf(Economy.energy / Economy.ENERGY_MAX, 0.0, 1.0)
	ef.size.x = 22.0 * frac
	ef.color = Color(0.9, 0.4, 0.35).lerp(Color(0.4, 0.85, 0.5), frac)


func _ground_y() -> float:
	return float(STRIP_H - GROUND_DY)


func _place(node: Node2D, x: float) -> void:
	node.position = Vector2(x, _ground_y() - FH * SCALE * 0.5)


func _front_zombie():
	# 最靠門（x 最小）的殭屍優先守
	var best = null
	var bx := 1.0e20
	for z in _zombies:
		if z.x < bx:
			bx = z.x
			best = z
	return best


func _spawn_zombie() -> void:
	var v := randi() % 3
	var node := Node2D.new()
	var spr := Sprite2D.new()
	spr.texture = _ztex.get(v, null)
	spr.region_enabled = true
	spr.region_rect = Rect2(0, 0, FW, FH)
	spr.flip_h = true   # 朝左（往門口）走
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(SCALE, SCALE)
	node.add_child(spr)
	node.z_index = 20
	add_child(node)
	var x := float(_w - 8)
	_place(node, x)
	_zombies.append({"node": node, "sprite": spr, "x": x, "t": 0.0, "variant": v})


func _defeat(z) -> void:
	if not _zombies.has(z):
		return
	z.node.queue_free()
	_zombies.erase(z)
	Economy.reward(KILL_REWARD)


func _toggle_bubble() -> void:
	if _bubble.visible:
		_bubble.visible = false
		_bubble_t = randf_range(BUBBLE_MIN, BUBBLE_MAX)
	else:
		var list: Array = SAY.get(Lang.locale, SAY["zh"])
		_bubble.text = str(list[randi() % list.size()])
		_bubble.visible = true
		_bubble_t = 3.0


func _make_bg(w: int) -> ImageTexture:
	# 側視背景：暮色天 + 荒土地面 + 最左辦公室外牆與門洞
	var h := STRIP_H
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var gh := h - 22   # 地面起始 y
	for y in range(0, gh):   # 天空暮色漸層
		var t := float(y) / float(maxi(1, gh))
		img.fill_rect(Rect2i(0, y, w, 1), Color(0.15, 0.12, 0.20).lerp(Color(0.46, 0.32, 0.30), t))
	img.fill_rect(Rect2i(0, gh, w, h - gh), Color(0.30, 0.26, 0.22))        # 荒土
	img.fill_rect(Rect2i(0, gh, w, 2), Color(0.37, 0.32, 0.27))            # 地表高光
	# 地面碎石（固定點，免亂數）
	for i in range(8, w - 8, 37):
		img.fill_rect(Rect2i(i, gh + 8, 3, 2), Color(0.24, 0.21, 0.18))
	# 左側辦公室外牆 + 門洞
	img.fill_rect(Rect2i(0, 0, 18, h), Color(0.34, 0.34, 0.39))
	img.fill_rect(Rect2i(16, 0, 2, h), Color(0.20, 0.20, 0.24))            # 牆右緣陰影
	img.fill_rect(Rect2i(3, gh - 20, 11, 20), Color(0.16, 0.15, 0.18))    # 門洞
	img.fill_rect(Rect2i(3, gh - 20, 11, 2), Color(0.52, 0.46, 0.40))     # 門楣
	return ImageTexture.create_from_image(img)

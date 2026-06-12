class_name FallbackArt
# 內建備援畫風：素材 PNG 缺檔時，程式即時生成原創像素機器人（100% 本專案原創，
# 可隨發行包散布，無第三方授權問題）。放入 LimeZu 素材後自動改用精緻版。
# 表格規格與 LimeZu 角色表對齊：16×32/幀；第2列站立、第3列走路（4向×6幀）、
# 第7列滑手機、第8列看書（12幀正面）—— main.gd 的取幀邏輯零修改。

const FW := 16
const FH := 32
const COLS := 24   # 4 向 × 6 幀


static func bot_sheet(idx: int) -> ImageTexture:
	# idx 1~9 → 每隻不同色相的小機器人
	var img := Image.create(COLS * FW, 8 * FH, false, Image.FORMAT_RGBA8)
	var hue := fposmod(0.55 + float(idx) * 0.41, 1.0)
	var body := Color.from_hsv(hue, 0.45, 0.85)
	var dark := Color.from_hsv(hue, 0.55, 0.55)
	for d in 4:
		for f in 6:
			var x := (d * 6 + f) * FW
			_frame(img, x, 1 * FH, d, 0, f % 3 == 0, body, dark, "")          # 站立：燈號慢閃
			_frame(img, x, 2 * FH, d, (f % 2) * 2 - 1, false, body, dark, "") # 走路：腳交替
	for f in 12:
		_frame(img, f * FW, 6 * FH, 3, 0, f % 4 < 2, body, dark, "phone")     # 滑手機：螢幕閃爍
		_frame(img, f * FW, 7 * FH, 3, 0, false, body, dark, "read")          # 看書
	return ImageTexture.create_from_image(img)


static func _frame(img: Image, x: int, y: int, dir: int, leg: int, lit: bool,
		body: Color, dark: Color, prop: String) -> void:
	var metal := Color(0.82, 0.84, 0.88)
	var shadow := Color(0, 0, 0, 0.18)
	# 腳底影子
	img.fill_rect(Rect2i(x + 4, y + 29, 8, 2), shadow)
	# 腳（走路時交替抬起）
	var l_up := 1 if leg < 0 else 0
	var r_up := 1 if leg > 0 else 0
	img.fill_rect(Rect2i(x + 5, y + 26 - l_up, 2, 3), dark)
	img.fill_rect(Rect2i(x + 9, y + 26 - r_up, 2, 3), dark)
	# 身體
	img.fill_rect(Rect2i(x + 4, y + 18, 8, 8), body)
	img.fill_rect(Rect2i(x + 4, y + 24, 8, 2), dark)             # 腰帶
	# 手臂
	img.fill_rect(Rect2i(x + 3, y + 19, 1, 5), dark)
	img.fill_rect(Rect2i(x + 12, y + 19, 1, 5), dark)
	# 頭
	img.fill_rect(Rect2i(x + 4, y + 10, 8, 8), metal)
	img.fill_rect(Rect2i(x + 4, y + 10, 8, 1), Color(0.92, 0.93, 0.96))   # 頭頂高光
	# 天線
	img.fill_rect(Rect2i(x + 7, y + 7, 1, 3), dark)
	img.fill_rect(Rect2i(x + 6, y + 5, 3, 2), body if lit else dark)      # 燈號
	# 臉（眼睛依方向；背面畫背板）
	var eye := Color(0.15, 0.35, 0.55)
	match dir:
		3:   # 正面
			img.fill_rect(Rect2i(x + 5, y + 13, 2, 2), eye)
			img.fill_rect(Rect2i(x + 9, y + 13, 2, 2), eye)
		0:   # 右
			img.fill_rect(Rect2i(x + 8, y + 13, 2, 2), eye)
			img.fill_rect(Rect2i(x + 11, y + 13, 1, 2), eye)
		2:   # 左
			img.fill_rect(Rect2i(x + 6, y + 13, 2, 2), eye)
			img.fill_rect(Rect2i(x + 4, y + 13, 1, 2), eye)
		1:   # 背面
			img.fill_rect(Rect2i(x + 5, y + 12, 6, 4), body)
			img.fill_rect(Rect2i(x + 6, y + 13, 4, 2), dark)
	# 道具
	if prop == "phone":
		img.fill_rect(Rect2i(x + 10, y + 20, 3, 5), Color(0.2, 0.22, 0.26))
		if lit:
			img.fill_rect(Rect2i(x + 10, y + 21, 3, 3), Color(0.55, 0.85, 1.0))
		img.fill_rect(Rect2i(x + 9, y + 22, 1, 2), dark)          # 手
	elif prop == "read":
		img.fill_rect(Rect2i(x + 3, y + 20, 10, 5), Color(0.93, 0.90, 0.80))
		img.fill_rect(Rect2i(x + 8, y + 20, 1, 5), Color(0.6, 0.5, 0.4))   # 書脊
		img.fill_rect(Rect2i(x + 3, y + 25, 10, 1), Color(0.6, 0.5, 0.4))


# ── 末日殭屍（程式生成，3 種外觀；橫向 4 幀走路 strip，朝右畫、朝左翻面）──────
const ZFRAMES := 4

static func zombie_sheet(variant: int) -> ImageTexture:
	# variant 0~2：膚色／衣服／眼睛各異，只求外表有差異即可
	var skin: Color
	var shirt: Color
	match variant % 3:
		0:
			skin = Color(0.46, 0.62, 0.40)   # 經典綠屍
			shirt = Color(0.28, 0.32, 0.44)
		1:
			skin = Color(0.56, 0.60, 0.62)   # 灰藍腐屍
			shirt = Color(0.46, 0.34, 0.26)
		_:
			skin = Color(0.64, 0.60, 0.30)   # 病黃感染者
			shirt = Color(0.52, 0.24, 0.24)
	var img := Image.create(ZFRAMES * FW, FH, false, Image.FORMAT_RGBA8)
	for f in ZFRAMES:
		_zombie_frame(img, f * FW, f, skin, shirt, variant % 3)
	return ImageTexture.create_from_image(img)


static func _zombie_frame(img: Image, x: int, f: int, skin: Color, shirt: Color, variant: int) -> void:
	var dark := skin.darkened(0.45)
	var shadow := Color(0, 0, 0, 0.18)
	var lf := f % 2               # 左右腳交替
	var bob := 0 if f % 2 == 0 else 1   # 走路時身體微微上下
	var by := 1 + bob            # 身體基準 y
	# 腳底影子
	img.fill_rect(Rect2i(x + 4, 30, 9, 2), shadow)
	# 腳（交替抬起）
	var legc := shirt.darkened(0.35)
	img.fill_rect(Rect2i(x + 5, 26 - lf, 2, 4), legc)
	img.fill_rect(Rect2i(x + 9, 26 - (1 - lf), 2, 4), legc)
	# 身體（破爛衣）
	img.fill_rect(Rect2i(x + 4, by + 17, 8, 9), shirt)
	img.fill_rect(Rect2i(x + 6, by + 21, 2, 2), dark)        # 破洞
	# 手臂前伸（朝右），讀起來像殭屍撲咬
	img.fill_rect(Rect2i(x + 11, by + 19, 4, 2), skin)
	img.fill_rect(Rect2i(x + 14, by + 19, 1, 2), dark)       # 手指
	if variant != 1:                                          # variant 1 缺一隻手臂
		img.fill_rect(Rect2i(x + 2, by + 20, 2, 4), skin)
	# 頭（駝背前傾）
	img.fill_rect(Rect2i(x + 5, by + 9, 8, 8), skin)
	img.fill_rect(Rect2i(x + 5, by + 9, 8, 1), skin.lightened(0.18))
	# 眼睛 + 嘴
	var eye := Color(0.85, 0.15, 0.12) if variant == 2 else Color(0.08, 0.08, 0.08)
	img.fill_rect(Rect2i(x + 7, by + 12, 1, 1), eye)
	img.fill_rect(Rect2i(x + 10, by + 12, 1, 1), eye)
	img.fill_rect(Rect2i(x + 7, by + 15, 4, 1), dark)        # 咧嘴

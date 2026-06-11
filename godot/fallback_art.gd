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

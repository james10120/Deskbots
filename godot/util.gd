class_name Util
# 共用小工具：JSON 讀寫、樣式、格式化。全部 static、無狀態。

# 狀態 → 顏色提示（名牌、看板色點、對話卡標題共用）
const STATE_COLOR := {
	"idle": Color(0.7, 0.7, 0.7),
	"thinking": Color(0.6, 0.8, 1.0),
	"working": Color(0.7, 1.0, 0.7),
	"waiting": Color(1.0, 0.85, 0.3),
	"done": Color(0.6, 1.0, 0.6),
	"error": Color(1.0, 0.5, 0.5),
}


static func read_json(path: String):
	# 讀 JSON 檔，回 Dictionary；讀不到/不是物件回 null
	var j = read_json_any(path)
	return j if j is Dictionary else null


static func read_json_any(path: String):
	# 讀 JSON 檔，回任意型別；讀不到回 null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var j = JSON.parse_string(f.get_as_text())
	f.close()
	return j


static func write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


static func fmt_tok(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


static func norm_cwd(p: String) -> String:
	# 路徑正規化（比對用）；要和 usage_poll.py 的 _norm_cwd 規則一致
	return p.replace("/", "\\").rstrip("\\").to_lower()


static func clip(s: String, n: int) -> String:
	s = s.replace("[", "(").replace("]", ")")   # 避免 BBCode 衝突
	return s if s.length() <= n else s.substr(0, n) + "…"


static func btn_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(9)
	sb.set_content_margin_all(10)
	return sb


static func style_btn(b: Button, normal: Color, hover: Color, font_col: Color, font_size: int) -> void:
	# 統一的卡片按鈕外觀：normal/hover/pressed 三態 + 字色字級 + 不搶焦點
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", btn_style(normal))
	b.add_theme_stylebox_override("hover", btn_style(hover))
	b.add_theme_stylebox_override("pressed", btn_style(normal))
	b.add_theme_color_override("font_color", font_col)


static func name_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)   # 名字半透明深色底，好讀
	sb.set_content_margin_all(2)
	sb.set_corner_radius_all(2)
	return sb

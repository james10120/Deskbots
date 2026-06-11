class_name DetailWindow
extends DragWindow
# 對話卡：點機器人開啟，顯示該 session 最近一輪 Q&A，可送訊息/指令、呼叫終端。
# 視窗不直接碰行程/winfocus —— 一律發 signal 由 main 處理，保持單向依賴。

signal send_requested(text: String)   # 要送給該 session 終端的文字（含斜線指令）
signal focus_requested                # 要求把該 session 的終端叫到最前
signal closed                         # 使用者關卡片（main 據此清掉選取）

var placed := false        # 位置已知（拖過/上次留下）→ 重開沿用，不再置中
var _header: Label
var _text: RichTextLabel
var _input: TextEdit       # 多行輸入：Enter 送出 / Shift+Enter 換行
var _hint: Label           # hwnd 缺失時的提示


func build() -> void:
	title = "Deskbots 對話"
	init_frame(Vector2i(540, 520))
	close_requested.connect(_close)
	var vbox := build_card(14, 18, 16, Color(0.12, 0.13, 0.18, 1.0), Color(0.26, 0.30, 0.42, 1.0))
	vbox.add_theme_constant_override("separation", 12)
	# 標題列：標題（可拖曳移動視窗）+ 自己的關閉鈕
	var headrow := HBoxContainer.new()
	vbox.add_child(headrow)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 17)
	_header.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make_drag_handle(_header)
	headrow.add_child(_header)
	var xbtn := Button.new()
	xbtn.text = "✕"
	xbtn.focus_mode = Control.FOCUS_NONE
	xbtn.add_theme_font_size_override("font_size", 15)
	var xsb := StyleBoxFlat.new()
	xsb.bg_color = Color(0.24, 0.11, 0.13, 1.0)
	xsb.set_corner_radius_all(8)
	xsb.set_content_margin_all(7)
	var xhsb := xsb.duplicate()
	xhsb.bg_color = Color(0.62, 0.20, 0.22, 1.0)
	xbtn.add_theme_stylebox_override("normal", xsb)
	xbtn.add_theme_stylebox_override("hover", xhsb)
	xbtn.add_theme_stylebox_override("pressed", xsb)
	xbtn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	xbtn.pressed.connect(_close)
	headrow.add_child(xbtn)
	# 聊天內容（內嵌一張稍深的卡片）
	var inner := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.09, 0.10, 0.14, 1.0)
	isb.set_corner_radius_all(10)
	isb.set_content_margin_all(12)
	inner.add_theme_stylebox_override("panel", isb)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(inner)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_text.scroll_following = true
	_text.selection_enabled = true
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_constant_override("line_separation", 3)
	inner.add_child(_text)
	# 送訊息/指令給這個 session（聚焦其終端 → 鍵盤注入文字 + Enter）
	var inrow := HBoxContainer.new()
	inrow.add_theme_constant_override("separation", 8)
	vbox.add_child(inrow)
	_input = TextEdit.new()
	_input.placeholder_text = "送訊息或指令給 Claude…（Enter 送出，Shift+Enter 換行）"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY   # 超出寬度自動換行，不再被截掉
	_input.scroll_fit_content_height = true              # 隨內容長高（多行也看得到）
	_input.custom_minimum_size = Vector2(0, 34)          # 起始約一行高
	_input.add_theme_font_size_override("font_size", 14)
	_input.gui_input.connect(_on_input_gui)              # Enter 送出 / Shift+Enter 換行
	inrow.add_child(_input)
	var sbtn := Button.new()
	sbtn.text = "送出"
	sbtn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 輸入框長高時，送出鈕仍貼齊頂部
	Util.style_btn(sbtn, Color(0.20, 0.44, 0.34), Color(0.26, 0.54, 0.42), Color(0.92, 1.0, 0.95), 14)
	sbtn.pressed.connect(_send_input)
	inrow.add_child(sbtn)
	# hwnd 缺失提示（無可聚焦終端時說明原因，避免靜默失敗）
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.visible = false
	vbox.add_child(_hint)
	# 快捷指令列
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 8)
	vbox.add_child(qrow)
	for q in [["/clear", "/clear"], ["/compact", "/compact"], ["⎋ 中斷", "<ESC>"]]:
		var qb := Button.new()
		qb.text = q[0]
		qb.tooltip_text = "送出 %s 給這個 session" % q[1]
		Util.style_btn(qb, Color(0.22, 0.24, 0.32), Color(0.30, 0.33, 0.43), Color(0.88, 0.92, 1.0), 13)
		var cmd: String = q[1]
		qb.pressed.connect(func(): send_requested.emit(cmd))
		qrow.add_child(qb)
	# 呼叫對應終端視窗（給 TAB 聚焦不到時用）
	var fbtn := Button.new()
	fbtn.text = "▸ 呼叫這個 session 的終端視窗"
	Util.style_btn(fbtn, Color(0.20, 0.34, 0.52), Color(0.26, 0.42, 0.62), Color(0.92, 0.96, 1.0), 14)
	fbtn.pressed.connect(func(): focus_requested.emit())
	vbox.add_child(fbtn)


func open_centered(scr: int) -> void:
	if not placed:   # 第一次開才置中；之後（含上次留下的位置）原地重開
		var sp := DisplayServer.screen_get_size(scr)
		var so := DisplayServer.screen_get_position(scr)
		position = so + (sp - size) / 2
		placed = true
	show()


func restore_position(p: Vector2i) -> void:
	position = p
	placed = true


func refresh(r: Dictionary) -> void:
	title = "Deskbots 對話 — %s" % str(r.project)
	var col: Color = Util.STATE_COLOR.get(str(r.state), Color.WHITE)
	_header.text = "💬 %s   ·   %s" % [str(r.project), str(r.state)]
	_header.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.3))
	var body := _transcript_log(str(r.get("transcript", "")))
	if body == "":
		body = "[color=#888888](尚無對話記錄)[/color]"
	_text.text = body
	# 沒有可聚焦的終端視窗（hwnd=0）→ 送指令/呼叫終端無法用，明確說明、輸入框變灰
	var has_win := int(r.get("hwnd", 0)) != 0
	_hint.visible = not has_win
	_hint.text = "⚠ 抓不到這個 session 的終端視窗（可能在 VS Code 整合終端或無視窗環境啟動）。用啟動器開的獨立 PowerShell 視窗才能送指令／呼叫終端。"
	_input.editable = has_win
	_input.placeholder_text = "送訊息或指令給 Claude…（Enter 送出，Shift+Enter 換行）" if has_win else "此 session 無可用終端視窗"


func flash_hint() -> void:
	if _hint != null:
		_hint.visible = true


func _close() -> void:
	hide()
	closed.emit()


func _send_input() -> void:
	var t := _input.text.strip_edges()
	if t == "":
		return
	send_requested.emit(t)
	_input.text = ""


func _on_input_gui(event: InputEvent) -> void:
	# Enter 送出；Shift+Enter 換行（交給 TextEdit 預設行為插入換行）
	if event is InputEventKey and event.pressed and not event.shift_pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_input.accept_event()   # 吃掉這個 Enter，不要插入換行
			_send_input()


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
				events.append("[color=#7fb3ff]▌ 你[/color]\n" + Util.clip(up, 800))
		elif t == "assistant" and content is Array:
			for b in content:
				if typeof(b) != TYPE_DICTIONARY:
					continue
				if str(b.get("type", "")) == "text" and str(b.get("text", "")).strip_edges() != "":
					events.append("[color=#cfcfcf]▌ Claude[/color]\n" + Util.clip(str(b.get("text", "")), 2000))
				elif str(b.get("type", "")) == "tool_use":
					events.append("[color=#e8b35a]   🔧 " + str(b.get("name", "")) + "[/color]  [color=#9a9a9a]" + Util.clip(_tool_hint(b.get("input", {})), 100) + "[/color]")
	# 只顯示「最近一次使用者提問」之後（最近一輪 Q&A）
	var last_user := -1
	for i in range(events.size()):
		if str(events[i]).begins_with("[color=#7fb3ff]"):
			last_user = i
	if last_user >= 0:
		events = events.slice(last_user)
	elif events.size() > 12:
		events = events.slice(events.size() - 12)
	return "\n\n".join(events)


func _tool_hint(inp) -> String:
	if typeof(inp) != TYPE_DICTIONARY:
		return ""
	for k in ["file_path", "command", "pattern", "query", "path", "url", "description"]:
		if inp.has(k):
			return str(inp[k])
	return ""

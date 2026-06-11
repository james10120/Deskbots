class_name UsageBoard
extends DragWindow
# 工作看板：在場 session 卡片（負荷量表 + LV + 產出/閱讀/回合）+ 全公司合計
# + 人才庫（可重新雇用的歷史專案，含 ✕ 移除）。
# 資料來源：usage.json / rehire.json（usage_poll.py 寫）；robots 由 main 每次 refresh 傳入。

signal card_clicked(sid: String)        # 點 session 卡片 → main 開/關對話卡
signal rehire_requested(cwd: String)    # 點人才庫列 → main 開新終端 claude -c

const USAGE_W := 260            # 看板視窗寬
const USAGE_MIN_H := 220        # 看板最小高（拉高把手的下限）
const CONTEXT_MAX := 200000.0   # 負荷量表的分母（context 上限；超過=超出負荷）
# 負荷比例 → 遊戲字眼（由低到高，取第一個達標的）
const LOAD_WORDS := [
	[0.30, "游刃有餘", Color(0.55, 0.85, 0.60)],
	[0.55, "漸入佳境", Color(0.70, 0.85, 0.55)],
	[0.75, "全神貫注", Color(0.95, 0.85, 0.45)],
	[0.90, "火力全開", Color(1.00, 0.65, 0.35)],
	[1.00, "瀕臨極限", Color(1.00, 0.45, 0.35)],
]
const LOAD_OVER := ["⚠ 工作量超出負荷", Color(1.0, 0.35, 0.30)]

var _box: VBoxContainer        # 卡片容器（每次刷新重建內容）
var _pin_btn: Button           # 釘選鈕（還原狀態時要同步外觀）
var _resizing := false         # 拖底部把手調整高度中
var _departed: Array = []      # 人才庫：可重新雇用的歷史專案 [{project, cwd, ago, mtime}]
var _hidden := {}              # 人才庫移除名單：norm_cwd -> 移除當下 unix 時間
var _robots_ref := {}          # 最近一次 refresh 的 robots（main 的同一份 dict，移除後立即重畫用）
var _selected := ""


func build() -> void:
	title = "Deskbots 工作看板"
	init_frame(Vector2i(USAGE_W, 380))
	close_requested.connect(hide)
	_hidden = _load_hidden()
	var vbox := build_card(6, 12, 14, Color(0.10, 0.11, 0.15, 0.62), Color(0.26, 0.30, 0.42, 0.7))
	vbox.add_theme_constant_override("separation", 8)
	# 標題列：標題（拖曳）+ 釘選 + 關閉
	var headrow := HBoxContainer.new()
	headrow.add_theme_constant_override("separation", 6)
	vbox.add_child(headrow)
	var heading := Label.new()
	heading.text = "⚒ 工作看板"
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make_drag_handle(heading)
	headrow.add_child(heading)
	_pin_btn = Button.new()
	_pin_btn.text = "📌"
	_pin_btn.toggle_mode = true
	_pin_btn.tooltip_text = "釘選看板：永遠置頂（與地圖分開）"
	_pin_btn.focus_mode = Control.FOCUS_NONE
	_pin_btn.add_theme_font_size_override("font_size", 12)
	_pin_btn.toggled.connect(_set_pin)
	headrow.add_child(_pin_btn)
	var xbtn := Button.new()
	xbtn.text = "✕"
	xbtn.focus_mode = Control.FOCUS_NONE
	xbtn.add_theme_font_size_override("font_size", 12)
	xbtn.pressed.connect(hide)
	headrow.add_child(xbtn)
	# 內容捲動（拉高視窗 = 一次看到更多卡片）
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	# 底部拉高把手
	var grip := Label.new()
	grip.text = "··· 拖此調整高度 ···"
	grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grip.add_theme_font_size_override("font_size", 10)
	grip.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	grip.gui_input.connect(_on_grip)
	vbox.add_child(grip)


func _process(delta: float) -> void:
	super._process(delta)   # 標題拖曳
	if _resizing:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var maxh := DisplayServer.screen_get_size(current_screen).y
			var h := DisplayServer.mouse_get_position().y - position.y + 10
			size = Vector2i(USAGE_W, clampi(h, USAGE_MIN_H, maxh))
		else:
			_resizing = false


func _set_pin(on: bool) -> void:
	# 對「顯示中」的透明分層視窗直接切 always_on_top，Windows 會重建視窗樣式，
	# per-pixel 透明的點擊判定會壞掉（整窗穿透、釘選鈕點不到）。
	# 安全作法：先藏 → 切旗標 → 重套透明 → 再顯示（位置大小原樣保留）。
	var pos := position
	var sz := size
	hide()
	always_on_top = on
	transparent_bg = true
	set_flag(Window.FLAG_TRANSPARENT, true)
	show()
	position = pos
	size = sz


func set_pin_state(on: bool) -> void:
	# 還原上次狀態用：藏著時直接設旗標即可，顯示中才需要 _set_pin 的安全流程
	if _pin_btn != null:
		_pin_btn.set_pressed_no_signal(on)
	if visible:
		_set_pin(on)
	else:
		always_on_top = on


func _on_grip(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_resizing = true


func refresh(robots: Dictionary, selected: String) -> void:
	if _box == null:
		return
	_robots_ref = robots
	_selected = selected
	var usage = Util.read_json(Paths.USAGE_FILE)
	if usage == null:
		usage = {}
	_load_departed()   # 重新讀人才庫（usage_poll 每 2s 更新）
	for c in _box.get_children():
		c.queue_free()
	# 依座位序排在場 session，畫面穩定不跳動
	var sids := robots.keys()
	sids.sort_custom(func(a, b): return int(robots[a].seat_idx) < int(robots[b].seat_idx))
	var t_in := 0; var t_out := 0; var t_cache := 0; var t_turns := 0
	var shown := 0
	for sid in sids:
		var r = robots[sid]
		var u = usage.get(sid, null)
		var col: Color = Util.STATE_COLOR.get(str(r.state), Color.WHITE)
		_box.add_child(_usage_card(str(sid), str(r.project), col, u))
		shown += 1
		if u != null:
			t_in += int(u.get("in", 0))
			t_out += int(u.get("out", 0))
			t_cache += int(u.get("cache", 0))
			t_turns += int(u.get("turns", 0))
	if shown == 0:
		var empty := Label.new()
		empty.text = "辦公室空無一人…"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
		_box.add_child(empty)
	else:
		# 全公司合計列
		_box.add_child(HSeparator.new())
		var tot := VBoxContainer.new()
		tot.add_theme_constant_override("separation", 1)
		var h := Label.new()
		h.text = "🏢 全公司 · %d 人上工" % shown
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
		tot.add_child(h)
		var l := Label.new()
		l.text = "⚒ 產出 %s   📖 閱讀 %s" % [Util.fmt_tok(t_out), Util.fmt_tok(t_in + t_cache)]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		tot.add_child(l)
		var l2 := Label.new()
		l2.text = "🔁 共 %d 回合" % t_turns
		l2.add_theme_font_size_override("font_size", 12)
		l2.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		tot.add_child(l2)
		_box.add_child(tot)
	# 人才庫：近期用過、目前沒在跑的專案，一鍵重新雇用（claude -c 接續上次對話）
	if _departed.size() > 0:
		_box.add_child(HSeparator.new())
		var dh := Label.new()
		dh.text = "📋 人才庫 · 點擊重新雇用"
		dh.add_theme_font_size_override("font_size", 12)
		dh.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
		_box.add_child(dh)
		for d in _departed:
			_box.add_child(_rehire_row(d))


func _on_card_input(event: InputEvent, sid: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		card_clicked.emit(sid)


func _usage_card(sid: String, project: String, col: Color, u) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# 被點選的 session 卡片高亮邊框，呼應對話框正在看的對象
	sb.bg_color = Color(0.17, 0.20, 0.28, 0.78) if sid == _selected else Color(0.14, 0.15, 0.20, 0.72)
	if sid == _selected:
		sb.set_border_width_all(1)
		sb.border_color = Color(0.45, 0.6, 0.95, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	# 點卡片 = 跳到對應 session（同點機器人：開/關該 session 的對話卡）
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e): _on_card_input(e, sid))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	# 標題列：狀態色點 + 專案名
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)
	var name := Label.new()
	name.text = project
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name)
	if u != null:
		# LV 徽章：依產出量成長（sqrt 曲線，前期升得快後期慢）
		var lv := 1 + int(sqrt(float(int(u.get("out", 0))) / 10000.0))
		var lvl := Label.new()
		lvl.text = "LV %d" % lv
		lvl.add_theme_font_size_override("font_size", 11)
		lvl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		hb.add_child(lvl)
	vb.add_child(hb)
	if u == null:
		var dash := Label.new()
		dash.text = "統計中…"
		dash.add_theme_font_size_override("font_size", 12)
		dash.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
		vb.add_child(dash)
		return card
	# 負荷量表（context 佔用 → 遊戲字眼）
	var ctx := int(u.get("context_now", 0))
	var frac: float = float(ctx) / CONTEXT_MAX
	var word: String = LOAD_OVER[0]
	var wcol: Color = LOAD_OVER[1]
	for lw in LOAD_WORDS:
		if frac < float(lw[0]):
			word = lw[1]
			wcol = lw[2]
			break
	var clab := Label.new()
	clab.text = "負荷 %d%%  ·  %s" % [int(frac * 100.0), word]
	clab.add_theme_font_size_override("font_size", 11)
	clab.add_theme_color_override("font_color", wcol)
	vb.add_child(clab)
	var pb := ProgressBar.new()
	pb.max_value = CONTEXT_MAX
	pb.value = clamp(float(ctx), 0.0, CONTEXT_MAX)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 1.0)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	# 負荷越高越偏紅
	fill.bg_color = Color(0.35, 0.7, 0.45).lerp(Color(0.9, 0.4, 0.35), clamp(frac, 0.0, 1.0))
	fill.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	vb.add_child(pb)
	# 戰績：產出（out）/ 閱讀（in+cache）/ 回合
	var stats := Label.new()
	stats.text = "⚒ %s   📖 %s   🔁 %d" % [
		Util.fmt_tok(int(u.get("out", 0))),
		Util.fmt_tok(int(u.get("in", 0)) + int(u.get("cache", 0))),
		int(u.get("turns", 0)),
	]
	stats.add_theme_font_size_override("font_size", 12)
	stats.add_theme_color_override("font_color", Color(0.68, 0.72, 0.8))
	vb.add_child(stats)
	return card


# ── 人才庫（離職名單 + 重新雇用 + ✕ 移除）──────────────────────
func _rehire_row(d: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var btn := Button.new()
	btn.text = "↻ %s   %s" % [str(d.get("project", "?")), str(d.get("ago", ""))]
	btn.tooltip_text = "重新雇用：在 %s 開新終端、接續上次對話 (claude -c)" % str(d.get("cwd", ""))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Util.style_btn(btn, Color(0.16, 0.22, 0.30, 0.8), Color(0.22, 0.32, 0.44, 0.9), Color(0.85, 0.92, 1.0), 12)
	var cwd := str(d.get("cwd", ""))
	btn.pressed.connect(func(): rehire_requested.emit(cwd))
	row.add_child(btn)
	# 移除：不想再看到的專案；之後該專案有新活動會自動回到人才庫
	var rm := Button.new()
	rm.text = "✕"
	rm.tooltip_text = "從人才庫移除（該專案之後有新活動會再出現）"
	Util.style_btn(rm, Color(0.24, 0.14, 0.16, 0.8), Color(0.50, 0.20, 0.22, 0.9), Color(1.0, 0.8, 0.8), 11)
	rm.pressed.connect(func(): _hide_rehire(d))
	row.add_child(rm)
	return row


func _hide_rehire(d: Dictionary) -> void:
	# 記下「移除當下」的時間；本地與 usage_poll.py 都用 mtime <= 移除時間 過濾，
	# 該專案之後有新活動（mtime 變新）就會自動回到人才庫。
	var key := Util.norm_cwd(str(d.get("cwd", "")))
	if key == "":
		return
	_hidden[key] = Time.get_unix_time_from_system()
	Util.write_json(Paths.REHIRE_HIDDEN_FILE, _hidden)
	refresh(_robots_ref, _selected)   # 立即從畫面拿掉，不等下次輪詢


func _load_hidden() -> Dictionary:
	var j = Util.read_json_any(Paths.REHIRE_HIDDEN_FILE)
	return j if j is Dictionary else {}


func _load_departed() -> void:
	# 人才庫由 usage_poll.py 掃 ~/.claude/projects 寫出（近期用過、目前沒在跑的專案）
	var j = Util.read_json_any(Paths.REHIRE_FILE)
	var rows: Array = j if j is Array else []
	_departed = []
	for d in rows:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		# 移除後 usage_poll 還沒重掃的空窗期，本地照同一規則過濾，畫面不閃回
		var key := Util.norm_cwd(str(d.get("cwd", "")))
		if _hidden.has(key) and float(d.get("mtime", 0)) <= float(_hidden[key]):
			continue
		_departed.append(d)

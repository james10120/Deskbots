class_name UsageBoard
extends DragWindow
# 工作看板：在場 session 卡片（負荷量表 + LV + 產出/閱讀/回合 + 動作列）+ 全公司合計
# + 人才庫（可重新雇用的歷史專案，含 ✕ 移除）。
# 卡片本體＝聚焦該 session 終端（遠端開 VS Code）；卡片動作列＝快速指令（本地）。
# 資料來源：usage.json / rehire.json（usage_poll.py 寫）；robots 由 main 每次 refresh 傳入。

signal focus_requested(sid: String)                   # 點 session 卡片本體 → 聚焦該終端（遠端開 VS Code）
signal command_requested(sid: String, text: String)   # 卡片快速指令鈕 → 注入該終端（/clear /compact ⎋）
signal rehire_requested(cwd: String, host: String)    # 點人才庫列 → 本地開終端 claude -c；遠端開 VS Code

const USAGE_W := 260            # 看板視窗寬
const USAGE_MIN_H := 220        # 看板最小高（拉高把手的下限）
const CONTEXT_MAX := 200000.0   # 負荷量表的分母（context 上限；超過=超出負荷）
# 負荷比例 → 遊戲字眼（由低到高，取第一個達標的）；字串存 Lang key，渲染時才翻譯
const LOAD_WORDS := [
	[0.30, "load_relaxed", Color(0.55, 0.85, 0.60)],
	[0.55, "load_warming", Color(0.70, 0.85, 0.55)],
	[0.75, "load_focused", Color(0.95, 0.85, 0.45)],
	[0.90, "load_full", Color(1.00, 0.65, 0.35)],
	[1.00, "load_limit", Color(1.00, 0.45, 0.35)],
]
const LOAD_OVER := ["load_over", Color(1.0, 0.35, 0.30)]

var _box: VBoxContainer        # 卡片容器（每次刷新重建內容）
var _heading: Label            # 標題列文字（換語言時即時更新）
var _grip: Label               # 底部拉高把手文字
var _pin_btn: Button           # 釘選鈕（還原狀態時要同步外觀）
var _resizing := false         # 拖底部把手調整高度中
var _departed: Array = []      # 人才庫：可重新雇用的歷史專案 [{project, cwd, ago, mtime}]
var _hidden := {}              # 人才庫移除名單：norm_cwd -> 移除當下 unix 時間
var _robots_ref := {}          # 最近一次 refresh 的 robots（main 的同一份 dict，移除後立即重畫用）
var _selected := ""


func build() -> void:
	title = Lang.t("board_title")
	init_frame(Vector2i(USAGE_W, 380))
	close_requested.connect(hide)
	_hidden = _load_hidden()
	var vbox := build_card(6, 12, 14, Color(0.10, 0.11, 0.15, 0.62), Color(0.26, 0.30, 0.42, 0.7))
	vbox.add_theme_constant_override("separation", 8)
	# 標題列：標題（拖曳）+ 釘選 + 關閉
	var headrow := HBoxContainer.new()
	headrow.add_theme_constant_override("separation", 6)
	vbox.add_child(headrow)
	_heading = Label.new()
	_heading.text = Lang.t("board_heading")
	_heading.add_theme_font_size_override("font_size", 15)
	_heading.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make_drag_handle(_heading)
	headrow.add_child(_heading)
	_pin_btn = Button.new()
	_pin_btn.text = "📌"
	_pin_btn.toggle_mode = true
	_pin_btn.tooltip_text = Lang.t("board_pin_tip")
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
	_grip = Label.new()
	_grip.text = Lang.t("board_grip")
	_grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grip.add_theme_font_size_override("font_size", 10)
	_grip.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	_grip.gui_input.connect(_on_grip)
	vbox.add_child(_grip)


func relocalize() -> void:
	# 換語言：靜態文字即時更新；卡片/合計/人才庫由 refresh 重建（讀 Lang）立即跟上
	title = Lang.t("board_title")
	if _heading != null:
		_heading.text = Lang.t("board_heading")
	if _pin_btn != null:
		_pin_btn.tooltip_text = Lang.t("board_pin_tip")
	if _grip != null:
		_grip.text = Lang.t("board_grip")
	refresh(_robots_ref, _selected)


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
		_box.add_child(_usage_card(str(sid), r, col, u))
		shown += 1
		if u != null:
			t_in += int(u.get("in", 0))
			t_out += int(u.get("out", 0))
			t_cache += int(u.get("cache", 0))
			t_turns += int(u.get("turns", 0))
	if shown == 0:
		var empty := Label.new()
		empty.text = Lang.t("board_empty")
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
		_box.add_child(empty)
	else:
		# 全公司合計列
		_box.add_child(HSeparator.new())
		var tot := VBoxContainer.new()
		tot.add_theme_constant_override("separation", 1)
		var h := Label.new()
		h.text = Lang.t("board_company") % shown
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
		tot.add_child(h)
		var l := Label.new()
		l.text = Lang.t("board_totals") % [Util.fmt_tok(t_out), Util.fmt_tok(t_in + t_cache)]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		tot.add_child(l)
		var l2 := Label.new()
		l2.text = Lang.t("board_turns") % t_turns
		l2.add_theme_font_size_override("font_size", 12)
		l2.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		tot.add_child(l2)
		_box.add_child(tot)
	# 人才庫：近期用過、目前沒在跑的專案，一鍵重新雇用（claude -c 接續上次對話）
	if _departed.size() > 0:
		_box.add_child(HSeparator.new())
		var dh := Label.new()
		dh.text = Lang.t("board_rehire_head")
		dh.add_theme_font_size_override("font_size", 12)
		dh.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
		_box.add_child(dh)
		for d in _departed:
			_box.add_child(_rehire_row(d))


func _on_card_input(event: InputEvent, sid: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		focus_requested.emit(sid)


func _usage_card(sid: String, r, col: Color, u) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# 最近一次互動的 session 卡片高亮邊框
	sb.bg_color = Color(0.17, 0.20, 0.28, 0.78) if sid == _selected else Color(0.14, 0.15, 0.20, 0.72)
	if sid == _selected:
		sb.set_border_width_all(1)
		sb.border_color = Color(0.45, 0.6, 0.95, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	# 點卡片本體 = 聚焦該 session 終端（遠端開 VS Code）；快速指令鈕另走自己的 signal
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
	name.text = str(r.project)
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name)
	vb.add_child(hb)
	if u == null:
		var dash := Label.new()
		dash.text = Lang.t("board_computing")
		dash.add_theme_font_size_override("font_size", 12)
		dash.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
		vb.add_child(dash)
	else:
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
		clab.text = Lang.t("board_load") % [int(frac * 100.0), Lang.t(word)]
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
	# 動作列：本地→快速指令；遠端→開 VS Code；抓不到終端→提示
	vb.add_child(_card_actions(sid, r))
	return card


func _card_actions(sid: String, r) -> Control:
	# 遠端 session（鍵盤注入打不到遠端）→ 只給「開 VS Code」
	var host := str(r.get("host", ""))
	if host != "":
		var vbtn := Button.new()
		vbtn.text = Lang.t("vscode_open")
		vbtn.tooltip_text = Lang.t("vscode_open_tip") % [host, str(r.get("cwd", ""))]
		vbtn.focus_mode = Control.FOCUS_NONE
		vbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Util.style_btn(vbtn, Color(0.20, 0.34, 0.52, 0.85), Color(0.26, 0.42, 0.62, 0.95), Color(0.92, 0.96, 1.0), 12)
		vbtn.pressed.connect(func(): focus_requested.emit(sid))
		return vbtn
	# 本地但抓不到終端視窗（hwnd=0）→ 明確提示，不給按鈕（送字/聚焦都打不到）
	if int(r.get("hwnd", 0)) == 0:
		var warn := Label.new()
		warn.text = Lang.t("no_terminal")
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return warn
	# 本地有終端 → 快速指令鈕（送出後 winfocus 會先聚焦再注入）
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for q in [["/clear", "/clear"], ["/compact", "/compact"], ["⎋", "<ESC>"]]:
		var qb := Button.new()
		qb.text = q[0]
		qb.tooltip_text = Lang.t("cmd_tip") % q[1]
		qb.focus_mode = Control.FOCUS_NONE
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Util.style_btn(qb, Color(0.22, 0.24, 0.32, 0.85), Color(0.30, 0.33, 0.43, 0.95), Color(0.88, 0.92, 1.0), 12)
		var cmd: String = q[1]
		qb.pressed.connect(func(): command_requested.emit(sid, cmd))
		row.add_child(qb)
	return row


# ── 人才庫（離職名單 + 重新雇用 + ✕ 移除）──────────────────────
func _rehire_row(d: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var btn := Button.new()
	var host := str(d.get("host", ""))
	# 相對時間在 Godot 端依語言重算（用 mtime）；沒有 mtime 才退回資料層的 ago 字串
	var mt := float(d.get("mtime", 0.0))
	var ago := Lang.ago(Time.get_unix_time_from_system() - mt) if mt > 0.0 else str(d.get("ago", ""))
	btn.text = "↻ %s   %s" % [str(d.get("project", "?")), ago]
	if host != "":
		btn.tooltip_text = Lang.t("rehire_tip_remote") % [host, str(d.get("cwd", ""))]
	else:
		btn.tooltip_text = Lang.t("rehire_tip_local") % str(d.get("cwd", ""))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Util.style_btn(btn, Color(0.16, 0.22, 0.30, 0.8), Color(0.22, 0.32, 0.44, 0.9), Color(0.85, 0.92, 1.0), 12)
	var cwd := str(d.get("cwd", ""))
	btn.pressed.connect(func(): rehire_requested.emit(cwd, host))
	row.add_child(btn)
	# 移除：不想再看到的專案；之後該專案有新活動會自動回到人才庫
	var rm := Button.new()
	rm.text = "✕"
	rm.tooltip_text = Lang.t("rehire_rm_tip")
	Util.style_btn(rm, Color(0.24, 0.14, 0.16, 0.8), Color(0.50, 0.20, 0.22, 0.9), Color(1.0, 0.8, 0.8), 11)
	rm.pressed.connect(func(): _hide_rehire(d))
	row.add_child(rm)
	return row


func _hidden_key(d: Dictionary) -> String:
	# 移除名單的鍵：本地=norm_cwd；遠端加 label 前綴（不同伺服器可能有同路徑）
	var k := Util.norm_cwd(str(d.get("cwd", "")))
	var lbl := str(d.get("label", ""))
	return (lbl + ":" + k) if lbl != "" else k


func _hide_rehire(d: Dictionary) -> void:
	# 記下「移除當下」的時間；本地與 usage_poll.py 都用 mtime <= 移除時間 過濾，
	# 該專案之後有新活動（mtime 變新）就會自動回到人才庫。
	var key := _hidden_key(d)
	if key == "" or key.ends_with(":"):
		return
	_hidden[key] = Time.get_unix_time_from_system()
	Util.write_json(Paths.REHIRE_HIDDEN_FILE, _hidden)
	refresh(_robots_ref, _selected)   # 立即從畫面拿掉，不等下次輪詢


func _load_hidden() -> Dictionary:
	var j = Util.read_json_any(Paths.REHIRE_HIDDEN_FILE)
	return j if j is Dictionary else {}


func _load_departed() -> void:
	# 人才庫＝本地（usage_poll.py 掃 ~/.claude/projects）＋ 遠端（ssh_bridge 彙整各台）
	var rows: Array = []
	for p in [Paths.REHIRE_FILE, Paths.REHIRE_REMOTE_FILE]:
		var j = Util.read_json_any(p)
		if j is Array:
			rows.append_array(j)
	rows.sort_custom(func(a, b): return float(a.get("mtime", 0)) > float(b.get("mtime", 0)))
	_departed = []
	for d in rows:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		# 移除後輪詢還沒重掃的空窗期，本地照同一規則過濾，畫面不閃回
		var key := _hidden_key(d)
		if _hidden.has(key) and float(d.get("mtime", 0)) <= float(_hidden[key]):
			continue
		_departed.append(d)

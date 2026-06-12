class_name UpgradeWindow
extends DragWindow
# 🛠 強化卡：餵養 CLAUDE CODE（補能量）、用經費買物資、花物資升級三項（物資增速/門口防禦/戰力）。
# 直接呼叫 Economy（static）做交易，動作後即時重畫；開著時每 0.5s 刷新數值。

const W := 248

var placed := false           # 位置已知（拖過/上次留下）→ 重開沿用，不再置中
var _box: VBoxContainer       # 內容容器（每次刷新重建）
var _t := 0.0


func build() -> void:
	title = Lang.t("up_title")
	init_frame(Vector2i(W, 300))
	close_requested.connect(hide)
	var vbox := build_card(6, 12, 14, Color(0.10, 0.11, 0.15, 0.96), Color(0.30, 0.30, 0.42, 1.0))
	vbox.add_theme_constant_override("separation", 8)
	var headrow := HBoxContainer.new()
	headrow.add_theme_constant_override("separation", 6)
	vbox.add_child(headrow)
	var h := Label.new()
	h.text = Lang.t("up_title")
	h.add_theme_font_size_override("font_size", 15)
	h.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make_drag_handle(h)
	headrow.add_child(h)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.add_theme_font_size_override("font_size", 12)
	x.pressed.connect(hide)
	headrow.add_child(x)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_box)
	_refresh()


func open_at(pos: Vector2i) -> void:
	if not placed:
		position = pos
		placed = true
	_refresh()
	show()


func restore_position(p: Vector2i) -> void:
	position = p
	placed = true


func _process(delta: float) -> void:
	super._process(delta)   # 標題拖曳
	if visible:
		_t -= delta
		if _t <= 0.0:
			_t = 0.5
			_refresh()


func _refresh() -> void:
	if _box == null:
		return
	for c in _box.get_children():
		c.queue_free()
	# 資源列
	var res := Label.new()
	res.text = Lang.t("hud_econ") % [Util.fmt_tok(int(Economy.funds)), Util.fmt_tok(int(Economy.supplies))]
	res.add_theme_font_size_override("font_size", 13)
	res.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	_box.add_child(res)
	# 能量列
	var en := Label.new()
	en.text = Lang.t("up_energy") % int(Economy.energy / Economy.ENERGY_MAX * 100.0)
	en.add_theme_font_size_override("font_size", 13)
	en.add_theme_color_override("font_color", Color(0.85, 0.92, 0.7))
	_box.add_child(en)
	# 餵養（補能量）
	var can_feed := Economy.supplies >= Economy.FEED_COST and Economy.energy < Economy.ENERGY_MAX
	_box.add_child(_act(Lang.t("up_feed") % [int(Economy.FEED_GAIN), int(Economy.FEED_COST)], can_feed,
		Color(0.20, 0.42, 0.30), "feed"))
	# 經費買物資
	_box.add_child(_act(Lang.t("up_buy") % [int(Economy.BUY_COST), int(Economy.BUY_GAIN)], Economy.funds >= Economy.BUY_COST,
		Color(0.20, 0.34, 0.52), "buy"))
	_box.add_child(HSeparator.new())
	# 三項升級（花物資）
	for it in [["supply", Lang.t("up_supply")], ["defense", Lang.t("up_defense")], ["power", Lang.t("up_power")]]:
		_box.add_child(_upgrade_row(str(it[0]), str(it[1])))


func _act(text: String, enabled: bool, col: Color, action: String) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.clip_text = true
	Util.style_btn(b, col, col.lightened(0.12), Color(0.95, 0.98, 1.0), 12)
	b.pressed.connect(_do_action.bind(action))
	return b


func _do_action(action: String) -> void:
	if action == "feed":
		Economy.feed()
	elif action == "buy":
		Economy.buy_supplies()
	_refresh()


func _upgrade_row(key: String, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = Lang.t("up_row") % [label_text, int(Economy.up.get(key, 0))]
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.86, 0.9, 0.98))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var cost := Economy.upgrade_cost(key)
	var b := Button.new()
	b.text = Lang.t("up_btn") % Util.fmt_tok(cost)
	b.disabled = Economy.supplies < float(cost)
	Util.style_btn(b, Color(0.30, 0.26, 0.40), Color(0.40, 0.34, 0.52), Color(0.95, 0.92, 1.0), 12)
	b.pressed.connect(_buy_upgrade.bind(key))
	row.add_child(b)
	return row


func _buy_upgrade(key: String) -> void:
	Economy.buy_upgrade(key)
	_refresh()

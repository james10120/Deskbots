class_name SettingsWindow
extends DragWindow
# 設定卡：地圖置頂開關、工作看板開關、離開遊戲。
# 視窗只發 signal，實際動作（切置頂/開關看板/退出）由 main 處理。

signal pin_toggled(on: bool)      # 地圖永遠置頂
signal board_toggle_requested     # 顯示/隱藏工作看板
signal quit_requested             # 離開遊戲（啟動器會自動還原全域設定）

var placed := false        # 位置已知（拖過/上次留下）→ 重開沿用，不再置中
var _pin_chk: CheckButton


func build() -> void:
	title = "Deskbots 設定"
	init_frame(Vector2i(250, 220))
	close_requested.connect(hide)
	var vbox := build_card(6, 14, 14, Color(0.12, 0.13, 0.18, 0.97), Color(0.26, 0.30, 0.42, 1.0))
	vbox.add_theme_constant_override("separation", 10)
	# 標題列：標題（拖曳）+ 關閉
	var headrow := HBoxContainer.new()
	headrow.add_theme_constant_override("separation", 6)
	vbox.add_child(headrow)
	var heading := Label.new()
	heading.text = "⚙ 設定"
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make_drag_handle(heading)
	headrow.add_child(heading)
	var xbtn := Button.new()
	xbtn.text = "✕"
	xbtn.focus_mode = Control.FOCUS_NONE
	xbtn.add_theme_font_size_override("font_size", 12)
	xbtn.pressed.connect(hide)
	headrow.add_child(xbtn)
	# 地圖置頂（與右上角「釘選」鈕同一個狀態，開卡片時由 main 同步進來）
	_pin_chk = CheckButton.new()
	_pin_chk.text = "地圖永遠置頂"
	_pin_chk.focus_mode = Control.FOCUS_NONE
	_pin_chk.add_theme_font_size_override("font_size", 13)
	_pin_chk.toggled.connect(func(on): pin_toggled.emit(on))
	vbox.add_child(_pin_chk)
	# 工作看板開關（無狀態按鈕，避免和看板自己的 ✕ 失同步）
	var bbtn := Button.new()
	bbtn.text = "⚒ 顯示 / 隱藏工作看板"
	Util.style_btn(bbtn, Color(0.22, 0.24, 0.32), Color(0.30, 0.33, 0.43), Color(0.88, 0.92, 1.0), 13)
	bbtn.pressed.connect(func(): board_toggle_requested.emit())
	vbox.add_child(bbtn)
	vbox.add_child(HSeparator.new())
	# 離開遊戲
	var qbtn := Button.new()
	qbtn.text = "⏻ 離開遊戲"
	qbtn.tooltip_text = "關閉地圖；啟動器會自動停背景行程並還原全域設定"
	Util.style_btn(qbtn, Color(0.42, 0.16, 0.18), Color(0.58, 0.22, 0.24), Color(1.0, 0.88, 0.88), 14)
	qbtn.pressed.connect(func(): quit_requested.emit())
	vbox.add_child(qbtn)


func open_at(pos: Vector2i, pinned: bool) -> void:
	_pin_chk.set_pressed_no_signal(pinned)   # 開卡片時同步目前置頂狀態
	if not placed:   # 第一次開才用傳入的置中位置；之後原地重開
		position = pos
		placed = true
	show()


func restore_position(p: Vector2i) -> void:
	position = p
	placed = true


func set_pin_state(on: bool) -> void:
	if _pin_chk != null:
		_pin_chk.set_pressed_no_signal(on)

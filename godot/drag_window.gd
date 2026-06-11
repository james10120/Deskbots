class_name DragWindow
extends Window
# 無邊框透明卡片視窗的共用底座：
#   init_frame()        — 無邊框、不可縮放、透明等旗標一次設好（add_child 之後呼叫）
#   build_card()        — 外距 + 圓角卡片 + 直向容器，回傳容器供放內容
#   make_drag_handle()  — 把任一 Control 變成拖曳把手
# 拖曳作法：按下把手開始，_process 每幀跟著滑鼠移動，放開即停
# （不依賴 motion 事件，拖出把手範圍也不斷線）。

var _dragging := false
var _drag_off := Vector2i()


func init_frame(sz: Vector2i) -> void:
	size = sz
	borderless = true       # 移除 OS 視窗邊框，改用卡片自己的關閉鈕
	unresizable = true
	transparent_bg = true   # 去背：卡片外透明，只露出圓角卡片
	always_on_top = false
	visible = false
	set_flag(Window.FLAG_TRANSPARENT, true)


func build_card(margin: int, pad: int, radius: int, bg: Color, border: Color) -> VBoxContainer:
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		outer.add_theme_constant_override(m, margin)
	add_child(outer)
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = bg
	csb.set_corner_radius_all(radius)
	csb.set_border_width_all(1)
	csb.border_color = border
	csb.set_content_margin_all(pad)
	card.add_theme_stylebox_override("panel", csb)
	outer.add_child(card)
	var vbox := VBoxContainer.new()
	card.add_child(vbox)
	return vbox


func make_drag_handle(ctrl: Control) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.mouse_default_cursor_shape = Control.CURSOR_MOVE
	ctrl.gui_input.connect(_on_drag_input)


func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true
		_drag_off = DisplayServer.mouse_get_position() - position


func _process(_delta: float) -> void:
	if _dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			position = DisplayServer.mouse_get_position() - _drag_off
		else:
			_dragging = false

class_name SettingsWindow
extends DragWindow
# 設定卡：地圖置頂開關、工作看板開關、SSH 伺服器管理、離開遊戲。
# 視窗只發 signal，實際動作（切置頂/開關看板/裝伺服器/退出）由 main 處理。

signal pin_toggled(on: bool)      # 地圖永遠置頂
signal board_toggle_requested     # 顯示/隱藏工作看板
signal quit_requested             # 離開遊戲（啟動器會自動還原全域設定）
signal add_server_requested(host: String, label: String)   # 開終端跑安裝
signal vscode_requested(host: String)                      # 開 VS Code Remote
signal remove_server_requested(host: String)               # 從 servers.json 移除

var placed := false        # 位置已知（拖過/上次留下）→ 重開沿用，不再置中
var _pin_chk: CheckButton
var _srv_box: VBoxContainer   # 伺服器列容器（讀 servers.json + bridge.json 重畫）
var _host_input: LineEdit
var _srv_t := 0.0
var _srv_snapshot := ""       # 上次畫面的資料快照，沒變不重畫（避免按鈕閃爍）


func build() -> void:
	title = "Deskbots 設定"
	init_frame(Vector2i(300, 360))
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
	# SSH 伺服器（ssh_bridge 鏡像遠端 session 進地圖；清單熱載入）
	var sh := Label.new()
	sh.text = "🖥 SSH 伺服器"
	sh.add_theme_font_size_override("font_size", 13)
	sh.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	vbox.add_child(sh)
	_srv_box = VBoxContainer.new()
	_srv_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_srv_box)
	var addrow := HBoxContainer.new()
	addrow.add_theme_constant_override("separation", 6)
	vbox.add_child(addrow)
	_host_input = LineEdit.new()
	_host_input.placeholder_text = "user@ip 或 ssh 別名"
	_host_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_input.add_theme_font_size_override("font_size", 12)
	_host_input.text_submitted.connect(func(_t): _on_add())
	addrow.add_child(_host_input)
	var abtn := Button.new()
	abtn.text = "＋ 連線安裝"
	Util.style_btn(abtn, Color(0.20, 0.34, 0.52), Color(0.26, 0.42, 0.62), Color(0.92, 0.96, 1.0), 12)
	abtn.pressed.connect(_on_add)
	addrow.add_child(abtn)
	var ahint := Label.new()
	ahint.text = "會開新視窗自動設定（第一次需輸入該機密碼）"
	ahint.add_theme_font_size_override("font_size", 10)
	ahint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	vbox.add_child(ahint)
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
	_srv_snapshot = ""   # 開卡片立即重畫伺服器列
	_srv_t = 0.0
	show()


func _process(delta: float) -> void:
	super._process(delta)   # 標題拖曳
	if visible:
		_srv_t -= delta
		if _srv_t <= 0.0:
			_srv_t = 3.0
			_refresh_servers()   # 連線綠點/在場數跟著 bridge.json 更新


func _on_add() -> void:
	var host := _host_input.text.strip_edges()
	if host == "":
		return
	_host_input.text = ""
	# label 取 user@ip 的 @ 後段，地圖名牌「專案@label」比較短
	var label := host.get_slice("@", 1) if host.contains("@") else host
	add_server_requested.emit(host, label)


func _refresh_servers() -> void:
	var servers = Util.read_json_any(Paths.SERVERS_FILE)
	if not (servers is Array):
		servers = []
	var status = Util.read_json(Paths.BRIDGE_FILE)
	if status == null:
		status = {}
	var snap := JSON.stringify([servers, status])
	if snap == _srv_snapshot:
		return
	_srv_snapshot = snap
	for c in _srv_box.get_children():
		c.queue_free()
	if servers.is_empty():
		var none := Label.new()
		none.text = "（尚未設定遠端伺服器）"
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		_srv_box.add_child(none)
		return
	for sv in servers:
		if typeof(sv) != TYPE_DICTIONARY:
			continue
		_srv_box.add_child(_server_row(sv, status))


func _server_row(sv: Dictionary, status: Dictionary) -> Control:
	var host := str(sv.get("host", ""))
	var label := str(sv.get("label", host))
	var st: Dictionary = status.get(label, {})
	var on := bool(st.get("connected", false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var dot := ColorRect.new()
	dot.color = Color(0.4, 0.9, 0.5) if on else Color(0.6, 0.42, 0.42)
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var nm := Label.new()
	nm.text = "%s · %d 在場" % [label, int(st.get("sessions", 0))] if on else "%s · 未連線" % label
	nm.tooltip_text = host
	nm.add_theme_font_size_override("font_size", 12)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	var vb := Button.new()
	vb.text = "VS Code"
	vb.tooltip_text = "開 VS Code Remote-SSH 連到 %s" % host
	Util.style_btn(vb, Color(0.20, 0.34, 0.52), Color(0.26, 0.42, 0.62), Color(0.92, 0.96, 1.0), 11)
	vb.pressed.connect(func(): vscode_requested.emit(host))
	row.add_child(vb)
	var rm := Button.new()
	rm.text = "✕"
	rm.tooltip_text = "從清單移除（遠端 hooks 保留，可用 remote_install.py --remove 卸載）"
	Util.style_btn(rm, Color(0.24, 0.14, 0.16, 0.8), Color(0.50, 0.20, 0.22, 0.9), Color(1.0, 0.8, 0.8), 11)
	rm.pressed.connect(func(): remove_server_requested.emit(host))
	row.add_child(rm)
	return row


func restore_position(p: Vector2i) -> void:
	position = p
	placed = true


func set_pin_state(on: bool) -> void:
	if _pin_chk != null:
		_pin_chk.set_pressed_no_signal(on)

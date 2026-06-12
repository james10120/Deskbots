class_name Lang
# 介面語言：中(zh)／英(en) 字串表。靜態無狀態，行程內共享 locale。
# UI 各處用 Lang.t("key")；含 %s/%d 的字串，格式相同、由呼叫端 % 進去。
# 動態內容（看板卡片、伺服器列）靠各自的刷新計時換語言，靜態文字由 relocalize() 即時換。

static var locale := "zh"

const STR := {
	"zh": {
		# main.gd —— 右上角小鈕 / 提示 / 對話框 / 玩家
		"c_pin": "釘選",
		"c_pin_tip": "釘選：地圖永遠置頂（再按取消）",
		"c_board": "看板",
		"c_board_tip": "顯示/隱藏工作看板",
		"c_settings": "設定",
		"c_settings_tip": "設定：置頂/看板開關、語言、離開遊戲",
		"hook_hint": "尚未偵測到 Claude Code hook\n\n正常雙擊 Deskbots.exe 會自動安裝；若仍看到此訊息，\n多半是找不到 Python（py）——請先安裝 Python，\n或手動執行一次  py app\\apply_settings.py，\n再開新的 Claude session。",
		"filedialog_title": "選擇專案資料夾 → 開新 PowerShell 跑 claude",
		"player_name": "你",
		# usage_board.gd
		"board_title": "Deskbots 工作看板",
		"board_heading": "⚒ 工作看板",
		"board_pin_tip": "釘選看板：永遠置頂（與地圖分開）",
		"board_grip": "··· 拖此調整高度 ···",
		"board_empty": "辦公室空無一人…",
		"board_company": "🏢 全公司 · %d 人上工",
		"board_totals": "⚒ 產出 %s   📖 閱讀 %s",
		"board_turns": "🔁 共 %d 回合",
		"board_rehire_head": "📋 人才庫 · 點擊重新雇用",
		"board_computing": "統計中…",
		"board_load": "負荷 %d%%  ·  %s",
		"load_relaxed": "游刃有餘",
		"load_warming": "漸入佳境",
		"load_focused": "全神貫注",
		"load_full": "火力全開",
		"load_limit": "瀕臨極限",
		"load_over": "⚠ 工作量超出負荷",
		"vscode_open": "▸ 在 VS Code 開啟",
		"vscode_open_tip": "開 VS Code Remote 到 %s 的 %s",
		"no_terminal": "⚠ 抓不到終端視窗（重開 session 才生效）",
		"cmd_tip": "送出 %s 給這個 session",
		"rehire_tip_remote": "開 VS Code Remote 到 %s 的 %s",
		"rehire_tip_local": "重新雇用：在 %s 開新終端、接續上次對話 (claude -c)",
		"rehire_rm_tip": "從人才庫移除（該專案之後有新活動會再出現）",
		"ago_min": "%d 分鐘前",
		"ago_hr": "%d 小時前",
		"ago_day": "%d 天前",
		# settings_window.gd
		"set_title": "Deskbots 設定",
		"set_heading": "⚙ 設定",
		"set_pin": "地圖永遠置頂",
		"set_board_btn": "⚒ 顯示 / 隱藏工作看板",
		"set_lang": "🌐 介面語言 / Language",
		"set_ssh": "🖥 SSH 伺服器",
		"set_host_ph": "user@ip 或 ssh 別名",
		"set_add": "＋ 連線安裝",
		"set_add_hint": "會開新視窗自動設定（第一次需輸入該機密碼）",
		"set_quit": "⏻ 離開遊戲",
		"set_quit_tip": "關閉地圖；啟動器會自動停背景行程並還原全域設定",
		"srv_none": "（尚未設定遠端伺服器）",
		"srv_on": "%s · %d 在場",
		"srv_off": "%s · 未連線",
		"srv_vscode_tip": "開 VS Code Remote-SSH 連到 %s",
		"srv_rm_tip": "從清單移除（遠端 hooks 保留，可用 remote_install.py --remove 卸載）",
	},
	"en": {
		"c_pin": "Pin",
		"c_pin_tip": "Pin: keep the map always on top (toggle)",
		"c_board": "Board",
		"c_board_tip": "Show / hide the work board",
		"c_settings": "Setup",
		"c_settings_tip": "Settings: pin / board toggle, language, quit",
		"hook_hint": "Claude Code hook not detected yet\n\nDouble-clicking Deskbots.exe normally installs it; if you still\nsee this, Python (py) is probably missing — install Python,\nor run  py app\\apply_settings.py  once,\nthen start a new Claude session.",
		"filedialog_title": "Pick a project folder → open a new PowerShell running claude",
		"player_name": "You",
		"board_title": "Deskbots Board",
		"board_heading": "⚒ Work Board",
		"board_pin_tip": "Pin board: always on top (separate from the map)",
		"board_grip": "··· drag to resize ···",
		"board_empty": "The office is empty…",
		"board_company": "🏢 Company · %d working",
		"board_totals": "⚒ Out %s   📖 Read %s",
		"board_turns": "🔁 %d turns",
		"board_rehire_head": "📋 Rehire · click to resume",
		"board_computing": "Measuring…",
		"board_load": "Load %d%%  ·  %s",
		"load_relaxed": "Cruising",
		"load_warming": "Warming up",
		"load_focused": "Locked in",
		"load_full": "Full throttle",
		"load_limit": "At the limit",
		"load_over": "⚠ Workload over capacity",
		"vscode_open": "▸ Open in VS Code",
		"vscode_open_tip": "Open VS Code Remote to %s at %s",
		"no_terminal": "⚠ No terminal window (restart the session to fix)",
		"cmd_tip": "Send %s to this session",
		"rehire_tip_remote": "Open VS Code Remote to %s at %s",
		"rehire_tip_local": "Rehire: open a new terminal at %s and resume (claude -c)",
		"rehire_rm_tip": "Remove from rehire (returns when the project sees new activity)",
		"ago_min": "%dm ago",
		"ago_hr": "%dh ago",
		"ago_day": "%dd ago",
		"set_title": "Deskbots Settings",
		"set_heading": "⚙ Settings",
		"set_pin": "Keep map always on top",
		"set_board_btn": "⚒ Show / hide work board",
		"set_lang": "🌐 介面語言 / Language",
		"set_ssh": "🖥 SSH servers",
		"set_host_ph": "user@ip or ssh alias",
		"set_add": "＋ Connect & install",
		"set_add_hint": "Opens a new window to set up (first time needs that host's password)",
		"set_quit": "⏻ Quit",
		"set_quit_tip": "Close the map; the launcher stops background processes and restores global settings",
		"srv_none": "(no remote servers configured)",
		"srv_on": "%s · %d online",
		"srv_off": "%s · offline",
		"srv_vscode_tip": "Open VS Code Remote-SSH to %s",
		"srv_rm_tip": "Remove from list (remote hooks stay; uninstall with remote_install.py --remove)",
	},
}


static func t(key: String) -> String:
	var tbl: Dictionary = STR.get(locale, STR["zh"])
	if tbl.has(key):
		return str(tbl[key])
	return str(STR["zh"].get(key, key))   # 缺字退回中文，再退回 key 本身


static func set_locale(loc: String) -> void:
	locale = "en" if loc == "en" else "zh"


static func detect() -> String:
	# 首次啟動（無存檔）依 OS 語系猜：zh* → 中文，其餘 → 英文
	return "zh" if OS.get_locale().begins_with("zh") else "en"


static func ago(sec: float) -> String:
	# 相對時間，依目前語言（給人才庫用；對齊 usage_poll.py 的級距）
	if sec < 3600.0:
		return t("ago_min") % max(1, int(sec / 60.0))
	if sec < 86400.0:
		return t("ago_hr") % int(sec / 3600.0)
	return t("ago_day") % int(sec / 86400.0)

class_name Economy
# 末日避難所經濟（MVP：只負責「賺」與存檔）。
#
# 設定：末日中，倖存者(session)在工作站持續產出，替避難所累積「物資」。
# 收入綁真實工作量——讀 usage.json 的 out token / 回合「增量」累進到持久庫存。
# 全 static、行程內共享（像 Util / Lang，免 autoload）。存檔在 runtime/economy.json，
# 刻意不列入乾淨模式的清理，讓進度跨次保留。
#
# 之後的「花費」（蓋樓擴建、扭蛋、升級）再疊在這層之上。

const RATE_OUT_PER_1K := 10.0   # 每 1k output token 換得的物資
const RATE_PER_TURN := 5.0      # 每完成一個回合換得的物資
const XP_PER_LEVEL := 10000.0   # 等級曲線分母：LV = 1 + sqrt(累積產出 / 此值)（sqrt → 只升不降、永不封頂）

static var supplies := 0.0       # 物資總庫存（持久）
static var today := 0.0          # 今日累積收入
static var _day := ""            # 今日日期 key（跨日重置 today）
static var _seen := {}           # sid -> {"out", "turns"} 上次見到的累計值（算增量基準）
static var proj_xp := {}         # 專案名 -> 歷來累積 output token（員工等級的依據，持久、只增）
static var _dirty := false       # 有變動待存檔


static func load_state() -> void:
	var j = Util.read_json(Paths.ECONOMY_FILE)
	if j == null:
		_day = _today_key()
		return
	supplies = float(j.get("supplies", 0.0))
	today = float(j.get("today", 0.0))
	_day = str(j.get("day", _today_key()))
	var px = j.get("proj_xp", {})
	proj_xp = px if typeof(px) == TYPE_DICTIONARY else {}
	if _day != _today_key():   # 開機就已跨日 → 今日歸零
		today = 0.0
		_day = _today_key()


static func save_state() -> void:
	Util.write_json(Paths.ECONOMY_FILE, {"supplies": supplies, "today": today, "day": _day, "proj_xp": proj_xp})
	_dirty = false


static func level_for(project: String) -> int:
	# 員工(專案)等級：依歷來累積產出，sqrt 曲線——升得越來越慢但永遠往上、不封頂、不重置
	var xp := float(proj_xp.get(project, 0.0))
	return 1 + int(sqrt(xp / XP_PER_LEVEL))


static func flush() -> void:
	# 有變動才寫檔（main 定期呼叫）
	if _dirty:
		save_state()


static func tick(usage, sid_proj = {}) -> void:
	# 每秒呼叫：依 usage.json 各 session 的 out/turns 增量累進物資；
	# 同時把 output 增量計入該 session 所屬「專案」的累積 XP（員工等級用）。
	# sid_proj: { sid -> 專案名 }（由 main 從 _robots 提供）。
	if typeof(usage) != TYPE_DICTIONARY:
		return
	if typeof(sid_proj) != TYPE_DICTIONARY:
		sid_proj = {}
	var k := _today_key()
	if k != _day:              # 跨日 → 今日歸零
		_day = k
		today = 0.0
		_dirty = true
	var live := {}
	for sid in usage:
		var u = usage[sid]
		if typeof(u) != TYPE_DICTIONARY:
			continue
		live[sid] = true
		var out := int(u.get("out", 0))
		var turns := int(u.get("turns", 0))
		var base = _seen.get(sid, null)
		# 新 session，或計數被重置（poller 重啟 / 換 transcript）→ 重設基準、不倒扣
		if base == null or out < int(base.get("out", 0)) or turns < int(base.get("turns", 0)):
			_seen[sid] = {"out": out, "turns": turns}
			continue
		var d_out := out - int(base.get("out", 0))
		var d_turns := turns - int(base.get("turns", 0))
		if d_out > 0 or d_turns > 0:
			var gain: float = d_out / 1000.0 * RATE_OUT_PER_1K + d_turns * RATE_PER_TURN
			supplies += gain
			today += gain
			# 員工等級 XP：output 增量累計到該專案（持久、只增）
			var pj := str(sid_proj.get(sid, ""))
			if pj != "" and d_out > 0:
				proj_xp[pj] = float(proj_xp.get(pj, 0.0)) + d_out
			_dirty = true
		_seen[sid] = {"out": out, "turns": turns}
	# 清掉已離場 session 的基準，避免無限長
	for sid in _seen.keys():
		if not live.has(sid):
			_seen.erase(sid)


static func _today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

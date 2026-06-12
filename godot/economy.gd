class_name Economy
# 末日避難所經濟（MVP：只負責「賺」與存檔）。
#
# 設定：末日中，倖存者(session)在工作站持續產出，替避難所累積「物資」。
# 收入綁真實工作量——讀 usage.json 的 out token / 回合「增量」累進到持久庫存。
# 全 static、行程內共享（像 Util / Lang，免 autoload）。存檔在 runtime/economy.json，
# 刻意不列入乾淨模式的清理，讓進度跨次保留。
#
# 之後的「花費」（蓋樓擴建、扭蛋、升級）再疊在這層之上。

const RATE_OUT_PER_1K := 10.0   # 每 1k output token 換得的「經費」
const RATE_PER_TURN := 5.0      # 每完成一個回合換得的「經費」
const XP_PER_LEVEL := 10000.0   # 等級曲線分母：LV = 1 + sqrt(累積產出 / 此值)（sqrt → 只升不降、永不封頂）
const SUPPLY_RATE := 1.0        # 放置時每秒被動產出的物資（基礎，受「物資增速」升級加成）
const BREACH_LOSS := 20.0       # 殭屍突破門口損失的物資（基礎，受「門口防禦」升級減免）
const ENERGY_MAX := 100.0       # CLAUDE CODE 能量上限
const ENERGY_DRAIN := 0.4       # 每秒能量下降（餵養補回）
const FEED_COST := 30.0         # 餵養一次花的物資
const FEED_GAIN := 25.0         # 餵養一次補的能量
const BUY_COST := 100.0         # 買物資一次花的經費
const BUY_GAIN := 100.0         # 買物資一次得的物資
const UP_BASE := 80.0           # 升級基礎成本（物資），逐級 ×1.7

# 雙貨幣：💵 經費＝工作賺（硬通貨）；📦 物資＝放置被動長＋擊退獎勵，拿去升級/餵養
static var funds := 0.0          # 經費總額（持久）
static var supplies := 0.0       # 物資總庫存（持久）
static var today := 0.0          # 今日物資進帳（被動+擊退）
static var energy := ENERGY_MAX  # CLAUDE CODE 能量（持久；低能量→變慢守不住）
static var up := {"supply": 0, "defense": 0, "power": 0}   # 升級等級（持久）
static var _day := ""            # 今日日期 key（跨日重置 today）
static var _seen := {}           # sid -> {"out", "turns"} 上次見到的累計值（算增量基準）
static var proj_xp := {}         # 專案名 -> 歷來累積 output token（員工等級的依據，持久、只增）
static var _dirty := false       # 有變動待存檔


static func load_state() -> void:
	var j = Util.read_json(Paths.ECONOMY_FILE)
	if j == null:
		_day = _today_key()
		return
	funds = float(j.get("funds", 0.0))
	supplies = float(j.get("supplies", 0.0))
	today = float(j.get("today", 0.0))
	energy = float(j.get("energy", ENERGY_MAX))
	var u = j.get("up", {})
	if typeof(u) == TYPE_DICTIONARY:
		up = {"supply": int(u.get("supply", 0)), "defense": int(u.get("defense", 0)), "power": int(u.get("power", 0))}
	_day = str(j.get("day", _today_key()))
	var px = j.get("proj_xp", {})
	proj_xp = px if typeof(px) == TYPE_DICTIONARY else {}
	if _day != _today_key():   # 開機就已跨日 → 今日歸零
		today = 0.0
		_day = _today_key()


static func save_state() -> void:
	Util.write_json(Paths.ECONOMY_FILE, {"funds": funds, "supplies": supplies, "today": today,
		"energy": energy, "up": up, "day": _day, "proj_xp": proj_xp})
	_dirty = false


# ── 升級效果（defense_strip / tick 讀這些）────────────────────────
static func supply_rate() -> float:
	return SUPPLY_RATE * (1.0 + 0.5 * int(up.get("supply", 0)))


static func breach_loss() -> float:
	return BREACH_LOSS * pow(0.75, int(up.get("defense", 0)))   # 每級突破損失 -25%


static func power_mult() -> float:
	return 1.0 + 0.25 * int(up.get("power", 0))   # 移速倍率


static func kill_range() -> float:
	return 13.0 + 4.0 * int(up.get("power", 0))   # 擊退範圍


static func energy_factor() -> float:
	# 能量越低越慢：滿能量 1.0、零能量 0.4
	return 0.4 + 0.6 * clampf(energy / ENERGY_MAX, 0.0, 1.0)


static func upgrade_cost(key: String) -> int:
	return int(UP_BASE * pow(1.7, int(up.get(key, 0))))


# ── 花費動作（強化卡用）；不足回 false ──────────────────────────
static func feed() -> bool:
	if supplies < FEED_COST or energy >= ENERGY_MAX:
		return false
	supplies -= FEED_COST
	energy = minf(ENERGY_MAX, energy + FEED_GAIN)
	_dirty = true
	return true


static func buy_supplies() -> bool:
	if funds < BUY_COST:
		return false
	funds -= BUY_COST
	supplies += BUY_GAIN
	_dirty = true
	return true


static func buy_upgrade(key: String) -> bool:
	if not up.has(key):
		return false
	var cost := upgrade_cost(key)
	if supplies < float(cost):
		return false
	supplies -= float(cost)
	up[key] = int(up[key]) + 1
	_dirty = true
	return true


static func reward(n: float) -> void:
	# 擊退殭屍等即時獎勵 → 進物資
	supplies += n
	today += n
	_dirty = true


static func on_breach() -> void:
	# 殭屍突破門口 → 損失物資（受門口防禦升級減免，不會變負）
	supplies = maxf(0.0, supplies - breach_loss())
	_dirty = true


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
			# 工作真實產出 → 賺經費（硬通貨）
			funds += d_out / 1000.0 * RATE_OUT_PER_1K + d_turns * RATE_PER_TURN
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
	# 放置：物資每秒被動增加（受升級加成）+ CLAUDE CODE 能量每秒下降（tick 約每秒一次）
	var sr := supply_rate()
	supplies += sr
	today += sr
	energy = maxf(0.0, energy - ENERGY_DRAIN)
	_dirty = true


static func _today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

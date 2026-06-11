class_name AssetStore
# 內嵌加密素材（assets.enc，AES-256-CBC）：發行包隨附完整美術，但不暴露原始 PNG
# （LimeZu 授權禁止散布素材「檔案」；嵌入遊戲並加密=業界正常使用+合理保護）。
# 載入優先序（main.gd / office_map.gd）：外部 assets/ 檔案 > assets.enc > 程式生成備援。
#
# 檔案格式（tools/pack_assets.gd 產生）：
#   "DBASSET1"(8B) + iv(16B) + plain_len(u64 LE) + AES-256-CBC 密文
#   明文 = u32 header長度 + header JSON {"files":[{"n":名稱,"s":大小},…]} + 各檔內容串接

static var _cache := {}      # name("characters/BOT1.png") -> Image
static var _loaded := false


static func image(name: String):
	# 回 Image；沒有（無金鑰/無檔/壞檔）回 null
	_ensure()
	return _cache.get(name)


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if AssetKey.KEY.length() != 64:
		return
	var f := FileAccess.open(Paths.ROOT + "/godot/assets.enc", FileAccess.READ)
	if f == null:
		return
	var raw := f.get_buffer(f.get_length())
	f.close()
	if raw.size() < 48 or raw.slice(0, 8).get_string_from_ascii() != "DBASSET1":
		return
	var iv := raw.slice(8, 24)
	var plain_len := raw.decode_u64(24)
	var cipher := raw.slice(32)
	var aes := AESContext.new()
	if aes.start(AESContext.MODE_CBC_DECRYPT, AssetKey.KEY.hex_decode(), iv) != OK:
		return
	var plain := aes.update(cipher)
	aes.finish()
	if plain.size() < plain_len:
		return
	plain = plain.slice(0, int(plain_len))
	var hlen := plain.decode_u32(0)
	var hdr = JSON.parse_string(plain.slice(4, 4 + hlen).get_string_from_utf8())
	if typeof(hdr) != TYPE_DICTIONARY:
		return
	var off := 4 + int(hlen)
	for e in hdr.get("files", []):
		var sz := int(e.get("s", 0))
		var img := Image.new()
		if img.load_png_from_buffer(plain.slice(off, off + sz)) == OK:
			_cache[str(e.get("n", ""))] = img
		off += sz

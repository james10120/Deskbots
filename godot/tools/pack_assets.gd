# 素材加密打包工具（package.ps1 呼叫；格式見 asset_store.gd）：
#   godot --headless --path godot --script tools/pack_assets.gd -- --key <64hex> --out <檔案>
# 把 assets/ 下的角色與瓦片集 PNG 打包成 AES-256-CBC 加密的 assets.enc。
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var key := ""
	var out := ""
	for i in range(args.size()):
		if args[i] == "--key" and i + 1 < args.size():
			key = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	if key.length() != 64 or out == "":
		push_error("用法：--key <64位hex> --out <輸出檔>")
		quit(1)
		return
	var names := []
	for i in range(1, 10):
		names.append("characters/BOT%d.png" % i)
	names.append_array(["tiled/Room_Builder_Office_16x16.png", "tiled/Modern_Office_16x16.png"])
	var root := ProjectSettings.globalize_path("res://..").rstrip("/")
	var files := []
	var blobs := PackedByteArray()
	for n in names:
		var f := FileAccess.open(root + "/assets/" + n, FileAccess.READ)
		if f == null:
			continue
		var d := f.get_buffer(f.get_length())
		f.close()
		files.append({"n": n, "s": d.size()})
		blobs.append_array(d)
	if files.is_empty():
		push_error("assets/ 沒有可打包的 PNG")
		quit(1)
		return
	var hdr := JSON.stringify({"files": files}).to_utf8_buffer()
	var plain := PackedByteArray()
	plain.resize(4)
	plain.encode_u32(0, hdr.size())
	plain.append_array(hdr)
	plain.append_array(blobs)
	var plain_len := plain.size()
	while plain.size() % 16 != 0:
		plain.append(0)
	var iv := Crypto.new().generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, key.hex_decode(), iv)
	var cipher := aes.update(plain)
	aes.finish()
	var o := FileAccess.open(out, FileAccess.WRITE)
	if o == null:
		push_error("無法寫出 " + out)
		quit(1)
		return
	o.store_buffer("DBASSET1".to_ascii_buffer())
	o.store_buffer(iv)
	o.store_64(plain_len)
	o.store_buffer(cipher)
	o.close()
	print("assets.enc 完成：%d 檔，%d bytes" % [files.size(), 32 + cipher.size()])
	quit(0)

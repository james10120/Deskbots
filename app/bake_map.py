"""把 Tiled 的 office.tmj 烘焙成 Godot 好讀的 map_baked.json。

Tiled 的圖層是 base64+zlib 壓縮的整數陣列；Godot 解 zlib 麻煩，
所以在這裡用 Python 解開，輸出每層的平面 GID 陣列 + tileset 資訊。
地圖更新後重跑這支即可（start_map.cmd 也會先跑它）。
"""
from __future__ import annotations

import base64
import json
import struct
import zlib
from collections import Counter
from pathlib import Path

TILED_DIR = Path(r"D:\Work\FunAI\assets\tiled")
TMJ = TILED_DIR / "office.tmj"

# 兩個 tileset（firstgid 來自 .tmj；圖檔已複製到 assets\tiled）
TILESETS = [
    {"firstgid": 1,   "image": "Room_Builder_Office_16x16.png", "columns": 16, "imagewidth": 256, "imageheight": 224},
    {"firstgid": 225, "image": "Modern_Office_16x16.png",       "columns": 16, "imagewidth": 256, "imageheight": 848},
]

FLIP_MASK = 0x1FFFFFFF  # 去掉 Tiled 的翻轉旗標位


def decode_layer(data_b64: str) -> list[int]:
    raw = zlib.decompress(base64.b64decode(data_b64))
    gids = struct.unpack("<%dI" % (len(raw) // 4), raw)
    return [g & FLIP_MASK for g in gids]


def main() -> None:
    m = json.loads(TMJ.read_text(encoding="utf-8"))
    out = {
        "width": m["width"],
        "height": m["height"],
        "tilewidth": m["tilewidth"],
        "tileheight": m["tileheight"],
        "tilesets": TILESETS,
        "layers": [],
    }
    for L in m["layers"]:
        if L.get("type") == "tilelayer":
            out["layers"].append({"name": L.get("name", ""), "data": decode_layer(L["data"])})

    # 障礙格：最底層(地板層)非地板瓦片(牆) 或 上層有家具 → 不可走
    n = out["width"] * out["height"]
    base = out["layers"][0]["data"] if out["layers"] else [0] * n
    floor_gid = Counter(g for g in base if g).most_common(1)[0][0]
    solid = []
    for idx in range(n):
        blocked = base[idx] != floor_gid  # 地板層的牆
        if not blocked:
            for L in out["layers"][1:]:    # 上層任何家具
                if L["data"][idx]:
                    blocked = True
                    break
        solid.append(1 if blocked else 0)
    out["solid"] = solid
    out["floor_gid"] = floor_gid

    (TILED_DIR / "map_baked.json").write_text(json.dumps(out), encoding="utf-8")
    print(f"烘焙完成：{len(out['layers'])} 層、{out['width']}x{out['height']} 格、"
          f"地板 GID={floor_gid}、障礙 {sum(solid)} 格")


if __name__ == "__main__":
    main()

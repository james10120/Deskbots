"""把 Tiled 模組依組裝順序拼成 Godot 好讀的 map_baked.json。

地圖由多個 11 格高的模組水平拼接而成（同「圖塊層 N」跨模組對齊）。
改 COMPOSITION 就能改辦公室佈局；地圖更新後重跑（start_map.cmd 也會跑它）。
"""
from __future__ import annotations

import base64
import json
import re
import struct
import zlib
from pathlib import Path

TILED_DIR = Path(r"D:\Work\FunAI\assets\tiled")

# 由左到右的模組組裝順序（檔名不含 .tmj）
COMPOSITION = [
    "office_entrance",   # 入口
    "office_lounge",     # 休息室
    "office_passage",    # 通道
    "office_room",       # 工作房
    "office_room",       # 工作房
    "office_passage",    # 通道
    "office_lounge",     # 休息室
    "office_end",        # 結束
]

# 兩個 tileset（firstgid 來自 .tmj；圖檔已在 assets\tiled）
TILESETS = [
    {"firstgid": 1,   "image": "Room_Builder_Office_16x16.png", "columns": 16},
    {"firstgid": 225, "image": "Modern_Office_16x16.png",       "columns": 16},
]

FLIP_MASK = 0x1FFFFFFF


def _decode(data_b64: str) -> list[int]:
    raw = zlib.decompress(base64.b64decode(data_b64))
    return [g & FLIP_MASK for g in struct.unpack("<%dI" % (len(raw) // 4), raw)]


def _load_module(name: str):
    m = json.loads((TILED_DIR / (name + ".tmj")).read_text(encoding="utf-8"))
    layers: dict[int, list[int]] = {}
    nav = None
    overlays: list[list[int]] = []
    for L in m["layers"]:
        if L.get("type") != "tilelayer":
            continue
        nm = L.get("name", "")
        if nm == "nav":                     # 走道標記層（不渲染，只當可走遮罩）
            nav = _decode(L["data"])
            continue
        if nm == "overlay":                 # 永遠畫在角色前面的層
            overlays.append(_decode(L["data"]))
            continue
        nums = re.findall(r"\d+", nm)
        if nums:
            layers[int(nums[0])] = _decode(L["data"])
    return layers, nav, overlays, int(m["width"]), int(m["height"])


def main() -> None:
    mods = [(_load_module(n)) for n in COMPOSITION]
    total_w = sum(w for _, _, _, w, _ in mods)
    H = mods[0][4]
    max_layer = max((max(L) if L else 0) for L, _, _, _, _ in mods)

    max_ov = max((len(ovs) for _, _, ovs, _, _ in mods), default=0)
    combined: dict[int, list[int]] = {n: [0] * (total_w * H) for n in range(1, max_layer + 1)}
    navmask = [0] * (total_w * H)
    overlays_out = [[0] * (total_w * H) for _ in range(max_ov)]   # 多個 overlay 層、保留順序
    xoff = 0
    for layers, nav, overlays, w, h in mods:
        for n, data in layers.items():
            for r in range(h):
                for c in range(w):
                    g = data[r * w + c]
                    if g:
                        combined[n][r * total_w + (xoff + c)] = g
        if nav:
            for r in range(h):
                for c in range(w):
                    if nav[r * w + c]:
                        navmask[r * total_w + (xoff + c)] = 1
        for k, ov in enumerate(overlays):
            for r in range(h):
                for c in range(w):
                    g = ov[r * w + c]
                    if g:
                        overlays_out[k][r * total_w + (xoff + c)] = g
        xoff += w

    out = {
        "width": total_w, "height": H, "tilewidth": 16, "tileheight": 16,
        "tilesets": TILESETS,
        "layers": [{"name": "L%d" % n, "data": combined[n]} for n in range(1, max_layer + 1)],
        "overlays": overlays_out,
        "solid": [0 if navmask[idx] else 1 for idx in range(total_w * H)],
    }

    (TILED_DIR / "map_baked.json").write_text(json.dumps(out), encoding="utf-8")
    print(f"烘焙完成：{len(COMPOSITION)} 模組 → {total_w}x{H}、{max_layer} 層、"
          f"可走 {sum(navmask)} 格、overlay {max_ov} 層")


if __name__ == "__main__":
    main()

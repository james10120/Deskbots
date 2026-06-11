"""把 Tiled 模組依組裝順序拼成 Godot 好讀的 map_baked.json。

地圖由多個 11 格高的模組水平拼接而成（同「圖塊層 N」跨模組對齊）。
改 COMPOSITION 就能改辦公室佈局；地圖更新後重跑（start_map.cmd 也會跑它）。

座位/休息點/等待點不再寫死在 Godot：每種模組在 MODULE_ANCHORS 定義一次
「模組內相對錨點」，烘焙時依拼接偏移換算成絕對格座標、就近配對後一起寫進
map_baked.json —— 任何 COMPOSITION（加房間、換順序）都自動得到正確地理。
"""
from __future__ import annotations

import base64
import json
import re
import struct
import zlib
from pathlib import Path

# 安裝根目錄＝本檔(app/)的上一層；整包可搬到任意位置
TILED_DIR = Path(__file__).resolve().parent.parent / "assets" / "tiled"

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

# 各模組的錨點（模組內相對格座標，皆須落在該模組 nav 可走格上）
#   seats   — 工作座位（face=面向 down/up）
#   waits   — 等待點（該房間的座位輪流使用）
#   lounges — 休息點（座位就近配對到最近的休息室）
MODULE_ANCHORS = {
    "office_room": {
        "seats": [
            {"col": 2, "row": 5, "face": "down"},
            {"col": 5, "row": 5, "face": "down"},
            {"col": 2, "row": 9, "face": "up"},
            {"col": 5, "row": 9, "face": "up"},
        ],
        "waits": [[1, 3], [4, 2], [8, 3], [6, 3]],
    },
    "office_lounge": {
        "lounges": [[1, 3], [3, 3], [1, 7], [3, 9]],
    },
}

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


def _assign_nearest(seats: list[dict], groups: list[list[list[int]]]) -> list[list[int]]:
    """每個座位配最近的點群（以群的平均欄位距離），群內輪流取點避免擠同一格。"""
    if not groups:
        return [[s["col"], s["row"]] for s in seats]   # 沒有該類模組：原地不動
    centers = [sum(c for c, _ in g) / len(g) for g in groups]
    taken = [0] * len(groups)
    out = []
    for s in seats:
        gi = min(range(len(groups)), key=lambda i: abs(centers[i] - s["col"]))
        g = groups[gi]
        out.append(g[taken[gi] % len(g)])
        taken[gi] += 1
    return out


def main() -> None:
    mods = [(_load_module(n)) for n in COMPOSITION]
    total_w = sum(w for _, _, _, w, _ in mods)
    H = mods[0][4]
    max_layer = max((max(L) if L else 0) for L, _, _, _, _ in mods)

    max_ov = max((len(ovs) for _, _, ovs, _, _ in mods), default=0)
    combined: dict[int, list[int]] = {n: [0] * (total_w * H) for n in range(1, max_layer + 1)}
    navmask = [0] * (total_w * H)
    overlays_out = [[0] * (total_w * H) for _ in range(max_ov)]   # 多個 overlay 層、保留順序
    seats: list[dict] = []                       # 絕對座標座位（模組由左到右）
    wait_groups: list[list[list[int]]] = []      # 每間房的等待點群
    lounge_groups: list[list[list[int]]] = []    # 每間休息室的休息點群
    xoff = 0
    for name, (layers, nav, overlays, w, h) in zip(COMPOSITION, mods):
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
        anchors = MODULE_ANCHORS.get(name, {})
        for s in anchors.get("seats", []):
            seats.append({"col": s["col"] + xoff, "row": s["row"], "face": s["face"]})
        if anchors.get("waits"):
            wait_groups.append([[c + xoff, r] for c, r in anchors["waits"]])
        if anchors.get("lounges"):
            lounge_groups.append([[c + xoff, r] for c, r in anchors["lounges"]])
        xoff += w

    # 每個座位配好自己的休息點/等待點，Godot 端零配對邏輯
    for s, lg, wt in zip(seats, _assign_nearest(seats, lounge_groups),
                         _assign_nearest(seats, wait_groups)):
        s["lounge"] = lg
        s["wait"] = wt

    out = {
        "width": total_w, "height": H, "tilewidth": 16, "tileheight": 16,
        "tilesets": TILESETS,
        "layers": [{"name": "L%d" % n, "data": combined[n]} for n in range(1, max_layer + 1)],
        "overlays": overlays_out,
        "solid": [0 if navmask[idx] else 1 for idx in range(total_w * H)],
        "seats": seats,
    }

    (TILED_DIR / "map_baked.json").write_text(json.dumps(out), encoding="utf-8")
    print(f"烘焙完成：{len(COMPOSITION)} 模組 → {total_w}x{H}、{max_layer} 層、"
          f"可走 {sum(navmask)} 格、overlay {max_ov} 層、座位 {len(seats)}")


if __name__ == "__main__":
    main()

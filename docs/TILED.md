# 用 Tiled 設計辦公室模組 → 烘焙拼接

地圖不是一張大圖，而是由多個 **11 格高的模組**水平拼接：
`bake_map.py` 依 `COMPOSITION` 順序把模組拼成 `map_baked.json`，Godot 只負責照著畫。
座位/休息點/等待點也在烘焙時依「模組錨點」自動算好——改佈局、加房間都不用碰 GDScript。

```
COMPOSITION（app/bake_map.py，由左到右）
entrance │ lounge │ passage │ room │ room │ passage │ lounge │ end
   1格       5格      1格      9格    9格     1格       5格     1格
```

---

## 1. 模組規格

- **Orientation**：Orthogonal，**Tile size：16×16**（務必，跟角色比例一致）
- **高度固定 11 格**，寬度自由（現有：entrance/passage/end=1、lounge=5、room=9）
- 存成 `assets/tiled/office_<名字>.tmj`（JSON 格式，圖層資料 Base64 + zlib）

## 2. 圖層命名規則（bake_map.py 認名字）

| 圖層名 | 用途 |
|--------|------|
| `圖塊層 N`（任何含數字的名字） | 一般渲染層，數字=疊放順序，跨模組同號對齊 |
| `nav` | **可走遮罩**（不渲染）：有畫=可走、空白=障礙。座位/休息/等待格都要標 |
| `overlay` | 永遠畫在角色**前面**的層（桌沿、椅背等遮擋物），可多層 |

## 3. 錨點（座位/休息/等待）

在 `app/bake_map.py` 的 `MODULE_ANCHORS` 為**每種模組**定義一次相對格座標：

```python
MODULE_ANCHORS = {
    "office_room": {
        "seats": [{"col": 2, "row": 5, "face": "down"}, ...],  # face=面向
        "waits": [[1, 3], [4, 2], ...],                        # 等待點
    },
    "office_lounge": {
        "lounges": [[1, 3], [3, 3], ...],                      # 休息點
    },
}
```

烘焙時依拼接偏移換算成絕對座標，並做**就近配對**：每個座位配最近休息室的點
（組內輪流取點，不會擠在同一格）。錨點必須落在該模組 `nav` 可走格上。

座標可用遊戲的 debug 格線讀：`godot --path godot -- --grid` 會在每格標 (col,row)。

## 4. 改佈局 / 加新模組

- **改佈局**：只改 `COMPOSITION` 陣列（加房間、換順序），重跑 `py app/bake_map.py`
  （啟動器每次都會自動跑，雙擊 `run_deskbots.cmd` 即生效）
- **加新模組**：畫新的 `office_<名字>.tmj`（含 `nav`，需要就加 `overlay`）→
  若有座位/休息點，在 `MODULE_ANCHORS` 加一條 → 加進 `COMPOSITION`

## 小抄

| 項目 | 設定 |
|------|------|
| Tile size | 16×16（務必），高度 11 格 |
| 匯出格式 | JSON (.tmj)，放 `assets/tiled/` |
| 可走標記 | `nav` 圖層（不渲染） |
| 前景遮擋 | `overlay` 圖層（可多層） |
| 座位等錨點 | `app/bake_map.py` 的 `MODULE_ANCHORS`（每種模組一次） |
| 佈局 | `app/bake_map.py` 的 `COMPOSITION` |

# 素材自備說明

本專案使用 [LimeZu](https://limezu.itch.io/) 的像素素材開發。**其授權允許用於遊戲/專案，
但禁止再散布素材檔案本身**，因此 repo / 發行包都不含這些 PNG——請自行取得後放入下列位置。
缺圖不會當機：地圖與角色會看不到，但名牌、看板等 UI 照常運作。

## 需要的檔案

| 放置路徑 | 內容 | 來源 |
|----------|------|------|
| `assets/characters/BOT1.png` ~ `BOT9.png` | 角色精靈表，**16×32/幀**，LimeZu 角色格式（每列一個動作、4 方向 × 6 幀；第 2 列站立、第 3 列走路、第 7 列滑手機、第 8 列看書） | [Modern Interiors](https://limezu.itch.io/moderninteriors) 的 Characters（免費版 Adam/Alex/… 即可，改名為 BOT1~9） |
| `assets/tiled/Room_Builder_Office_16x16.png` | 地板/牆瓦片集，16×16、每列 16 格 | [Modern Office Revamped](https://limezu.itch.io/modernoffice) |
| `assets/tiled/Modern_Office_16x16.png` | 辦公家具瓦片集，16×16、每列 16 格 | 同上 |

> 檔名與格線必須一致（`app/bake_map.py` 的 `TILESETS` 表寫死了 firstgid/columns）。
> 想用別的素材：同尺寸格線的瓦片集都可替換，地圖模組（`office_*.tmj`）引用的是格號不是圖片內容。

## 角色精靈表格式（換自製角色用）

- 每幀 **16×32 px**，方向序：右0 上1 左2 正3，每方向 6 幀
- 用到的列：第 2 列站立待機、第 3 列走路、第 7 列等待滑手機（12 幀正面）、第 8 列休息看書（12 幀正面）
- 放幾張算幾張（BOT1~BOT9，缺的會自動略過）

## 圖示

`assets/icon.png`（與 `godot/icon.png` 同圖）是本專案自己的 LOGO，已隨 repo 提供，不需另外準備。

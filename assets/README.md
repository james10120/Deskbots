# Bring your own assets / 素材自備說明

This project was built with pixel art by [LimeZu](https://limezu.itch.io/).
**LimeZu's license allows using the assets in projects but forbids redistributing the
asset files themselves**, so neither this repo nor the release zip contains the PNGs —
please obtain them and drop them into the paths below.
Missing art does not crash anything: the map and robots will be invisible, but
nameplates, the board and all UI still work.

## Required files

| Place at | What | Source |
|----------|------|--------|
| `assets/characters/BOT1.png` … `BOT9.png` | character sprite sheets, **16×32 per frame**, LimeZu character layout (one action per row, 4 directions × 6 frames; row 2 idle, row 3 walk, row 7 phone, row 8 reading) | [Modern Interiors](https://limezu.itch.io/moderninteriors) characters (the free Adam/Alex/… are fine — rename them to BOT1~9) |
| `assets/tiled/Room_Builder_Office_16x16.png` | floor/wall tileset, 16×16, 16 columns per row | [Modern Office Revamped](https://limezu.itch.io/modernoffice) |
| `assets/tiled/Modern_Office_16x16.png` | office furniture tileset, 16×16, 16 columns per row | same as above |

> File names and grid layout must match (`app/bake_map.py`'s `TILESETS` table hardcodes
> firstgid/columns). Any tileset with the same grid works as a substitute — the map
> modules (`office_*.tmj`) reference tile indices, not image contents.

## Character sheet format (for custom characters)

- Each frame **16×32 px**; direction order: right 0, up 1, left 2, down 3; 6 frames each
- Rows used: row 2 idle, row 3 walk, row 7 waiting/phone (12 frames, front-facing),
  row 8 resting/reading (12 frames, front-facing)
- Provide any subset of BOT1~BOT9 — missing ones are skipped automatically

## Icon

`assets/icon.png` (same image as `godot/icon.png`) is this project's own logo and ships
with the repo — nothing to prepare.

---

## 中文摘要

LimeZu 授權允許在專案中使用素材、但**禁止再散布素材檔案**，因此 repo 與發行包都不含 PNG。
請自行取得並放入上表位置：角色表 `BOT1~9.png`（16×32/幀，列 2 站立、列 3 走路、列 7 滑手機、
列 8 看書；免費版 Adam/Alex/… 改名即可）、兩張 16×16 瓦片集（檔名須一致）。
缺圖不會當機，只是地圖與角色看不到。`assets/icon.png` 是本專案自己的 LOGO，已隨 repo 提供。

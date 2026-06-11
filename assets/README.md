# Assets / 素材說明

**Deskbots works out of the box** — when the PNGs below are absent, the game generates
its own original flat-style office and little robots at runtime (100% original art,
no third-party license involved).

For the full pixel-art look, the project was designed around assets by
[LimeZu](https://limezu.itch.io/). **LimeZu's license allows using the assets in
projects but forbids redistributing the asset files**, so neither this repo nor the
release zip contains them — drop them into the paths below and the game upgrades
automatically.

## Optional upgrade files

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

**開箱即用**：沒放 PNG 時，遊戲會即時生成原創簡約風辦公室與小機器人（100% 本專案原創，
無第三方授權問題）。想要完整像素風，再放入 LimeZu 素材即自動升級：LimeZu 授權允許在
專案中使用、但**禁止再散布素材檔案**，因此 repo 與發行包都不含 PNG。放入位置見上表：
角色表 `BOT1~9.png`（16×32/幀，列 2 站立、列 3 走路、列 7 滑手機、列 8 看書；免費版
Adam/Alex/… 改名即可）、兩張 16×16 瓦片集（檔名須一致）。
`assets/icon.png` 是本專案自己的 LOGO，已隨 repo 提供。

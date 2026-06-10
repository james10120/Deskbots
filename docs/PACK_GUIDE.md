# Modern Interiors 完整版（moderninteriors-win）素材導覽

原始路徑：`D:\Work\GameDev\Resource\Pixel\Modern_Interiors\moderninteriors-win\`
（本專案要用的幾張已複製到 `D:\Work\FunAI\assets\tiled\`）

挑素材原則：**用 16×16 版本**（跟角色比例一致）。

---

## 最上層結構

| 資料夾 | 是什麼 | 用到嗎 |
|--------|--------|--------|
| **1_Interiors/** | 室內瓦片（地板/牆/家具），分 16/32/48px | ⭐ 主力 |
| **2_Characters/** | 角色（預製 + 自由拼裝組件） | 想換角色才用 |
| **3_Animated_objects/** | 317 個會動物件（gif 預覽 + 精靈表） | ⭐ 電腦/咖啡機/門 |
| **4_User_Interface_Elements/** | UI 元素、思考泡泡動畫 | ⭐ 之後做「!」「思考泡泡」 |
| **6_Home_Designs/** | 現成佈置好的整間房間設計 | 佈局參考/直接用 |
| Palettes / READ_ME.txt / LICENSE.txt | 調色盤、說明、授權 | — |

---

## 1_Interiors/16x16（主力）

- `Interiors_16x16.png` — **全家具總表**（16×1064 格，啥都有，超大）
- `Room_Builder_16x16.png` — 地板 + 牆總表
- `Room_Builder_subfiles/` — 房間建構件（拆開）：
  - `Room_Builder_Floors_16x16.png` — 地板
  - `Room_Builder_3d_walls_16x16.png` — **3D 牆面**（俯瞰立體牆，最推薦）
  - `Room_Builder_Walls_16x16.png` — 平面牆
  - `Room_Builder_Baseboards_16x16.png` — 踢腳板
  - `Room_Builder_borders_16x16.png` — 邊框
  - `Room_Builder_Arched_Entryways_16x16.png` — 拱門入口
  - `Room_Builder_Floor_Paths / Floor_Connectors / Floor_Shadows` — 地板路徑/接縫/陰影
- `Theme_Sorter/` — **按主題分類的家具（最好找東西的地方）**，26 個主題：
  - `1_Generic`（通用/辦公家具）⭐
  - `2_LivingRoom`（沙發、客廳）⭐
  - `3_Bathroom`、`4_Bedroom`
  - `5_Classroom_and_library`（課桌、書櫃）⭐
  - `6_Music_and_sport`、`7_Art`、`8_Gym`、`9_Fishing`
  - `10_Birthday_party`、`11_Halloween`、`12_Kitchen`
  - **`13_Conference_Hall`（會議廳/長桌）** ⭐
  - `14_Basement`、`15_Christmas`、`16_Grocery_store`、`17_Visible_Upstairs_System`
  - `18_Jail`、`19_Hospital`、`20_Japanese_interiors`、`21_Clothing_Store`
  - `22_Museum`、`23_Television_and_Film_Studio`、`24_Ice_Cream_Shop`、`25_Shooting_Range`、`26_Condominium`
- Theme_Sorter 變體（同家具、不同呈現）：
  - `Theme_Sorter_Singles` — **每件家具拆成獨立小圖**（在 Tiled 挑單品最方便）⭐
  - `Theme_Sorter_Black_Shadow` — 帶黑色陰影
  - `Theme_Sorter_Shadowless` — 無陰影
  - `..._Black_Shadow_Singles` / `..._Shadowless_Singles` — 上述的單件版
- `Old stuff/` — 舊版，略過

---

## 3_Animated_objects（會動的物件）

每個尺寸（16/32/48）下都有 `gif/`（看動畫預覽）和 `spritesheets/`（給程式播的精靈表）。共 317 個。對辦公室有用：
- `animated_coffee` — 咖啡機
- `animated_control_room_screens`、`animated_control_room_server` — **電腦螢幕/伺服器**
- `animated_*_monitor` — 螢幕
- `animated_door_*` — 門
- 還有各種燈、風扇、時鐘、寵物（cat）等

> 注意：放進 Tiled 只會顯示靜態第一格；要真的會動，得由程式讀精靈表播放（之後我做）。先在 Tiled 擺好位置即可。

---

## 4_User_Interface_Elements

- `UI_16x16.png` — 對話框、圖示、愛心等 UI 圖
- `UI_thinking_emotes_animation_16x16.png` — **思考泡泡動畫**（做 thinking/waiting 提示很適合）
- `Animated_Spritesheets/` — UI 動畫精靈表

---

## 2_Characters

- `Character_Generator/0_Premade_Characters/` — 預製角色（16/32/48），看 `Premade_Characters_LIST.png` 一覽
- `Character_Generator/{Bodies, Eyes, Hairstyles, Outfits, Accessories, Books, Smartphones}` — 角色組件（自由拼角色）；`*_kids` 是小孩版
- `Old/Single_Characters_Legacy/` — 舊版單一角色（目前免費版用的 Adam/Alex/Amelia/Bob 就屬這類格式）

---

## 6_Home_Designs（現成房間）

整間佈置好的設計，可當佈局靈感或直接整塊貼：
`Condominium_Designs`、`Generic_Home_Designs`、`Gym_Designs`、`Ice-Cream_Shop_Designs`、`Japanese_Interiors_Home_Designs`、`Museum_Designs`、`Shooting_Range_Designs`、`TV_Studio_Designs`（各有 16/32/48）

---

## 🎯 辦公室「去哪找」速查

| 要找 | 檔案 |
|------|------|
| 地板 | `Room_Builder_subfiles/Room_Builder_Floors_16x16.png` |
| 牆（立體） | `Room_Builder_subfiles/Room_Builder_3d_walls_16x16.png` |
| 會議長桌 | `Theme_Sorter/13_Conference_Hall_16x16.png`、`1_Generic` |
| 辦公桌/椅 | `Theme_Sorter/1_Generic`、`5_Classroom_and_library` |
| 沙發（休息室） | `Theme_Sorter/1_Generic`、`2_LivingRoom` |
| 植栽/地毯 | `Theme_Sorter/1_Generic` |
| 咖啡機/電腦（會動） | `3_Animated_objects/16x16/spritesheets/animated_coffee`、`animated_control_room_screens` |
| 思考泡泡/「!」 | `4_User_Interface_Elements/UI_16x16.png`、`UI_thinking_emotes_animation_16x16.png` |

辦公家具集中在 **1_Generic + 13_Conference_Hall + 5_Classroom**。挑單件用 **Theme_Sorter_Singles** 系列最方便。

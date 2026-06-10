# 用 Tiled 設計辦公室 → 交給我渲染

你在 Tiled 把辦公室排好、再用「物件」標記座位與休息點，匯出 `.tmj`，連同瓦片 PNG 給我。
我寫一個 Tiled 載入器，照你的排版原樣畫出地圖，機器人依你標的點去工作/休息。

---

## 1. 建立地圖

- Tiled → New Map
- **Orientation**：Orthogonal
- **Tile size**：**16 × 16 px**（一定要 16，才跟角色比例一致）
- **Map size**：建議 **17 × 11 格** 左右（我會用 4 倍放大 → 約 1088×704 的視窗）。
  想更大也行，我會把視窗配合你的地圖尺寸自動調整。

## 2. 加入瓦片集（Tilesets）

對每張要用的 PNG：Tiled → New Tileset →「Based on Tileset Image」
- Source：選 Modern Interiors 的 PNG，例如
  - `Room_Builder_subfiles/Room_Builder_Floors_16x16.png`（地板）
  - `Room_Builder_subfiles/Room_Builder_3d_walls_16x16.png`（牆）
  - `Theme_Sorter/1_Generic_16x16.png` 或 `Interiors_16x16.png`（家具：長桌、沙發、飲水機、植栽）
- **Tile width/height = 16**，Margin = 0，Spacing = 0

## 3. 畫圖層（Tile Layers）

建幾個圖層由下往上畫（圖層順序＝繪製順序）：
1. `floor`（地板鋪滿）
2. `walls`（外牆、隔間）
3. `furniture`（長桌、沙發、飲水機、植栽、地毯…）

> 想要會議長桌坐 6 人，就在 furniture 層把長桌拼出來、兩側留出椅子位置。

## 4. 標記「座位」與「休息點」（最關鍵）★

機器人要知道去哪坐、去哪休息 —— 用一個**物件層**告訴我：

- 新增一個 **Object Layer**（名字隨意，例如 `markers`）
- 用 **Insert Point**（點物件）放下標記，並在右側 **Name** 欄命名：
  - **6 個工作座位** → 每個點命名 `seat`
    （放在每張椅子/桌前該坐的位置；我會由左到右依序分配給 session）
  - **休息點** → 每個點命名 `lounge`
    （沙發座位、飲水機旁、想讓他們閒晃待著的點，放幾個都行）
- 點的位置 = 機器人會站/坐的位置（大概對準椅子即可，可微調）

> 之後想加變化也只要加命名點，例如 `door`（進場點）、`plant` 之類，跟我說新名字代表什麼即可。

## 5. 匯出

- File → **Export As** → **JSON map files (*.tmj)**，存成例如 `office.tmj`
- 瓦片集圖片：請把**用到的 PNG 複製到跟 `office.tmj` 同一個資料夾**
  （這樣 .tmj 裡的相對路徑我才找得到圖。或者在 Tiled 裡把 tileset「Embed in Map」後再匯出也可以，但 PNG 還是要給我。）

---

## 6. 交給我什麼

把這些放進 `D:\Work\FunAI\assets\tiled\`（資料夾自己建）：
1. `office.tmj`
2. 它用到的所有瓦片集 **PNG**（跟 .tmj 同資料夾）

然後跟我說一句：**「office.tmj 在 assets\tiled\ 了」** 即可。

我會做的事：
- 寫一個 `.tmj` 載入器，照圖層原樣渲染整間辦公室（取代目前的程式拼圖）
- 讀 `markers` 物件層：`seat` 點 → 6 個工作座位、`lounge` 點 → 休息點
- 機器人行為不變：工作時去 seat 坐、忙完走去 lounge 休息

---

## 小抄

| 項目 | 設定 |
|------|------|
| Tile size | 16×16（務必） |
| 匯出格式 | JSON (.tmj) |
| 座位標記 | Object Layer 裡命名 `seat` 的點（6 個） |
| 休息標記 | 命名 `lounge` 的點（數個） |
| 給我 | `office.tmj` + 用到的 PNG，放 `assets\tiled\` |

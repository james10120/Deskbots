# Deskbots 打包：匯出免安裝 exe + 組出發行 zip（不含 LimeZu 素材，授權禁止散布）
#
#   powershell -File app\package.ps1 [-Version 1.0.0]
#
# 產物：
#   godot\Deskbots.exe                  匯出的單檔遊戲（pck 內嵌）
#   dist\Deskbots-<版本>-win64.zip      解壓即用：放好素材（見 assets\README.md）
#                                       → 雙擊 app\run_deskbots.cmd
#
# 需求（打包機）：Godot 4.6 編輯器 + 對應版本 export templates。
param([string]$Version = 'dev')

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$Root = Split-Path $PSScriptRoot -Parent

# 找 Godot 編輯器（打包要用編輯器本體，不是匯出的 exe）
$Godot = $env:DESKBOTS_GODOT
if (-not $Godot -or -not (Test-Path $Godot)) {
    $cmd = Get-Command 'godot','godot4' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $Godot = $cmd.Source }
}
if (-not $Godot) {
    foreach ($dir in @("$env:LOCALAPPDATA\Programs\Godot", 'C:\Program Files\Godot', 'D:\Work\GameDev\Godot')) {
        $hit = Get-ChildItem $dir -Filter 'Godot*win64.exe' -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notmatch 'console' } | Select-Object -First 1
        if ($hit) { $Godot = $hit.FullName; break }
    }
}
if (-not $Godot) { throw '找不到 Godot 編輯器（設 DESKBOTS_GODOT 或加入 PATH）' }

$Proj = Join-Path $Root 'godot'
$Exe = Join-Path $Root 'godot\Deskbots.exe'
$KeyFile = Join-Path $Root 'config\asset_key.txt'
$KeyGd = Join-Path $Root 'godot\asset_key.gd'
$AssetsEnc = Join-Path $Root 'godot\assets.enc'

# ── 內嵌加密素材：本機有 LimeZu PNG 才做（金鑰不入庫，第一次自動產生）────
$HaveAssets = (Test-Path "$Root\assets\characters\BOT1.png") -and
              (Test-Path "$Root\assets\tiled\Modern_Office_16x16.png")
$Key = ''
if ($HaveAssets) {
    if (-not (Test-Path $KeyFile)) {
        New-Item -ItemType Directory -Force (Split-Path $KeyFile) | Out-Null
        $Key = -join ((1..64) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
        Set-Content $KeyFile $Key -Encoding ascii
        Write-Host "== 產生素材加密金鑰：$KeyFile（請保管，不入庫）=="
    }
    $Key = (Get-Content $KeyFile -Raw).Trim()
    Write-Host '== 加密素材 → godot\assets.enc =='
    Remove-Item $AssetsEnc -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $Godot -Wait -NoNewWindow `
        -ArgumentList "--headless --path `"$Proj`" --script tools/pack_assets.gd -- --key $Key --out `"$AssetsEnc`""
    if (-not (Test-Path $AssetsEnc)) { throw '素材加密失敗' }
} else {
    Write-Host '== 本機沒有 LimeZu 素材 → 發行包用程式生成備援畫風 =='
}

# 預先烘焙地圖（map_baked.json）放進發行包：直接雙擊 exe 或 bake 失敗時也有地圖
Write-Host '== 烘焙地圖 → assets\tiled\map_baked.json =='
& py "$Root\app\bake_map.py"
$Baked = Join-Path $Root 'assets\tiled\map_baked.json'
if (-not (Test-Path $Baked)) { throw '地圖烘焙失敗（map_baked.json 未產生）' }

Write-Host "== 匯出 godot\Deskbots.exe（$Godot）=="
Remove-Item $Exe -Force -ErrorAction SilentlyContinue   # 確保拿到的是本次匯出的新檔
# 匯出期間暫時把真實金鑰寫進 asset_key.gd（讓解密能力編進 exe），結束後還原占位版
# asset_key.gd 為純 ASCII 檔（PS 5.1 無 BOM 讀寫不傷內容）
$KeyGdBackup = Get-Content $KeyGd -Raw
if ($Key) {
    ($KeyGdBackup -replace 'const KEY := ""', "const KEY := `"$Key`"") | Set-Content $KeyGd -Encoding ascii
}
try {
    # Godot 編輯器是 GUI 程式，& 呼叫不會等它 → 必須 Start-Process -Wait，否則會打包到舊 exe
    # （ArgumentList 用單字串自帶引號：PS 5.1 不會幫含空白的參數補引號）
    Start-Process -FilePath $Godot -Wait -NoNewWindow `
        -ArgumentList "--headless --path `"$Proj`" --export-release `"Windows Desktop`""
} finally {
    Set-Content $KeyGd $KeyGdBackup -Encoding ascii   # 還原占位版，金鑰絕不入庫
}
if (-not (Test-Path $Exe)) { throw '匯出失敗（export templates 裝了嗎？）' }

Write-Host '== 組發行目錄 =='
$Stage = Join-Path $Root 'dist\Deskbots'
# 先停掉可能鎖住舊 stage exe 的殘留行程（否則 Remove/Copy 會失敗）
Get-Process Deskbots -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Stage\app", "$Stage\godot", "$Stage\assets\tiled", "$Stage\assets\characters", "$Stage\config", "$Stage\docs", "$Stage\runtime" | Out-Null

Copy-Item "$Root\app\*.py"  "$Stage\app\"
Copy-Item "$Root\app\*.cmd" "$Stage\app\"
Copy-Item "$Root\app\*.ps1" "$Stage\app\"
Copy-Item "$Root\godot\Deskbots.exe" "$Stage\godot\"
if (Test-Path $AssetsEnc) { Copy-Item $AssetsEnc "$Stage\godot\" }   # 內嵌加密素材
Copy-Item "$Root\assets\README.md"   "$Stage\assets\"
Copy-Item "$Root\assets\tiled\*.tmj" "$Stage\assets\tiled\"
Copy-Item $Baked "$Stage\assets\tiled\"   # 預烘地圖：免使用者端 bake 也能顯示
Copy-Item "$Root\assets\icon.png"    "$Stage\assets\"
Copy-Item "$Root\config\servers.example.json" "$Stage\config\"
Copy-Item "$Root\docs\*.md" "$Stage\docs\"
Copy-Item "$Root\README.md", "$Root\LICENSE" "$Stage\"

$Zip = Join-Path $Root "dist\Deskbots-$Version-win64.zip"
Remove-Item $Zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path $Stage -DestinationPath $Zip
Write-Host "== 完成：$Zip =="
Write-Host '   使用者解壓後：1) 照 assets\README.md 放素材  2) 雙擊 app\run_deskbots.cmd'

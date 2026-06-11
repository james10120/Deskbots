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

Write-Host "== 匯出 godot\Deskbots.exe（$Godot）=="
$Proj = Join-Path $Root 'godot'
& $Godot --headless --path $Proj --export-release 'Windows Desktop'
$Exe = Join-Path $Root 'godot\Deskbots.exe'
if (-not (Test-Path $Exe)) { throw '匯出失敗（export templates 裝了嗎？）' }

Write-Host '== 組發行目錄 =='
$Stage = Join-Path $Root 'dist\Deskbots'
Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Stage\app", "$Stage\godot", "$Stage\assets\tiled", "$Stage\assets\characters", "$Stage\config", "$Stage\docs", "$Stage\runtime" | Out-Null

Copy-Item "$Root\app\*.py"  "$Stage\app\"
Copy-Item "$Root\app\*.cmd" "$Stage\app\"
Copy-Item "$Root\app\*.ps1" "$Stage\app\"
Copy-Item "$Root\godot\Deskbots.exe" "$Stage\godot\"
Copy-Item "$Root\assets\README.md"   "$Stage\assets\"
Copy-Item "$Root\assets\tiled\*.tmj" "$Stage\assets\tiled\"
Copy-Item "$Root\assets\icon.png"    "$Stage\assets\"
Copy-Item "$Root\config\servers.example.json" "$Stage\config\"
Copy-Item "$Root\docs\*.md" "$Stage\docs\"
Copy-Item "$Root\README.md", "$Root\LICENSE" "$Stage\"

$Zip = Join-Path $Root "dist\Deskbots-$Version-win64.zip"
Remove-Item $Zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path $Stage -DestinationPath $Zip
Write-Host "== 完成：$Zip =="
Write-Host '   使用者解壓後：1) 照 assets\README.md 放素材  2) 雙擊 app\run_deskbots.cmd'

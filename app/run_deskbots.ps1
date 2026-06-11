# Deskbots 乾淨生命週期啟動器
#
# 開 → 用 → 關，全程不汙染現有環境：
#   1. 安裝 Deskbots 的 hooks / statusLine 到全域 ~/.claude/settings.json
#   2. 啟動用量輪詢（背景）+ 地圖（前景）
#   3. 地圖一關閉 → finally 區塊「一定」會跑：停背景行程、還原全域設定、清 Deskbots runtime
#
# try/finally 確保不管正常關閉、Godot 崩潰、還是 Ctrl+C，全域設定都會被還原。
# 由 run_deskbots.cmd 以 `-ExecutionPolicy Bypass` 呼叫（避免雙擊 .ps1 被執行原則擋）。
# -MapOnly：常駐模式（start_map.cmd 用）——不裝/不還原 hooks，只開地圖與背景行程。

param([switch]$MapOnly)

$ErrorActionPreference = 'Continue'
# cp950 主控台會把本腳本與 py 子行程的 UTF-8 中文輸出印成亂碼 → 切到 UTF-8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$env:PYTHONUTF8 = '1'   # 讓所有 py 子行程輸出也是 UTF-8（clean/bake 的中文才不亂碼）
$Root  = Split-Path $PSScriptRoot -Parent   # 安裝根目錄＝本腳本(app/)的上一層
$App   = $PSScriptRoot
$Runtime = Join-Path $Root 'runtime'

# ── 找 Godot：打包版exe → 環境變數 → PATH → 常見位置 ───────────────
function Find-Godot {
    $packed = Join-Path $Root 'godot\Deskbots.exe'         # 打包版（package.ps1 產出）
    if (Test-Path $packed) { return $packed }
    if ($env:DESKBOTS_GODOT -and (Test-Path $env:DESKBOTS_GODOT)) { return $env:DESKBOTS_GODOT }
    $cmd = Get-Command 'godot','godot4' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($dir in @("$env:LOCALAPPDATA\Programs\Godot", 'C:\Program Files\Godot', 'D:\Work\GameDev\Godot')) {
        $hit = Get-ChildItem $dir -Filter 'Godot*win64.exe' -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notmatch 'console' } | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}
$Godot = Find-Godot
if (-not $Godot) {
    Write-Host '!! 找不到 Godot。請（擇一）：'
    Write-Host '   1. 使用打包版（godot\Deskbots.exe，見 README 的「打包」一節）'
    Write-Host '   2. 設環境變數 DESKBOTS_GODOT=<Godot exe 完整路徑>'
    Write-Host '   3. 把 Godot 4.6 加入 PATH'
    pause
    exit 1
}

if (-not $MapOnly) {
    Write-Host '== Deskbots：安裝 hooks / statusLine（離開時會自動還原）=='
    & py "$App\apply_settings.py"
}
& py "$App\clean_sessions.py"
& py "$App\bake_map.py"

$usage = $null
$bridge = $null
try {
    Write-Host '== 啟動用量輪詢（背景，最小化）=='
    $usage = Start-Process -FilePath 'py' -ArgumentList "$App\usage_poll.py" `
                           -WindowStyle Minimized -PassThru

    # SSH 橋接：鏡像遠端伺服器的 session 進地圖。servers.json 熱載入，
    # 沒設定也先跑著（之後在遊戲設定卡「＋ 連線安裝」就會自動生效）
    Write-Host '== 啟動 SSH 橋接（背景，最小化）=='
    $bridge = Start-Process -FilePath 'py' -ArgumentList "$App\ssh_bridge.py" `
                            -WindowStyle Minimized -PassThru

    Write-Host '== 啟動地圖 —— 關閉地圖視窗即會自動還原環境 =='
    if ((Split-Path $Godot -Leaf) -eq 'Deskbots.exe') {
        Start-Process -FilePath $Godot -Wait                # 打包版：專案已內嵌
    } else {
        Start-Process -FilePath $Godot -ArgumentList '--path', (Join-Path $Root 'godot') -Wait
    }
}
finally {
    Write-Host ''
    Write-Host '== 清理中：停背景行程 =='
    # 殺整個 process tree（py.exe 會生 python 子行程，/T 才連子帶孫清乾淨）
    if ($usage -and -not $usage.HasExited) {
        taskkill /PID $usage.Id /T /F 2>$null | Out-Null
    }
    if ($bridge -and -not $bridge.HasExited) {
        taskkill /PID $bridge.Id /T /F 2>$null | Out-Null
    }
    if (-not $MapOnly) {
        & py "$App\apply_settings.py" --remove
        # 清掉 Deskbots 自己的 runtime 暫存（不屬於使用者環境，下次開乾淨）
        Remove-Item "$Runtime\sessions\*.json" -Force -ErrorAction SilentlyContinue
        Remove-Item "$Runtime\usage.json"      -Force -ErrorAction SilentlyContinue
        Write-Host '== 已還原，環境乾淨。 =='
    }
}

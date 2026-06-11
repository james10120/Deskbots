# Deskbots 乾淨生命週期啟動器
#
# 開 → 用 → 關，全程不汙染現有環境：
#   1. 安裝 Deskbots 的 hooks / statusLine 到全域 ~/.claude/settings.json
#   2. 啟動用量輪詢（背景）+ 地圖（前景）
#   3. 地圖一關閉 → finally 區塊「一定」會跑：停背景行程、還原全域設定、清 Deskbots runtime
#
# try/finally 確保不管正常關閉、Godot 崩潰、還是 Ctrl+C，全域設定都會被還原。
# 由 run_funai.cmd 以 `-ExecutionPolicy Bypass` 呼叫（避免雙擊 .ps1 被執行原則擋）。

$ErrorActionPreference = 'Continue'
# cp950 主控台會把本腳本與 py 子行程的 UTF-8 中文輸出印成亂碼 → 切到 UTF-8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$env:PYTHONUTF8 = '1'   # 讓所有 py 子行程輸出也是 UTF-8（clean/bake 的中文才不亂碼）
$Root  = Split-Path $PSScriptRoot -Parent   # 安裝根目錄＝本腳本(app/)的上一層
$App   = $PSScriptRoot
$Godot = 'D:\Work\GameDev\Godot\Godot_v4.6.3-stable_win64.exe'
$Runtime = Join-Path $Root 'runtime'

Write-Host '== Deskbots：安裝 hooks / statusLine（離開時會自動還原）=='
& py "$App\apply_settings.py"
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
    Start-Process -FilePath $Godot -ArgumentList '--path', (Join-Path $Root 'godot') -Wait
}
finally {
    Write-Host ''
    Write-Host '== 清理中：停背景行程 + 還原全域設定 =='
    # 殺整個 process tree（py.exe 會生 python 子行程，/T 才連子帶孫清乾淨）
    if ($usage -and -not $usage.HasExited) {
        taskkill /PID $usage.Id /T /F 2>$null | Out-Null
    }
    if ($bridge -and -not $bridge.HasExited) {
        taskkill /PID $bridge.Id /T /F 2>$null | Out-Null
    }
    & py "$App\apply_settings.py" --remove
    # 清掉 Deskbots 自己的 runtime 暫存（不屬於使用者環境，下次開乾淨）
    Remove-Item "$Runtime\sessions\*.json" -Force -ErrorAction SilentlyContinue
    Remove-Item "$Runtime\usage.json"      -Force -ErrorAction SilentlyContinue
    Write-Host '== 已還原，環境乾淨。 =='
}

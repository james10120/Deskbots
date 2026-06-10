# FunAI 乾淨生命週期啟動器
#
# 開 → 用 → 關，全程不汙染現有環境：
#   1. 安裝 FunAI 的 hooks / statusLine 到全域 ~/.claude/settings.json
#   2. 啟動用量輪詢（背景）+ 地圖（前景）
#   3. 地圖一關閉 → finally 區塊「一定」會跑：停背景行程、還原全域設定、清 FunAI runtime
#
# try/finally 確保不管正常關閉、Godot 崩潰、還是 Ctrl+C，全域設定都會被還原。
# 由 run_funai.cmd 以 `-ExecutionPolicy Bypass` 呼叫（避免雙擊 .ps1 被執行原則擋）。

$ErrorActionPreference = 'Continue'
$App   = 'D:\Work\FunAI\app'
$Godot = 'D:\Work\GameDev\Godot\Godot_v4.6.3-stable_win64.exe'
$Runtime = 'D:\Work\FunAI\runtime'

Write-Host '== FunAI：安裝 hooks / statusLine（離開時會自動還原）=='
& py "$App\apply_settings.py"
& py "$App\clean_sessions.py"
& py "$App\bake_map.py"

$usage = $null
try {
    Write-Host '== 啟動用量輪詢（背景，最小化）=='
    $usage = Start-Process -FilePath 'py' -ArgumentList "$App\usage_poll.py" `
                           -WindowStyle Minimized -PassThru

    Write-Host '== 啟動地圖 —— 關閉地圖視窗即會自動還原環境 =='
    Start-Process -FilePath $Godot -ArgumentList '--path', 'D:\Work\FunAI\godot' -Wait
}
finally {
    Write-Host ''
    Write-Host '== 清理中：停背景行程 + 還原全域設定 =='
    # 殺整個 process tree（py.exe 會生 python 子行程，/T 才連子帶孫清乾淨）
    if ($usage -and -not $usage.HasExited) {
        taskkill /PID $usage.Id /T /F 2>$null | Out-Null
    }
    & py "$App\apply_settings.py" --remove
    # 清掉 FunAI 自己的 runtime 暫存（不屬於使用者環境，下次開乾淨）
    Remove-Item "$Runtime\sessions\*.json" -Force -ErrorAction SilentlyContinue
    Remove-Item "$Runtime\usage.json"      -Force -ErrorAction SilentlyContinue
    Write-Host '== 已還原，環境乾淨。 =='
}

# FunAI 機器人地圖啟動器 —— 清殭屍 + 常駐啟動地圖（背景，不佔終端）
# 用法：  ! D:\Work\FunAI\app\start_map.ps1

$ErrorActionPreference = 'SilentlyContinue'

$godot = 'D:\Work\GameDev\Godot\Godot_v4.6.3-stable_win64.exe'
$proj  = 'D:\Work\FunAI\godot'

# 1) 清掉殭屍 session
py D:\Work\FunAI\app\clean_sessions.py

# 2) 若已在跑就先關掉舊的（避免重複疊視窗）
Get-Process -Name 'Godot_v4.6.3-stable_win64' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $godot } | Stop-Process -Force -ErrorAction SilentlyContinue

# 3) 常駐啟動（detached，關掉終端也會繼續跑）
Start-Process -FilePath $godot -ArgumentList '--path', $proj
Write-Host "✅ 機器人地圖已啟動。開新的 Claude Code session 就會出現角色。"

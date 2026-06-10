@echo off
REM FunAI 機器人地圖啟動器 —— 雙擊即可，或在終端執行
REM 清殭屍 session，再背景常駐啟動地圖

py "D:\Work\FunAI\app\clean_sessions.py"
py "D:\Work\FunAI\app\bake_map.py"
start "" "D:\Work\GameDev\Godot\Godot_v4.6.3-stable_win64.exe" --path "D:\Work\FunAI\godot"
echo.
echo [OK] 機器人地圖已啟動。開新的 Claude Code session 就會出現角色。

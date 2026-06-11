@echo off
REM Deskbots map launcher -- double-click or run from a terminal.
REM Resolves its own location, so the whole folder can live anywhere.
REM Clean zombie sessions, bake the map, then start usage poll + map.
set "APP=%~dp0"
set "ROOT=%~dp0.."
py "%APP%clean_sessions.py"
py "%APP%bake_map.py"
REM Background-resident: per-session token usage -> runtime\usage.json (minimized).
start "Deskbots-Usage" /min py "%APP%usage_poll.py"
start "" "D:\Work\GameDev\Godot\Godot_v4.6.3-stable_win64.exe" --path "%ROOT%\godot"
echo.
echo [OK] Map started. Open a new Claude Code session to see the robots.

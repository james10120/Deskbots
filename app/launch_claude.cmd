@echo off
REM Called by the map: open a new PowerShell window in the given folder and run claude.
REM Usage: launch_claude.cmd "C:\path\to\project" [extra claude args, e.g. -c to continue]
REM Keep this file ASCII-only (cmd.exe parses batch as cp950; UTF-8 Chinese breaks it).
start "Claude" powershell.exe -NoExit -Command "Set-Location -LiteralPath '%~1'; claude %~2"

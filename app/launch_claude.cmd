@echo off
REM 由地圖啟動器呼叫：在指定資料夾開一個新 PowerShell 視窗並啟動 claude
REM 用法：launch_claude.cmd "C:\path\to\project"
start "Claude" powershell.exe -NoExit -Command "Set-Location -LiteralPath '%~1'; claude"

@echo off
REM FunAI 乾淨生命週期啟動器 —— 雙擊即可。
REM 開啟時安裝 hooks/statusLine，關閉地圖後自動還原全域設定、不留痕跡。
REM 用 -ExecutionPolicy Bypass -File 呼叫 .ps1，避免雙擊 .ps1 被執行原則擋。
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_funai.ps1"

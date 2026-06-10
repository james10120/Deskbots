@echo off
REM FunAI clean-lifecycle launcher. Double-click to run.
REM Installs hooks/statusLine on start; auto-restores global settings on map close.
REM NOTE: keep this file ASCII-only -- cmd.exe parses batch files as cp950, and
REM UTF-8 Chinese comments get split into garbage commands (window flashes and dies).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_funai.ps1"

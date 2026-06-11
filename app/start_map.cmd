@echo off
REM Deskbots map-only launcher (resident mode). Double-click to run.
REM Assumes hooks are already installed (py app\apply_settings.py once);
REM opens the map + background pollers, does NOT touch global settings on exit.
REM ASCII only: cmd.exe parses batch files with the OEM codepage.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_deskbots.ps1" -MapOnly

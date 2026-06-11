@echo off
REM Deskbots: open a PowerShell window to set up an SSH server for the map.
REM   %1 = host (user@ip or ssh alias)   %2 = label (optional)
REM Runs remote_install.py --bootstrap: generate/push SSH key (asks the
REM server password once), install remote hooks, register in servers.json.
REM ssh_bridge hot-reloads the list, so the robot appears without restarting.
REM ASCII only: cmd.exe parses this file with the OEM codepage.
start "Deskbots-SSH-Setup" powershell.exe -NoExit -Command "$env:PYTHONUTF8='1'; py '%~dp0remote_install.py' '%~1' --bootstrap --label '%~2'"

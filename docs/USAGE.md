# User Guide

**English** | [繁體中文](USAGE.zh-TW.md)

Installation is covered in the [README](../README.md); this guide is about using the map
once it's running.

---

## 1. Launch modes

| Mode | How | Hooks | On close |
|------|-----|-------|----------|
| **Double-click the exe** (simplest) | double-click `godot\Deskbots.exe` | installed automatically on launch | global settings restored, daemons stopped, runtime cleaned (self-managed) |
| **run_deskbots.cmd** | double-click `app\run_deskbots.cmd` | installed automatically on launch | same as above, but via PowerShell `try/finally` (cleanup guaranteed even on crash) |
| **Resident mode** | run `py app\apply_settings.py` once, then double-click `app\start_map.cmd` | stay installed | daemons stopped only, settings untouched |

- Start the Claude sessions you want to watch **after** the map is open (the terminal
  hwnd is captured once at SessionStart and sticks).
- If the launcher window gets force-killed before restoring: run
  `py app\apply_settings.py --remove` once.
- For sessions that were already open, restart them to pick up the hooks/statusline.

## 2. Robot states

| Claude event | State | Robot behaviour | Nameplate |
|--------------|-------|-----------------|-----------|
| UserPromptSubmit | thinking | at its desk | blue |
| PreToolUse / actively outputting | working | working at its desk | green |
| Notification (permission needed) | waiting | phone-scrolling in the waiting area | **yellow (look here!)** |
| Stop | done → idle | reading on the lounge couch | green → gray |
| PostToolUse with an error | error | at its desk | red |
| SessionEnd / transcript stale | leaves | robot disappears | — |

Interrupt detection: Claude Code has no interrupt hook, so the transcript file's mtime is
used as a heartbeat (stops updating → back to idle).

## 3. Map controls

- **Click a robot** → open/close its chat card
- **Click an empty chair** → pick a folder, a new PowerShell window runs `claude` there
  (the new session takes that seat)
- **Drag empty floor** → move the whole map window
- **WASD / arrow keys** → walk your own character around (purely cosmetic)
- Top-right buttons: **設定 (settings)** / **看板 (board)** / **釘選 (pin map always-on-top)**

Window positions, pin state, board height/visibility are remembered
(`runtime/ui_state.json`) and restored on the next launch.

## 4. Chat card (click a robot)

- Shows the session's **latest Q&A round** (including tool-call summaries)
- Input box sends a message (Enter to send, Shift+Enter for newline); quick buttons for
  `/clear`, `/compact`, `⎋ interrupt`
- **▸ Summon terminal**: brings that session's terminal window to the front
- Sending works by focusing the terminal and injecting keystrokes, so **remote sessions
  are view-only** — the button becomes **▸ Open in VS Code**, landing on the right
  machine and folder
- For the "no usable terminal" cases and fixes, see
  [ARCHITECTURE §5](ARCHITECTURE.md) (zh-TW)

## 5. Usage board

- One card per live session: **context-load gauge** (the fuller, the redder), LV (grows
  with output), ⚒ output / 📖 read tokens, 🔁 turns; click a card to open its chat card
- Bottom grip drags the board taller; 📌 in the title bar pins the board on top
  (independent of the map pin)
- **Rehire list** — recently used, currently-not-running projects (local + every remote
  machine, merged, sorted by last activity):
  - click a local row → new PowerShell with `claude -c` (resume last conversation)
  - click a remote row (`project@machine`) → VS Code Remote at that working directory
  - **✕ remove**: hides the entry; it returns automatically when that project has new
    activity

## 6. Settings card

- **Map always-on-top** (synced with the top-right pin button), **show/hide board**
- **SSH servers**:
  - list shows a green dot when connected plus the live session count; **VS Code** opens
    a Remote window to that machine; ✕ removes it from the list
  - add: type `user@ip` (or an ssh alias) → **＋ 連線安裝** — a terminal window opens and
    does everything: generate/push an SSH key (you type the server password once), deploy
    the remote agent + hooks, register the server. **No map restart needed** — the bridge
    hot-reloads and the robots walk in
- **⏻ Quit**: closes the map; in clean mode the launcher then restores your environment

SSH via CLI, and requirements:

```
py app\remote_install.py user@ip --bootstrap [--label name]   # install (label shows on nameplates)
py app\remote_install.py user@ip --remove                     # uninstall remote hooks
```

Remote machine: Linux/macOS, python3, sshd. Local `ssh user@ip` must be passwordless key
auth (bootstrap sets this up for you).

## 7. Debug flags

```
godot --path godot -- --grid    # tile grid + S/W/L anchor markers (seat/wait/lounge)
godot --path godot -- --shot    # run 1s, auto-screenshot (map/board/open cards), exit
godot --path godot -- --bot     # character sheet viewer
```

The packaged build supports the same: `godot\Deskbots.exe -- --grid`.

## 8. runtime/ files (all gitignored)

| File | Writer | Contents |
|------|--------|----------|
| `sessions/<id>.json` | emit.py / ssh_bridge | per-session state (remote ones are named `<label>__<id>`) |
| `usage.json` | usage_poll | per-session token usage |
| `rehire.json` / `rehire_remote.json` | usage_poll / ssh_bridge | local / remote rehire lists |
| `rehire_hidden.json` | board ✕ | rehire removals (survives restarts) |
| `ui_state.json` | main.gd | window positions/pin/board state (survives restarts) |
| `bridge.json` | ssh_bridge | per-server connection status (settings card dots) |
| `transcripts/` | ssh_bridge | cached remote transcript tails (chat card / heartbeat) |

## 9. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| No robot appears | session was started **before** the map → restart that session; or hooks not installed (`py app\apply_settings.py`) |
| Chat card says "no usable terminal" | see [ARCHITECTURE §5](ARCHITECTURE.md); VS Code integrated terminals are unreliable — standalone PowerShell windows (the launcher / empty-chair flow) work best |
| Server dot stays gray | is `ssh user@ip` passwordless? does the remote have `python3`? firewall? check the bridge window's reconnect log |
| Garbled CJK output | switch the terminal to UTF-8 (the launcher already sets `PYTHONUTF8=1`) |
| Full uninstall | `py app\apply_settings.py --remove` (local) + `py app\remote_install.py <host> --remove` (each remote), then delete the folder — nothing else is left on the system |

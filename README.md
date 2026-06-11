<p align="center">
  <img src="assets/icon.png" width="120" alt="Deskbots">
</p>

# Deskbots — a robot office map for Claude Code

**English** | [繁體中文](README.zh-TW.md)

Every running Claude Code session becomes a little robot in a pixel-art office:
coding at its desk while working, phone-scrolling in the waiting area when it needs your
approval, reading on the lounge couch when idle. The map is a transparent, borderless,
optionally always-on-top overlay — one glance tells you which project is busy and which
one is waiting for you.

<p align="center">
  <img src="docs/img/map.png" width="780" alt="office map"><br>
  <img src="docs/img/board.png" width="300" alt="usage board">
</p>

- **Usage board** — per-session context-load gauge, level, output/read tokens, turn count
- **Chat card** — click a robot to see the latest Q&A, send messages/slash-commands back
  to its terminal, or summon the terminal window
- **Rehire list** — recently used projects, one click to resume (`claude -c`)
- **SSH multi-server** — sessions on remote machines appear on the same map; remote
  projects open directly in VS Code Remote at the right working directory
- **Clean lifecycle** — hooks are installed on launch and your global
  `~/.claude/settings.json` is restored automatically on exit; no traces left

## Architecture

```
Data layer (Python, stdlib only)            Render layer (Godot 4.6, GL Compatibility)
Claude Code hooks
  └ app/emit.py <EVENT>                     transparent overlay window, polls 0.4s
      └ writes runtime/sessions/<id>.json → one robot per session (BOT1~9)
app/usage_poll.py (daemon)                  state-driven walking/animations, A* pathing
  └ usage.json / rehire.json            →   usage board, rehire list
app/ssh_bridge.py (daemon)
  └ ssh <host> remote_agent.py          →   remote sessions mirrored into the same dir
app/winfocus.py  ←── (chat card send/focus: Win32 focus + keystroke injection)
```

**Core design: the filesystem is the IPC.** Hooks only write, Godot only reads, winfocus
only touches windows — zero coupling between processes; any one of them can die without
taking the others down.

| Doc | Contents |
|-----|----------|
| [docs/USAGE.md](docs/USAGE.md) | **User guide** (EN): controls, states, board/chat/settings cards, SSH, debug, troubleshooting |
| [docs/USAGE.zh-TW.md](docs/USAGE.zh-TW.md) | 使用手冊（中文版） |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | **Deep dive** (zh-TW): data flow, terminal hwnd capture, keystroke injection, SSH bridge, failure modes |
| [docs/TILED.md](docs/TILED.md) | **Map modules** (zh-TW): Tiled layer rules, anchors, changing the layout |
| [assets/README.md](assets/README.md) | **Bring your own assets**: which files, formats, where to get them |

## Requirements

| Item | Notes |
|------|-------|
| Windows 10/11 | winfocus (focus/keystroke injection) and the launchers are Windows-only |
| Python 3.8+ (`py` launcher) | data layer is pure stdlib, zero dependencies |
| [Claude Code](https://claude.com/claude-code) CLI | the thing being visualized |
| Godot 4.6 | either install the editor (dev) or use the packaged `godot\Deskbots.exe` (no install) |
| Asset PNGs | LimeZu's license forbids redistribution — **add them yourself, see [assets/README.md](assets/README.md)** |
| (optional) VS Code + Remote-SSH, OpenSSH | for the SSH multi-server feature |

## Install & run

```
git clone https://github.com/james10120/Deskbots.git && cd Deskbots
(drop in the asset PNGs as described in assets/README.md)
```

**Clean mode (recommended)** — double-click **`app\run_deskbots.cmd`**.
Hooks/statusLine are merged into your global settings on launch and **automatically
restored when you close the map** (guaranteed by `try/finally`; if the window gets
force-killed, run `py app\apply_settings.py --remove` once).
Start the Claude sessions you want to watch **after** the map is open.

**Resident mode** — run `py app\apply_settings.py` once (idempotent, makes a `.bak`),
then double-click **`app\start_map.cmd`** to open just the map; global settings are left
alone. Uninstall: `py app\apply_settings.py --remove`.

The launcher finds Godot in this order: `godot\Deskbots.exe` (packaged) →
`DESKBOTS_GODOT` env var → PATH → common install locations.

## Package as a standalone app

```
powershell -File app\package.ps1 -Version 1.0.0
```

Requires the Godot 4.6 editor + matching export templates on the build machine.
Produces `dist\Deskbots-<version>-win64.zip`: unzip → add assets → double-click
`app\run_deskbots.cmd`. No Godot install needed (Python still is).

## SSH multi-server

When you develop on several machines (the VS Code Remote-SSH kind), their Claude
sessions can join the map too:

1. Map → top-right **設定 (Settings)** → SSH servers → type `user@ip` → **＋ 連線安裝 (install)**
   — a terminal window opens and does everything: generate/push an SSH key (you type the
   server password once), deploy the remote agent + hooks, register the server.
2. Remote sessions appear as `project@machine`; their chat card is view-only with an
   **Open in VS Code** button that lands in the right folder on the right machine.
3. The rehire list also shows the remote machine's recent projects — one click opens
   VS Code Remote at that working directory.

CLI equivalent: `py app\remote_install.py user@ip --bootstrap [--label name]`
(`--remove` to uninstall). Remote needs Linux/macOS + python3 + sshd; the local `ssh`
must be passwordless key auth (bootstrap sets that up).

## Files

```
app/
  emit.py            hook entry: compute state, grab terminal hwnd, write session JSON
  states.py          shared: paths, state machine, time decay, session file I/O
  statusline.py      Claude Code status line
  usage_poll.py      daemon: token usage (usage.json) + local rehire list (rehire.json)
  ssh_bridge.py      daemon: multi-server mirroring (hot-reloads servers.json)
  remote_agent.py    (deployed to remotes) streams session snapshots + recent projects
  remote_install.py  one-shot remote deploy (--bootstrap incl. SSH key setup)
  winfocus.py        Win32: find/focus terminal windows, inject keystrokes (CJK-safe)
  apply_settings.py  merge/remove hooks+statusLine in global settings (idempotent)
  bake_map.py        Tiled module composer (COMPOSITION layout, MODULE_ANCHORS seats)
  run_deskbots.*     clean-lifecycle launcher; start_map.cmd resident; package.ps1 packer
godot/
  main.gd            main loop: session scan, robot behaviour, window signal wiring
  office_map.gd      map render, A* grid, seat/lounge/wait geography (all data-driven)
  detail_window.gd   chat card; usage_board.gd board; settings_window.gd settings
  drag_window.gd     shared borderless-transparent card window base; paths.gd / util.gd
assets/              art (PNGs are bring-your-own, see assets/README.md); tiled/*.tmj modules
config/              servers.json (your SSH server list, gitignored)
runtime/             runtime state (gitignored, cleaned by the launcher on exit)
```

## Tuning

- **Office layout**: `COMPOSITION` in `app/bake_map.py` (modules left-to-right; seats and
  lounge/wait points are computed at bake time)
- **Module anchors**: `MODULE_ANCHORS` in the same file; map-module authoring in
  [docs/TILED.md](docs/TILED.md)
- **Scale / seat offsets**: `SCALE`, `SEAT_UP_DY/DOWN_DY` in `godot/office_map.gd`
- Debug: `--grid` shows the tile grid + seat/wait/lounge anchor markers; `--shot`
  auto-screenshots and exits

## License

Code is MIT (see [LICENSE](LICENSE)). Art assets (LimeZu Modern Interiors / Modern Office
Revamped) are **not** included in this repo — obtain them under LimeZu's own terms.

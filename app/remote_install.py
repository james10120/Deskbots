"""把 Deskbots 遠端側裝到 SSH 伺服器（hooks + 遠端代理），並登記進 servers.json。

用法（host = ~/.ssh/config 的別名或 user@ip）：
    py app/remote_install.py <host>                # 安裝/更新（需已能免密碼登入）
    py app/remote_install.py <host> --bootstrap    # 含首次設定：產生/推送 SSH 金鑰
                                                   #（推送時會要你輸一次該機密碼）
    py app/remote_install.py <host> --remove       # 卸載遠端 hooks（檔案保留）
    可選：--label 名字（地圖顯示用，預設=host 的 @ 後段）、--root 路徑（預設 ~/deskbots）

遊戲設定卡的「＋ 連線安裝」就是開新視窗跑本檔的 --bootstrap 模式
（經 add_server.cmd）；ssh_bridge 熱載入 servers.json，裝完機器人自動出現。

做的事：
  1. ssh 建遠端目錄 <root>/app、<root>/runtime/sessions
  2. scp emit.py / states.py / apply_settings.py / remote_agent.py 過去
  3. ssh 跑遠端 apply_settings.py（把 hooks 裝進遠端 ~/.claude/settings.json）
  4. 把這台加進本地 config/servers.json（已存在就更新）
之後 run_deskbots 啟動時 ssh_bridge.py 會自動連上這台。
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

APP = Path(__file__).resolve().parent
SERVERS_FILE = APP.parent / "config" / "servers.json"
FILES = ["states.py", "emit.py", "apply_settings.py", "remote_agent.py"]
SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new"]


def _run(cmd: list[str], desc: str) -> bool:
    print(f"→ {desc}")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.stdout.strip():
        print("  " + r.stdout.strip().replace("\n", "\n  "))
    if r.returncode != 0:
        print(f"!! 失敗（exit {r.returncode}）：{r.stderr.strip()}")
        return False
    return True


def _register(host: str, label: str, root: str) -> None:
    try:
        servers = json.loads(SERVERS_FILE.read_text(encoding="utf-8-sig"))
        if not isinstance(servers, list):
            servers = []
    except (OSError, json.JSONDecodeError):
        servers = []
    servers = [s for s in servers if not (isinstance(s, dict) and s.get("host") == host)]
    servers.append({"host": host, "label": label, "root": root})
    SERVERS_FILE.parent.mkdir(parents=True, exist_ok=True)
    SERVERS_FILE.write_text(json.dumps(servers, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"✅ 已登記到 {SERVERS_FILE}（label={label}）")


def _bootstrap(host: str) -> None:
    """首次設定：本地沒金鑰就產一把，無法免密碼登入就推公鑰（互動輸一次密碼）。"""
    ssh_dir = Path.home() / ".ssh"
    pub = next((ssh_dir / k for k in ("id_ed25519.pub", "id_rsa.pub", "id_ecdsa.pub")
                if (ssh_dir / k).exists()), None)
    if pub is None:
        print("→ 本機沒有 SSH 金鑰，產生一把（ed25519，無通行碼）")
        ssh_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ssh-keygen", "-t", "ed25519", "-N", "", "-q",
                        "-f", str(ssh_dir / "id_ed25519")], check=False)
        pub = ssh_dir / "id_ed25519.pub"
        if not pub.exists():
            print("!! 金鑰產生失敗")
            sys.exit(1)
    test = subprocess.run(["ssh", *SSH_OPTS, host, "echo OK"], capture_output=True, text=True)
    if test.returncode == 0:
        print("✅ 已可免密碼登入")
        return
    print(f"→ 推送公鑰到 {host} —— 請在下方輸入該機密碼（只此一次）")
    # ssh 的密碼提示直接走終端 tty；stdin 管線餵的是遠端指令的輸入（公鑰內容），兩者不衝突
    r = subprocess.run(
        ["ssh", "-o", "StrictHostKeyChecking=accept-new", host,
         "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys"
         " && chmod 600 ~/.ssh/authorized_keys"],
        input=pub.read_text(encoding="utf-8").strip() + "\n", text=True)
    if r.returncode != 0:
        print("!! 公鑰推送失敗（密碼錯誤或無法連線）")
        sys.exit(1)
    if subprocess.run(["ssh", *SSH_OPTS, host, "echo OK"], capture_output=True).returncode != 0:
        print("!! 公鑰已推送但免密碼登入仍失敗，請檢查遠端 sshd 設定（PubkeyAuthentication）")
        sys.exit(1)
    print("✅ 免密碼登入設定完成")


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        sys.exit(1)
    host = args[0]
    flags = sys.argv[1:]
    def _opt(name: str, default: str) -> str:
        if name in flags and flags.index(name) + 1 < len(flags):
            return flags[flags.index(name) + 1]
        return default
    # 預設 label 取 user@ip 的 @ 後段（地圖名牌「專案@label」比較短）
    label = _opt("--label", "") or (host.split("@", 1)[1] if "@" in host else host)
    root = _opt("--root", "~/deskbots")

    if "--bootstrap" in flags:
        _bootstrap(host)

    if "--remove" in flags:
        ok = _run(["ssh", *SSH_OPTS, host, f"python3 {root}/app/apply_settings.py --remove"],
                  f"卸載 {host} 的遠端 hooks")
        sys.exit(0 if ok else 1)

    if not _run(["ssh", *SSH_OPTS, host, f"mkdir -p {root}/app {root}/runtime/sessions"],
                f"建立遠端目錄 {host}:{root}"):
        print("   （請先確認 `ssh " + host + "` 能免密碼登入：ssh-keygen + ssh-copy-id）")
        sys.exit(1)
    srcs = [str(APP / f) for f in FILES]
    if not _run(["scp", *SSH_OPTS, *srcs, f"{host}:{root}/app/"], "複製 agent 檔案"):
        sys.exit(1)
    if not _run(["ssh", *SSH_OPTS, host, f"python3 {root}/app/apply_settings.py"],
                "安裝遠端 hooks（遠端 ~/.claude/settings.json）"):
        sys.exit(1)
    _register(host, label, root)
    print("完成。重開地圖（或下次 run_deskbots）即會連上；"
          "在該機新開的 Claude session 會以「專案@%s」出現。" % label)


if __name__ == "__main__":
    main()

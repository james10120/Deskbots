"""FunAI session manager — 用 claude-agent-sdk 驅動「地圖自有」的 Claude session。

開一個本機 TCP（127.0.0.1:8123），收 Godot 的指令、把串流輸出傳回去。
協定：每行一個 JSON。
  Godot → manager:
    {"cmd":"start","sid":"m1","cwd":"D:/Work/Foo","label":"Foo"}
    {"cmd":"prompt","sid":"m1","text":"..."}
    {"cmd":"stop","sid":"m1"}
  manager → Godot:
    {"ev":"started","sid":...,"label":...}
    {"ev":"text","sid":...,"text":"<逐字>"}
    {"ev":"tool","sid":...,"name":"Edit"}
    {"ev":"done","sid":...}
    {"ev":"error","sid":...,"msg":...}

Phase 1：純對話（allowed_tools=[]），不會卡權限；工具之後再加。
"""
from __future__ import annotations

import asyncio
import json

from claude_agent_sdk import (
    ClaudeSDKClient, ClaudeAgentOptions, ResultMessage, StreamEvent,
)

HOST, PORT = "127.0.0.1", 8123

_writers: set[asyncio.StreamWriter] = set()
_sessions: dict[str, asyncio.Queue] = {}


def broadcast(obj: dict) -> None:
    line = (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
    for w in list(_writers):
        try:
            w.write(line)
        except Exception:
            _writers.discard(w)


async def session_task(sid: str, cwd: str, label: str) -> None:
    opts = ClaudeAgentOptions(
        cwd=cwd or None,
        allowed_tools=[],                 # Phase 1：純對話
        include_partial_messages=True,
    )
    q = _sessions[sid]
    try:
        async with ClaudeSDKClient(options=opts) as client:
            broadcast({"ev": "started", "sid": sid, "label": label})
            while True:
                text = await q.get()
                if text is None:           # stop
                    break
                await client.query(text)
                async for msg in client.receive_response():
                    if isinstance(msg, StreamEvent):
                        ev = msg.event
                        et = ev.get("type")
                        if et == "content_block_delta":
                            d = ev.get("delta", {})
                            if d.get("type") == "text_delta":
                                broadcast({"ev": "text", "sid": sid, "text": d.get("text", "")})
                        elif et == "content_block_start":
                            cb = ev.get("content_block", {})
                            if cb.get("type") == "tool_use":
                                broadcast({"ev": "tool", "sid": sid, "name": cb.get("name", "")})
                    elif isinstance(msg, ResultMessage):
                        pass
                broadcast({"ev": "done", "sid": sid})
    except Exception as e:
        broadcast({"ev": "error", "sid": sid, "msg": str(e)})
    finally:
        _sessions.pop(sid, None)


async def handle_cmd(obj: dict) -> None:
    cmd = obj.get("cmd")
    sid = str(obj.get("sid", ""))
    if cmd == "start":
        if sid and sid not in _sessions:
            _sessions[sid] = asyncio.Queue()
            asyncio.create_task(session_task(sid, str(obj.get("cwd", "")), str(obj.get("label", sid))))
    elif cmd == "prompt":
        q = _sessions.get(sid)
        if q is not None:
            await q.put(str(obj.get("text", "")))
    elif cmd == "stop":
        q = _sessions.get(sid)
        if q is not None:
            await q.put(None)


async def on_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    _writers.add(writer)
    broadcast({"ev": "hello"})
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            try:
                obj = json.loads(line.decode("utf-8"))
            except Exception:
                continue
            await handle_cmd(obj)
    finally:
        _writers.discard(writer)
        try:
            writer.close()
        except Exception:
            pass


async def main() -> None:
    server = await asyncio.start_server(on_client, HOST, PORT)
    print(f"session_manager listening on {HOST}:{PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())

#!/usr/bin/env python3
"""agent-scan.py — 터미널에 붙어 실행 중인 코딩 에이전트 세션을 JSON 으로 출력.

Agent Cockpit(~/.hammerspoon/agent-cockpit.lua) 이 주기적으로 호출한다. 훅 이벤트를 아직 보내지 않은
세션(콕핏 설치 전에 시작한 것, 훅 신뢰가 안 된 Codex 등)도 목록에 올리기 위한 보조 소스.

출력: [{agent, pid, tty, started, cwd, project, key, name, status, term, threadId}] (JSON 배열)
  - key   : Claude 는 sessionId(~/.claude/sessions/<pid>.json), Codex 는 resume 인자의 thread id,
            없으면 "<agent>:pid:<pid>" — 훅 이벤트의 세션 키와 맞춰 병합된다.
  - status: Claude 는 sessions json 의 status(busy/idle …), Codex 는 null
  - term  : 부모 프로세스를 따라 올라가 만난 터미널 앱 이름(ghostty/kitty/WezTerm/iTerm.app/Apple_Terminal)
"""
import json, os, re, subprocess, sys, time
from datetime import datetime

AGENTS = {"claude": "claude", "codex": "codex", "kiro-cli": "kiro", "hermes": "hermes"}
TERMINALS = {"ghostty": "ghostty", "kitty": "kitty", "wezterm-gui": "WezTerm", "iTerm2": "iTerm.app", "Terminal": "Apple_Terminal"}
GENERIC_DIR = {"main", "master", "dev", "develop", "src", "app", "repo"}
SESS_DIR = os.path.expanduser("~/.claude/sessions")


def ps_table():
    out = subprocess.run(["ps", "-axo", "pid=,ppid=,tty=,lstart=,command="], capture_output=True, text=True).stdout
    rows = {}
    for line in out.splitlines():
        m = re.match(r"\s*(\d+)\s+(\d+)\s+(\S+)\s+(\w{3}\s+\w{3}\s+\d+\s+[\d:]+\s+\d{4})\s+(.*)$", line)
        if not m:
            continue
        pid, ppid, tty, lstart, cmd = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4), m.group(5)
        rows[pid] = {"pid": pid, "ppid": ppid, "tty": tty, "lstart": lstart, "cmd": cmd}
    return rows


def agent_of(cmd):
    # 첫 토큰(경로 포함) 또는 node 래퍼(node …/.bin/codex) 의 대상 스크립트 이름으로 판별
    toks = cmd.split()
    if not toks:
        return None
    first = os.path.basename(toks[0])
    if first in ("node", "bun") and len(toks) > 1:
        first = os.path.basename(toks[1])
    if first in AGENTS:
        return AGENTS[first]
    return None


def cwd_of(pid):
    r = subprocess.run(["lsof", "-a", "-d", "cwd", "-p", str(pid), "-Fn"], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if line.startswith("n"):
            return line[1:]
    return None


def project_of(cwd):
    if not cwd:
        return "?"
    base = os.path.basename(cwd.rstrip("/"))
    if base in GENERIC_DIR:
        return os.path.basename(os.path.dirname(cwd.rstrip("/"))) + "/" + base
    return base


def term_of(pid, rows):
    seen = 0
    while pid in rows and seen < 12:
        name = os.path.basename(rows[pid]["cmd"].split()[0]) if rows[pid]["cmd"].split() else ""
        for k, v in TERMINALS.items():
            if name == k or name.startswith(k):
                return v
        pid = rows[pid]["ppid"]
        seen += 1
    return None


def claude_session(pid):
    p = os.path.join(SESS_DIR, f"{pid}.json")
    try:
        return json.load(open(p))
    except (OSError, json.JSONDecodeError):
        return None


def main():
    rows = ps_table()
    cands = []
    for pid, r in rows.items():
        if r["tty"] == "??":            # 터미널에 붙지 않은 것(데몬·앱 내장 codex 등)은 제외
            continue
        agent = agent_of(r["cmd"])
        if not agent:
            continue
        if re.search(r"agent-scan|agent-cockpit|codex-code-mode|app-server|mcp-server|exec-server", r["cmd"]):
            continue
        cands.append((pid, agent, r))

    # 같은 tty 의 같은 에이전트는 하나로(node 래퍼 + 네이티브 바이너리 쌍). 부모가 후보에 있으면 자식을 버린다.
    cand_pids = {pid for pid, _, _ in cands}
    result = []
    for pid, agent, r in cands:
        if r["ppid"] in cand_pids and rows[r["ppid"]]["tty"] == r["tty"]:
            continue
        started = None
        try:
            started = int(time.mktime(datetime.strptime(r["lstart"], "%a %b %d %H:%M:%S %Y").timetuple()))
        except ValueError:
            pass
        cwd = cwd_of(pid)
        entry = {"agent": agent, "pid": pid, "tty": r["tty"], "started": started, "cwd": cwd, "project": project_of(cwd),
                 "key": f"{agent}:pid:{pid}", "name": None, "status": None, "term": term_of(pid, rows), "threadId": None,
                 "cmd": r["cmd"][:120]}
        if agent == "claude":
            s = claude_session(pid)
            if s:
                entry["key"] = s.get("sessionId") or entry["key"]
                entry["name"] = s.get("name")
                entry["status"] = s.get("status")
                entry["cwd"] = s.get("cwd") or cwd
                entry["project"] = project_of(entry["cwd"])
                if s.get("startedAt"):
                    entry["started"] = int(s["startedAt"] / 1000)
        elif agent == "codex":
            m = re.search(r"\bresume\s+([0-9a-f-]{20,})", r["cmd"])
            if m:
                entry["threadId"] = m.group(1)
                entry["key"] = m.group(1)
        result.append(entry)

    result.sort(key=lambda e: e["started"] or 0)
    seen = {}
    for e in result:                      # 같은 세션 ID 를 두 프로세스가 쓰면(-c 재개 등) 뒤의 것에 pid 를 덧붙인다
        if e["key"] in seen:
            e["key"] = f'{e["key"]}#{e["pid"]}'
        seen[e["key"]] = True
    json.dump(result, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()

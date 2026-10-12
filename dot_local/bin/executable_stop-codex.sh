#!/bin/bash
# Run from a separate terminal: this also terminates active Codex sessions.
set -euo pipefail
exec python3 - "$@" <<'PY'
import argparse
import os
from pathlib import PurePath
import signal
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description="현재 사용자의 Codex 앱·CLI·app-server·보조 프로세스를 종료합니다. 별도 터미널에서 실행하세요.")
parser.add_argument("--dry-run", action="store_true", help="종료 대상만 표시")
parser.add_argument("--force", action="store_true", help="정상 종료 대기 후 남은 프로세스에 SIGKILL 전송")
parser.add_argument("--timeout", type=float, default=10, help="정상 종료 대기 시간(초, 기본 10)")
args = parser.parse_args()
if not 0 <= args.timeout <= 300:
    parser.error("--timeout은 0~300초여야 합니다.")


def targets():
    result = subprocess.run(["ps", "-axo", "uid=,pid=,comm="], check=True, capture_output=True, text=True)
    found = {}
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) != 3:
            continue
        uid, pid, executable = fields
        if int(uid) != os.getuid() or int(pid) == os.getpid():
            continue
        name = PurePath(executable).name
        if name in {"codex", "Codex", "codex-code-mode-host"} or "/Codex.app/Contents/" in executable:
            found[int(pid)] = executable
    return found


def send(pids, sig):
    for pid in pids:
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass
        except PermissionError as error:
            print(f"종료 실패 PID {pid}: {error}", file=sys.stderr)


current = targets()
if not current:
    print("실행 중인 Codex 프로세스가 없습니다.")
    sys.exit(0)
for pid, executable in sorted(current.items()):
    print(f"{pid:>7}  {executable}")
print(f"대상: {len(current)}개", flush=True)
if args.dry_run:
    sys.exit(0)

print("SIGTERM으로 종료를 요청합니다.", flush=True)
send(current, signal.SIGTERM)
signaled = set(current.items())
deadline = time.monotonic() + args.timeout
while time.monotonic() < deadline:
    time.sleep(0.25)
    current = targets()
    if not current:
        break
    # A running parent may briefly restart a child while shutting down.
    fresh = {pid: exe for pid, exe in current.items() if (pid, exe) not in signaled}
    send(fresh, signal.SIGTERM)
    signaled.update(fresh.items())

current = targets()
if current and args.force:
    print(f"남은 {len(current)}개 프로세스를 강제 종료합니다.", flush=True)
    send(current, signal.SIGKILL)
    time.sleep(1)
    current = targets()
if current:
    print("아직 실행 중이거나 자동 재시작된 프로세스:", file=sys.stderr)
    for pid, executable in sorted(current.items()):
        print(f"{pid:>7}  {executable}", file=sys.stderr)
    if not args.force:
        print("강제 종료가 필요하면 --force 옵션으로 다시 실행하세요.", file=sys.stderr)
    print("자동 재시작되는 경우 해당 Codex를 실행한 앱 또는 서비스를 먼저 종료하세요.", file=sys.stderr)
    sys.exit(1)
print("Codex 프로세스 종료 완료.")
PY

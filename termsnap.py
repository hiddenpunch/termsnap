#!/usr/bin/python3
"""Ghostty 창·탭·분할과 그 안의 세션(Claude Code, Codex, 기타 명령)을 저장하고 되살린다.

  termsnap snapshot [--quiet]                지금 상태를 ~/.termsnap/ 에 저장
  termsnap show [저장본|--latest]             저장본 내용 보기
  termsnap restore [저장본|restore-point] [--mode all|missing|replace] [--run-all] [--dry-run]
        all      저장본의 분할을 전부 연다(기본값)
        missing  이미 떠 있는 세션은 건너뛰고 없는 것만 연다
        replace  지금 열린 터미널을 모두 닫고 연다
  termsnap list                              복원할 수 있는 저장본 목록(JSON)
  termsnap plan [저장본] [--cached]           복원 방식별로 열릴 개수(JSON)
  termsnap status                            최신 저장본과 복원 지점 요약(JSON)
  termsnap dismiss                           복원 지점 알림 끄기
"""
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys

os.environ["LC_ALL"] = "C"   # ps 의 날짜 형식이 로캘에 따라 바뀌면 프로세스 목록을 못 읽는다
HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".termsnap")
SEP = "\x1f"
AUTORUN = ("claude", "codex")   # 복원 때 자동 실행할 종류. 나머지는 입력만 해 둔다(--run-all 로 전부 실행)


def sh(cmd):
    return subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True).stdout


def osa(script):
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("osascript 실패: " + r.stderr.strip())
    return r.stdout


# ---------- Ghostty 구조 ----------
def ghostty_layout():
    script = f'''
    set sep to (character id 31)
    set out to ""
    tell application "Ghostty"
      repeat with w in windows
        set out to out & "W" & sep & (id of w) & linefeed
        repeat with t in tabs of w
          set out to out & "T" & sep & (index of t) & sep & (selected of t) & sep & (name of t) & linefeed
          repeat with s in terminals of t
            set out to out & "S" & sep & (id of s) & sep & (working directory of s) & sep & (name of s) & linefeed
          end repeat
        end repeat
      end repeat
    end tell
    return out'''
    windows = []
    for line in osa(script).splitlines():
        p = line.split(SEP)
        if p[0] == "W":
            windows.append({"id": p[1], "tabs": []})
        elif p[0] == "T":
            windows[-1]["tabs"].append({"index": int(p[1]), "selected": p[2] == "true", "name": p[3], "terminals": []})
        elif p[0] == "S":
            windows[-1]["tabs"][-1]["terminals"].append({"id": p[1], "cwd": p[2], "title": SEP.join(p[3:])})
    return windows


# ---------- 프로세스 ----------
def process_table():
    procs = {}
    for line in sh("ps -axo pid=,ppid=,tty=,lstart=,command=").splitlines():
        p = line.split(None, 8)
        if len(p) < 9:
            continue
        procs[int(p[0])] = {"pid": int(p[0]), "ppid": int(p[1]), "tty": p[2], "start": " ".join(p[3:8]), "cmd": p[8]}
    return procs


def cwd_of(pid):
    m = re.search(r"^n(.*)$", sh(f"lsof -a -p {pid} -d cwd -Fn 2>/dev/null"), re.M)
    return m.group(1) if m else None


def cwd_map(pids):
    """여러 프로세스의 작업 폴더를 lsof 한 번으로 조회한다(하나씩 부르면 분할 수만큼 느려진다)."""
    out, cur = {}, None
    if not pids:
        return out
    for line in sh("lsof -a -d cwd -Fpn -p " + ",".join(map(str, pids)) + " 2>/dev/null").splitlines():
        if line.startswith("p"):
            cur = int(line[1:])
        elif line.startswith("n") and cur is not None:
            out[cur] = line[1:]
    return out


def claude_info(pid, cmd, cwd):
    """실행 중인 claude 의 세션 ID·제목·이어가기 명령."""
    sid = name = None
    busy = False
    try:
        d = json.load(open(f"{HOME}/.claude/sessions/{pid}.json"))
        sid, name, cwd = d.get("sessionId"), d.get("name"), d.get("cwd") or cwd
        busy = d.get("status") == "busy"
    except (OSError, ValueError):
        m = re.search(r"--resume (\S+)", cmd)
        sid = m.group(1) if m else None
    title = None
    if sid and cwd:
        path = f"{HOME}/.claude/projects/{re.sub(r'[^A-Za-z0-9]', '-', cwd)}/{sid}.jsonl"
        def scan(lines):
            found = None
            for line in lines:
                if '"ai-title"' in line or '"custom-title"' in line:
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    found = d.get("customTitle") or d.get("aiTitle") or found
            return found
        try:
            with open(path, "rb") as f:   # 제목은 주기적으로 다시 기록되므로 끝부분만 봐도 대개 있다
                f.seek(max(0, os.path.getsize(path) - 2_000_000))
                title = scan(f.read().decode("utf-8", "replace").splitlines())
            if not title:
                title = scan(open(path, errors="replace"))
        except OSError:
            pass
    flags = re.sub(r"^claude\b", "", cmd)
    flags = re.sub(r"--resume(=|\s+)\S+", "", flags)
    flags = re.sub(r"--session-id(=|\s+)\S+|--fork-session|(?<!\S)(-c|-r|--resume|--continue)(?!\S)", "", flags).split()
    resume = " ".join(["claude", "--resume", sid] + flags) if sid else "claude --continue"
    return {"session": sid, "titles": [t for t in (title, name) if t], "resume": resume, "busy": busy}


def codex_info(pid, procs):
    """codex 본 세션 ID. 열어 둔 rollout 중 subagent 가 아닌 것, 없으면 subagent 의 부모."""
    real = next((p["pid"] for p in procs.values() if p["ppid"] == pid and "/bin/codex" in p["cmd"]), pid)
    files = {l.split()[-1] for l in sh(f"lsof -p {real} 2>/dev/null").splitlines() if "/.codex/sessions/" in l and l.rstrip().endswith(".jsonl")}
    main, parents = [], []
    for f in files:
        try:
            pl = json.loads(open(f).readline()).get("payload", {})
        except (OSError, ValueError):
            continue
        if isinstance(pl.get("source"), dict):
            parents.append((os.path.getmtime(f), pl.get("parent_thread_id") or pl.get("session_id")))
        else:
            main.append((os.path.getmtime(f), pl.get("id")))
    sid = (max(main)[1] if main else max(parents)[1] if parents else None)
    if not sid:  # 열어 둔 파일이 없으면: 프로세스 시작 뒤 같은 폴더에서 생긴 기록의 부모를 본다
        cwd, best = cwd_of(real), None
        for f in glob.glob(f"{HOME}/.codex/sessions/*/*/*/rollout-*.jsonl"):
            try:
                if os.path.getmtime(f) < dt.datetime.strptime(procs[real]["start"], "%a %b %d %H:%M:%S %Y").timestamp():
                    continue
                pl = json.loads(open(f).readline()).get("payload", {})
            except (OSError, ValueError, KeyError):
                continue
            if pl.get("cwd") == cwd:
                cand = pl.get("parent_thread_id") or pl.get("session_id") if isinstance(pl.get("source"), dict) else pl.get("id")
                if cand and (best is None or os.path.getmtime(f) > best[0]):
                    best = (os.path.getmtime(f), cand)
        sid = best[1] if best else None
    return {"session": sid, "titles": [], "resume": f"codex resume {sid}" if sid else "codex resume --last"}


HELPER = re.compile(r"mcp|notify-hub|node_repl|caffeinate|trusted-worker|kernel\.js|codex sandbox|app-server|code-mode-host")


def terminal_processes(ghostty_pid, procs):
    """Ghostty 의 분할 하나 = login 프로세스 하나. 각 분할에서 돌던 것을 뽑는다."""
    found = []
    for lg in (p for p in procs.values() if p["ppid"] == ghostty_pid and p["cmd"].startswith("/usr/bin/login")):
        shell = next((p for p in procs.values() if p["ppid"] == lg["pid"]), None)
        if not shell:
            continue
        kids = [p for p in procs.values() if p["ppid"] == shell["pid"] and not HELPER.search(p["cmd"])]
        found.append((lg, shell, min(kids, key=lambda p: p["pid"]) if kids else None))
    cwds = cwd_map([x["pid"] for _, shell, main in found for x in (shell, main) if x])
    out = []
    for lg, shell, main in found:
        ent = {"tty": lg["tty"], "shell_cwd": cwds.get(shell["pid"]), "kind": "shell", "cmd": None, "cwd": None, "session": None,
               "titles": [], "resume": None}
        if main:
            ent.update(cmd=main["cmd"], cwd=cwds.get(main["pid"]))
            first = os.path.basename(main["cmd"].split()[0])
            if first == "claude":
                ent.update(kind="claude", **claude_info(main["pid"], main["cmd"], ent["cwd"]))
            elif "codex" in main["cmd"].split()[:2][-1] or first == "codex":
                ent.update(kind="codex", **codex_info(main["pid"], procs))
            else:
                ent.update(kind="other", resume=main["cmd"], titles=[main["cmd"], first])
        out.append(ent)
    return out


# ---------- 짝짓기 ----------
def norm(s):
    return re.sub(r"^[^\w/~]+", "", s or "").strip()   # 제목 앞의 ✳ ◐ ⠼ 같은 표시를 뗀다


def score(term, proc):
    """폴더가 같거나 제목이 맞아야 짝이 된다. 둘 다 아니면 0 점이라 짝짓지 않는다."""
    title = norm(term["title"])
    cwds = {proc["shell_cwd"], proc["cwd"]} - {None}
    same_cwd = term["cwd"] in cwds
    same_title = any(t and (title == t or title.startswith(t) or t.startswith(title) and len(title) > 6) for t in proc["titles"])
    if not same_cwd and not same_title:
        return 0
    s = (10 if same_cwd else 0) + (100 if same_title else 0)
    if same_cwd and proc["kind"] == "shell" and (title.startswith("/") or title.startswith("~")):
        s += 20
    if same_cwd and proc["kind"] == "codex" and any(os.path.basename(c) and os.path.basename(c) in title for c in cwds):
        s += 5
    return s


def match(windows, tprocs):
    terms = [t for w in windows for tab in w["tabs"] for t in tab["terminals"]]
    pairs = sorted(((score(t, p), i, j) for i, t in enumerate(terms) for j, p in enumerate(tprocs)), reverse=True)
    used_t, used_p = set(), set()
    for sc, i, j in pairs:
        if sc < 10 or i in used_t or j in used_p:
            continue
        terms[i]["proc"], terms[i]["match_score"] = tprocs[j], sc
        used_t.add(i); used_p.add(j)
    for i, t in enumerate(terms):
        t.setdefault("proc", None)
    return [p for j, p in enumerate(tprocs) if j not in used_p]


# ---------- 복원 지점 ----------
RP = os.path.join(STATE, "restore-point.json")
LATEST = os.path.join(STATE, "latest.json")
ALERT_CAUSES = ("reboot", "login", "crash")   # 이 경로로 사라졌을 때만 알린다. quit·closed 는 복원 지점만 남긴다
CAUSE_KO = {"reboot": "재부팅", "login": "로그아웃 후 로그인", "crash": "Ghostty 충돌", "quit": "Ghostty 종료", "closed": "창 닫음"}


def terms_of(snap):
    return [t for w in snap.get("windows", []) for tab in w["tabs"] for t in tab["terminals"]]


def key_of(t):
    """분할 하나를 가리키는 키. 같은 세션이 살아 있는지 비교하는 데 쓴다."""
    p = t.get("proc") or {}
    return p.get("session") or f"{p.get('kind', 'none')}:{p.get('resume') or ''}:{t['cwd']}"


def keys_of(snap):
    return [key_of(t) for t in terms_of(snap)]


def only_missing(target, live):
    """target 에서, 지금 살아 있는 분할과 같은 것을 뺀 저장본을 만든다. 비는 탭·창은 없앤다."""
    left = keys_of(live)
    windows = []
    for w in target["windows"]:
        tabs = []
        for tab in w["tabs"]:
            keep = []
            for t in tab["terminals"]:
                k = key_of(t)
                if k in left:
                    left.remove(k)
                else:
                    keep.append(t)
            if keep:
                tabs.append({**tab, "terminals": keep})
        if tabs:
            windows.append({**w, "tabs": tabs})
    return {**target, "windows": windows}


def close_terminals(terms):
    """분할의 tty 에 HUP 을 보내 닫는다. 셸이 끝나면 Ghostty 가 그 분할을 닫으므로 확인 창이 뜨지 않는다."""
    for t in terms:
        tty = (t.get("proc") or {}).get("tty")
        if tty and tty.startswith("ttys"):
            # macOS 의 pkill -t 는 이 tty 이름을 못 찾는다. ps 로 그 tty 의 내 프로세스를 찾아 HUP 을 보낸다
            me = os.environ.get("USER") or sh("id -un").strip()
            pids = [l.split()[0] for l in sh(["ps", "-t", tty, "-o", "pid=,user="]).splitlines() if l.split()[1:] == [me]]
            if pids:
                subprocess.run(["kill", "-HUP"] + pids, capture_output=True)
        else:
            subprocess.run(["osascript", "-e", f'tell application "Ghostty" to close (first terminal whose id is "{t["id"]}")'],
                           capture_output=True)


def counts(snap):
    ts = terms_of(snap)
    kinds = [(t.get("proc") or {}).get("kind") for t in ts]
    return {"windows": len(snap.get("windows", [])), "tabs": sum(len(w["tabs"]) for w in snap.get("windows", [])),
            "terminals": len(ts), "claude": kinds.count("claude"), "codex": kinds.count("codex"),
            "other": len(ts) - kinds.count("claude") - kinds.count("codex"),
            "busy": sum(1 for t in ts if (t.get("proc") or {}).get("busy"))}


def boot_time():
    m = re.search(r"sec = (\d+)", sh("sysctl -n kern.boottime"))
    return int(m.group(1)) if m else 0


def login_time(procs):
    """지금 로그인 세션이 시작된 시각(Dock 프로세스 시작 시각)."""
    for p in procs.values():
        if p["cmd"].endswith("/Dock.app/Contents/MacOS/Dock"):
            return dt.datetime.strptime(p["start"], "%a %b %d %H:%M:%S %Y").timestamp()
    return 0


def loss_cause(prev_ts, ghostty_running, procs):
    if boot_time() > prev_ts:
        return "reboot"
    if login_time(procs) > prev_ts:
        return "login"
    if not ghostty_running:
        reports = glob.glob(f"{HOME}/Library/Logs/DiagnosticReports/[gG]hostty*")
        return "crash" if any(os.path.getmtime(f) > prev_ts for f in reports) else "quit"
    return "closed"


def write_json(obj, path):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def read_json(path):
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return None


def detect_loss(prev, cur, ghostty_running, procs):
    """직전 저장본의 세션 절반 이상이 한 번에 사라졌으면 직전 저장본을 복원 지점으로 고정한다."""
    if not prev:
        return
    pk, ck = keys_of(prev), keys_of(cur)
    if len(pk) < 3:
        return
    left = list(ck)
    alive = 0
    for k in pk:
        if k in left:
            left.remove(k); alive += 1
    if alive / len(pk) >= 0.5:
        return
    rp = read_json(RP)
    if rp and rp.get("state") == "pending" and len(terms_of(rp["snapshot"])) > len(pk):
        return  # 더 큰 복원 지점이 아직 처리되지 않았으면 덮어쓰지 않는다
    prev_ts = dt.datetime.fromisoformat(prev["taken_at"]).timestamp()
    cause = loss_cause(prev_ts, ghostty_running, procs)
    write_json({"state": "pending", "cause": cause, "alert": cause in ALERT_CAUSES,
                "detected_at": dt.datetime.now().isoformat(timespec="seconds"), "snapshot": prev}, RP)


def fingerprint(snap):
    """구조와 분할별 폴더·세션만 본다. 제목은 작업 중 표시 때문에 계속 바뀌어서 뺀다."""
    return [[[(t["cwd"], (t.get("proc") or {}).get("kind"), (t.get("proc") or {}).get("session"), (t.get("proc") or {}).get("resume"))
              for t in tab["terminals"]] for tab in w["tabs"]] for w in snap.get("windows", [])]


# ---------- 명령 ----------
def snapshot():
    os.makedirs(STATE, exist_ok=True)
    procs = process_table()
    gpid = next((p["pid"] for p in procs.values() if p["cmd"].endswith("/Ghostty.app/Contents/MacOS/ghostty")), None)
    # Ghostty 가 꺼져 있을 때 osascript 로 물으면 Ghostty 가 켜지므로 묻지 않는다
    windows = ghostty_layout() if gpid else []
    unmatched = match(windows, terminal_processes(gpid, procs)) if gpid else []
    snap = {"taken_at": dt.datetime.now().isoformat(timespec="seconds"), "windows": windows, "unmatched": unmatched}
    prev = read_json(LATEST)
    detect_loss(prev, snap, bool(gpid), procs)
    write_json(snap, LATEST)
    if prev and fingerprint(prev) == fingerprint(snap):
        return snap, None   # 직전과 같으면 기록 파일을 새로 만들지 않는다
    path = os.path.join(STATE, dt.datetime.now().strftime("snap-%Y%m%d-%H%M%S.json"))
    write_json(snap, path)
    for old in sorted(glob.glob(os.path.join(STATE, "snap-*.json")))[:-200]:
        os.remove(old)
    return snap, path


def command_for(term):
    p = term.get("proc")
    if not p or p["kind"] == "shell" or not p["resume"]:
        return None, False
    return p["resume"], p["kind"] in AUTORUN


def show(snap):
    n = m = 0
    print(f"저장 시각 {snap['taken_at']}")
    for wi, w in enumerate(snap["windows"], 1):
        print(f"창 {wi}")
        for tab in w["tabs"]:
            print(f"  탭 {tab['index']} [{tab['name']}]")
            for t in tab["terminals"]:
                n += 1
                cmd, auto = command_for(t)
                p = t.get("proc")
                m += bool(p)
                kind = p["kind"] if p else "짝 없음"
                print(f"    - {t['title'][:40]:40} | {t['cwd']} | {kind} | {cmd or '(셸만)'}{'' if auto or not cmd else '  [입력만]'}")
    print(f"분할 {n}개 중 {m}개 짝지음, 짝 없는 프로세스 {len(snap['unmatched'])}개")
    for p in snap["unmatched"]:
        print("   ?", p["tty"], p["kind"], p["shell_cwd"], (p["cmd"] or "")[:60])


def load(args):
    """파일을 주면 그것을, 아니면 복원 지점을, 그것도 없으면 최신 저장본을 쓴다."""
    path = next((a for a in args if not a.startswith("--")), None)
    if path:
        print("저장본:", path, file=sys.stderr)
        return json.load(open(path))
    rp = read_json(RP)
    if rp and "--latest" not in args:
        print(f"복원 지점: {rp['snapshot']['taken_at']} ({CAUSE_KO.get(rp['cause'], rp['cause'])})", file=sys.stderr)
        return rp["snapshot"]
    print("저장본:", LATEST, file=sys.stderr)
    return json.load(open(LATEST))


def resolve(state):
    rp = read_json(RP)
    if rp:
        rp.update(state=state, alert=False)
        write_json(rp, RP)


def status():
    latest, rp = read_json(LATEST), read_json(RP)
    out = {"latest": {"taken_at": latest["taken_at"], **counts(latest)} if latest else None, "restore_point": None}
    if rp:
        out["restore_point"] = {"state": rp["state"], "cause": rp["cause"], "cause_ko": CAUSE_KO.get(rp["cause"], rp["cause"]),
                                "alert": bool(rp.get("alert")) and rp["state"] == "pending", "detected_at": rp["detected_at"],
                                "taken_at": rp["snapshot"]["taken_at"], **counts(rp["snapshot"])}
    return out


def listing(limit=8):
    rp = read_json(RP)
    out = []
    if rp:
        out.append({"id": "restore-point", "label": f"복원 지점 ({CAUSE_KO.get(rp['cause'], rp['cause'])})",
                    "taken_at": rp["snapshot"]["taken_at"], **counts(rp["snapshot"])})
    for f in sorted(glob.glob(os.path.join(STATE, "snap-*.json")), reverse=True)[:limit]:
        snap = read_json(f)
        if snap and terms_of(snap):
            out.append({"id": f, "label": "", "taken_at": snap["taken_at"], **counts(snap)})
    return out


def target_of(ident):
    if ident in (None, "restore-point"):
        rp = read_json(RP)
        return (rp["snapshot"] if rp else read_json(LATEST)), bool(rp)
    return json.load(open(ident)), False


def plan(ident, cached=False):
    """복원 전에 보여 줄 숫자: 지금 열린 분할, 작업 중인 세션, 방식별로 열릴 개수.
    cached 면 새로 저장하지 않고 최신 저장본을 쓴다(앱은 메뉴를 열 때 미리 저장해 둔다)."""
    live = (read_json(LATEST) if cached else None) or snapshot()[0]
    target, _ = target_of(ident)
    n_all = len(terms_of(target))
    n_missing = len(terms_of(only_missing(target, live)))
    return {"live": len(terms_of(live)), "busy": counts(live)["busy"], "all": n_all, "missing": n_missing, "skipped": n_all - n_missing}


def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def restore(snap, dry_run=False, run_all=False):
    lines = ['tell application "Ghostty"', "activate"]
    for w in snap["windows"]:
        first_tab = True
        for tab in w["tabs"]:
            prev = None
            for t in tab["terminals"]:
                cmd, auto = command_for(t)
                cfg = ["set cfg to new surface configuration", f"set initial working directory of cfg to {q(t['cwd'])}"]
                if cmd:
                    cfg.append(f"set initial input of cfg to {q(cmd + (chr(10) if auto or run_all else ''))}")
                lines += cfg
                if prev is None and first_tab:
                    lines += ["set win to new window with configuration cfg", "set term to focused terminal of selected tab of win"]
                elif prev is None:
                    lines += ["set tb to new tab in win with configuration cfg", "set term to focused terminal of tb"]
                else:
                    lines.append("set term to split term direction right with configuration cfg")
                prev = t
            first_tab = False
    lines.append("end tell")
    script = "\n".join(lines)
    if dry_run:
        print(script)
        return
    r = subprocess.run(["osascript", "-"], input=script, capture_output=True, text=True)
    print("복원 완료" if r.returncode == 0 else "복원 실패", r.stderr.strip())
    return r.returncode == 0


if __name__ == "__main__":
    cmd, args = (sys.argv[1] if len(sys.argv) > 1 else "show"), sys.argv[2:]
    if cmd == "snapshot":
        snap, path = snapshot()
        show(snap) if "--quiet" not in args else None
        print("저장:", path) if path else print("변화 없음: 기록 파일을 새로 만들지 않았습니다")
    elif cmd == "show":
        show(load(args))
    elif cmd == "restore":
        # restore [저장본|restore-point] [--mode all|missing|replace] [--dry-run] [--run-all]
        ident = next((a for a in args if not a.startswith("--") and a not in ("all", "missing", "replace")), None)
        mode = args[args.index("--mode") + 1] if "--mode" in args else "all"
        dry = "--dry-run" in args
        target, is_rp = target_of(ident) if "--latest" not in args else (read_json(LATEST), False)
        if mode in ("missing", "replace"):
            live, _ = snapshot()
            if mode == "missing":
                target = only_missing(target, live)
            elif not dry:
                import signal
                signal.signal(signal.SIGHUP, signal.SIG_IGN)   # 이 명령을 실행한 터미널이 닫혀도 복원은 끝까지 한다
                json.dump(live, open(os.path.join(STATE, "before-replace.json"), "w"), ensure_ascii=False, indent=1)
                close_terminals(terms_of(live))
                import time
                time.sleep(2)
        if not terms_of(target):
            print("열 것이 없습니다")
        else:
            ok = restore(target, dry_run=dry, run_all="--run-all" in args)
            if ok and is_rp and not dry:
                resolve("restored")
    elif cmd == "list":
        print(json.dumps(listing(), ensure_ascii=False))
    elif cmd == "plan":
        print(json.dumps(plan(next((a for a in args if not a.startswith("--")), None), cached="--cached" in args), ensure_ascii=False))
    elif cmd == "dismiss":
        resolve("dismissed")
    elif cmd == "status":
        print(json.dumps(status(), ensure_ascii=False))
    else:
        print(__doc__)

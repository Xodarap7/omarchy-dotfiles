#!/usr/bin/env python3
import sys
import os
import json
import subprocess
import re
import time
import signal
import sqlite3

def get_hypr_clients():
    try:
        out = subprocess.check_output(['hyprctl', 'clients', '-j'], timeout=2)
        return json.loads(out)
    except Exception:
        return []

def get_proc_parents(pid):
    parents = [pid]
    cur = pid
    while cur > 1:
        try:
            with open(f'/proc/{cur}/stat') as f:
                parts = f.read().split()
                ppid = int(parts[3])
                if ppid <= 1:
                    break
                parents.append(ppid)
                cur = ppid
        except Exception:
            break
    return parents

def parse_agy_info(pid):
    cid = None
    # 1. Look for open presence lock file in fd: ~/.gemini/antigravity-cli/presence/<cid>.lock
    try:
        for fd in os.listdir(f'/proc/{pid}/fd'):
            try:
                target = os.readlink(f'/proc/{pid}/fd/{fd}')
                if '/presence/' in target and target.endswith('.lock'):
                    fname = os.path.basename(target)
                    cand = fname[:-5]
                    if re.match(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', cand):
                        cid = cand
                        break
            except Exception:
                continue
    except Exception:
        pass

    # 2. Fallback: Look for open log files in fd (search backwards from tail of log)
    if not cid:
        try:
            for fd in os.listdir(f'/proc/{pid}/fd'):
                try:
                    target = os.readlink(f'/proc/{pid}/fd/{fd}')
                    if 'cli-' in target and target.endswith('.log'):
                        size = os.path.getsize(target)
                        with open(target, 'r', errors='ignore') as f:
                            TAIL = min(size, 65536)
                            if size > TAIL:
                                f.seek(size - TAIL)
                            tail_lines = f.readlines()
                            for line in reversed(tail_lines):
                                m_conv = re.search(r'(?:Streaming conversation|Created conversation)\s+([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', line)
                                if m_conv:
                                    cid = m_conv.group(1)
                                    break
                                m = re.search(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', line)
                                if m and not cid:
                                    cid = m.group(0)
                        if cid:
                            break
                except Exception:
                    continue
        except Exception:
            pass

    task = "Без задачи"
    status_text = "Ожидает"
    status_code = "idle"
    active_task_desc = ""

    if cid:
        transcript_path = f'/home/yar/.gemini/antigravity-cli/brain/{cid}/.system_generated/logs/transcript.jsonl'
        if os.path.exists(transcript_path):
            try:
                size = os.path.getsize(transcript_path)
                with open(transcript_path, 'r', errors='ignore') as f:
                    # Read first prompt from head of file (fast early exit)
                    for _ in range(30):
                        line = f.readline()
                        if not line:
                            break
                        if 'USER_INPUT' in line:
                            try:
                                obj = json.loads(line)
                                if obj.get('type') == 'USER_INPUT':
                                    raw = obj.get('content', '')
                                    clean = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', raw, flags=re.DOTALL)
                                    clean = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', clean, flags=re.DOTALL)
                                    clean = re.sub(r'<[^>]+>', '', clean).strip()
                                    clean = ' '.join(clean.split())
                                    if clean:
                                        task = clean[:250] + ('...' if len(clean) > 250 else '')
                                        break
                            except Exception:
                                pass

                    # Read tail of file (last 48 KB) for current status and active background tasks
                    TAIL_BYTES = 49152
                    if size > TAIL_BYTES:
                        f.seek(size - TAIL_BYTES)
                        f.readline()  # discard partial line

                    lines = f.readlines()
                    last_step = None
                    last_actionable_step = None
                    active_tasks = {}

                    for l in lines:
                        if not l.strip():
                            continue
                        try:
                            obj = json.loads(l)
                            st = obj.get('type')
                            if st in ('USER_INPUT', 'PLANNER_RESPONSE', 'GENERIC'):
                                last_actionable_step = obj
                            last_step = obj

                            content = str(obj.get('content') or '')
                            # Check task start (only real background tasks belonging to this cid)
                            if 'background task' in content.lower():
                                m = re.search(rf'task id:\s*(?:{cid}/)?(task-\d+)', content, re.IGNORECASE)
                                if m:
                                    tid = m.group(1)
                                    desc = 'Фоновая задача'
                                    m_desc = re.search(r'Task Description:\s*([^\n]+)', content)
                                    if m_desc:
                                        desc = m_desc.group(1).strip('"\'')
                                    active_tasks[tid] = desc

                            # Check task completion
                            m_done = re.search(r'sender=(?:[^\s/]+/)?(task-\d+)', content)
                            if m_done:
                                done_tid = m_done.group(1)
                                active_tasks.pop(done_tid, None)

                            # Check task cancellation
                            m_canc = re.search(r'Task "?(?:[^\s"/]+/)?(task-\d+)"? cancelled', content)
                            if m_canc:
                                canc_tid = m_canc.group(1)
                                active_tasks.pop(canc_tid, None)

                            # Check manage_task kill
                            tool_calls = obj.get('tool_calls') or []
                            for tc in tool_calls:
                                if tc.get('name') == 'manage_task':
                                    args = tc.get('args') or {}
                                    act = str(args.get('Action', '')).strip('"\'')
                                    if act == 'kill':
                                        ktid = str(args.get('TaskId', '')).strip('"\'').split('/')[-1]
                                        active_tasks.pop(ktid, None)
                        except Exception:
                            pass

                    # Status evaluation
                    if active_tasks:
                        first_desc = list(active_tasks.values())[-1]
                        status_code = "busy"
                        if "Timer:" in first_desc or "timer" in first_desc.lower():
                            m_t = re.search(r'Timer:\s*(\d+[a-zA-Z]*)', first_desc)
                            dur = m_t.group(1) if m_t else ""
                            status_text = f"Таймер ({dur})" if dur else "Таймер"
                            active_task_desc = f"⏱️ Таймер ({dur})" if dur else "⏱️ Таймер"
                        elif "Cron:" in first_desc or "cron" in first_desc.lower():
                            status_text = "Крон активен"
                            active_task_desc = "⏱️ Крон-расписание"
                        else:
                            status_text = "Фоновая задача"
                            active_task_desc = "⚙️ " + first_desc[:40]
                    else:
                        eval_step = last_actionable_step or last_step
                        if eval_step:
                            step_type = eval_step.get('type')
                            tool_calls = eval_step.get('tool_calls') or []

                            if step_type in ('USER_INPUT', 'GENERIC'):
                                status_text = "Думает..."
                                status_code = "busy"
                            elif step_type == 'PLANNER_RESPONSE':
                                if tool_calls:
                                    is_q = any(tc.get('name') == 'ask_question' for tc in tool_calls)
                                    if is_q:
                                        status_text = "Ждет ответа"
                                        status_code = "idle"
                                    else:
                                        status_text = "Выполняет команду"
                                        status_code = "busy"
                                else:
                                    status_text = "Ожидает запроса"
                                    status_code = "idle"
                            else:
                                status_text = "Ожидает запроса"
                                status_code = "idle"
            except Exception:
                pass
    else:
        # Check if agy has busy child processes
        try:
            with open(f'/proc/{pid}/task/{pid}/children') as f:
                children = f.read().split()
                if len(children) > 1:
                    status_text = "Выполняет команду"
                    status_code = "busy"
        except Exception:
            pass

    cwd = "?"
    try:
        raw_cwd = os.readlink(f'/proc/{pid}/cwd')
        home = os.path.expanduser('~')
        if raw_cwd == home:
            cwd = "~"
        elif raw_cwd.startswith(home + "/"):
            cwd = "~" + raw_cwd[len(home):]
        else:
            cwd = raw_cwd
    except Exception:
        pass

    return {
        "cid": cid,
        "cid_short": cid[:8] if cid else "",
        "cwd": cwd,
        "task": task,
        "active_task": active_task_desc,
        "status_text": status_text,
        "status_code": status_code,
        "type": "agy",
        "name": "Antigravity (AGY)"
    }

def parse_opencode_info(pid):
    cwd = "?"
    raw_cwd = ""
    try:
        raw_cwd = os.readlink(f'/proc/{pid}/cwd')
        home = os.path.expanduser('~')
        if raw_cwd == home:
            cwd = "~"
        elif raw_cwd.startswith(home + "/"):
            cwd = "~" + raw_cwd[len(home):]
        else:
            cwd = raw_cwd
    except Exception:
        pass

    task = "Сессия OpenCode"
    status_text = "Ожидает запроса"
    status_code = "idle"
    cid = ""
    cid_short = ""

    db_path = os.path.expanduser('~/.local/share/opencode/opencode.db')
    if os.path.exists(db_path):
        try:
            conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
            c = conn.cursor()
            row = None
            if raw_cwd:
                c.execute('SELECT id, title, time_updated, time_idle FROM session_v2 WHERE directory = ? ORDER BY time_updated DESC LIMIT 1', (raw_cwd,))
                row = c.fetchone()
            if not row:
                c.execute('SELECT id, title, time_updated, time_idle FROM session_v2 ORDER BY time_updated DESC LIMIT 1')
                row = c.fetchone()

            if row:
                sid, title, tupd, tidle = row
                cid = sid
                cid_short = ('OC·' + sid[4:10]) if sid.startswith('ses_') else sid[:8]

                # Get the latest user message for current task/prompt
                c2 = conn.cursor()
                c2.execute('SELECT data FROM session_message WHERE session_id = ? AND type = "user" ORDER BY time_created DESC LIMIT 1', (sid,))
                u_row = c2.fetchone()
                if u_row:
                    try:
                        u_data = json.loads(u_row[0])
                        p_text = u_data.get('text', '').strip()
                        if p_text:
                            clean_p = re.sub(r'<[^>]+>', '', p_text).strip()
                            task = ' '.join(clean_p.split())[:250]
                    except Exception:
                        pass
                if task == "Сессия OpenCode" and title:
                    task = title[:250]

                # Check child processes of opencode
                has_busy_children = False
                try:
                    with open(f'/proc/{pid}/task/{pid}/children') as f:
                        children = f.read().split()
                        if children:
                            has_busy_children = True
                except Exception:
                    pass

                if has_busy_children:
                    status_text = "Выполняет команду"
                    status_code = "busy"
                else:
                    c2.execute('SELECT type, data, time_created FROM session_message WHERE session_id = ? ORDER BY time_created DESC LIMIT 1', (sid,))
                    last_msg = c2.fetchone()
                    if last_msg:
                        mtype, mdata_raw, mtime = last_msg
                        if mtype == 'user':
                            status_text = "Думает..."
                            status_code = "busy"
                        elif mtype == 'assistant':
                            try:
                                mdata = json.loads(mdata_raw)
                                if mdata.get('time', {}).get('completed'):
                                    status_text = "Ожидает запроса"
                                    status_code = "idle"
                                else:
                                    status_text = "Генерирует ответ..."
                                    status_code = "busy"
                            except Exception:
                                status_text = "Думает..."
                                status_code = "busy"
                        elif mtype == 'idle':
                            status_text = "Ожидает запроса"
                            status_code = "idle"
                        else:
                            if tidle and tupd and tidle >= tupd:
                                status_text = "Ожидает запроса"
                                status_code = "idle"
                            else:
                                status_text = "Думает..."
                                status_code = "busy"
                    else:
                        status_text = "Ожидает запроса"
                        status_code = "idle"

            conn.close()
        except Exception:
            pass

    return {
        "cid": cid,
        "cid_short": cid_short,
        "cwd": cwd,
        "task": task,
        "active_task": "",
        "status_text": status_text,
        "status_code": status_code,
        "type": "opencode",
        "name": "OpenCode"
    }

def find_running_agent_pids():
    # Ultra-fast pure Python /proc scan (~2-3ms instead of 75ms with pgrep)
    agy_pids = []
    other_agents = []

    known_other = {
        'claude': ('claude', 'Claude Code'),
        'codex': ('codex', 'Codex'),
        'gemini': ('gemini', 'Gemini'),
        'opencode': ('opencode', 'OpenCode'),
        'opencode.exe': ('opencode', 'OpenCode')
    }

    try:
        for pid_str in os.listdir('/proc'):
            if not pid_str.isdigit():
                continue
            pid = int(pid_str)
            try:
                with open(f'/proc/{pid_str}/comm', 'r') as f:
                    comm = f.read().strip()

                if comm == 'agy':
                    agy_pids.append(pid)
                elif comm in known_other:
                    try:
                        with open(f'/proc/{pid_str}/cmdline', 'rb') as f_cmd:
                            cmd = f_cmd.read().replace(b'\x00', b' ').decode('utf-8', errors='ignore')
                            if 'serve --service' in cmd:
                                continue
                    except Exception:
                        pass
                    other_agents.append((pid, known_other[comm][0], known_other[comm][1]))
                elif comm in ('node', 'python', 'python3', 'bun'):
                    with open(f'/proc/{pid_str}/cmdline', 'rb') as f:
                        cmd = f.read().replace(b'\x00', b' ').decode('utf-8', errors='ignore')
                        if 'serve --service' in cmd:
                            continue
                        for k, v in known_other.items():
                            if k in cmd:
                                other_agents.append((pid, v[0], v[1]))
                                break
            except Exception:
                pass
    except Exception:
        pass

    return agy_pids, other_agents

def list_agents():
    clients = get_hypr_clients()
    agents = []

    agy_pids, other_agents = find_running_agent_pids()

    # 1. Process AGY instances
    for pid in agy_pids:
        try:
            info = parse_agy_info(pid)
            parents = get_proc_parents(pid)

            matched_client = None
            for c in clients:
                if c.get('pid') in parents:
                    matched_client = c
                    break

            if not matched_client and not info["cid"]:
                continue

            agents.append({
                "pid": pid,
                "window_pid": matched_client.get("pid") if matched_client else None,
                "cid": info.get("cid", ""),
                "type": info["type"],
                "name": info["name"],
                "task": info["task"],
                "active_task": info.get("active_task", ""),
                "cwd": info.get("cwd", "?"),
                "cid_short": info.get("cid_short", ""),
                "status": info["status_code"],
                "status_text": info["status_text"],
                "workspace": str(matched_client.get("workspace", {}).get("name", "?")) if matched_client else "?",
                "address": matched_client.get("address", "") if matched_client else "",
                "window_title": matched_client.get("title", "") if matched_client else "",
                "has_window": bool(matched_client and matched_client.get("address"))
            })
        except Exception:
            pass

    # 2. Process other agents (OpenCode, Claude, Codex, etc.)
    for pid, agent_bin, agent_name in other_agents:
        try:
            parents = get_proc_parents(pid)
            matched_client = None
            for c in clients:
                if c.get('pid') in parents:
                    matched_client = c
                    break

            if agent_bin == 'opencode':
                info = parse_opencode_info(pid)
                agents.append({
                    "pid": pid,
                    "window_pid": matched_client.get("pid") if matched_client else None,
                    "cid": info.get("cid", ""),
                    "type": info["type"],
                    "name": info["name"],
                    "task": info["task"],
                    "active_task": info.get("active_task", ""),
                    "cwd": info.get("cwd", "?"),
                    "cid_short": info.get("cid_short", ""),
                    "status": info["status_code"],
                    "status_text": info["status_text"],
                    "workspace": str(matched_client.get("workspace", {}).get("name", "?")) if matched_client else "?",
                    "address": matched_client.get("address", "") if matched_client else "",
                    "window_title": matched_client.get("title", "") if matched_client else "",
                    "has_window": bool(matched_client and matched_client.get("address"))
                })
            else:
                cwd = "?"
                try:
                    raw_cwd = os.readlink(f'/proc/{pid}/cwd')
                    home = os.path.expanduser('~')
                    if raw_cwd == home:
                        cwd = "~"
                    elif raw_cwd.startswith(home + "/"):
                        cwd = "~" + raw_cwd[len(home):]
                    else:
                        cwd = raw_cwd
                except Exception:
                    pass

                agents.append({
                    "pid": pid,
                    "window_pid": matched_client.get("pid") if matched_client else None,
                    "type": agent_bin,
                    "name": agent_name,
                    "task": "Сессия " + agent_name,
                    "cwd": cwd,
                    "status": "idle",
                    "status_text": "Активен",
                    "workspace": str(matched_client.get("workspace", {}).get("name", "?")) if matched_client else "?",
                    "address": matched_client.get("address", "") if matched_client else "",
                    "window_title": matched_client.get("title", "") if matched_client else "",
                    "has_window": bool(matched_client and matched_client.get("address"))
                })
        except Exception:
            pass

    return agents

def focus_agent(address):
    if not address:
        return
    try:
        lua_code = f"""
local target = nil
for _, w in ipairs(hl.get_windows()) do
  if w.address == '{address}' then
    target = w
    break
  end
end
if target then
  local cur_ws = hl.get_active_workspace()
  hl.dispatch(hl.dsp.focus({{ window = target }}))
  hl.dispatch(hl.dsp.window.move({{ workspace = tostring(cur_ws.name or cur_ws.id) }}))
  hl.dispatch(hl.dsp.focus({{ window = target }}))
end
"""
        subprocess.run(['hyprctl', 'eval', lua_code], timeout=2)
    except Exception as e:
        sys.stderr.write(f"Focus error: {e}\n")

def kill_agent(pid_str, window_pid_str=""):
    try:
        pid = int(pid_str)
    except Exception:
        pid = None

    try:
        wpid = int(window_pid_str) if window_pid_str else None
    except Exception:
        wpid = None

    # Safety guard: NEVER kill self or parent
    self_pids = {os.getpid(), os.getppid()}

    # If wpid is missing, try to resolve from client list
    if not wpid and pid:
        try:
            clients = get_hypr_clients()
            parents = get_proc_parents(pid)
            for c in clients:
                if c.get('pid') in parents:
                    wpid = c.get('pid')
                    break
        except Exception:
            pass

    # 1. Safely terminate the terminal window process (foot/kitty/etc.)
    if wpid and wpid > 1 and wpid not in self_pids:
        try:
            os.kill(wpid, signal.SIGTERM)
        except Exception:
            pass

    # 2. Terminate the agent process and its children
    if pid and pid > 1 and pid not in self_pids:
        try:
            try:
                with open(f'/proc/{pid}/task/{pid}/children') as f:
                    for c in f.read().split():
                        c_int = int(c)
                        if c_int > 1 and c_int not in self_pids:
                            try:
                                os.kill(c_int, signal.SIGTERM)
                            except Exception:
                                pass
            except Exception:
                pass
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except Exception:
            pass

def get_opencode_history(limit=20, active_cids=None):
    db_path = os.path.expanduser('~/.local/share/opencode/opencode.db')
    if not os.path.exists(db_path):
        return []
    try:
        conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
        c = conn.cursor()
        c.execute('SELECT id, title, time_updated, time_created FROM session_v2 ORDER BY time_updated DESC LIMIT ?', (limit,))
        rows = c.fetchall()
        items = []
        for sid, title, tupd, tcre in rows:
            c2 = conn.cursor()
            c2.execute('SELECT data FROM session_message WHERE session_id = ? AND type = "user" ORDER BY time_created ASC LIMIT 1', (sid,))
            u_row = c2.fetchone()
            prompt = ''
            if u_row:
                try:
                    d = json.loads(u_row[0])
                    prompt = d.get('text', '').strip()
                except Exception:
                    pass
            if not prompt and title:
                prompt = title
            elif not prompt:
                prompt = 'Без названия'

            clean = re.sub(r'<[^>]+>', '', prompt).strip()
            clean = ' '.join(clean.split())
            clean = clean[:140] + ('...' if len(clean) > 140 else '')

            mtime = (tupd / 1000.0) if tupd else ((tcre / 1000.0) if tcre else 0)
            items.append({
                'cid': sid,
                'cid_short': ('OC·' + sid[4:10]) if sid.startswith('ses_') else sid[:8],
                'date': time.strftime('%d.%m %H:%M', time.localtime(mtime)),
                'prompt': clean,
                'mtime': mtime,
                'is_active': sid in (active_cids or set()),
                'type': 'opencode'
            })
        conn.close()
        return items
    except Exception:
        return []

def get_session_history(limit=20, active_cids=None):
    agy_history = []
    brain_dir = os.path.expanduser('~/.gemini/antigravity-cli/brain')
    if os.path.isdir(brain_dir):
        def get_cid_mtime(cid):
            tpath = os.path.join(brain_dir, cid, '.system_generated', 'logs', 'transcript.jsonl')
            if os.path.exists(tpath):
                try:
                    return os.path.getmtime(tpath)
                except Exception:
                    pass
            try:
                return os.path.getmtime(os.path.join(brain_dir, cid))
            except Exception:
                return 0

        try:
            cids = [d for d in os.listdir(brain_dir) if os.path.isdir(os.path.join(brain_dir, d)) and len(d) == 36]
            cids.sort(key=get_cid_mtime, reverse=True)
            for cid in cids[:limit]:
                tpath = os.path.join(brain_dir, cid, '.system_generated', 'logs', 'transcript.jsonl')
                mtime = get_cid_mtime(cid)
                mtime_str = time.strftime('%d.%m %H:%M', time.localtime(mtime))
                prompt = "Без названия"
                if os.path.exists(tpath):
                    try:
                        with open(tpath, 'r', errors='ignore') as f:
                            for _ in range(25):
                                line = f.readline()
                                if not line:
                                    break
                                if 'USER_INPUT' in line:
                                    obj = json.loads(line)
                                    if obj.get('type') == 'USER_INPUT':
                                        raw = obj.get('content', '')
                                        clean = re.sub(r'<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>', '', raw, flags=re.DOTALL)
                                        clean = re.sub(r'<USER_SETTINGS_CHANGE>.*?</USER_SETTINGS_CHANGE>', '', clean, flags=re.DOTALL)
                                        clean = re.sub(r'<[^>]+>', '', clean).strip()
                                        clean = ' '.join(clean.split())
                                        if clean:
                                            prompt = clean[:140] + ('...' if len(clean) > 140 else '')
                                            break
                    except Exception:
                        pass

                agy_history.append({
                    'cid': cid,
                    'cid_short': cid[:8],
                    'date': mtime_str,
                    'prompt': prompt,
                    'mtime': mtime,
                    'is_active': cid in (active_cids or set()),
                    'type': 'agy'
                })
        except Exception:
            pass

    oc_history = get_opencode_history(limit=limit, active_cids=active_cids)
    all_history = agy_history + oc_history
    all_history.sort(key=lambda x: x.get('mtime', 0), reverse=True)
    return all_history[:limit]

def resume_session(cid):
    if not cid:
        return
    # If this session already has an open window, just focus it
    try:
        agents = list_agents()
        for a in agents:
            if a.get('cid') == cid and a.get('address'):
                focus_agent(a.get('address'))
                return
    except Exception:
        pass

    try:
        if cid.startswith('ses_'):
            cmd = ['foot', '--app-id=org.omarchy.opencode', '-e', '/home/yar/.local/bin/opencode', '--session', cid]
        else:
            cmd = ['foot', '--app-id=org.omarchy.agy', '-e', '/usr/bin/agy', '--dangerously-skip-permissions', '--conversation', cid]
        subprocess.Popen(cmd, start_new_session=True)
    except Exception as e:
        sys.stderr.write(f"Direct resume error: {e}\n")
        try:
            if cid.startswith('ses_'):
                cmd_str = f"foot --app-id=org.omarchy.opencode -e /home/yar/.local/bin/opencode --session {cid}"
            else:
                cmd_str = f"foot --app-id=org.omarchy.agy -e /usr/bin/agy --dangerously-skip-permissions --conversation {cid}"
            subprocess.run(['hyprctl', 'dispatch', f'hl.dsp.exec_cmd("{cmd_str}")'], timeout=2)
        except Exception:
            pass

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'focus':
        if len(sys.argv) > 2:
            focus_agent(sys.argv[2])
    elif len(sys.argv) > 1 and sys.argv[1] == 'kill':
        if len(sys.argv) > 2:
            wpid = sys.argv[3] if len(sys.argv) > 3 else ""
            kill_agent(sys.argv[2], wpid)
    elif len(sys.argv) > 1 and sys.argv[1] == 'resume':
        if len(sys.argv) > 2:
            resume_session(sys.argv[2])
    elif len(sys.argv) > 1 and sys.argv[1] == '--lite':
        agents = list_agents()
        print(json.dumps({'active': agents, 'history': []}, ensure_ascii=False))
    else:
        agents = list_agents()
        active_cids = {a.get('cid') for a in agents if a.get('cid')}
        history = get_session_history(limit=20, active_cids=active_cids)
        print(json.dumps({'active': agents, 'history': history}, ensure_ascii=False))

#!/usr/bin/env python3
# Clau猪 Touch Bar 动画常驻程序（由 LaunchAgent com.claudepig.touchbar 保持运行）。
# 每 0.3 秒一帧；只有画面变化时才推给 BTT，空闲时几乎不推送。
import glob, os, json, time, subprocess, urllib.parse

UUID = "2BAC6BA3-2A0B-40A1-881E-028C55BFEAB7"
FR = "/Users/a0000/Claude/touchbar/frames/"
TICK = 0.3
SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"


def claude_running():
    out = subprocess.run(["ps", "-axo", "args"], capture_output=True, text=True).stdout
    return any("claude-code/" in l and "claude.app/Contents/MacOS/claude" in l for l in out.splitlines())


def claude_busy():
    # 读各会话 transcript 最后一条消息：用户消息/工具结果/未说完 = 工作中；end_turn 或被中断 = 空闲
    now = time.time()
    for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
        try:
            age = now - os.path.getmtime(f)
            if age > 600:
                continue
            if age < 4:
                return True
            with open(f, "rb") as fh:
                fh.seek(max(0, os.path.getsize(f) - 200000))
                lines = fh.read().splitlines()
            for l in reversed(lines):
                try:
                    d = json.loads(l)
                except Exception:
                    continue
                if d.get("type") not in ("user", "assistant") or d.get("isSidechain"):
                    continue
                m = d.get("message", {}); c = m.get("content")
                if d["type"] == "assistant":
                    if m.get("stop_reason") in ("tool_use", None):
                        return True
                else:
                    txt = c if isinstance(c, str) else " ".join(x.get("text", "") for x in c if isinstance(x, dict))
                    if "[Request interrupted" not in txt:
                        return True
                break
        except Exception:
            pass
    return False


def push(text, icon, bg):
    q = urllib.parse.quote
    url = (f"btt://update_touch_bar_widget/?uuid={UUID}&text={q(text)}&icon_path={q(FR + icon)}"
           f"&background_color={bg}&font_color=255,255,255,255")
    subprocess.run(["open", "-g", url])


last, state, t_state, i = None, "idle", 0, 0
while True:
    now = time.time()
    if now - t_state >= 1:                      # 状态每秒判断一次，动画每 0.3 秒一帧
        state = ("busy" if claude_busy() else "idle") if claude_running() else "off"
        t_state = now
    if state == "busy":
        # 深蓝底轻微呼吸：亮度在 0.75~1.0 之间来回
        k = 0.75 + 0.25 * abs((i % 12) - 6) / 6
        frame = (f"Clau猪 干活中 {SPIN[i % len(SPIN)]}", f"walk{i % 4}.png",
                 f"{int(30*k)},{int(70*k)},{int(140*k)},255")
    elif state == "idle":
        blink = (i % 15) == 0                   # 约每 4.5 秒眨一次眼
        frame = ("Clau猪 摸鱼中", "blink.png" if blink else "idle.png", "28,28,32,255")
    else:
        frame = ("Clau猪 睡了", "sleep.png", "60,60,64,255")
    if frame != last:
        push(*frame)
        last = frame
    i += 1
    time.sleep(TICK)

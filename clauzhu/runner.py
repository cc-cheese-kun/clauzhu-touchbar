#!/usr/bin/env python3
# Clau猪「跑道」：BTT Touch Bar 上原來的小組件不動，在右邊空地另加一個 300 點寬的小組件「Clau猪跑道」，
# 螃蟹在裡面跑。由 LaunchAgent com.claudepig.runner 常駐。
#   幹活：側身來回跑、上下搖；空閒：原地慢慢上下搖；Claude 沒開：灰色趴著冒 z。
# 幀由 render_track.swift 預先畫好放在 frames/track/（用上一版那套帶陰影的螃蟹，不用張手的幀）。
# 踩過的坑：text 為空時 BTT 會把整個小組件藏起來，所以 text 用零寬空格；BTT 不支援 GIF 圖標。
import os, sys, time, json, subprocess, urllib.parse

UUID_FILE = "/Users/a0000/Claude/touchbar/runner-uuid"
OUT = "/Users/a0000/Claude/touchbar/frames/track/"
CUR = "/Users/a0000/Claude/touchbar/runner-current.json"   # 小組件腳本 cat 這個文件（BTT 重啟後的第一幀）
ZWSP = "​"
BG = "0,0,0,255"     # 每次推送都帶上黑底：不帶的話 BTT 重畫後會退回默認灰底
TICK = 0.02            # open 本身約 0.1 秒，循環主要由它控速；每幀走 3 點
STEP, MAXX = 6, 534    # 和 render_track.swift 一致
POS = list(range(0, MAXX + 1, STEP))


def claude_running():
    out = subprocess.run(["ps", "-axo", "args"], capture_output=True, text=True).stdout
    return any("claude-code/" in l and "claude.app/Contents/MacOS/claude" in l for l in out.splitlines())


def claude_busy():
    r = subprocess.run(["/usr/bin/python3", "/Users/a0000/Claude/claude-state.py"], capture_output=True, text=True)
    return r.stdout.strip() == "busy"


def push(uuid, icon):
    q = urllib.parse.quote
    subprocess.run(["open", "-g", f"btt://update_touch_bar_widget/?uuid={uuid}&text={q(ZWSP)}&icon_path={q(icon)}&background_color={BG}"])


STATE = {"s": "off"}


def watch_state():
    # 狀態判斷要跑 ps 和 claude-state.py，放後台線程，不卡動畫
    while True:
        try:
            STATE["s"] = ("busy" if claude_busy() else "idle") if claude_running() else "off"
        except Exception:
            pass
        time.sleep(1)


def main():
    import threading
    threading.Thread(target=watch_state, daemon=True).start()
    uuid = open(UUID_FILE).read().strip()
    last, i, k, d = None, 0, len(POS) - 1, -1
    while True:
        state = STATE["s"]
        face = "R" if d > 0 else "L"
        if state == "busy":
            if not 0 <= k + d < len(POS): d = -d; face = "R" if d > 0 else "L"
            k += d
            name = f"walk{face}_{POS[k]}"
        elif state == "idle":
            name = f"idle{face}_{POS[k]}_{(i // 3) % 4}"     # 0.24 秒換一下，慢慢搖
        else:
            name = f"sleep_{POS[k]}"
        icon = f"{OUT}{name}.png"
        if icon != last:
            push(uuid, icon)
            with open(CUR, "w") as f: json.dump({"text": ZWSP, "icon_path": icon, "background_color": BG}, f)
            last = icon
        i += 1
        time.sleep(TICK)


if __name__ == "__main__":
    main()

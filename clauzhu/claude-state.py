#!/usr/bin/env python3
# 判断 Claude Code 是否在工作：看各会话 transcript 的最后一条消息，不看 CPU。
# 工作中 = 最后一条是用户消息/工具结果，或助手 stop_reason=tool_use（还没说完），且文件 10 分钟内有更新。
# 空闲 = 最后一条是助手 end_turn，或用户中断。
import glob, os, json, time
now = time.time()
state = "idle"
for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
    try:
        age = now - os.path.getmtime(f)
        if age > 600: continue
        if age < 4: state = "busy"; break  # 刚写入的 4 秒内算工作中，短回复也能看见
        with open(f, "rb") as fh:
            fh.seek(max(0, os.path.getsize(f) - 200000))
            lines = fh.read().splitlines()
        last = None
        for l in reversed(lines):
            try: d = json.loads(l)
            except Exception: continue
            if d.get("type") in ("user", "assistant") and not d.get("isSidechain"):
                last = d; break
        if not last: continue
        m = last.get("message", {}); c = m.get("content")
        if last["type"] == "assistant":
            busy = m.get("stop_reason") in ("tool_use", None)
        else:
            txt = c if isinstance(c, str) else " ".join(x.get("text", "") for x in c if isinstance(x, dict))
            busy = "[Request interrupted" not in txt
        if busy: state = "busy"; break
    except Exception:
        pass
print(state)

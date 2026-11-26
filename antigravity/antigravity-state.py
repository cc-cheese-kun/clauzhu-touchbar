#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
判断 Antigravity 是否在工作：
1. 观察 Antigravity 会话数据（brain/*/transcript.jsonl 与 conversation_summaries.db）
2. 状态判定严格满足：
   - 用户发消息后、回复前：判为工作中 (busy)
   - 回复完成后：保持约 2 秒 busy，之后变为空闲 (idle)
   - 调用工具时（含长时间工具）：判为工作中 (busy)
   - 被用户中断后：变为空闲 (idle)
"""

import glob, os, json, time, sqlite3

def check_interrupted(item):
    """检查是否被用户中断或取消"""
    if not item:
        return False
    if item.get("status") in ("CANCELED", "CANCELLED", "ERROR_CANCELED"):
        return True
    content = str(item.get("content", ""))
    if any(k in content for k in ("[Request interrupted", "Request cancelled", "Tool execution was canceled", "was cancelled")):
        return True
    return False

def get_state():
    now = time.time()
    
    # 查找最近更新的 transcript.jsonl
    transcripts = glob.glob(os.path.expanduser("~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl"))
    if not transcripts:
        return "idle"
    
    # 按修改时间从新到旧排序
    transcripts.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    
    for f in transcripts:
        try:
            mtime = os.path.getmtime(f)
            age = now - mtime
            # 超过 10 分钟没有变动的会话忽略
            if age > 600:
                continue

            # 读取文件末尾最新记录
            size = os.path.getsize(f)
            read_size = min(size, 40000)
            with open(f, "rb") as fh:
                if size > read_size:
                    fh.seek(size - read_size)
                lines = fh.read().splitlines()

            last_meaningful = None
            for l in reversed(lines):
                try:
                    d = json.loads(l)
                except Exception:
                    continue
                t = d.get("type")
                if t in ("USER_INPUT", "PLANNER_RESPONSE", "GENERIC", "SYSTEM_MESSAGE"):
                    last_meaningful = d
                    break

            if not last_meaningful:
                continue

            # 1. 检查是否处于被中断状态
            if check_interrupted(last_meaningful):
                return "idle"

            t = last_meaningful.get("type")

            # 2. 用户刚发消息，模型在思考准备回复 -> busy
            if t == "USER_INPUT":
                return "busy"

            # 3. 工具刚刚返回输出，模型在思考下一步 -> busy
            if t == "GENERIC":
                return "busy"

            # 4. 系统消息如果不是中断 -> busy
            if t == "SYSTEM_MESSAGE":
                return "busy"

            # 5. 规划器响应
            if t == "PLANNER_RESPONSE":
                tool_calls = last_meaningful.get("tool_calls")
                if tool_calls and len(tool_calls) > 0:
                    # 正在调用/等待工具执行 -> busy
                    return "busy"
                else:
                    # 已经说完，这是对用户的最终回答
                    # 在回复完成后的 4 秒内保持 busy，2 秒后变为空闲
                    if age < 2.0:
                        return "busy"
                    else:
                        return "idle"
        except Exception:
            pass

    return "idle"

if __name__ == "__main__":
    print(get_state())

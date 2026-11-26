#!/bin/bash
# 常驻循环：每秒判断一次状态（claude-status.sh 只在变化时才推送）。
# 不用 launchd 的 StartInterval，因为它实际最快 10 秒才跑一次。
while true; do
  /bin/bash /Users/a0000/Claude/claude-status.sh >/dev/null 2>&1
  sleep 1
done

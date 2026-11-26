#!/bin/bash
# 由 BetterTouchTool 的 Touch Bar「Shell 脚本/任务小组件」每 5 秒运行一次。
# 作用：判断 Claude 是否在工作，并通过 BTT 的 URL 接口把图标+文字推给该小组件。
# 判断依据：claude-state.py 读 transcript 最后一条消息（不再用 CPU）。
WIDGET_UUID="2BAC6BA3-2A0B-40A1-881E-028C55BFEAB7"
ICON="/Users/a0000/Claude/touchbar/crab.png"

st=$(/usr/bin/python3 /Users/a0000/Claude/claude-state.py)
if ! ps -axo args | grep -E "claude-code/.*/claude\.app/Contents/MacOS/claude" | grep -qv grep; then
  text="Clau猪 离线"; bg="70,70,75,255"
elif [ "$st" = "busy" ]; then
  text="Clau猪 工作"; bg="30,70,140,255"
else
  text="Clau猪 空闲"; bg="28,28,32,255"
fi
cpu=-
# 只在内容变化时推送：每次推送 BTT 都会重画小组件，重复推送会闪。
# 记录里带上 BTT 的进程号，BTT 重启后会重新推一次，避免它重启后一直空白。
CACHE="/Users/a0000/Claude/touchbar/last-push"
btt_pid=$(pgrep -x BetterTouchTool 2>/dev/null || ps -axo pid,args | awk '/MacOS\/BetterTouchTool$/{print $1}')
key="${text}|${bg}|${btt_pid}"
if [ "$(cat "$CACHE" 2>/dev/null)" != "$key" ]; then
  enc=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$text")
  iconenc=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$ICON")
  open -g "btt://update_touch_bar_widget/?uuid=${WIDGET_UUID}&text=${enc}&icon_path=${iconenc}&background_color=${bg}&font_color=255,255,255,255"
  echo "$key" > "$CACHE"
fi
# BTT 每 5 秒自己跑这个脚本，会用输出覆盖小组件。输出 BTT 支持的 JSON（文字+图标+颜色），
# 这样它覆盖后图标和颜色也还在，和推送的内容一致。
printf '{"text":"%s","icon_path":"%s","background_color":"%s","font_color":"255,255,255,255"}\n' "$text" "$ICON" "$bg"

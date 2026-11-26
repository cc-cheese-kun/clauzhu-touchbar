#!/bin/bash
# BetterTouchTool Touch Bar 状态推送脚本：获取 Antigravity 状态并推送到 BTT Touch Bar 小组件
# 两条路都会跑它：LaunchAgent（每 2 秒）和 BTT 小组件自己（每 5 秒，读输出）。
# 防闪（2026-11-18）：
#  - 输出 JSON（带底色+图标），BTT 自己跑脚本时不会退回默认灰底；
#  - 只有状态变了才 open 推送，不再每 2 秒重画一次；
#  - 工作→空闲要稳定 4 秒才切，避免两步之间的空隙来回跳。
# 旧版：antigravity-status.sh.bak

WIDGET_UUID="AADC6407-9709-4BAF-993F-8274F7F42E6D"
ICON="/Users/a0000/Antigravity-touchbar/antigravity.png"
DIR="/Users/a0000/Antigravity-touchbar"
LAST="$DIR/.last-state"
BUSY_AT="$DIR/.last-busy"
HOLD=4

if ! ps -axo args | grep -E "/Applications/Antigravity\.app/Contents/MacOS/Antigravity" | grep -qv grep; then
  state=off
else
  st=$(/usr/bin/python3 "$DIR/antigravity-state.py")
  now=$(date +%s)
  if [ "$st" = "busy" ]; then
    echo "$now" > "$BUSY_AT"; state=busy
  else
    lb=$(cat "$BUSY_AT" 2>/dev/null || echo 0)
    if [ $((now - lb)) -lt $HOLD ]; then state=busy; else state=idle; fi
  fi
fi

case $state in
  off)  text="Antigravity 离线"; bg="70,70,75,255" ;;
  busy) text="Antigravity 工作"; bg="30,70,140,255" ;;
  *)    text="Antigravity 空闲"; bg="28,28,32,255" ;;
esac

# 只在状态变化时推送
if [ "$(cat "$LAST" 2>/dev/null)" != "$state" ]; then
  echo "$state" > "$LAST"
  enc=$(/usr/bin/python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$text")
  iconenc=$(/usr/bin/python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$ICON")
  open -g "btt://update_touch_bar_widget/?uuid=${WIDGET_UUID}&text=${enc}&icon_path=${iconenc}&background_color=${bg}&font_color=255,255,255,255"
fi

# BTT 读这一行：带底色和图标，和推送的一致
printf '{"text":"%s","icon_path":"%s","background_color":"%s","font_color":"255,255,255,255"}\n' "$text" "$ICON" "$bg"

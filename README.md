# Clau猪 Touch Bar 小组件（已停用存档）

MacBook Pro Touch Bar 上显示 AI 工作状态的小组件，靠 [BetterTouchTool](https://folivora.ai/)（BTT）的「Shell 脚本 / 任务小组件」加 `btt://` URL 推送实现。

2026-11-26 起已停用：BTT 已卸载，后台常驻任务已停，这里只是存档。

## 里面有什么

| 目录 | 内容 |
|---|---|
| `clauzhu/` | Clau猪：判断 Claude Code 在干活 / 空闲 / 离线，推给 Touch Bar |
| `clauzhu/claude-state.py` | 读 `~/.claude/projects/*/*.jsonl` 最后一条消息判断忙闲（不看 CPU） |
| `clauzhu/claude-status.sh` + `loop.sh` | 状态小组件：橙色像素螃蟹 + 「Clau猪 工作/空闲/离线」，只在状态变化时推送 |
| `clauzhu/runner.py` + `render_track.swift` + `frames/track/` | 跑道小组件：300pt 宽，小螃蟹干活时边走边晃、空闲慢慢晃、离线变灰打 z |
| `clauzhu/make_frames.py` | 纯 Python 画 12×12 像素螃蟹帧（`frames/*.png`） |
| `clauzhu/native/` | 全宽原生 Touch Bar 版（Swift，私有 DFRFoundation），fork 自 [Srtvanes/Clawd-TouchBar-Pet](https://github.com/Srtvanes/Clawd-TouchBar-Pet)（MIT，见 `native/LICENSE`、`native/ATTRIBUTION.md`）。当时就停用了，因为系统模态 Touch Bar 会盖住 BTT |
| `antigravity/` | Antigravity 的同款状态小组件 |
| `launchagents/` | 当时用的 LaunchAgent（`com.claudepig.touchbar`、`com.claudepig.runner`、`com.antigravity.touchbar`） |
| `btt/btt-triggers.json` | BTT 里 4 个 Touch Bar 小组件的导出（`get_triggers`） |

## 踩过的坑

- 每次推送都要带 `background_color=0,0,0,255`，不然 BTT 重画后退回默认灰底。
- 小组件文字为空时 BTT 会把它藏起来，要用零宽空格。
- BTT 不能显示 GIF 图标（小组件直接消失），动画只能逐帧推 PNG，约 7 fps 封顶。
- BTT 自己也会定时跑小组件脚本并用输出覆盖显示，所以脚本输出 JSON（文字 + 图标 + 底色），和推送内容一致才不闪。

## 想恢复的话

1. 装回 BetterTouchTool，按 `btt/btt-triggers.json` 建回小组件（UUID 要和脚本里的一致）。
2. 脚本里写死了 `/Users/a0000/...` 路径，换机器要改。
3. 把 `launchagents/` 里的 plist 放回 `~/Library/LaunchAgents/`，然后 `launchctl load`。

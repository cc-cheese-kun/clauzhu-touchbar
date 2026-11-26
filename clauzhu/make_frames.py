#!/usr/bin/env python3
# 画 Clau猪 小螃蟹的动画帧（纯 Python 写 PNG，不依赖第三方库）。
# 造型沿用原来的 crab.png（12x12 网格，每格 10 像素 = 120x120），只做动作变化。
import zlib, struct, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frames")
N, S = 12, 10
COL = {
    "O": (218, 119, 88, 255),   # 螃蟹橙
    "K": (0, 0, 0, 255),        # 眼睛
    "G": (135, 135, 140, 255),  # 睡觉的灰螃蟹
    "g": (40, 40, 44, 255),     # 灰螃蟹闭眼
    "Z": (210, 215, 235, 255),  # z
}

BASE = [
    "............",
    "............",
    "..OOOOOOOO..",
    "..OKOOOOKO..",
    "OOOKOOOOKOOO",   # 两侧是手臂
    "OOOOOOOOOOOO",
    "..OOOOOOOO..",
    "..OOOOOOOO..",
    "..O.O..O.O..",   # 4 条腿
    "..O.O..O.O..",
    "............",
    "............",
]


def png(path, grid):
    px = N * S
    rows = []
    for y in range(px):
        row = bytearray(b"\x00")
        for x in range(px):
            row += bytes(COL.get(grid[y // S][x // S], (0, 0, 0, 0)))
        rows.append(bytes(row))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", px, px, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))
    open(path, "wb").write(data)


def edit(rows, changes):
    g = list(rows)
    for r, line in changes.items():
        g[r] = line
    return g


ARMS_UP = {3: "OOOKOOOOKOOO", 4: "..OKOOOOKO.."}
STEP_L = {9: "....O....O.."}   # 第 1、3 条腿抬起
STEP_R = {9: "..O....O...."}   # 第 2、4 条腿抬起

os.makedirs(OUT, exist_ok=True)
# 工作中：手臂上下挥 + 腿左右迈步，4 帧
png(f"{OUT}/walk0.png", BASE)
png(f"{OUT}/walk1.png", edit(BASE, {**ARMS_UP, **STEP_L}))
png(f"{OUT}/walk2.png", BASE)
png(f"{OUT}/walk3.png", edit(BASE, {**ARMS_UP, **STEP_R}))
# 空闲：站着 / 眨眼（眼睛只剩下半截）
png(f"{OUT}/idle.png", BASE)
png(f"{OUT}/blink.png", edit(BASE, {3: "..OOOOOOOO.."}))
# 未运行：灰色、闭眼、趴下（身体下沉、腿收起），右上角冒 z
sleep = ["............"] * 2 + [l.replace("O", "G") for l in BASE[2:8]]
sleep[3] = "..GGGGGGGG.."
sleep[4] = "GGggGGGGggGG"
sleep = ["............"] * 2 + sleep[:-2] + ["............"] * 2   # 整体下沉 2 格
sleep = (sleep + ["............"] * 12)[:12]
g = [list(r) for r in sleep]
for (x, y) in [(8, 0), (9, 0), (10, 0), (11, 0), (10, 1), (9, 2), (8, 3), (9, 3), (10, 3), (11, 3)]:
    g[y][x] = "Z"
png(f"{OUT}/sleep.png", ["".join(r) for r in g])
print("ok", sorted(os.listdir(OUT)))

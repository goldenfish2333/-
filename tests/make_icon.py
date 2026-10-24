import os
from PIL import Image, ImageDraw

S = 1024
out = Image.new("RGB", (S, S))
d = ImageDraw.Draw(out)

# 竖向渐变底色：深墨绿 -> 亮青绿
top = (16, 74, 66)
bottom = (32, 158, 122)
for y in range(S):
    t = y / (S - 1)
    d.line(
        [(0, y), (S, y)],
        fill=(
            round(top[0] + (bottom[0] - top[0]) * t),
            round(top[1] + (bottom[1] - top[1]) * t),
            round(top[2] + (bottom[2] - top[2]) * t),
        ),
    )

# 中间一张白色小票
wx, hy = 330, 430
left, right = (S - wx) // 2, (S + wx) // 2
top_y = (S - hy) // 2
bot_y = top_y + hy
d.rectangle([left, top_y, right, bot_y], fill=(255, 255, 255))

# 底部锯齿边
teeth = 8
step = wx / (teeth * 2)
x = left
for i in range(teeth * 2):
    if i % 2 == 0:
        d.polygon(
            [(x, bot_y), (x + step, bot_y), (x + step / 2, bot_y + step)],
            fill=(255, 255, 255),
        )
    x += step

# 上半：三条「账目行」占位横线
line_color = (200, 216, 212)
for i in range(3):
    y = top_y + 62 + i * 56
    w = wx - 116 if i % 2 == 0 else wx - 172
    d.rounded_rectangle([left + 58, y, left + 58 + w, y + 17], radius=8, fill=line_color)

# 下半：人民币符号 ¥
cx = 512
arm_y = top_y + 205
apex_y = arm_y + 62
d.line([(cx - 58, arm_y), (cx, apex_y), (cx + 58, arm_y)], fill=top, width=21, joint="curve")
d.line([(cx, apex_y), (cx, apex_y + 98)], fill=top, width=21)
for dy in (18, 46):
    d.line([(cx - 66, apex_y + dy), (cx + 66, apex_y + dy)], fill=top, width=17)

# ---- 导出各尺寸 ----
target = r"D:\dsh\screenshot-ledger\ScreenshotLedger\Assets.xcassets\AppIcon.appiconset"
os.makedirs(target, exist_ok=True)

legacy = {
    "icon-20@2x.png": 40, "icon-20@3x.png": 60,
    "icon-29@2x.png": 58, "icon-29@3x.png": 87,
    "icon-40@2x.png": 80, "icon-40@3x.png": 120,
    "icon-60@2x.png": 120, "icon-60@3x.png": 180,
    "icon-76@1x.png": 76, "icon-76@2x.png": 152,
    "icon-83.5@2x.png": 167,
    "icon-1024.png": 1024,
}
for name, px in legacy.items():
    out.resize((px, px), Image.LANCZOS).save(os.path.join(target, name))
print("ok", len(legacy), "files")

# WattCap Launcher v2 - sprite generator. Rotates only the two fan disks of rtxf1.png
# (9 blades -> 40 deg period), LANCZOS-downscales exactly like rtxf1.ico was made.
import sys, numpy as np
from PIL import Image, ImageDraw, ImageFilter
SRC = sys.argv[1] if len(sys.argv) > 1 else 'rtxf1.png'
N = 80; PERIOD = 40.0                      # frames per blade period (0.5 deg steps), degrees
CENTERS = [(322.165, 500.165), (702.165, 500.165)]  # continuous coords (1024 px)
R = 177.0                                  # cut in the middle of the uniform dark ring
SIZES = [24,32,36,40,48,56,60,64,72,80,96,112,120,128,144,160,168,192,240,256]
src = Image.open(SRC).convert('RGBA')
W = src.size[0]
# soft mask, supersampled
ss = 4; masks = []
for cx, cy in CENTERS:
    m = Image.new('L', (W*ss, W*ss), 0)
    ImageDraw.Draw(m).ellipse([(cx-R)*ss, (cy-R)*ss, (cx+R)*ss, (cy+R)*ss], fill=255)
    masks.append(m.resize((W, W), Image.LANCZOS))
frames = []
for i in range(N):
    ang = PERIOD * i / N
    if i == 0: frames.append(src); continue
    out = src.copy()
    for (cx, cy), mask in zip(CENTERS, masks):
        rot = src.rotate(-ang, resample=Image.BICUBIC, center=(cx, cy))  # clockwise
        out = Image.composite(rot, out, mask)
    frames.append(out)
for s in SIZES:
    sheet = Image.new('RGBA', (s*N, s))
    for i, f in enumerate(frames):
        sheet.paste(f.resize((s, s), Image.LANCZOS), (i*s, 0))
    sheet.save('assets/fans_%d.png' % s, optimize=True)
print('ok')

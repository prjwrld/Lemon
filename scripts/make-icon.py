"""Makes Lemon's app icon set from Design/AppIcon-source.webp.
Cuts the icon out of its dark background and places it on Apple's 1024 px macOS grid.
Run from the project folder: python3 scripts/make-icon.py (needs numpy and Pillow)."""
import json
import numpy as np
from PIL import Image, ImageFilter
src = Image.open("Design/AppIcon-source.webp").convert("RGB")
a = np.asarray(src).astype(np.float32) / 255
h, w, _ = a.shape
bg = np.median(np.concatenate([a[:20, :20].reshape(-1, 3), a[-20:, -20:].reshape(-1, 3)]), axis=0)
lum = a @ np.array([0.2126, 0.7152, 0.0722])
lbg = bg @ np.array([0.2126, 0.7152, 0.0722])
alpha = np.clip((lum - lbg) / (0.93 - lbg), 0, 1)
inside = alpha > 0.5
# The icon body is convex: everything between its edges (rows and columns) is solid.
rows = np.zeros_like(inside); cols = np.zeros_like(inside)
for y in range(h):
    xs = np.flatnonzero(inside[y])
    if xs.size: rows[y, xs[0] + 3:xs[-1] - 2] = True
for x in range(w):
    ys = np.flatnonzero(inside[:, x])
    if ys.size: cols[ys[0] + 3:ys[-1] - 2, x] = True
alpha[rows & cols] = 1
# Remove the dark background mixed into edge pixels.
safe = np.maximum(alpha, 1e-3)[..., None]
rgb = np.clip((a - bg * (1 - alpha[..., None])) / safe, 0, 1)
rgba = np.dstack([rgb, alpha])
img = Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBA")
ys, xs = np.nonzero(alpha > 0.02)
img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
# Apple's macOS grid: 1024 canvas, 824 body, with a soft shadow.
scale = 824 / max(img.size)
body = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
ox, oy = (1024 - body.width) // 2, (1024 - body.height) // 2
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
mask = body.split()[3].point(lambda v: int(v * 0.28))
shadow.paste((0, 0, 0, 255), (ox, oy + 12), mask)
shadow = shadow.filter(ImageFilter.GaussianBlur(14))
canvas = Image.alpha_composite(canvas, shadow)
canvas.alpha_composite(body, (ox, oy))
folder = "Lemon/Assets.xcassets/AppIcon.appiconset"
images = []
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        canvas.resize((size * scale, size * scale), Image.LANCZOS).save(f"{folder}/{name}")
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{size}x{size}"})
json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(f"{folder}/Contents.json", "w"), indent=2)

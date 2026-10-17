"""Makes Lemon's menu bar icon from Design/AppIcon-source.webp.
Keeps only the six yellow slices (not their thin outer rims, which blur at 16 pt) as a
black template image, so macOS tints it for light and dark menu bars and the active state.
Run from the project folder: python3 scripts/make-menubar-icon.py (needs numpy, scipy and Pillow)."""
import json
import os
import numpy as np
from PIL import Image
from scipy import ndimage

src = Image.open("Design/AppIcon-source.webp").convert("RGB")
a = np.asarray(src).astype(np.float32) / 255
# Yellow is bright in red and green and dark in blue; white and the dark background are not.
alpha = np.clip((np.minimum(a[..., 0], a[..., 1]) - a[..., 2] - 0.15) / 0.45, 0, 1)
# The slices are thick; the rims around them are thin. Keep shapes thicker than 40 px.
shapes, count = ndimage.label(alpha > 0.5)
thickness = ndimage.maximum(ndimage.distance_transform_edt(alpha > 0.5), shapes, range(1, count + 1))
slices = np.isin(shapes, 1 + np.flatnonzero(np.asarray(thickness) > 40))
alpha *= ndimage.binary_dilation(slices, iterations=4)
img = Image.fromarray((alpha * 255).round().astype(np.uint8), "L")
ys, xs = np.nonzero(alpha > 0.02)
img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
side = max(img.size)
square = Image.new("L", (side, side), 0)
square.paste(img, ((side - img.width) // 2, (side - img.height) // 2))

# Menu bar icons sit in an 18 pt square; the lemon fills 16 pt of it.
folder = "Lemon/Assets.xcassets/MenuBarIcon.imageset"
os.makedirs(folder, exist_ok=True)
images = []
for scale in [1, 2, 3]:
    canvas = Image.new("L", (18 * scale, 18 * scale), 0)
    glyph = square.resize((16 * scale, 16 * scale), Image.LANCZOS)
    canvas.paste(glyph, (scale, scale))
    rgba = Image.merge("RGBA", [Image.new("L", canvas.size, 0)] * 3 + [canvas])
    name = f"menubar{'' if scale == 1 else f'@{scale}x'}.png"
    rgba.save(f"{folder}/{name}")
    images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
json.dump({"images": images, "info": {"author": "xcode", "version": 1},
           "properties": {"template-rendering-intent": "template"}},
          open(f"{folder}/Contents.json", "w"), indent=2)

"""Draws the background of Lemon's install window (the DMG): soft lemon glow, an arrow from Lemon to Applications
and one line of help. Run from the project folder: python3 scripts/make-dmg-background.py (needs Pillow).
Icon positions in Config/dmg-settings.py match it: Lemon at (170, 200), Applications at (490, 200)."""
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageFont

def draw(scale):
    w, h = 660 * scale, 400 * scale
    img = Image.new("RGB", (w, h), (250, 248, 240))
    glow = Image.new("RGB", (w, h), (250, 248, 240))
    d = ImageDraw.Draw(glow)
    d.ellipse((w * 0.05, -h * 0.6, w * 0.95, h * 0.55), fill=(255, 232, 140))
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(120 * scale)), 0.55)
    d = ImageDraw.Draw(img)
    # Arrow between the two icons.
    y = 200 * scale
    d.line((262 * scale, y, 388 * scale, y), fill=(225, 160, 20), width=5 * scale)
    d.polygon([(400 * scale, y), (382 * scale, y - 12 * scale), (382 * scale, y + 12 * scale)], fill=(225, 160, 20))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 15 * scale)
    except OSError:
        font = ImageFont.load_default()
    text = "Drag Lemon into Applications, then open it from there."
    tw = d.textlength(text, font=font)
    d.text(((w - tw) / 2, 330 * scale), text, fill=(110, 105, 95), font=font)
    return img

draw(1).save("Config/dmg/background.png")
draw(2).save("Config/dmg/background@2x.png")
subprocess.run(["tiffutil", "-cathidpicheck", "Config/dmg/background.png", "Config/dmg/background@2x.png",
                "-out", "Config/dmg/background.tiff"], check=True)

"""Generates CourseGrab's app icons (macOS asset catalog + Windows .ico).

    python3 tool/generate_icons.py

Design: blue rounded square with a white "download into tray" glyph, matching
the in-app logo mark. Drawn at 4x and downsampled for clean anti-aliasing.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BLUE_TOP = (79, 145, 255)
BLUE_BOTTOM = (37, 99, 235)
WHITE = (255, 255, 255, 255)


def render(size: int, macos_margin: bool) -> Image.Image:
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    # macOS Big Sur+ icons sit inside the canvas with room for a shadow.
    inset = int(s * 0.098) if macos_margin else int(s * 0.02)
    box = (inset, inset, s - inset, s - inset)
    w = box[2] - box[0]
    radius = int(w * 0.225)

    if macos_margin:
        shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (box[0], box[1] + int(s * 0.012), box[2], box[3] + int(s * 0.012)),
            radius, fill=(0, 0, 0, 90))
        img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s * 0.014)))

    # Vertical blue gradient clipped to the rounded square.
    grad = Image.new("RGBA", (s, s))
    gd = ImageDraw.Draw(grad)
    for y in range(s):
        t = min(max((y - box[1]) / max(w, 1), 0), 1)
        c = tuple(int(BLUE_TOP[i] + (BLUE_BOTTOM[i] - BLUE_TOP[i]) * t) for i in range(3))
        gd.line([(0, y), (s, y)], fill=c + (255,))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # Glyph: arrow shaft + head + tray.
    d = ImageDraw.Draw(img)
    cx = s / 2
    stroke = w * 0.085
    top, head_y = box[1] + w * 0.22, box[1] + w * 0.56
    d.rounded_rectangle((cx - stroke / 2, top, cx + stroke / 2, head_y + stroke * 0.2),
                        radius=stroke / 2, fill=WHITE)
    hw = w * 0.21
    d.line([(cx - hw, head_y - hw * 0.95), (cx, head_y + stroke * 0.35)], fill=WHITE, width=int(stroke))
    d.line([(cx + hw, head_y - hw * 0.95), (cx, head_y + stroke * 0.35)], fill=WHITE, width=int(stroke))
    for x in (cx - hw, cx + hw):
        d.ellipse((x - stroke / 2, head_y - hw * 0.95 - stroke / 2, x + stroke / 2, head_y - hw * 0.95 + stroke / 2), fill=WHITE)
    d.ellipse((cx - stroke / 2, head_y + stroke * 0.35 - stroke / 2, cx + stroke / 2, head_y + stroke * 0.35 + stroke / 2), fill=WHITE)
    tray_y = box[1] + w * 0.76
    tw = w * 0.30
    d.rounded_rectangle((cx - tw, tray_y - stroke / 2, cx + tw, tray_y + stroke / 2), radius=stroke / 2, fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    icons = ROOT / "assets" / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    render(1024, macos_margin=False).save(icons / "app_icon_1024.png")

    mac = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        render(size, macos_margin=True).save(mac / f"app_icon_{size}.png")

    win = render(256, macos_margin=False)
    win.save(ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icons written")


if __name__ == "__main__":
    main()

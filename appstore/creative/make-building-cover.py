"""Cover image for the Building panel: three Handscroll screens on Cloud Dancer paper."""
from PIL import Image, ImageDraw, ImageFilter

W, H = 2400, 1200
BG = (240, 238, 233)          # Cloud Dancer surface-base
TINT = (238, 243, 243)        # accent-subtle
LINE = (228, 225, 218)

canvas = Image.new("RGB", (W, H), BG)
# soft accent wash in the top-left, like the page's hero panel
wash = Image.new("RGBA", (W, H), (0, 0, 0, 0))
wd = ImageDraw.Draw(wash)
wd.ellipse([-500, -600, 1200, 700], fill=TINT + (170,))
wash = wash.filter(ImageFilter.GaussianBlur(160))
canvas = Image.alpha_composite(canvas.convert("RGBA"), wash).convert("RGB")
draw = ImageDraw.Draw(canvas)

shots = ["split.png", "drift.png", "settings.png"]
TARGET_H = 880
imgs = []
for name in shots:
    im = Image.open(f"docs/assets/{name}").convert("RGB")
    w = round(im.width * TARGET_H / im.height)
    imgs.append(im.resize((w, TARGET_H), Image.LANCZOS))

gap = 42
total = sum(i.width for i in imgs) + gap * (len(imgs) - 1)
x = (W - total) // 2
y0 = (H - TARGET_H) // 2

for idx, im in enumerate(imgs):
    y = y0 + (0 if idx == 1 else (-26 if idx == 0 else 18))
    radius = 52
    # shadow
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [x - 8, y + 26, x + im.width + 8, y + im.height + 26],
        radius=radius + 8, fill=(44, 42, 39, 66),
    )
    sh = sh.filter(ImageFilter.GaussianBlur(38))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), sh).convert("RGB")
    # screenshot with rounded corners
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=radius, fill=255)
    canvas.paste(im, (x, y), mask)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        [x, y, x + im.width - 1, y + im.height - 1], radius=radius, outline=LINE, width=2
    )
    x += im.width + gap

canvas.save("/Users/weirui/dev/media/handscroll/cover.png")
print("saved", canvas.size)

"""Compose the App Store universal creative asset (5244 x 2950, opaque PNG)."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 5244, 2950
BG = (246, 247, 249)
TEXT = (17, 19, 23)
SECONDARY = (107, 114, 128)
MUTED = (154, 160, 172)
STROKE = (228, 231, 236)

SF = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight):
    f = ImageFont.truetype(SF, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def text_size(draw, s, f, tracking=0):
    if tracking == 0:
        return draw.textlength(s, font=f)
    return sum(draw.textlength(ch, font=f) for ch in s) + tracking * (len(s) - 1)


def draw_tracked(draw, xy, s, f, fill, tracking):
    x, y = xy
    for ch in s:
        draw.text((x, y), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + tracking


canvas = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(canvas)

# --- right: screenshot in a white rounded card -------------------------------
shot = Image.open("appstore/screenshots-6.3/01-split.png").convert("RGB")
shot_h = 2100
shot_w = round(shot.width * shot_h / shot.height)          # 1206x2622 -> ~966
shot = shot.resize((shot_w, shot_h), Image.LANCZOS)
radius = 64
card_x, card_y = W - 778 - shot_w, (H - shot_h) // 2

# soft shadow
shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle(
    [card_x - 10, card_y + 30, card_x + shot_w + 10, card_y + shot_h + 30],
    radius=radius + 10, fill=(17, 19, 23, 60),
)
shadow = shadow.filter(ImageFilter.GaussianBlur(46))
canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
draw = ImageDraw.Draw(canvas)

# white card + screenshot clipped to rounded corners
card = Image.new("RGB", (shot_w, shot_h), (255, 255, 255))
card.paste(shot, (0, 0))
mask = Image.new("L", (shot_w, shot_h), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot_w - 1, shot_h - 1], radius=radius, fill=255)
canvas.paste(card, (card_x, card_y), mask)
draw = ImageDraw.Draw(canvas)
draw.rounded_rectangle(
    [card_x, card_y, card_x + shot_w - 1, card_y + shot_h - 1],
    radius=radius, outline=STROKE, width=3,
)

# --- left: icon, wordmark, tagline ------------------------------------------
icon = Image.open("Seamless/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png").convert("RGB")
icon_size = 300
icon = icon.resize((icon_size, icon_size), Image.LANCZOS)
icon_radius = round(icon_size * 0.225)
icon_mask = Image.new("L", (icon_size, icon_size), 0)
ImageDraw.Draw(icon_mask).rounded_rectangle([0, 0, icon_size - 1, icon_size - 1], radius=icon_radius, fill=255)
icon_x, icon_y = 780, 760

# same soft shadow as the screenshot card
icon_shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(icon_shadow).rounded_rectangle(
    [icon_x - 6, icon_y + 18, icon_x + icon_size + 6, icon_y + icon_size + 18],
    radius=icon_radius + 6, fill=(17, 19, 23, 46),
)
canvas = Image.alpha_composite(canvas.convert("RGBA"), icon_shadow.filter(ImageFilter.GaussianBlur(28))).convert("RGB")
draw = ImageDraw.Draw(canvas)

canvas.paste(icon, (icon_x, icon_y), icon_mask)
draw = ImageDraw.Draw(canvas)

wordmark = font(300, "Semibold")
tracking = 3
wm_w = text_size(draw, "handscroll", wordmark, tracking)
wm_y = icon_y + icon_size + 110
draw_tracked(draw, ((icon_x + 700 - wm_w) / 2 if False else icon_x, wm_y), "handscroll", wordmark, TEXT, tracking)

tagline = font(104, "Regular")
draw.text((icon_x, wm_y + 400), "One wide photo, a few good ways to post it.", font=tagline, fill=SECONDARY)

modes = font(80, "Regular")
draw.text((icon_x, wm_y + 560), "Split  ·  Fit  ·  Crop  ·  Drift", font=modes, fill=MUTED)

canvas.save("appstore/creative/universal-5244x2950.png")
print("saved", canvas.size)

# --- previews of the two placements -----------------------------------------
header_h = round(W / (21 / 9))
header = canvas.crop((0, (H - header_h) // 2, W, (H - header_h) // 2 + header_h))
header.resize((1600, round(1600 * header_h / W)), Image.LANCZOS).save("/tmp/creative-header.png")

search_w = round(H * 3 / 2)
search = canvas.crop(((W - search_w) // 2, 0, (W - search_w) // 2 + search_w, H))
search.resize((round(1400 * search_w / H), 1400), Image.LANCZOS).save("/tmp/creative-search.png")
print("previews saved")

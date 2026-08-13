"""Draws the still layers the finished video is composited from.

ffmpeg can draw text, but not well: no kerning control, no wrapping, and one
`drawtext` filter per line. Everything typographic is therefore rendered here
with Pillow into transparent PNGs, and ffmpeg only ever overlays them.

Layers, bottom to top:

    bg.png          opaque backdrop, brand gradient plus the shadow the phone
                    appears to cast
    <the recording> scaled into SCREEN and overlaid
    frame.png       RGBA phone bezel with a hole where SCREEN is, so the video
                    gets rounded corners and a body for free
    caption-*.png   RGBA, one per beat, full-frame
    title.png       opaque opening card
    end.png         opaque closing card

Two orientations, chosen with --orientation:

    landscape  1920x1080, phone on the right, copy in a left-hand column.
               For anything watched on a laptop.
    portrait   1080x1920, phone centred with the caption beneath it. For
               Stories, Reels and anything watched on a phone.

A 1080x2400 phone screen is 9:20, and a portrait frame is 9:16, so the screen
cannot fill it without throwing away a fifth of the height. It is therefore
centred at full height with the caption in the band underneath, rather than
cropped -- losing the bottom navigation bar or the day's takings off the top
would cost more than the margins do.

Run by tool\\demo\\edit.ps1; takes build\\demo\\beats.json and writes into an
assets directory.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# The recording's own aspect, used to derive a screen width from a height so the
# app is never stretched.
DEVICE_W, DEVICE_H = 1080, 2400

INK = (232, 238, 242)
ACCENT = (221, 168, 80)        # accentDark -- the ochre reads better on dark
PRIMARY_TINT = (127, 187, 220)

FOOTER = "Offline  \u00b7  No account  \u00b7  One phone"
KICKER = "SALES TRACKER FOR A SARI-SARI STORE"


class Layout:
    """Where everything sits, for one orientation."""

    def __init__(self, name: str):
        self.name = name

        if name == "landscape":
            self.W, self.H = 1920, 1080
            self.screen_h = 942
            self.screen_w = round(self.screen_h * DEVICE_W / DEVICE_H)   # 424
            self.screen_x = 1210
            self.screen_y = (self.H - self.screen_h) // 2
            self.bezel = 13
            self.corner = 46
            self.body_corner = 58
            # Copy runs down a column to the left of the phone.
            self.text_left = 132
            self.text_right = 1090
            self.centred = False
            self.caption_top = 384
            self.caption_size = 60
            self.caption_leading = 70
        elif name == "portrait":
            self.W, self.H = 1080, 1920
            # 1560 rather than as tall as it would fit: the caption needs a band
            # under the phone with room for two lines, and squeezing it against
            # the footer looked like a mistake.
            self.screen_h = 1560
            self.screen_w = round(self.screen_h * DEVICE_W / DEVICE_H)   # 702
            self.screen_x = (self.W - self.screen_w) // 2
            self.screen_y = 36
            self.bezel = 11
            self.corner = 38
            self.body_corner = 48
            # Copy sits in the band under the phone, centred.
            self.text_left = 60
            self.text_right = self.W - 60
            self.centred = True
            self.caption_top = 1656
            self.caption_size = 52
            self.caption_leading = 60
        else:
            raise ValueError(f"unknown orientation: {name}")

    @property
    def text_width(self) -> int:
        return self.text_right - self.text_left

    @property
    def screen_box(self) -> tuple[int, int, int, int]:
        return (
            self.screen_x,
            self.screen_y,
            self.screen_x + self.screen_w,
            self.screen_y + self.screen_h,
        )


def font(size: int, *, bold: bool = False, semi: bool = False) -> ImageFont.FreeTypeFont:
    """Segoe UI, which every Windows install has and which carries the peso sign."""
    if bold:
        names = ["segoeuib.ttf", "seguibl.ttf", "arialbd.ttf"]
    elif semi:
        names = ["seguisb.ttf", "segoeuib.ttf", "arial.ttf"]
    else:
        names = ["segoeui.ttf", "arial.ttf"]
    for name in names:
        try:
            return ImageFont.truetype(f"C:/Windows/Fonts/{name}", size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, max_width: int) -> list[str]:
    lines: list[str] = []
    current = ""
    for word in text.split():
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=fnt) <= max_width or not current:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def vertical_gradient(size: tuple[int, int], top: tuple, bottom: tuple) -> Image.Image:
    """One column stretched sideways -- far quicker than filling per pixel."""
    width, height = size
    strip = Image.new("RGB", (1, height))
    pixels = strip.load()
    for y in range(height):
        t = y / (height - 1)
        pixels[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return strip.resize((width, height), Image.BILINEAR)


def draw_text(
    draw: ImageDraw.ImageDraw,
    layout: Layout,
    y: int,
    text: str,
    fnt,
    fill,
) -> None:
    """Left-aligned in landscape, centred in portrait."""
    if layout.centred:
        x = (layout.W - draw.textlength(text, font=fnt)) / 2
    else:
        x = layout.text_left
    draw.text((x, y), text, font=fnt, fill=fill)


def brand_mark(draw: ImageDraw.ImageDraw, x: int, y: int, *, size: int = 34) -> None:
    """'BentaGo' with the ochre dot."""
    fnt = font(size, bold=True)
    draw.text((x, y), "BentaGo", font=fnt, fill=INK)
    width = draw.textlength("BentaGo", font=fnt)
    r = max(3, size // 8)
    cy = y + size * 0.92
    draw.ellipse([x + width + 7, cy - r, x + width + 7 + r * 2, cy + r], fill=ACCENT)


def make_background(layout: Layout, out: Path) -> None:
    image = vertical_gradient((layout.W, layout.H), (16, 27, 35), (9, 16, 22))

    # A cool wash behind the phone, so the bright screen is not sitting on flat
    # colour. Drawn oversized on its own layer and blurred hard.
    glow = Image.new("RGB", (layout.W, layout.H), (0, 0, 0))
    cx = layout.screen_x + layout.screen_w // 2
    cy = layout.screen_y + layout.screen_h // 2
    spread = int(layout.screen_h * 0.62)
    ImageDraw.Draw(glow).ellipse(
        [cx - spread, cy - spread, cx + spread, cy + spread],
        fill=(28, 62, 84),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(190))
    image = Image.blend(image, Image.blend(image, glow, 0.55), 0.7)

    # The shadow the phone casts.
    left, top, right, bottom = layout.screen_box
    shadow = Image.new("L", (layout.W, layout.H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [
            left - layout.bezel + 16,
            top - layout.bezel + 30,
            right + layout.bezel + 16,
            bottom + layout.bezel + 44,
        ],
        radius=layout.body_corner,
        fill=185,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(46))
    image = Image.composite(
        Image.new("RGB", (layout.W, layout.H), (4, 8, 11)), image, shadow
    )

    draw = ImageDraw.Draw(image)

    if layout.name == "landscape":
        # A hairline down the gutter between the copy and the phone.
        draw.line(
            [(layout.text_right + 60, 150), (layout.text_right + 60, layout.H - 150)],
            fill=(34, 52, 63),
            width=1,
        )
        brand_mark(draw, layout.text_left, 92, size=30)
        draw.text(
            (layout.text_left, 138), KICKER, font=font(15, semi=True), fill=(96, 118, 132)
        )
        draw.text(
            (layout.text_left, layout.H - 118), FOOTER, font=font(19), fill=(88, 108, 121)
        )
    else:
        # No room above the phone, so only the footer survives down here. The
        # title card carries the branding anyway.
        draw_text(draw, layout, layout.H - 44, FOOTER, font(18), (82, 101, 114))

    image.save(out / "bg.png")


def make_frame(layout: Layout, out: Path) -> None:
    """The phone body, with the screen punched out to transparent."""
    layer = Image.new("RGBA", (layout.W, layout.H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    left, top, right, bottom = layout.screen_box
    body = [
        left - layout.bezel,
        top - layout.bezel,
        right + layout.bezel,
        bottom + layout.bezel,
    ]
    draw.rounded_rectangle(body, radius=layout.body_corner, fill=(26, 39, 49, 255))
    # A lit top edge and a dark inner one: enough to read as an object.
    draw.rounded_rectangle(
        body, radius=layout.body_corner, outline=(58, 78, 91, 255), width=2
    )
    draw.rounded_rectangle(
        [body[0] + 2, body[1] + 2, body[2] - 2, body[3] - 2],
        radius=layout.body_corner - 2,
        outline=(12, 20, 26, 200),
        width=2,
    )

    # Punch the screen through, replacing rather than blending so the corners
    # come out cleanly transparent.
    hole = Image.new("RGBA", (layout.W, layout.H), (0, 0, 0, 0))
    ImageDraw.Draw(hole).rounded_rectangle(
        [left, top, right, bottom], radius=layout.corner, fill=(0, 0, 0, 255)
    )
    layer.paste((0, 0, 0, 0), (0, 0), hole)

    layer.save(out / "frame.png")


def make_caption(layout: Layout, out: Path, index: int, beat: dict) -> None:
    layer = Image.new("RGBA", (layout.W, layout.H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    top = layout.caption_top
    number_font = font(17, bold=True)
    label = f"{index:02d}"
    label_w = draw.textlength(label, font=number_font)

    if layout.centred:
        # Number and rule sit as one centred unit above the heading.
        unit = label_w + 14 + 48
        start = (layout.W - unit) / 2
        draw.text((start, top), label, font=number_font, fill=ACCENT)
        draw.line(
            [(start + label_w + 14, top + 11), (start + unit, top + 11)],
            fill=(74, 96, 110),
            width=2,
        )
    else:
        draw.text((layout.text_left, top), label, font=number_font, fill=ACCENT)
        draw.line(
            [
                (layout.text_left + label_w + 14, top + 11),
                (layout.text_left + label_w + 62, top + 11),
            ],
            fill=(74, 96, 110),
            width=2,
        )

    heading_font = font(layout.caption_size, bold=True)
    y = top + 44
    for line in wrap(draw, beat["caption"], heading_font, layout.text_width):
        draw_text(draw, layout, y, line, heading_font, INK)
        y += layout.caption_leading

    layer.save(out / f"caption-{index:02d}-{beat['id']}.png")


def make_card(layout: Layout, out: Path, name: str, card: dict, *, opening: bool) -> None:
    image = vertical_gradient((layout.W, layout.H), (18, 31, 40), (9, 15, 21))

    glow = Image.new("RGB", (layout.W, layout.H), (0, 0, 0))
    gx, gy = int(layout.W * 0.66), int(layout.H * 0.39)
    ImageDraw.Draw(glow).ellipse(
        [layout.W // 2 - gx, layout.H // 2 - gy, layout.W // 2 + gx, layout.H // 2 + gy],
        fill=(26, 58, 79),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(200))
    image = Image.blend(image, glow, 0.42)
    draw = ImageDraw.Draw(image)

    # The heading has to fit the narrower frame, so scale it off the width.
    scale = layout.W / 1920 if layout.name == "landscape" else layout.W / 1080 * 0.86
    heading_font = font(int(126 * scale), bold=True)
    sub_font = font(int(40 * scale), semi=False)
    foot_font = font(max(16, int(24 * scale)), semi=True)

    heading = card["heading"]
    hw = draw.textlength(heading, font=heading_font)
    hx = (layout.W - hw) / 2
    hy = layout.H / 2 - 168 * scale
    draw.text((hx, hy), heading, font=heading_font, fill=INK)

    r = max(7, int(13 * scale))
    draw.ellipse(
        [hx + hw + 20 * scale, hy + 116 * scale,
         hx + hw + 20 * scale + r * 2, hy + 116 * scale + r * 2],
        fill=ACCENT,
    )

    sub = card["subheading"]
    sub_y = hy + 200 * scale
    for line in wrap(draw, sub, sub_font, layout.W - 120):
        draw.text(
            ((layout.W - draw.textlength(line, font=sub_font)) / 2, sub_y),
            line,
            font=sub_font,
            fill=PRIMARY_TINT,
        )
        sub_y += int(52 * scale)

    rule_y = sub_y + 34 * scale
    draw.line(
        [(layout.W / 2 - 90, rule_y), (layout.W / 2 + 90, rule_y)],
        fill=(70, 92, 106),
        width=2,
    )

    foot_y = rule_y + 30 * scale
    for line in wrap(draw, card["footer"], foot_font, layout.W - 120):
        draw.text(
            ((layout.W - draw.textlength(line, font=foot_font)) / 2, foot_y),
            line,
            font=foot_font,
            fill=(126, 148, 162),
        )
        foot_y += int(32 * scale)

    if not opening:
        tag = "Built with Flutter  \u00b7  SQLite  \u00b7  no backend"
        tag_font = font(max(14, int(19 * scale)))
        draw.text(
            ((layout.W - draw.textlength(tag, font=tag_font)) / 2, layout.H - 110 * scale),
            tag,
            font=tag_font,
            fill=(84, 104, 118),
        )

    image.save(out / name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("beats", type=Path, help="build/demo/beats.json")
    parser.add_argument("out", type=Path, help="directory to write the layers into")
    parser.add_argument(
        "--orientation",
        default="landscape",
        choices=["landscape", "portrait"],
        help="frame shape (default: landscape)",
    )
    args = parser.parse_args()

    layout = Layout(args.orientation)
    args.out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(args.beats.read_text(encoding="utf-8-sig"))

    make_background(layout, args.out)
    make_frame(layout, args.out)
    make_card(layout, args.out, "title.png", manifest["title"], opening=True)
    make_card(layout, args.out, "end.png", manifest["end"], opening=False)

    for index, beat in enumerate(manifest["beats"], start=1):
        make_caption(layout, args.out, index, beat)

    # The single source of truth for where the video sits, read back by edit.ps1
    # so the two cannot drift apart.
    (args.out / "geometry.json").write_text(
        json.dumps(
            {
                "orientation": layout.name,
                "width": layout.W,
                "height": layout.H,
                "screenX": layout.screen_x,
                "screenY": layout.screen_y,
                "screenW": layout.screen_w,
                "screenH": layout.screen_h,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    print(
        f"rendered {len(manifest['beats']) + 4} {layout.name} layers "
        f"({layout.W}x{layout.H}, screen {layout.screen_w}x{layout.screen_h}) "
        f"into {args.out}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

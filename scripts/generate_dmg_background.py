#!/usr/bin/env python3

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH = 720
HEIGHT = 440


def load_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for candidate in candidates:
        if os.path.exists(candidate):
            try:
                return ImageFont.truetype(candidate, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def vertical_gradient(image: Image.Image, top: str, bottom: str) -> None:
    draw = ImageDraw.Draw(image)
    top_rgb = tuple(int(top[i : i + 2], 16) for i in (1, 3, 5))
    bottom_rgb = tuple(int(bottom[i : i + 2], 16) for i in (1, 3, 5))

    for y in range(HEIGHT):
        ratio = y / max(HEIGHT - 1, 1)
        color = tuple(
            int(top_rgb[index] + (bottom_rgb[index] - top_rgb[index]) * ratio)
            for index in range(3)
        )
        draw.line((0, y, WIDTH, y), fill=color)


def rounded_panel(
    draw: ImageDraw.ImageDraw,
    bounds: tuple[int, int, int, int],
    *,
    fill: str,
    outline: str,
    radius: int = 24,
) -> None:
    draw.rounded_rectangle(bounds, radius=radius, fill=fill, outline=outline, width=2)


def main() -> None:
    output_path = os.environ.get("DMG_BACKGROUND_PATH")
    if not output_path:
        raise SystemExit("DMG_BACKGROUND_PATH is required")

    image = Image.new("RGB", (WIDTH, HEIGHT))
    vertical_gradient(image, "#0f172a", "#111827")
    draw = ImageDraw.Draw(image)

    title_font = load_font(34)
    caption_font = load_font(20)

    # Subtle structure so the real Finder icons remain the focus.
    draw.rounded_rectangle((18, 18, WIDTH - 18, HEIGHT - 18), radius=28, outline="#22314b", width=2)
    draw.line((360, 126, 360, 344), fill="#22314b", width=2)

    rounded_panel(
        draw,
        (52, 142, 308, 348),
        fill="#111c2f",
        outline="#253753",
    )
    rounded_panel(
        draw,
        (412, 142, 668, 348),
        fill="#111c2f",
        outline="#253753",
    )

    arrow = [
        (318, 232),
        (382, 232),
        (382, 204),
        (430, 245),
        (382, 286),
        (382, 258),
        (318, 258),
    ]
    draw.polygon(arrow, fill="#2563eb")

    draw.text(
        (WIDTH // 2, 40),
        "Install TypoFixr",
        font=title_font,
        fill="#f8fafc",
        anchor="ma",
    )
    draw.text(
        (WIDTH // 2, 84),
        "Drag TypoFixr.app into Applications",
        font=caption_font,
        fill="#cbd5e1",
        anchor="ma",
    )

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path, format="PNG")


if __name__ == "__main__":
    main()

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFont


OUTPUT_PATH = os.path.join('assets', 'images', 'app_icon.png')
SIZE = 512
BACKGROUND_TOP = (243, 112, 33, 255)
BACKGROUND_BOTTOM = (210, 81, 18, 255)
TEXT = 'oldes'
TEXT_COLOR = (255, 255, 255, 255)
BORDER_COLOR = (252, 231, 214, 255)
BORDER_WIDTH = 8
BORDER_RADIUS = 96


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    preferred_paths = [
        r'C:/Windows/Fonts/arialbd.ttf',
        r'C:/Windows/Fonts/arial.ttf',
        r'/System/Library/Fonts/SFNSDisplay-Bold.ttf',
        r'/System/Library/Fonts/SFNS.ttf',
    ]
    for path in preferred_paths:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _measure_text(font: ImageFont.ImageFont, text: str) -> tuple[int, int]:
    if hasattr(font, 'getbbox'):
        left, top, right, bottom = font.getbbox(text)
        return right - left, bottom - top
    width, height = font.getsize(text)
    return width, height


def _resolve_font(text: str) -> tuple[ImageFont.ImageFont, tuple[int, int]]:
    max_width = SIZE - 160
    max_height = SIZE - 160

    for size in range(260, 80, -4):
        font = _load_font(size)
        if isinstance(font, ImageFont.FreeTypeFont):
            width, height = _measure_text(font, text)
            if width <= max_width and height <= max_height:
                return font, (width, height)

    fallback_font = _load_font(120)
    width, height = _measure_text(fallback_font, text)
    return fallback_font, (width, height)


def main() -> None:
    img = Image.new('RGBA', (SIZE, SIZE), BACKGROUND_TOP)
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        ratio = y / (SIZE - 1)
        r = int(BACKGROUND_TOP[0] * (1 - ratio) + BACKGROUND_BOTTOM[0] * ratio)
        g = int(BACKGROUND_TOP[1] * (1 - ratio) + BACKGROUND_BOTTOM[1] * ratio)
        b = int(BACKGROUND_TOP[2] * (1 - ratio) + BACKGROUND_BOTTOM[2] * ratio)
        draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

    draw.rounded_rectangle(
        (64, 64, SIZE - 64, SIZE - 64),
        radius=BORDER_RADIUS,
        outline=BORDER_COLOR,
        width=BORDER_WIDTH,
    )

    font, (text_width, text_height) = _resolve_font(TEXT)
    text_x = (SIZE - text_width) / 2
    text_y = (SIZE - text_height) / 2 - 6
    draw.text((text_x, text_y), TEXT, font=font, fill=TEXT_COLOR)

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    img.save(OUTPUT_PATH)
    print(f'Icon written to {OUTPUT_PATH}')


if __name__ == '__main__':
    main()

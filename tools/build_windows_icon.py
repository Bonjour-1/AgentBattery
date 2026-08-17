"""Build the multi-resolution Windows icons from the checked-in artwork."""

from __future__ import annotations

import argparse
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SVG = ROOT / "assets/icons/app_icon_default.svg"
HIDDEN_SOURCE = ROOT / "assets/icons/hidden_catgirl_battery_source.png"
RESOURCE_DIR = ROOT / "windows/runner/resources"
SIZES = (16, 20, 24, 32, 40, 48, 64, 256)
RENDER_SCALE = 4

PURPLE = "#4B3278"
LIGHTNING = "#8A4DE8"
MINT = "#BCEBDD"


def _number(value: str) -> float:
    return float(value.rstrip("px"))


def _color(value: str | None, default: str | None = None) -> str | None:
    if value is None or value == "none":
        return default
    return value


def _points(value: str, scale: float) -> list[tuple[float, float]]:
    values = [float(part) for part in value.replace(",", " ").split()]
    return [(values[index] * scale, values[index + 1] * scale)
            for index in range(0, len(values), 2)]


def _stroke_width(element: ET.Element, scale: float) -> int:
    return max(1, round(_number(element.get("stroke-width", "1")) * scale))


def _draw_svg(svg_path: Path, size: int) -> Image.Image:
    """Render the deliberately small SVG subset used by app_icon_default.svg."""
    root = ET.parse(svg_path).getroot()
    scale = size * RENDER_SCALE / 256
    canvas = Image.new("RGBA", (size * RENDER_SCALE, size * RENDER_SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    for element in root:
        tag = element.tag.rsplit("}", 1)[-1]
        fill = _color(element.get("fill"))
        stroke = _color(element.get("stroke"))
        width = _stroke_width(element, scale)
        outline = stroke if stroke else None

        if tag == "rect":
            box = tuple(round(_number(element.get(name, "0")) * scale)
                        for name in ("x", "y", "width", "height"))
            box = (box[0], box[1], box[0] + box[2], box[1] + box[3])
            radius = round(_number(element.get("rx", "0")) * scale)
            if radius:
                draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)
            else:
                draw.rectangle(box, fill=fill, outline=outline, width=width)
        elif tag == "polygon":
            points = _points(element.get("points", ""), scale)
            draw.polygon(points, fill=fill)
            if outline:
                draw.line(points + [points[0]], fill=outline, width=width, joint="curve")
        elif tag in ("polyline", "line"):
            if tag == "line":
                points = [(float(element.get("x1", 0)) * scale,
                           float(element.get("y1", 0)) * scale),
                          (float(element.get("x2", 0)) * scale,
                           float(element.get("y2", 0)) * scale)]
            else:
                points = _points(element.get("points", ""), scale)
            if stroke:
                draw.line(points, fill=stroke, width=width, joint="curve")
        elif tag == "circle":
            cx = _number(element.get("cx", "0")) * scale
            cy = _number(element.get("cy", "0")) * scale
            radius = _number(element.get("r", "0")) * scale
            draw.ellipse((round(cx - radius), round(cy - radius),
                          round(cx + radius), round(cy + radius)),
                         fill=fill, outline=outline, width=width)
        elif tag == "ellipse":
            cx = _number(element.get("cx", "0")) * scale
            cy = _number(element.get("cy", "0")) * scale
            rx = _number(element.get("rx", "0")) * scale
            ry = _number(element.get("ry", "0")) * scale
            draw.ellipse((round(cx - rx), round(cy - ry), round(cx + rx), round(cy + ry)),
                         fill=fill, outline=outline, width=width)

    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def _draw_default_small(size: int) -> Image.Image:
    """Use fewer details at tiny sizes while retaining the icon's three signals."""
    scale = RENDER_SCALE
    image = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    def box(x: float, y: float, w: float, h: float) -> tuple[int, int, int, int]:
        return tuple(round(value * size / 16 * scale) for value in (x, y, x + w, y + h))

    # The terminal is separate from the body so it survives icon-size reduction.
    draw.rounded_rectangle(box(3, 3, 10, 11), radius=round(2 * scale),
                           fill="#EDE5FF", outline=PURPLE, width=round(1.2 * scale))
    draw.rounded_rectangle(box(12, 6, 3, 5), radius=round(1.2 * scale),
                           fill=MINT, outline=PURPLE, width=round(0.9 * scale))
    draw.polygon([(round(x * size / 16 * scale), round(y * size / 16 * scale))
                  for x, y in ((8, 4), (6.3, 7.8), (8, 7.8), (7.3, 12), (10.2, 7.2), (8.5, 7.2))],
                 fill=LIGHTNING)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def _draw_hidden_small(size: int) -> Image.Image:
    """Simplify the hidden design but keep ears, battery, terminal, and bolt."""
    scale = RENDER_SCALE
    image = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    factor = size / 16 * scale
    point = lambda x, y: (round(x * factor), round(y * factor))

    draw.rounded_rectangle((point(1, 2), point(15, 15)), radius=round(4 * factor),
                           fill="#F4EEFF", outline=PURPLE, width=round(0.8 * factor))
    draw.polygon([point(3, 6), point(4, 1), point(7, 4), point(9, 4),
                  point(12, 1), point(13, 6)], fill="#B79BEA", outline=PURPLE)
    draw.ellipse((point(3, 3), point(13, 13)), fill="#C9B2F0", outline=PURPLE,
                 width=round(0.8 * factor))
    # Foreground battery is intentionally independent of the cat silhouette.
    draw.rounded_rectangle((point(5, 7), point(13, 14)), radius=round(1.5 * factor),
                           fill="#EDE5FF", outline=PURPLE, width=round(0.8 * factor))
    draw.rounded_rectangle((point(13, 9), point(15, 12)), radius=round(0.9 * factor),
                           fill=MINT, outline=PURPLE, width=round(0.7 * factor))
    draw.polygon([point(9.5, 8), point(7.8, 11), point(9.2, 11),
                  point(8.7, 13), point(11.2, 10), point(9.8, 10)], fill=LIGHTNING)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def _hidden_image(size: int) -> Image.Image:
    if size in (16, 32):
        return _draw_hidden_small(size)
    with Image.open(HIDDEN_SOURCE) as source:
        image = source.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    # The supplied source is RGB with black pixels outside its rounded tile.
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1),
                                            radius=round(size * 0.185), fill=255)
    image.putalpha(mask)
    return image


def _write_ico(images: list[Image.Image], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    images[-1].save(path, format="ICO", sizes=[(image.width, image.height) for image in images],
                    append_images=images[:-1])


def build() -> None:
    if not DEFAULT_SVG.is_file():
        raise FileNotFoundError(DEFAULT_SVG)
    if not HIDDEN_SOURCE.is_file():
        raise FileNotFoundError(HIDDEN_SOURCE)

    default_images = [(_draw_default_small(size) if size in (16, 32)
                       else _draw_svg(DEFAULT_SVG, size)) for size in SIZES]
    hidden_images = [_hidden_image(size) for size in SIZES]
    _write_ico(default_images, RESOURCE_DIR / "app_icon.ico")
    _write_ico(hidden_images, RESOURCE_DIR / "app_icon_catgirl_hidden.ico")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    build()


if __name__ == "__main__":
    main()

"""Render Berry draw-call captures with the official AWTRIX NG small BDF font.

The input JSON files are produced by the copied Berry harnesses in work/.
No pixels are synthesized for the panel: every panel pixel comes from a
captured script draw call. Captions and gallery backgrounds live outside the
52x16 panels and are only for human browsing.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable, Sequence

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = ROOT / "source-notices" / "awtrix-small.bdf"
SCALE_PNG = 20
SCALE_GIF = 12
PANEL_SIZE = (52, 16)


def load_font() -> dict[str, dict[str, object]]:
    """Read BDF glyph metrics and bitmap rows without using a substitute font."""

    glyphs: dict[str, dict[str, object]] = {}
    current: dict[str, object] = {}
    bitmap = False
    for line in FONT_PATH.read_text(encoding="utf-8").splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == "STARTCHAR":
            current = {"rows": []}
        elif words[0] == "ENCODING":
            current["code"] = int(words[1])
        elif words[0] == "DWIDTH":
            current["advance"] = int(words[1])
        elif words[0] == "BBX":
            current["box"] = [int(number) for number in words[1:]]
        elif words[0] == "BITMAP":
            bitmap = True
        elif words[0] == "ENDCHAR":
            bitmap = False
            glyphs[chr(int(current["code"]))] = current
        elif bitmap:
            current["rows"].append(line)
    return glyphs


GLYPHS = load_font()


def color_from_packed(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def validate_point(x: int, y: int, label: str) -> None:
    if not (0 <= x < PANEL_SIZE[0] and 0 <= y < PANEL_SIZE[1]):
        raise ValueError(f"{label} point out of bounds: {(x, y)}")


def render_calls(commands: Sequence[Sequence[object]]) -> Image.Image:
    """Render one Berry drawing array at native 52x16 resolution."""

    panel = Image.new("RGB", PANEL_SIZE, (0, 0, 0))
    draw = ImageDraw.Draw(panel)
    for call in commands:
        if not call:
            raise ValueError("empty draw call")
        kind = str(call[0])
        args = list(call[1:])
        packed = int(args[-1])
        color = color_from_packed(packed)
        if kind == "text":
            x, baseline, label, _ = args
            x = int(x)
            baseline = int(baseline)
            label = str(label)
            for char in label:
                if char not in GLYPHS:
                    raise ValueError(f"BDF has no glyph for {char!r}")
                glyph = GLYPHS[char]
                width, height, dx, dy = (int(value) for value in glyph["box"])
                rows = glyph["rows"]
                for row, bits_hex in enumerate(rows):
                    bits = bin(int(str(bits_hex), 16))[2:].zfill(len(str(bits_hex)) * 4)
                    for column, bit in enumerate(bits[:width]):
                        if bit == "1":
                            validate_point(x + dx + column, baseline - height - dy + row, "text")
                            draw.point((x + dx + column, baseline - height - dy + row), fill=color)
                x += int(glyph["advance"])
        elif kind == "pixel":
            x, y, _ = args
            x, y = int(x), int(y)
            validate_point(x, y, kind)
            draw.point((x, y), fill=color)
        elif kind == "line":
            x, y, x2, y2, _ = args
            x, y, x2, y2 = int(x), int(y), int(x2), int(y2)
            validate_point(x, y, kind)
            validate_point(x2, y2, kind)
            draw.line((x, y, x2, y2), fill=color)
        elif kind in {"fill", "rect"}:
            x, y, width, height, _ = args
            x, y, width, height = int(x), int(y), int(width), int(height)
            if width <= 0 or height <= 0:
                raise ValueError(f"{kind} has non-positive size")
            validate_point(x, y, kind)
            validate_point(x + width - 1, y + height - 1, kind)
            box = (x, y, x + width - 1, y + height - 1)
            if kind == "fill":
                draw.rectangle(box, fill=color)
            else:
                draw.rectangle(box, outline=color)
        else:
            raise ValueError(f"unsupported draw call: {kind}")
    return panel


def scaled(panel: Image.Image, factor: int) -> Image.Image:
    return panel.resize((PANEL_SIZE[0] * factor, PANEL_SIZE[1] * factor), Image.Resampling.NEAREST)


def read_frames(path: Path) -> list[Image.Image]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list) or not payload:
        raise ValueError(f"capture is not a non-empty frame list: {path}")
    return [render_calls(frame) for frame in payload]


def global_palette(frames: Sequence[Image.Image]) -> Image.Image:
    """Build one 256-color palette from all native frames for stable GIF colors."""

    sample = Image.new("RGB", (PANEL_SIZE[0], PANEL_SIZE[1] * len(frames)))
    for index, frame in enumerate(frames):
        sample.paste(frame, (0, index * PANEL_SIZE[1]))
    return sample.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def save_gif(frames: Sequence[Image.Image], path: Path, duration_ms: int = 100) -> None:
    palette = global_palette(frames)
    images = [scaled(frame, SCALE_GIF).quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    images[0].save(
        path,
        save_all=True,
        append_images=images[1:],
        duration=duration_ms,
        loop=0,
        optimize=False,
        # Keep the previous composed frame when Pillow emits a delta rectangle.
        # Disposal 2 clears that rectangle to GIF palette index 0, which is not
        # guaranteed to be black and can create yellow/other background blocks.
        disposal=1,
    )


def save_still(frame: Image.Image, native_path: Path, scaled_path: Path) -> None:
    frame.save(native_path)
    scaled(frame, SCALE_PNG).save(scaled_path)


def caption_font() -> ImageFont.ImageFont:
    return ImageFont.load_default()


def make_contact_sheet(
    title: str,
    entries: Sequence[tuple[str, Image.Image]],
    path: Path,
    columns: int = 2,
) -> None:
    """Create a labeled gallery; the individual panel assets remain clean."""

    cell_width, cell_height = 560, 210
    rows = (len(entries) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell_width, 55 + rows * cell_height), "#111820")
    pen = ImageDraw.Draw(sheet)
    font = caption_font()
    pen.text((18, 12), title, fill="#F5FAFF", font=font)
    pen.text((18, 30), "RENDERED PREVIEW | Berry draw calls | simulated sample data | not a device photo", fill="#9DB2C4", font=font)
    for index, (name, frame) in enumerate(entries):
        x = (index % columns) * cell_width + 18
        y = 55 + (index // columns) * cell_height
        pen.text((x, y), name, fill="#C8D8E4", font=font)
        sheet.paste(scaled(frame, 10), (x, y + 18))
    sheet.save(path)


def render_app(
    app_name: str,
    capture_dir: Path,
    output_dir: Path,
    scene_names: Sequence[str],
    animated_names: set[str],
) -> dict[str, Image.Image]:
    native_dir = output_dir / "native"
    screenshots_dir = output_dir / "screenshots"
    animations_dir = output_dir / "animations"
    native_dir.mkdir(parents=True, exist_ok=True)
    screenshots_dir.mkdir(parents=True, exist_ok=True)
    animations_dir.mkdir(parents=True, exist_ok=True)

    stills: dict[str, Image.Image] = {}
    for name in scene_names:
        frames = read_frames(capture_dir / f"{name}.json")
        still = frames[len(frames) // 2]
        stills[name] = still
        save_still(still, native_dir / f"{name}.png", screenshots_dir / f"{name}.png")
        gif_path = animations_dir / f"{name}.gif"
        if name in animated_names:
            save_gif(frames, gif_path)
        elif gif_path.exists():
            # Remove a stale generated GIF when a scene is intentionally static.
            gif_path.unlink()

    showcase_frames = read_frames(capture_dir / f"{app_name.lower()}-showcase.json")
    save_gif(showcase_frames, output_dir / f"{app_name.lower()}-showcase.gif")
    return stills


def render_solar() -> None:
    names = [
        "solar-production-large",
        "solar-production-half",
        "battery-charging",
        "battery-discharging",
        "house-solar",
        "house-battery",
        "house-grid",
        "house-unknown",
        "grid-import",
        "grid-export",
        "grid-idle",
    ]
    output = ROOT / "SolarApp"
    stills = render_app("SolarApp", ROOT / "work" / "captures", output, names, set(names))
    save_still(
        stills["solar-production-large"],
        output / "native" / "solarapp-cover.png",
        output / "solarapp-cover.png",
    )
    make_contact_sheet(
        "SolarApp - simulated gallery",
        [(name, stills[name]) for name in names],
        output / "gallery-contact-sheet.png",
        columns=2,
    )


def render_pellet() -> None:
    names = [
        "heating",
        "temperatures",
        "pellets-empty",
        "pellets-half",
        "pellets-full",
        "cleaning-1h3",
        "cleaning-due",
        "ash-20",
        "ash-50",
        "ash-100",
        "cooling",
        "error-clear",
        "error-fault",
        "off",
        "standby-status",
        "standby-temperature",
    ]
    output = ROOT / "PelletStove"
    animated = set(names) - {"pellets-empty", "error-clear", "off", "standby-status"}
    stills = render_app("PelletStove", ROOT / "work" / "pellet-captures", output, names, animated)
    save_still(
        stills["heating"],
        output / "native" / "pelletstove-cover.png",
        output / "pelletstove-cover.png",
    )
    make_contact_sheet(
        "PelletStove - simulated gallery",
        [(name, stills[name]) for name in names],
        output / "gallery-contact-sheet.png",
        columns=2,
    )


def render_event() -> None:
    scenes = ["motion", "mail_received", "mail_collected", "heat", "water", "doorbell", "garage"]
    names = scenes + [scene + "-labels" for scene in scenes]
    output = ROOT / "EventTrigger"
    stills = render_app("EventTrigger", ROOT / "work/event-captures", output, names, set(names))
    save_still(stills["doorbell"], output / "native/eventtrigger-cover.png", output / "eventtrigger-cover.png")
    make_contact_sheet("Event trigger - simulated example scenes", [(name, stills[name]) for name in names],
                       output / "gallery-contact-sheet.png", columns=2)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--solar", action="store_true", help="render SolarApp captures")
    parser.add_argument("--pellet", action="store_true", help="render PelletStove captures")
    parser.add_argument("--event", action="store_true", help="render Event trigger captures")
    parser.add_argument("--all", action="store_true", help="render all capture sets")
    args = parser.parse_args()
    if not (args.solar or args.pellet or args.event or args.all):
        parser.error("choose --solar, --pellet, --event, or --all")
    if args.solar or args.all:
        render_solar()
    if args.pellet or args.all:
        render_pellet()
    if args.event or args.all:
        render_event()
    print("Rendered requested media with the official BDF font")


if __name__ == "__main__":
    main()

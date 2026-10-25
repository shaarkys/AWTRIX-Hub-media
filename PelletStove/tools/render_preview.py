"""Render actual Berry draw-call captures. This is a simulation, not a TC002 capture."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent


def load_font():
    """Read the upstream unmodified BDF: DWIDTH advance, BBX baseline offsets."""
    glyphs = {}
    current = {}
    bitmap = False
    for line in (ROOT.parents[1] / "source-notices/awtrix-small.bdf").read_text(encoding="utf-8").splitlines():
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
            current["box"] = [int(n) for n in words[1:]]
        elif words[0] == "BITMAP":
            bitmap = True
        elif words[0] == "ENDCHAR":
            bitmap = False
            glyphs[chr(current["code"])] = current
        elif bitmap:
            current["rows"].append(line)
    return glyphs


GLYPHS = load_font()


def render_calls(commands):
    panel = Image.new("RGB", (52, 16))
    draw = ImageDraw.Draw(panel)
    for kind, *args in commands:
        packed = args[-1]
        color = ((packed >> 16) & 255, (packed >> 8) & 255, packed & 255)
        if kind == "text":
            x, baseline, label, _ = args
            for char in label:
                glyph = GLYPHS[char]
                width, height, dx, dy = glyph["box"]
                for row, bits in enumerate(glyph["rows"]):
                    bits = bin(int(bits, 16))[2:].zfill(len(bits) * 4)
                    for column, bit in enumerate(bits[:width]):
                        if bit == "1":
                            draw.point((x + dx + column, baseline - height - dy + row), fill=color)
                x += glyph["advance"]
        elif kind == "pixel":
            draw.point(tuple(args[:2]), fill=color)
        elif kind == "line":
            draw.line(tuple(args[:4]), fill=color)
        elif kind == "fill":
            x, y, width, height, _ = args
            draw.rectangle((x, y, x + width - 1, y + height - 1), fill=color)
        else:
            raise ValueError(f"Unsupported draw call: {kind}")
    return panel.resize((624, 192), Image.Resampling.NEAREST)


def main():
    frames = json.loads((ROOT / "preview-frames.json").read_text(encoding="utf-8"))
    assert len(frames) == 330
    images = [render_calls(frame) for frame in frames]
    out = ROOT.parent
    images[0].save(out / "rotation-preview.gif", save_all=True, append_images=images[1:],
                   duration=100, loop=0, optimize=False)
    warnings = images[150:250]
    warnings[0].save(out / "warning-preview.gif", save_all=True, append_images=warnings[1:],
                     duration=100, loop=0, optimize=False)
    titles = ["Heating + mode", "Actual / target temperature (C)", "Pellets (kg)", "Cleaning (hours left)",
              "Ash limit (% used)", "Active fault"]
    sheet = Image.new("RGB", (664, 1382), "#161d24")
    pen = ImageDraw.Draw(sheet)
    pen.text((20, 12), "SIMULATION - sample MQTT values; not a recording from the TC002", fill="white")
    for page, title in enumerate(titles):
        top = 43 + page * 222
        pen.text((20, top), title, fill="#b9cbd6")
        sheet.paste(images[page * 50], (20, top + 18))
    sheet.save(out / "preview.png")
    progress = json.loads((ROOT / "progress-frames.json").read_text(encoding="utf-8"))
    assert len(progress) == 6
    comparison = Image.new("RGB", (1016, 310), "#161d24")
    pen = ImageDraw.Draw(comparison)
    pen.text((20, 8), "SIMULATION - hopper level and ash usage; not a TC002 recording", fill="white")
    captions = ["Pellets: 0 kg / empty", "Pellets: 15 kg / half", "Pellets: 30 kg / full",
                "Ash: 0% / clean", "Ash: 50% used", "Ash: 100% / full"]
    for index, commands in enumerate(progress):
        x = 20 + index % 3 * 332
        y = 34 + index // 3 * 134
        pen.text((x, y), captions[index], fill="#b9cbd6")
        panel = render_calls(commands).resize((312, 96), Image.Resampling.NEAREST)
        comparison.paste(panel, (x, y + 18))
    comparison.save(out / "progress-preview.png")
    cooling = json.loads((ROOT / "cooling-frames.json").read_text(encoding="utf-8"))
    assert len(cooling) == 40
    fan_images = [render_calls(frame) for frame in cooling]
    fan_images[0].save(out / "cooling-preview.gif", save_all=True, append_images=fan_images[1:],
                       duration=100, loop=0, optimize=False)
    cleaning = json.loads((ROOT / "cleaning-frames.json").read_text(encoding="utf-8"))
    assert len(cleaning) == 60
    cloth_images = [render_calls(frame) for frame in cleaning]
    cloth_images[0].save(out / "cleaning-preview.gif", save_all=True, append_images=cloth_images[1:],
                         duration=100, loop=0, optimize=False)
    print("Created overview/progress PNGs and rotation/warning/cooling/cleaning GIFs from Berry draw calls")


if __name__ == "__main__":
    main()

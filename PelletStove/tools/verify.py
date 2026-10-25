"""Offline checks for script metadata, Homey input contracts and captured layout."""
import hashlib
import json
import re
import shlex
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def font_advances():
    widths = {}
    code = None
    for line in (REPO / "source-notices/awtrix-small.bdf").read_text(encoding="utf-8").splitlines():
        if line.startswith("ENCODING "):
            code = int(line.split()[1])
        elif line.startswith("DWIDTH "):
            widths[chr(code)] = int(line.split()[1])
    return widths


def main():
    source = (ROOT / "PelletStove.ax").read_text(encoding="utf-8")
    settings = {}
    for line in source.splitlines():
        if not line.startswith("# @config "):
            continue
        key, kind, title, *options = shlex.split(line[len("# @config "):])
        opts = dict(option.split("=", 1) for option in options)
        check(key not in settings and len(key) <= 24, f"Duplicate/long setting: {key}")
        check(kind in ("text", "number", "bool"), f"Unknown setting type: {kind}")
        check("default" in opts, f"Missing default: {key}")
        if kind == "number":
            check(float(opts["min"]) <= float(opts["default"]) <= float(opts["max"]), key)
        if kind == "bool":
            check(opts["default"] in ("true", "false"), key)
        settings[key] = (kind, title, opts)
    used = set(re.findall(r'store\.get\("([^"]+)"', source))
    check(used == settings.keys(), f"Setting declarations/use differ: {used ^ settings.keys()}")
    check("# @display 52x16" in source, "TC002 geometry")
    check("mqtt.publish" not in source and "http." not in source, "Display must only subscribe")
    scalar_topics = [item[2]["default"] for key, item in settings.items()
                     if key.startswith("topic_") and key != "topic_state"]
    check(len(scalar_topics) == len(set(scalar_topics)) == 9, "Nine unique scalar default topics")
    check(settings["topic_state"][2]["default"] == "", "Combined JSON opt-in")

    sample = json.loads((ROOT / "example-state.json").read_text(encoding="utf-8"))
    contract = json.loads((ROOT / "input-contract.json").read_text(encoding="utf-8"))
    check(len(sample) == 9 and sample.keys() == set(contract["capabilities"]), "Existing capability IDs only")
    check(sample["onoff"] is True, "Example must include the required power gate")
    for capability, expected in [("measure_stove_cleaning_in", "h"),
                                 ("measure_stove_maintenance_in", "%"),
                                 ("stove_pellets_actual", "kg")]:
        check(contract["units"][capability] == expected, f"Input unit changed: {capability}")
    check(contract["target_temperature"]["min"] == 5, "Target lower bound")
    check(contract["target_temperature"]["max"] == 35, "Target upper bound")

    widths = font_advances()
    harness = (ROOT / "tools/test_pelletstove.be").read_text(encoding="utf-8")
    mocked = json.loads(re.search(r"var advances = (\{.*?\})", harness, re.S).group(1))
    expected = {char: widths[char] for char in widths if 32 <= ord(char) < 127 and widths[char] != 4}
    check(mocked == expected, "Test text metrics must match upstream small font")
    notice = (REPO / "source-notices/FONT-NOTICE.md").read_text(encoding="utf-8")
    for name in ("awtrix-small.bdf", "FONT-LICENSE.txt"):
        checksum = hashlib.sha256((REPO / "source-notices" / name).read_bytes()).hexdigest()
        check(checksum in notice, f"Font provenance changed: {name}")

    capture = ROOT / "tools/preview-frames.json"
    check(capture.exists(), "Run the Berry tests first to create draw-call evidence")
    frames = json.loads(capture.read_text(encoding="utf-8"))
    check(len(frames) == 330, "Six sample views, 5s each, with an 8s fault")
    progress = json.loads((ROOT / "tools/progress-frames.json").read_text(encoding="utf-8"))
    check(len(progress) == 6, "Three hopper levels and three ash levels")
    cooling = json.loads((ROOT / "tools/cooling-frames.json").read_text(encoding="utf-8"))
    check(len(cooling) == 40, "Four seconds of cooling animation")
    cleaning = json.loads((ROOT / "tools/cleaning-frames.json").read_text(encoding="utf-8"))
    check(len(cleaning) == 60, "Six seconds of microfiber animation")
    for frame in frames + progress + cooling + cleaning:
        for kind, *args in frame:
            if kind == "text":
                x, baseline, label, _ = args
                check(x == 17 and baseline in (6, 14), "Text region/baseline")
                check(sum(widths[char] for char in label) <= 34, f"Text exceeds region: {label}")
            else:
                x, y = args[:2]
                check(0 <= x < 52 and 0 <= y < 16, f"Drawing origin: {kind}")
                if kind == "fill":
                    width, height = args[2:4]
                    check(width > 0 and height > 0 and x + width <= 52 and y + height <= 16, "Fill bounds")
                elif kind == "line":
                    x2, y2 = args[2:4]
                    check(0 <= x2 < 52 and 0 <= y2 < 16, "Line bounds")
                else:
                    check(kind == "pixel", f"Unknown draw call: {kind}")
    print(f"PASS: {len(settings)} settings, nine Homey capabilities, font metrics/provenance, {len(frames) + len(progress) + len(cooling) + len(cleaning)} captured frames")


if __name__ == "__main__":
    main()

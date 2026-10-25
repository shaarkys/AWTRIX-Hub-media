"""Verify all apps and rebuild simulated Hub media from this checkout only."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(args: list[str], cwd: Path = ROOT) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def resolve_berry(value: str | None) -> str:
    requested = value or os.environ.get("BERRY") or "berry"
    resolved = shutil.which(requested)
    if resolved:
        return resolved
    path = Path(requested).expanduser().resolve()
    if not path.is_file():
        raise SystemExit("Berry not found. Supply --berry PATH or set BERRY to a Berry 1.1 executable.")
    return str(path)


def prepare_capture(app: str, capture_name: str) -> Path:
    work = ROOT / "work"
    work.mkdir(exist_ok=True)
    for folder in ("captures", "pellet-captures", "event-captures"):
        (work / folder).mkdir(exist_ok=True)
    test_paths = {"SolarApp": "test_solarapp.be", "PelletStove": "tools/test_pelletstove.be",
                  "EventTrigger": "tools/test_eventtrigger.be"}
    test = ROOT / app / test_paths[app]
    harness = test.read_text(encoding="utf-8")
    prefix = harness.split("var app = new_app({})", 1)[0]
    if prefix == harness:
        raise ValueError(f"Cannot locate test harness boundary: {test}")
    source = ROOT / app / (app + ".ax")
    needle = f'compile("{app}.ax", "file")'
    if needle not in prefix:
        raise ValueError(f"Cannot locate script compilation in {test}")
    prefix = prefix.replace(needle, f'compile({json.dumps(source.as_posix())}, "file")')
    if app == "SolarApp":
        # The legacy logic suite uses approximate width; publication captures use
        # the actual upstream BDF advances, identical to the firmware small font.
        from render_media import GLYPHS

        widths = {char: glyph["advance"] for char, glyph in GLYPHS.items() if 32 <= ord(char) < 127}
        replacement = "var media_advances = " + json.dumps(widths, ensure_ascii=True) + "\n"
        replacement += "def text_width(value)\n  var width = 0\n  for index : 0 .. size(value) - 1\n"
        replacement += '    width += media_advances.find(value[index .. index], 4)\n  end\n  return width\nend'
        prefix = prefix.replace("def text_width(value) return size(value) * 4 end", replacement)
    scenario = (ROOT / "tools" / capture_name).read_text(encoding="utf-8")
    target = work / ("capture_" + app.lower() + ".be")
    target.write_text(prefix + "\n" + scenario, encoding="utf-8", newline="\n")
    return target


def write_hashes() -> None:
    paths = [
        "SolarApp/SolarApp.ax", "SolarApp/SolarApp-TC002-Animated.ax",
        "SolarApp/SolarApp-TC002-SourceAware.ax", "SolarApp/test_solarapp.be",
        "PelletStove/PelletStove.ax", "PelletStove/tools/test_pelletstove.be",
        "PelletStove/input-contract.json", "tools/capture_solar_media.be",
        "tools/capture_pellet_media.be", "tools/render_media.py",
        "source-notices/awtrix-small.bdf", "source-notices/FONT-LICENSE.txt",
        "source-notices/FONT-NOTICE.md",
        "EventTrigger/EventTrigger.ax", "EventTrigger/event_core.be.inc",
        "EventTrigger/event_graphics.be.inc", "EventTrigger/build_eventtrigger.py",
        "EventTrigger/tools/test_eventtrigger.be", "tools/capture_event_media.be",
        "EventTrigger/tools/test_artwork.be",
    ]
    sources = [{"path": name, "sha256": hashlib.sha256((ROOT / name).read_bytes()).hexdigest()} for name in paths]
    (ROOT / "source-hashes.json").write_text(json.dumps({"sources": sources}, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--berry", help="Berry 1.1 interpreter with 32-bit integers and single-precision floats")
    args = parser.parse_args()
    berry = resolve_berry(args.berry)
    (ROOT / "work").mkdir(exist_ok=True)
    probe = ROOT / "work/check_runtime.be"
    probe.write_text('assert(2147483647 + 1 == -2147483647 - 1, "32-bit integer Berry required")\n'
                     'assert(1.0 + 0.00000001 == 1.0, "single-precision Berry required")\n'
                     'print("PASS: Berry numeric configuration")\n', encoding="utf-8", newline="\n")
    run([berry, str(probe)])
    run([sys.executable, "verify_extension.py"], ROOT / "SolarApp")
    run([berry, "test_solarapp.be"], ROOT / "SolarApp")
    run([berry, "tools/test_pelletstove.be"], ROOT / "PelletStove")
    run([sys.executable, "tools/verify.py"], ROOT / "PelletStove")
    run([sys.executable, "build_eventtrigger.py"], ROOT / "EventTrigger")
    run([berry, "tools/test_eventtrigger.be"], ROOT / "EventTrigger")
    run([sys.executable, "tools/verify.py"], ROOT / "EventTrigger")
    run([berry, "EventTrigger/tools/test_artwork.be"])
    for app, scenario in [("SolarApp", "capture_solar_media.be"), ("PelletStove", "capture_pellet_media.be"),
                          ("EventTrigger", "capture_event_media.be")]:
        capture = prepare_capture(app, scenario)
        run([berry, capture.name], capture.parent)
    run([sys.executable, "tools/render_media.py", "--all"])
    write_hashes()
    run([sys.executable, "tools/package_media.py"])
    run([sys.executable, "tools/validate_media.py"])
    print("PASS: standalone source verification, all Berry suites, captures, media, source hashes and publication ZIP")


if __name__ == "__main__":
    main()

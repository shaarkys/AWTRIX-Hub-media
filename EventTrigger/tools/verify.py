"""Check generated Event trigger source and its configurable input contract."""

from pathlib import Path
import json
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCENES = {"motion", "mail_received", "mail_collected", "heat", "water", "doorbell", "garage", "dishwasher_finished", "cooker_finished", "washing_machine_finished", "dryer_finished"}


def main():
    path = ROOT / "EventTrigger.ax"
    before = path.read_bytes()
    subprocess.run([sys.executable, "build_eventtrigger.py"], cwd=ROOT, check=True)
    assert path.read_bytes() == before, "Generated EventTrigger.ax is out of sync"
    source = path.read_text(encoding="utf-8")
    assert re.search(r"^#\s*@name\s+Event trigger\s*$", source, re.M)
    assert "# @display 52x16" in source
    assert not re.search(r"^#\s*@(?:headless|ondemand)\b", source, re.M), "Artwork requires a normal drawing app"
    assert "mqtt.publish" not in source and "http." not in source and "rotation.pause" not in source
    assert "settings.set" not in source, "Do not modify saved device settings"
    settings = {}
    for line in source.splitlines():
        if not line.startswith("# @config "):
            continue
        key, kind, title, *options = shlex.split(line[len("# @config "):])
        opts = dict(item.split("=", 1) for item in options)
        assert key not in settings and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,23}", key)
        assert kind in {"text", "number", "select", "bool"}
        assert "default" in opts
        if kind == "number":
            assert float(opts["min"]) <= float(opts["default"]) <= float(opts["max"])
        if kind == "bool":
            assert opts["default"] in {"true", "false"}
        if kind == "select":
            assert opts["default"] in opts["options"].split(",")
        settings[key] = (kind, opts)
    used = set(re.findall(r'store\.get\("([^"]+)"', source))
    assert used == set(settings), f"Setting metadata and use differ: {used ^ set(settings)}"
    assert settings["topic"][1]["default"] == "homey/events/+"
    assert set(settings["event_mode"][1]["options"].split(",")) == SCENES | {"auto"}
    assert settings["show_labels"][1]["default"] == "false"
    assert settings["wake_display"][1]["default"] == "false"
    advances = {}
    code = None
    for line in (ROOT.parent / "source-notices/awtrix-small.bdf").read_text(encoding="utf-8").splitlines():
        if line.startswith("ENCODING "):
            code = int(line.split()[1])
        elif line.startswith("DWIDTH ") and 32 <= code < 127:
            width = int(line.split()[1])
            if width != 4:
                advances[chr(code)] = width
    for name in ("test_eventtrigger.be", "test_artwork.be"):
        harness = (ROOT / "tools" / name).read_text(encoding="utf-8")
        mocked = json.loads(re.search(r"var advances = (\{.*?\})", harness, re.S).group(1))
        assert mocked == advances, f"Font advances differ from official BDF in {name}"
    print(f"PASS: Event trigger generation, {len(settings)} settings, {len(SCENES)} scene IDs, subscribe-only/device-setting boundaries")


if __name__ == "__main__":
    main()

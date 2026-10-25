"""Verify NetatmoV2 generation, metadata, fixtures and offline boundaries."""

from __future__ import annotations

import json
from pathlib import Path
import re
import shlex
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
EXPECTED_TYPES = {"NAMain", "NAModule1", "NAModule2", "NAModule3", "NAModule4"}


def bdf_advances() -> dict[str, int]:
    advances: dict[str, int] = {}
    code = None
    for line in (REPO / "source-notices" / "awtrix-small.bdf").read_text(encoding="utf-8").splitlines():
        if line.startswith("ENCODING "):
            code = int(line.split()[1])
        elif line.startswith("DWIDTH ") and code is not None and 32 <= code < 127:
            width = int(line.split()[1])
            if width != 4:
                advances[chr(code)] = width
    return advances


def walk_modules(payload: dict) -> list[dict]:
    modules: list[dict] = []
    for device in payload.get("body", {}).get("devices", []):
        modules.append(device)
        modules.extend(device.get("modules", []))
    return modules


def main() -> None:
    output = ROOT / "NetatmoV2.ax"
    before = output.read_bytes()
    subprocess.run([sys.executable, "build_netatmov2.py"], cwd=ROOT, check=True)
    assert output.read_bytes() == before, "generated NetatmoV2.ax is out of sync"
    source = output.read_text(encoding="utf-8")

    assert re.search(r"^#\s*@name\s+NetatmoV2\s*$", source, re.M)
    assert "# @display 52x16" in source
    oauth_line = re.search(r"^#\s*@oauth\s+(.+)$", source, re.M)
    assert oauth_line
    oauth_meta = shlex.split(oauth_line.group(1))
    assert oauth_meta == [
        "authorize=https://api.netatmo.com/oauth2/authorize",
        "token=https://api.netatmo.com/oauth2/token",
        "api=api.netatmo.com",
        "scope=read_station",
        "auth=body",
    ]
    assert "import oauth" in source and 'oauth.get("https://api.netatmo.com/api/getstationsdata"' in source
    assert '"cap":65536' in source
    assert "client_secret" not in source.lower() and "access_token" not in source.lower()
    assert not re.search(r"#\s*@config\s+\w*(?:token|secret|client)", source, re.I)
    assert "http." not in source and "store.set" not in source and "settings.set" not in source
    assert "var page_elapsed = elapsed_ms - index * self.page_ms" in source
    assert "self.paint_page(page, page_elapsed % 4000" in source

    settings: dict[str, tuple[str, dict[str, str]]] = {}
    for line in source.splitlines():
        if not line.startswith("# @config "):
            continue
        key, kind, _title, *options = shlex.split(line[len("# @config ") :])
        opts = dict(item.split("=", 1) for item in options)
        assert key not in settings and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,23}", key)
        assert kind in {"text", "number", "bool"} and "default" in opts
        if kind == "number":
            assert float(opts["min"]) <= float(opts["default"]) <= float(opts["max"])
        if kind == "bool":
            assert opts["default"] in {"true", "false"}
        settings[key] = (kind, opts)
    used = set(re.findall(r'store\.get\("([^"]+)"', source))
    assert used == set(settings), f"setting metadata and use differ: {used ^ set(settings)}"
    assert settings["every"][1] == {"default": "10", "min": "5", "max": "60", "unit": "min", "group": "Freshness"}
    assert all(settings[name][1]["default"] == "true" for name in ("indoor", "outdoor", "extra", "rain", "wind"))

    fixture_paths = sorted((ROOT / "fixtures").glob("*.json"))
    assert fixture_paths and all(json.loads(path.read_text(encoding="utf-8")) for path in fixture_paths)
    primary = json.loads((ROOT / "fixtures" / "stations-v1.json").read_text(encoding="utf-8"))
    modules = walk_modules(primary)
    assert {module["type"] for module in modules} == EXPECTED_TYPES
    assert len({module["_id"] for module in modules}) == 5
    stamps = {module["dashboard_data"]["time_utc"] for module in modules}
    assert stamps == {1700000000}
    fixture_text = "\n".join(path.read_text(encoding="utf-8") for path in fixture_paths)
    assert "synthetic-" in fixture_text
    assert not re.search(r'"(?:access_token|refresh_token|client_secret|password)"', fixture_text, re.I)

    harness_text = (ROOT / "tools" / "test_netatmov2.be").read_text(encoding="utf-8")
    for path in fixture_paths:
        compact = json.dumps(json.loads(path.read_text(encoding="utf-8")), ensure_ascii=False, separators=(",", ":"))
        escaped = compact.replace("\\", "\\\\").replace('"', '\\"')
        assert f'"{path.name}":"{escaped}"' in harness_text, f"embedded fixture drift: {path.name}"

    expected_advances = bdf_advances()
    for name in ("test_netatmov2.be", "test_artwork.be"):
        harness = (ROOT / "tools" / name).read_text(encoding="utf-8")
        mocked = json.loads(re.search(r"var advances = (\{.*?\})", harness, re.S).group(1))
        assert mocked == expected_advances, f"font advances differ from official BDF in {name}"
    assert "var app = new_app({})" in harness_text

    print(f"PASS: NetatmoV2 generation, {len(settings)} settings, {len(fixture_paths)} synthetic fixtures, OAuth-only boundary")


if __name__ == "__main__":
    main()

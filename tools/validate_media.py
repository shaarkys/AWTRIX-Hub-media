"""Validate generated AWTRIX-Hub media and the publication ZIP."""

from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageSequence

try:
    from .render_media import SCALE_GIF, global_palette, render_calls, scaled
except ImportError:  # Direct `python tools/validate_media.py` execution.
    from render_media import SCALE_GIF, global_palette, render_calls, scaled


ROOT = Path(__file__).resolve().parents[1]
ZIP_PATH = ROOT / "dist" / "AWTRIX-Hub-media.zip"
FRAME_MS = 100


def fail(message: str) -> None:
    raise AssertionError(message)


def check_decoded_gif(gif_path: Path, capture_path: Path) -> None:
    """Compare every decoded 100 ms GIF timestamp with its captured draw frame.

    GIF encoders may merge identical frames into a longer-duration frame. The
    comparison expands those durations back onto the capture timeline and
    checks the fully decoded/composited RGB pixels, using the exact global
    palette produced by render_media.py. This catches disposal/background
    corruption that a dimension/frame-count check cannot see.
    """

    payload = json.loads(capture_path.read_text(encoding="utf-8"))
    expected_native = [render_calls(frame) for frame in payload]
    palette = global_palette(expected_native)
    expected = [
        scaled(frame, SCALE_GIF).quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB").tobytes()
        for frame in expected_native
    ]
    cursor = 0
    with Image.open(gif_path) as image:
        for encoded_index, frame in enumerate(ImageSequence.Iterator(image)):
            duration = int(frame.info.get("duration") or 0)
            if duration <= 0 or duration % FRAME_MS != 0:
                fail(f"{gif_path}: invalid decoded duration at frame {encoded_index}: {duration} ms")
            ticks = duration // FRAME_MS
            decoded = frame.convert("RGB").tobytes()
            if cursor + ticks > len(expected):
                fail(f"{gif_path}: decoded timeline exceeds capture at {cursor * FRAME_MS} ms")
            for tick in range(ticks):
                if decoded != expected[cursor + tick]:
                    fail(
                        f"{gif_path}: decoded pixels differ from captured draw frame "
                        f"at {((cursor + tick) * FRAME_MS)} ms"
                    )
            cursor += ticks
    if cursor != len(expected):
        fail(f"{gif_path}: decoded timeline {cursor * FRAME_MS} ms != capture {len(expected) * FRAME_MS} ms")


def check_images(app: str, expected_scene_count: int, expected_animation_count: int, expected_showcase_ms: int) -> int:
    app_root = ROOT / app
    capture_dir = ROOT / "work" / {"SolarApp": "captures", "PelletStove": "pellet-captures",
                                   "EventTrigger": "event-captures", "NetatmoV2": "netatmo-captures"}[app]
    native = sorted((app_root / "native").glob("*.png"))
    screenshots = sorted((app_root / "screenshots").glob("*.png"))
    gifs = sorted((app_root / "animations").glob("*.gif"))
    if len(native) != expected_scene_count + 1:  # scenes + cover
        fail(f"{app}: unexpected native PNG count {len(native)}")
    if len(screenshots) != expected_scene_count:
        fail(f"{app}: unexpected screenshot PNG count {len(screenshots)}")
    if len(gifs) != expected_animation_count:
        fail(f"{app}: unexpected animation GIF count {len(gifs)}")

    checked = 0
    for path in native:
        with Image.open(path) as image:
            if image.size != (52, 16):
                fail(f"{path}: expected 52x16, got {image.size}")
            image.verify()
        checked += 1
    for path in screenshots:
        with Image.open(path) as image:
            if image.size != (1040, 320):
                fail(f"{path}: expected 1040x320, got {image.size}")
            image.verify()
        checked += 1

    for cover in (app_root / f"{app.lower()}-cover.png", app_root / "gallery-contact-sheet.png"):
        with Image.open(cover) as image:
            if cover.name.endswith("-cover.png") and image.size != (1040, 320):
                fail(f"{cover}: expected 1040x320 cover, got {image.size}")
            image.verify()
        checked += 1

    for path in gifs:
        with Image.open(path) as image:
            if image.size != (624, 192):
                fail(f"{path}: expected 624x192, got {image.size}")
            if getattr(image, "n_frames", 1) < 2:
                fail(f"{path}: animation has fewer than two encoded frames")
            durations = []
            fingerprints = set()
            for frame in ImageSequence.Iterator(image):
                durations.append(frame.info.get("duration"))
                fingerprints.add(hashlib.sha256(frame.convert("RGB").tobytes()).hexdigest())
            if sum(durations) != 4000 or any(duration % 100 != 0 for duration in durations):
                fail(f"{path}: expected 4000 ms in 100 ms increments, got {sum(durations)} ms")
            if len(fingerprints) < 2:
                fail(f"{path}: animation has no changing frames")
            image.seek(0)
            image.verify()
        check_decoded_gif(path, capture_dir / f"{path.stem}.json")
        checked += 1

    showcase = app_root / f"{app.lower()}-showcase.gif"
    with Image.open(showcase) as image:
        if image.size != (624, 192) or image.n_frames < 2:
            fail(f"{showcase}: wrong showcase geometry/frame count")
        durations = []
        fingerprints = set()
        for frame in ImageSequence.Iterator(image):
            durations.append(frame.info.get("duration"))
            fingerprints.add(hashlib.sha256(frame.convert("RGB").tobytes()).hexdigest())
        if sum(durations) != expected_showcase_ms or any(duration % 100 != 0 for duration in durations) or len(fingerprints) < 2:
            fail(f"{showcase}: invalid showcase timing or animation")
        image.seek(0)
        image.verify()
    check_decoded_gif(showcase, capture_dir / f"{app.lower()}-showcase.json")
    checked += 1
    return checked


def check_manifest_sources() -> None:
    manifest_path = ROOT / "source-hashes.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for entry in manifest["sources"]:
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            fail(f"source path must stay inside this checkout: {relative}")
        path = ROOT / relative
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != entry["sha256"]:
            fail(f"source changed after capture: {path} ({actual} != {entry['sha256']})")


def check_zip() -> int:
    if not ZIP_PATH.exists():
        fail(f"missing package: {ZIP_PATH}")
    forbidden = ("work/", "tools/", "captures/", "__pycache__/")
    with zipfile.ZipFile(ZIP_PATH) as archive:
        names = archive.namelist()
        from package_media import publication_files
        expected = publication_files()
        if set(names) != set(expected) or len(names) != len(expected):
            fail("package does not match the publication file list")
        if archive.testzip() is not None:
            fail("package CRC validation failed")
        for name, path in expected.items():
            if archive.read(name) != path.read_bytes():
                fail(f"package member is out of date: {name}")
        if "README.md" not in names:
            fail("package has no README.md")
        if not any(name.startswith("SolarApp/") for name in names):
            fail("package has no SolarApp media")
        if not any(name.startswith("PelletStove/") for name in names):
            fail("package has no PelletStove media")
        if not any(name.startswith("EventTrigger/") for name in names):
            fail("package has no Event trigger media")
        if not any(name.startswith("NetatmoV2/") for name in names):
            fail("package has no NetatmoV2 media")
        if any(name.startswith(forbidden) for name in names):
            fail("package contains work/captures/tools intermediate files")
        return len(names)


def main() -> None:
    solar_checked = check_images("SolarApp", 11, 11, 20000)
    pellet_checked = check_images("PelletStove", 16, 12, 30000)
    event_checked = check_images("EventTrigger", 14, 14, 28000)
    netatmo_checked = check_images("NetatmoV2", 15, 15, 32000)
    check_manifest_sources()
    package_files = check_zip()
    print(f"PASS: {solar_checked + pellet_checked + event_checked + netatmo_checked} AWTRIX image assets; source hashes; ZIP entries={package_files}")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, FileNotFoundError, KeyError, ValueError, zipfile.BadZipFile) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)

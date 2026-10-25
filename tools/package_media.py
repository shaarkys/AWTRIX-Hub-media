"""Rebuild the publication ZIP inside dist/, excluding source and work files."""

from __future__ import annotations

import zipfile
import os
from pathlib import Path
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ZIP_PATH = ROOT / "dist" / "AWTRIX-Hub-media.zip"


def publication_files() -> dict[str, Path]:
    files = {"README.md": ROOT / "MEDIA.md", "source-hashes.json": ROOT / "source-hashes.json"}
    for path in (ROOT / "source-notices").iterdir():
        if path.is_file():
            files[path.relative_to(ROOT).as_posix()] = path
    for app in ("SolarApp", "PelletStove"):
        app_root = ROOT / app
        candidates = [app_root / name for name in (
            f"{app.lower()}-cover.png", f"{app.lower()}-showcase.gif", "gallery-contact-sheet.png"
        )]
        for folder in ("native", "screenshots", "animations"):
            candidates.extend((app_root / folder).glob("*"))
        for path in candidates:
            if path.is_file() and path.suffix in {".png", ".gif"}:
                files[path.relative_to(ROOT).as_posix()] = path
    return files


def main() -> None:
    files = publication_files()
    ZIP_PATH.parent.mkdir(exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="media-", suffix=".zip", dir=ZIP_PATH.parent)
    os.close(descriptor)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name, path in sorted(files.items()):
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        os.replace(temporary, ZIP_PATH)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print(f"Created {ZIP_PATH} with {len(files)} user-facing files")


if __name__ == "__main__":
    main()

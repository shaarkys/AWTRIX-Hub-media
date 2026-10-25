"""Create the sibling publication ZIP without helper/work files."""

from __future__ import annotations

import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ZIP_PATH = ROOT.parent / "AWTRIX-Hub-media.zip"
ALLOWED_FILES = [ROOT / "README.md", ROOT / "source-hashes.json"]
ALLOWED_DIRS = [ROOT / "SolarApp", ROOT / "PelletStove", ROOT / "source-notices"]


def main() -> None:
    if ZIP_PATH.exists():
        raise SystemExit(f"Refusing to overwrite existing package: {ZIP_PATH}")
    files: list[Path] = [path for path in ALLOWED_FILES if path.exists()]
    for directory in ALLOWED_DIRS:
        files.extend(path for path in directory.rglob("*") if path.is_file())
    if not files:
        raise SystemExit("No media files found")
    with zipfile.ZipFile(ZIP_PATH, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(files):
            archive.write(path, path.relative_to(ROOT).as_posix())
    print(f"Created {ZIP_PATH} with {len(files)} user-facing files")


if __name__ == "__main__":
    main()

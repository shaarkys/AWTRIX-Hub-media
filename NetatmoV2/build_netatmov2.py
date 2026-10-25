"""Build the standalone NetatmoV2 Berry app reproducibly."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parent
CORE = ROOT / "netatmo_core.be.inc"
GRAPHICS = ROOT / "netatmo_graphics.be.inc"
OUTPUT = ROOT / "NetatmoV2.ax"


def split_core(source: str) -> tuple[str, str]:
    marker = "class NetatmoV2 : NetatmoArtwork"
    if source.count(marker) != 1:
        raise ValueError(f"expected one {marker!r} declaration in {CORE}")
    if "return NetatmoV2()" in source:
        raise ValueError("core include must not contain a return statement")
    header, core = source.split(marker, 1)
    return header.rstrip() + "\n\n", marker + core.rstrip() + "\n"


def read_graphics(source: str) -> str:
    marker = "class NetatmoArtwork"
    if source.count(marker) != 1:
        raise ValueError(f"expected one {marker!r} declaration in {GRAPHICS}")
    if "return NetatmoV2()" in source or "class NetatmoV2" in source:
        raise ValueError("graphics include must contain only NetatmoArtwork")
    return source.strip() + "\n\n"


def build() -> str:
    header, core = split_core(CORE.read_text(encoding="utf-8"))
    artwork = read_graphics(GRAPHICS.read_text(encoding="utf-8"))
    output = header + artwork + core + "return NetatmoV2()\n"
    OUTPUT.write_text(output, encoding="utf-8", newline="\n")
    return output


if __name__ == "__main__":
    build()
    print(f"wrote {OUTPUT}")

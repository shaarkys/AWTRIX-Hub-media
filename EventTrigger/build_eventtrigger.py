"""Build the standalone Event trigger Berry app reproducibly.

The metadata/import section and EventTrigger class live in ``event_core.be.inc``;
the procedural drawing class is supplied by ``event_graphics.be.inc``. Keeping
the generated script assembled from those two sources makes the graphics and
runtime work independently while leaving SolarApp and PelletStove untouched.
"""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parent
CORE = ROOT / "event_core.be.inc"
GRAPHICS = ROOT / "event_graphics.be.inc"
OUTPUT = ROOT / "EventTrigger.ax"


def split_core(source: str) -> tuple[str, str]:
    marker = "class EventTrigger : EventArtwork"
    if source.count(marker) != 1:
        raise ValueError(f"expected one {marker!r} declaration in {CORE}")
    header, core = source.split(marker, 1)
    return header.rstrip() + "\n\n", marker + core.rstrip() + "\n"


def read_graphics(source: str) -> str:
    marker = "class EventArtwork"
    if source.count(marker) != 1:
        raise ValueError(f"expected one {marker!r} declaration in {GRAPHICS}")
    # The graphics include is intentionally a class-only source file. Rejecting
    # a second return/header here prevents an accidental non-standalone build.
    if "return EventTrigger()" in source or "class EventTrigger" in source:
        raise ValueError("graphics include must contain only EventArtwork")
    return source.strip() + "\n\n"


def build() -> str:
    header, core = split_core(CORE.read_text(encoding="utf-8"))
    artwork = read_graphics(GRAPHICS.read_text(encoding="utf-8"))
    output = header + artwork + core + "return EventTrigger()\n"
    OUTPUT.write_text(output, encoding="utf-8", newline="\n")
    return output


if __name__ == "__main__":
    build()
    print(f"wrote {OUTPUT}")

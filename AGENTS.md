# AWTRIX workspace

This repository is the source of truth for SolarApp, PelletStove, Event trigger and NetatmoV2. Keep AWTRIX work here; the Haas+Sohn Homey app repository is a separate project.

- Preserve MQTT topics, setting IDs and existing runtime behavior during organization-only changes.
- `SolarApp/build_extension.py`, `SolarApp/SolarApp.original.ax` and `SolarApp/graphics.be.inc` generate the three matching SolarApp deliverables.
- `PelletStove/PelletStove.ax` is authored directly. Its input contract is frozen in `PelletStove/input-contract.json`.
- `EventTrigger/build_eventtrigger.py` combines the core and artwork fragments into `EventTrigger/EventTrigger.ax`. Event indices and behavior are documented in `EventTrigger/SPEC.md`.
- `NetatmoV2/build_netatmov2.py` combines its core and artwork fragments into `NetatmoV2/NetatmoV2.ax`. Keep OAuth credentials and real account responses out of sources, fixtures, captures and Git; use synthetic fixtures only.
- Run `python tools/build.py --berry PATH` with a Berry 1.1 interpreter built with 32-bit integers and single-precision floats. Python/Pillow render previews; these do not verify hardware behavior.
- Keep generated work, captures and caches ignored. Preserve historical recovery archives and font licensing/provenance.
- Before cleanup of old source directories, confirm their contents are covered by the recovery manifest and that the final commit is present on GitHub.
- Do not publish to AWTRIX Hub, install scripts, change device settings, or communicate with live MQTT devices unless explicitly requested.

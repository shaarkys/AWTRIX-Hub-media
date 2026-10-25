# AWTRIX NG apps and Hub media

Standalone MQTT display apps for the **Ulanzi TC002 / AWTRIX NG, 52 x 16 pixels**. This repository is the single working location for the scripts, configuration guides, source generators, tests, and publication media.

| App | Installable script | Configure | Screenshots | Animation |
| --- | --- | --- | --- | --- |
| SolarApp | [SolarApp.ax](SolarApp/SolarApp.ax) | [Guide](SolarApp/README.md) | [Gallery](SolarApp/gallery-contact-sheet.png) | [Rotation GIF](SolarApp/solarapp-showcase.gif) |
| PelletStove | [PelletStove.ax](PelletStove/PelletStove.ax) | [Guide](PelletStove/README.md) | [Gallery](PelletStove/gallery-contact-sheet.png) | [Rotation GIF](PelletStove/pelletstove-showcase.gif) |
| Event trigger | [EventTrigger.ax](EventTrigger/EventTrigger.ax) | [Guide](EventTrigger/README.md) | [Gallery](EventTrigger/gallery-contact-sheet.png) | [Example events GIF](EventTrigger/eventtrigger-showcase.gif) |

**SolarApp** rotates through solar production/yield, battery charge, measured house load, and signed grid import/export. Solar is skipped when production is zero or stale. The house source graphic is illustrative; it does not calculate an energy split.

**PelletStove** rotates through stove mode/status, current/target temperatures, pellets, cleaning, ash usage, and errors. It includes cooling-fan and microfiber-cloth animations, proportional 30 kg fuel levels, urgent cleaning/ash blinking, a standby page showing current room temperature, and the optional temperature-only standby turn. Valid false error readings clear old faults even in standby, OFF, or before fresh power/mode messages arrive.

**Event trigger** displays animated scenes for motion, received/collected mail, heat, water leak, doorbell, and garage opening. Graphics are text-free and silent by default, with optional labels. It requests a turn on receiving a matching event and stays out of the rotation while idle. Use one auto-routing copy or configure separate copies for individual sensor topics.

Paste only the chosen `.ax` file into the AWTRIX Scripts editor. MQTT publishing is configured in Homey or another publisher. These scripts subscribe to data; they do not control the stove or inverter.

## Layout

- `SolarApp/`: active SolarApp sources, generated deliverables, tests, guide and media.
- `PelletStove/`: active PelletStove source, frozen Homey input contract, tests, guide and media.
- `EventTrigger/`: generated event app, core/artwork sources, input and queue tests, guide and media.
- `tools/`: portable build, Berry capture, media rendering, packaging and validation.
- `source-notices/`: unmodified upstream font, its license and provenance.
- `dist/AWTRIX-Hub-media.zip`: current publication media bundle.
- `archive/`: verified recovery snapshot of every original file before consolidation.
- `work/`: ignored generated capture files; recreated by the build.

The old `SolarApp-extension` and Haas+Sohn `docs/awtrixng` folders are migration sources, not ongoing working locations. No Homey driver or firmware is required in a neighboring checkout.

## Rebuild and verify

Requirements: Python (tested with 3.13.1), Pillow 10.4.0, Git, and a **Berry 1.1 interpreter built with 32-bit integers and single-precision floats**. The interpreter is an external development tool; it is not installed on the clock and is not bundled in this repository. The recovery snapshot includes the original Berry Makefile used for the local build. A different Berry numeric configuration is not equivalent to the embedded runtime used by these tests.

```powershell
python -m pip install -r requirements-dev.txt
$env:BERRY = 'C:\path\to\berry32.exe'
python tools/build.py --berry $env:BERRY
```

The command regenerates SolarApp and Event trigger, runs the mocked Berry suites, checks the frozen PelletStove input contract, captures the scripts with the official small-font metrics, renders the PNG/GIF media, writes relative source hashes, rebuilds the publication ZIP and validates every decoded GIF timestamp. All inputs come from this checkout. Full cold-build verification also checks that ignored `work/` data is unnecessary.

Individual commands are documented in each app guide. `python tools/validate_media.py` checks an existing capture/export; run the full build first on a new clone.

## Media and device verification

All images here are **simulated previews using sample MQTT data**, not physical TC002 recordings. Exact hardware colors, brightness, timing, firmware integration and MQTT delivery remain unverified by the offline build. See [MEDIA.md](MEDIA.md) for dimensions, sample values and a caption to use when uploading to the Hub. Publishing this GitHub repository does not upload anything to AWTRIX Hub or install anything on a device.

[TC002 color-calibration notes](docs/TC002-display-calibration.md) preserve the latest suggested trial settings and the distinction between LED output and the raw preview.

The publication ZIP contains media, its source-hash manifest and font notices. Clone/download the repository to obtain the scripts and development sources.

## Provenance and recovery

SolarApp extends the supplied SolarApp 4.3.1; the unchanged original input retains its upstream Hub identity in `SolarApp/SolarApp.original.ax`. Current generated deliverables omit that identity. Retained third-party font terms are in [source-notices](source-notices/FONT-NOTICE.md). This reorganization does not invent or change the upstream license terms.

The initial public backup commit is `4096c95`. [Recovery instructions](archive/README.md) and its SHA-256 inventory cover all files from the original three working directories, including intermediate captures and older export ZIPs. Historical files are recovery material; active development belongs in the app folders above.

See the [migration map](MIGRATION.md) for the original paths and guarded cleanup procedure. The cleanup helper defaults to a dry run and refuses to remove files unless the current clean commit is on GitHub and every old file matches the recovery inventory.

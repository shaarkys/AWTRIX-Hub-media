# AWTRIX Hub publication media

This folder contains clean upload-ready PNG screenshots and animated GIF previews for the SolarApp and PelletStove AWTRIX NG scripts.

## Important disclosure

Every panel image in this package is a **SIMULATED RENDERED PREVIEW**. It was produced by executing the copied Berry 1.1 scripts with mocked AWTRIX drawing, MQTT, and time APIs, then rasterizing the captured draw calls. These files are not photographs, screen recordings, or proof of rendering on a physical TC002. No live MQTT broker, Homey instance, AWTRIX device, brightness setting, or device firmware was used.

Contact sheets are explicitly labeled `RENDERED PREVIEW`. Individual upload frames are intentionally clean and contain no watermark; keep this disclosure in the Hub description or caption.

Suggested AWTRIX Hub caption:

> Simulated AWTRIX NG preview rendered from the script's Berry draw calls with sample MQTT data. The PNG/GIF shows the intended 52×16 layout; it is not a physical TC002 recording. Actual colors, timing, brightness, font firmware, and live MQTT values can vary on the device.

## Files

- `SolarApp/solarapp-cover.png` — clean 1040×320 hero frame.
- `SolarApp/solarapp-showcase.gif` — normal four-view SolarApp rotation, 20 seconds at 10 FPS.
- `SolarApp/screenshots/` — clean 1040×320 stills; matching native 52×16 files are in `SolarApp/native/`.
- `SolarApp/animations/` — clean 624×192 four-second per-scene GIFs at 10 FPS.
- `PelletStove/` — the corresponding PelletStove cover, rotation, stills, and scene GIFs. The empty-hopper, clear-error, and power-off states are clean stills only because the source produces no meaningful animation in those states; the remaining dynamic scenes have genuine Berry-driven GIF motion.
- `EventTrigger/` — seven animated sample events, label variants, native frames, gallery and a staged 28-second showcase. This is an event app: the showcase demonstrates examples and is not an idle rotation.
- `source-notices/` — the unmodified official AWTRIX NG BDF source, its retained license, and provenance notice.

`dist/AWTRIX-Hub-media.zip` contains only the README, provenance/hash manifest, source notices, and user-facing media folders. It intentionally excludes Berry source snapshots, JSON captures, and helper scripts.

## Rendering assumptions

- Native panel geometry is 52×16; PNG screenshots use integer nearest-neighbor scaling to 1040×320 (20×), and GIFs use 624×192 (12×).
- The capture harness advances simulated time by 25 ms per Berry draw, matching a nominal 40 FPS display loop, and saves every fourth draw for 10 FPS GIF output. The physical app scheduler and device frame rate can vary.
- SolarApp's source increments its animation phase per draw; this media therefore assumes the nominal draw cadence. PelletStove's current animation is sampled at the same nominal cadence. Neither timing assumption is physical-device proof.
- Each scene was warmed with approximately two seconds of actual script draws before `on_show()` and capture. The SolarApp showcase is a normal 5-second-per-view four-page rotation. The PelletStove showcase is a normal six-page 5-second rotation (30 seconds total) from the final source snapshot.

## Sample data and interpretation

SolarApp scenes use the requested sample values: 2500 W production, 12345 Wh daily yield, 900 W house load, 76% SOC, +850 W battery charging, and −420 W grid export. Signed battery/grid values are interpreted using the script's default `charge_positive` and `import_positive` conventions. The house-unknown scene uses 0 W solar, 0 W battery, 0 W grid, and 3000 W house load; the lightning icon is the script's source-unknown activity graphic and does not infer an energy split.

PelletStove scenes use the Berry harness's sample state: on/off enabled, heating mode, 21.4°C actual / 22.0°C target, 8.4 kg pellets, 32.5 h cleaning interval, 45% ash usage, and clear error unless the scene says otherwise. The `standby-status` still shows the ordinary `STANDBY` page with live current temperature 24.0C. The separate optional standby scene sets `standby_skip=true` (the setting defaults to `false`), requires power `Yes`, enters mode `STANDBY`, establishes the 21.4°C / 22.0°C baseline, then feeds a changed 21.5°C reading; the captured `SET22.0C` temperature-only visit is the source behavior. It does not claim that the physical script was skipped on a device.

Event trigger samples publish active pulses for motion, mail received, mail collected, heat, water, doorbell and garage. Seven full-panel scenes and seven labelled variants each cover four seconds of elapsed animation. The combined showcase stages those seven full-panel examples. It does not imply the app cycles through all events without MQTT input. Artwork is generated procedurally by the app; no external scene icons are loaded.

## Provenance

The media uses the unmodified official small font copied from `source-notices/awtrix-small.bdf`, not the older SolarApp approximate renderer font. The accompanying `FONT-LICENSE.txt` and `FONT-NOTICE.md` are retained verbatim. The notice records upstream `Blueforcer/awtrix-ng`, source path `assets/fonts/awtrix.bdf`, retrieval date 2026-10-24, and source commit `0ec2b1b14d628c34d958bde6027cfb2748f64330`.

The exact source SHA-256 values and repository-relative source paths are recorded in `source-hashes.json`. The SolarApp source used for the capture was `SolarApp/SolarApp.ax`; its three supplied SolarApp deliverables were byte-identical at capture time. The active sources now live together in this repository, including the latest PelletStove fault-clear correction.

## Deterministic recapture and limits

The `tools/` sources are committed for reproducibility. Generated `work/` captures are ignored and rebuilt from the active sources. Both are excluded from the media-only ZIP. From the repository root, run:

```powershell
python tools/build.py --berry $env:BERRY
```

See the [repository build guide](https://github.com/shaarkys/AWTRIX-Hub-media#rebuild-and-verify) for the external Berry runtime and Python requirements. `source-hashes.json` uses paths relative to this checkout; it has no dependency on the original folders.

The capture used the available Berry 1.1.0 32-bit VM and Python 3.13.1 with Pillow 10.4.0. Validation checks PNG/GIF opening, native/scaled geometry, GIF timing and total duration, changing frames for genuinely animated scenes, and every decoded GIF timestamp against the corresponding captured draw frame quantized with the same global palette; this catches disposal/background corruption. It also checks source hashes and ZIP contents. It does not prove Homey runtime behavior, MQTT delivery, AWTRIX Hub acceptance, physical display appearance, or actual hardware timing.

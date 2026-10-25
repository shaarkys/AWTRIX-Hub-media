# SolarApp for AWTRIX NG on TC002

Import **SolarApp.ax** in the AWTRIX NG **Scripts** tab, or paste its contents into
the script editor and save. This is a complete, single-file Berry application for
the TC002's 52x16 display. It needs no uploaded icons, helper modules or sounds.
The original script is retained as `SolarApp.original.ax` for comparison/recovery.
Nothing has been installed on your clock. This is a standalone AWTRIX NG script,
not a Homey app.

## Published media

The rendered previews are kept beside the active source in this public repository:

- [Cover image](solarapp-cover.png)
- [Gallery contact sheet](gallery-contact-sheet.png)
- [20-second showcase (5 seconds per view)](solarapp-showcase.gif)
- [Individual rendered scenes](screenshots/)
- [Per-scene animations](animations/)
- [Native 52x16 PNG frames](native/)
- [AWTRIX-Hub-media repository](https://github.com/shaarkys/AWTRIX-Hub-media/tree/main/SolarApp)

The PNG and GIF files are simulated Berry-rendered previews, not photographs or
recordings of a physical TC002. See the [repository disclosure](../MEDIA.md)
for the rendering assumptions and sample MQTT values.

## Rotation

The default order is **Solar -> FVE battery -> House -> Grid**, five seconds each.
Select advances immediately. Left/right retain their normal clock navigation.
The script requests enough display time for one complete cycle before AWTRIX moves
to the next application. Changing settings restarts the script, as documented by
AWTRIX NG.

| View | Top row | Bottom row | When shown |
| --- | --- | --- | --- |
| Solar | Actual solar power, W/kW | Actual daily yield, Wh/kWh | Fresh production exceeds the configured threshold (default 1 W) |
| FVE battery | State of charge, % | Optional signed battery power | Fresh state of charge |
| House | Actual house load, W/kW | LOAD | Fresh house reading, including zero |
| Grid | Actual net grid power, W/kW | IMPORT / EXPORT / IDLE | Fresh signed grid reading, including zero |

Empty topics and the individual Show switches disable the associated views.
Missing/stale primary readings are skipped. If no view qualifies, the display
shows NO DATA / MQTT. A missing yield or optional battery power shows `--` without
removing the otherwise valid solar/battery view. `OVR` means a formatted amount is
too wide for the available text area.

The existing sun_large and sun_half animated solar styles are retained. Other
views share the original scene layout with its shaded right-edge house and warm,
flickering windows. The battery has a bevelled case, shaded glass and illuminated
cells that follow its percentage. The grid uses a shaded steel pylon with glowing
insulators. Energy particles move towards the battery when charging and away when
discharging; they move from grid to house for import and back for export. Their
paths sit between the text rows, keeping values clear. Idle readings have no
directional stream.

The house view illustrates an available measured source: solar when producing,
otherwise a discharging battery or importing grid. If none is identified, a generic
electricity/load symbol with a breathing glow and orbiting sparks replaces the
dim sun. This symbol animates while house load is positive; it does not assert a
source or a direction of supply. Zero load has no activity pulse or sparks. Solar
still stays out of the rotation while production is zero. The view does not
calculate an energy mix or infer grid direction from solar minus house load. The
top number remains the actual house load in every case.

Source-status transitions are logged when house load is active. The messages
distinguish solar at zero/below threshold from solar missing/expired, and report
when measured solar, battery discharge or grid import becomes available. They do
not include MQTT topics or raw message contents.

## Configure your MQTT inputs

The original settings `topic_power`, `topic_yield`, `topic_consumption`,
`visual_style`, `max_power`, `anim_speed`, and `yield_unit` keep their keys.
Existing saved Max Power (for example, 5000 W) remains applicable when replacing
the source under the same install name. Defaults for the original three topics
are unchanged. New battery/grid topics are empty until you enter your own.

| Setting | Meaning | Example payload |
| --- | --- | --- |
| Power MQTT Topic | Solar generation in W | `2500` or `{"P_AC":2500}` |
| Daily Yield MQTT Topic | Daily generation, Wh by default | `12345` or `{"YieldDay":12345}` |
| Consumption MQTT Topic | Actual house load in W | `900` or `{"consumption":900}` |
| FVE Battery Capacity MQTT Topic (%) | Battery state of charge from 0 to 100 | `76` or `{"soc":76}` |
| FVE Battery Power MQTT Topic (W) | Optional signed battery charge/discharge power | `850` or `{"battery_power":850}` |
| Grid Power MQTT Topic (W) | Signed net import/export power | `-420` or `{"grid_power":-420}` |

All power inputs are **W**, not kW. Battery capacity here means **state of charge
in percent**, not the installed battery's rated kWh capacity.

The default grid convention is **positive = import**, **negative = export**.
The default battery convention is **positive = charge**, **negative = discharge**.
Both conventions can be reversed independently in settings. Battery power is
displayed with `+` for charging and `-` for discharging after that conversion.
Grid/battery idle thresholds default to 10 W to avoid direction flicker around zero.

`MQTT Yield Input Unit` specifies whether the incoming yield is Wh or kWh.
`Yield Display Unit` independently selects Wh, kWh, or automatic display units.
Live readings expire after 120 seconds by default; yield after 3600 seconds.
Choose longer timeouts for slowly publishing devices, or 0 to disable expiry.
Freshness measures time since reception: an old retained MQTT message is treated
as newly received because these payloads do not carry a source timestamp.

Numeric payloads and JSON numeric strings are supported. For JSON objects, the
script uses known top-level field aliases, or an exact top-level field name you
enter under Optional JSON fields. Nested JSON paths and separate unsigned
import/export topics are not supported by this version; publish a signed net grid
value upstream. A shared JSON topic can supply several/all readings: configure
the same topic for each and specify its respective field. For example:

```json
{"pv":2500,"today":12345,"house":900,"soc":76,"battery":850,"grid":-420}
```

Set the six JSON fields to `pv`, `today`, `house`, `soc`, `battery`, and `grid`.
There is only one subscription for each distinct configured topic/filter (at most
six, below the documented limit of eight). MQTT wildcards are supported; choose a
filter that represents the intended metric, since all matching messages feed it.
Invalid values leave the previous reading untouched without refreshing its age.
Diagnostic logs identify the input index (0 solar, 1 yield, 2 house, 3 SOC, 4 battery
power, 5 grid) without exposing message contents.

The house input must represent **house load**. The previous automatic `grid_power`
alias was removed from that input because a net grid reading is not house load,
especially with a battery. Use Grid Power MQTT Topic for that measurement.
The old `default_view` key is retained: `yield` starts at solar and `consumption`
starts at house; new choices are battery/grid. Select now cycles full views rather
than toggling a bottom row. The legacy saved `active_view` is no longer used.

The original Hub signature was removed from this locally modified copy so it does
not claim to be the original Hub source. The original version string was retained;
this is an unpublished local extension, not an upstream release.

## Verification and TC002 retest

The checks use the actual upstream Berry 1.1.0 compiler/VM, configured with 32-bit
integers and single-precision reals, and mocked AWTRIX storage, time, MQTT and draw
calls. This checks Berry syntax and logic, not the installed TC002 firmware or a
real broker. The test harness's numeric helper uses JSON number parsing; the
firmware's documented `num()` also accepts formats such as leading-zero numbers.

From this directory, run `python build_extension.py` to reproduce the standalone
.ax from the original, extension source and `graphics.be.inc`, then run
`<berry-interpreter> test_solarapp.be` with the upstream 32-bit Berry 1.1.0 VM.
`python verify_extension.py` checks generation, configuration, the deliverable
hash and whitespace. The verifier invokes the same Python interpreter that
started it, so no machine-specific Python path is required.

To capture Berry draw calls for a local diagnostic, run
`<berry-interpreter> capture_animation.be`; it writes the ignored
`animation-frames.json`. The old approximate-font render helpers and their
pre-rendered JSON/GIF inputs are intentionally not active sources here.
The generated file itself needs **no build step** on AWTRIX.

`SolarApp.ax`, `SolarApp-TC002-Animated.ax` and `SolarApp-TC002-SourceAware.ax`
are generated byte-identical copies. The SourceAware name identifies the house
fallback correction dated 2026-10-23; replace the contents of the existing app to
keep its configured topics instead of creating a second app.

On your TC002 after importing:

1. Configure the real topics and correct yield/sign conventions. Enable MQTT in
   the clock's system settings if it is not already connected.
2. Check solar and yield against the inverter. Set production to zero through
   your normal test data source and confirm solar leaves the cycle.
3. Verify 0%, 50%, and 100% battery readings, charging and discharging directions,
   and an actual house-load reading.
4. Verify one known import, one known export, and a near-zero grid reading. Check
   direction against the meter before relying on the sign setting.
5. Let each view rotate, press Select, and confirm another AWTRIX app gets its
   next turn after this application's full cycle.
6. Stop publishing long enough to cross the timeout; confirm stale primary views
   disappear. Resume and confirm they recover. Check both solar styles.

The offline build makes no device changes. Hardware rendering, real MQTT delivery and the
installed firmware's script memory/instruction budgets remain unverified.

## Historical recovery material

The recovery snapshot at `../archive/pre-consolidation-2026-10-25.zip` retains
the pre-consolidation SolarApp folder byte-for-byte, including
`SolarApp.before-graphics.ax`, `SolarApp.before-house-fix.ax`, the approximate-font
preview renders, and `reproduce_house_input.be`. Those files are preserved for
forensics and recovery only; use the flat active files in this directory for
generation and tests. The archive is accompanied by its SHA-256 manifest.

## Documentation used

- [Requested ESP32 scripting guide](https://blueforcer.github.io/awtrix-ng/esp32/guides/scripting/)
- [TC002 scripting guide](https://blueforcer.github.io/awtrix-ng/tc002/guides/scripting/)
- [MQTT callbacks](https://blueforcer.github.io/awtrix-ng/tc002/guides/scripting/network/)
- [Settings and persistence](https://blueforcer.github.io/awtrix-ng/tc002/guides/scripting/storage/)
- [Drawing](https://blueforcer.github.io/awtrix-ng/tc002/guides/scripting/drawing/)
- [Rotation and duration](https://blueforcer.github.io/awtrix-ng/tc002/guides/scripting/several-apps/)
- [TC002 limits](https://blueforcer.github.io/awtrix-ng/tc002/reference/limits/)

One-row changelog: Added configurable rotating solar/yield, FVE battery, house-load
and signed grid import/export views with animated energy scenes for TC002.

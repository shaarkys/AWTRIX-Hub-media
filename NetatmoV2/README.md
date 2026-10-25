# NetatmoV2 for AWTRIX NG / TC002

NetatmoV2 discovers your Netatmo Weather Station and its attached modules and rotates through **one or two pages per module** on the TC002's 52 x 16 display. Built-in shaded pixel art identifies indoor, outdoor, additional indoor/Couch, rain and wind modules. There are no icon names, icon numbers or downloads to configure.

The canvas is **black**. Colored module graphics and readings stand on it without tinted panels, dividers or permanent name captions. Climate pages show plain readings such as **23.2°C** and **56%**, with Celsius/Fahrenheit following the clock's setting.

[Installable script](NetatmoV2.ax) · [Gallery](gallery-contact-sheet.png) · [Simulated rotation](netatmov2-showcase.gif)

## Why the supplied Netatmo script could be empty

The supplied Netatmo 6.3 by Oliver Rummeyer has several failure paths visible in its source:

- It only displays exact module names entered in `Rooms`. Its defaults list German room names. Renamed modules, English/Czech names or a different spelling will not match.
- It searches for literal `"_id":"` and other compact JSON substrings. Spaces, field ordering and nested module records can prevent it from finding the correct device/dashboard fields.
- It requires a `Temperature` value before processing any module, so rain gauges and anemometers are skipped.
- Signed-in but unmatched modules can leave no readable page. The red request-failure indicator does not explain missing modules.

Those are verified source-level problems; without a signed-in account response, they do not establish which path caused your particular empty display. NetatmoV2 replaces name matching and string slicing with structured JSON discovery, handles rain/wind independently, and always has a diagnostic page.

## Install and sign in

1. In the TC002 web UI, create a normal script named **NetatmoV2**, paste the complete [NetatmoV2.ax](NetatmoV2.ax), save and enable it. No supporting files need uploading.
2. Open the script's gear/settings dialog and its native **Sign-in** section. Enter your Netatmo developer application's Client ID and Client secret there.
3. Configure the developer application's redirect URL as `https://awtrix.de/oauth/callback`, exactly as specified in the [AWTRIX sign-in guide](https://blueforcer.github.io/awtrix-ng/tc002/guides/sign-in/).
4. Press **Sign in**, log into Netatmo in the browser and approve `read_station` access. Client ID and secret alone are not a station access token.
5. Return to the clock. It polls when signed in; no module names or icon setup are required. Leave **Station ID** blank to discover all returned stations.

The new app name has a separate sign-in from the original Netatmo script. Renaming the installed app or changing its OAuth metadata can also require signing in again. Keep the app enabled so background polling continues. This version targets TC002 native OAuth; it does not offer a TC001 manual-token fallback.

Credentials and tokens stay in the native sign-in system. They are not read by this script, included in the repository, saved in fixtures or printed in logs. See the official [script OAuth API](https://blueforcer.github.io/awtrix-ng/tc002/guides/oauth/).

## Discovery and module switches

The API's stable module types determine the view; names never control matching. The additional indoor module can therefore be named `Couch`, `Cauch` or anything else without losing its readings. Distinct API IDs identify modules even when names are duplicated.

**Show room names** defaults to **Off**. The infographic identifies the module type, and uses the full available height while names are hidden. Enable this option when you have multiple modules in different rooms or locations; a shortened safe room label then appears below the graphic. Every discovered module still gets its own readings and pages with the option either on or off. The gallery includes a `couch-climate-named` example of this optional presentation.

| Switch | API type | Pages, if values exist |
| --- | --- | --- |
| Indoor | `NAMain` | Temperature/humidity; air quality with CO2, pressure and noise |
| Outdoor | `NAModule1` | Temperature/humidity; optional reported daily min/max |
| Additional indoor / Couch | `NAModule4` | Temperature/humidity; available air-quality values |
| Rain sensor | `NAModule3` | Latest rain and 1-hour total; 24-hour total |
| Anemometer | `NAModule2` | Wind/gust speed; optional direction and reported daily maximum |

All five switches default on. Disable the modules you do not want displayed. These switches filter real discovered modules; they do not create readings or substitute manual values for absent hardware. There is no icon setting.

**Show wind direction** and **Show daily min/max** both default to **Off**. The normal wind page shows wind speed and gust; enable wind direction for a second page such as `225°` plus the reported daily maximum speed. Daily min/max adds an outdoor page with down/up arrows and temperature units. The old `LO` label meant today's minimum temperature, not an alert; it is no longer used.

Indoor and additional indoor readings use a shaded house. Outdoor readings use a garden tree, timber fence and grass, with subtle leaf highlights; no sun/cloud symbol implies weather conditions that the temperature module cannot measure. Rain uses an umbrella with falling drops when the latest reported rain amount is positive; the daily-total page labels its period `24H`. Wind uses a three-blade rotating turbine, which stops for calm or unavailable current wind. Its animation responds to the measured speed but does not represent physical turbine RPM. Room-name mode uses compact versions of these graphics.

Missing individual measurements are omitted; zero rain and zero wind remain valid readings. At most two pages are built for each module. CO2 reads simply `987 ppm`, without a CO2 prefix, and keeps its configured warning colors. Main-module air quality keeps this on the upper line and alternates pressure/noise on the lower line when both are present; a CO2-only page centers the single reading. If no CO2 exists, the available pressure/noise measurements use the two lines. A known module without usable data gets a clear offline page.

Rain is shown in **mm**, with latest/1H/24H periods identified. The latest API rain value is not relabelled as a fabricated mm/hour rate. Wind speed is **km/h**. Temperature follows the clock's Celsius/Fahrenheit setting. No weather forecast is inferred from an outdoor temperature measurement.

Discovery is bounded to 12 modules / 24 pages. Optional **Station ID** filters one station when your account has several. Station names and module IDs are not needed for the normal setup.

## V1 timing and old data

The [Netatmo Weather API](https://dev.netatmo.com/apidocumentation/weather) documents cloud readings from `getstationsdata` as updating approximately every ten minutes. This app intentionally uses that endpoint for V1-style stations; it does not assume near-realtime `homestatus` support or guess the hardware generation from a reading delay. Later modules that expose the same documented station schema can also be discovered; generation-specific hardware behavior is unverified.

- Polling defaults to **10 minutes**, configurable from 5 to 60.
- **Stale after** defaults to **45 minutes**. Last good values remain visible with an amber indicator.
- **Maximum age** defaults to **180 minutes**. Expired values are hidden behind a module `NO DATA` state.
- Freshness follows the measurement timestamp, not whether its numerical value changed. Re-fetching an old timestamp does not make it fresh.
- Missing/unreachable modules can retain their previous readings with an old-data indicator until expiry. Invalid responses and connection failures do not erase good measurements.
- Without a valid wall clock/source timestamp, the script uses elapsed time since receipt. In that case it cannot know how old a cached cloud reading already was before receipt.

Quiet hours can skip the app's normal turn while polling continues. Page duration defaults to six seconds. A rotation turn uses a stable page snapshot so a background update cannot change the page count halfway through a visit. No chart/history requests, file downloads, daily flash writes or production dependencies are required.

## When something is wrong

| Display condition | Check |
| --- | --- |
| Sign-in / authorization hint | Sign in under NetatmoV2's native settings; verify redirect URL and `read_station` access |
| Loading | Allow the first network request to finish |
| No modules | Confirm the same Netatmo account owns/accesses the station and clear an incorrect Station ID filter |
| Disabled | Turn on at least one module visibility switch |
| Request / parse error | Check connectivity; last good readings are retained, while logs give a bounded status description |
| Amber old-data indicator | Check the module's last reading in Netatmo; normal ten-minute V1 intervals remain below the default threshold |
| Module NO DATA | Data are missing or expired; check module batteries/radio reachability and the station's connection |

The app never logs raw response bodies, client credentials or tokens. Transient requests retry with bounded delays; rate-limit responses back off for at least ten minutes. A request watchdog prevents a lost callback from blocking polling indefinitely.

## Source, media and checks

`netatmo_core.be.inc` and `netatmo_graphics.be.inc` generate `NetatmoV2.ax` through `build_netatmov2.py`. The [implementation contract](SPEC.md) defines the field and rendering interface. Synthetic fixtures contain no real account data. The original attachment is not included as a public credential/configuration backup.

From this folder:

```powershell
python build_netatmov2.py
& $env:BERRY tools/test_netatmov2.be
python tools/verify.py
```

From the repository root, use `python tools/build.py --berry $env:BERRY` to verify all apps and rebuild previews, source hashes and the media ZIP.

All PNGs/GIFs are **simulated previews from the actual generated script's Berry drawing calls**, with synthetic data and the official font. They do not prove live Netatmo access, TC002 resource use, firmware timing, or physical color reproduction. No real account query or device installation is part of the offline verification.

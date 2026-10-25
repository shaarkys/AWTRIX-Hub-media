# Event trigger for AWTRIX NG / TC002

**Event trigger** listens for MQTT events and brings an animated scene onto the 52 x 16 TC002 display. It stays out of the normal rotation while idle. No external icons or sound files are needed.

The default presentation is **animation only, without text or sound**. Turn on **Show event labels** for a compact illustration with two short labels alongside it. One copy can handle all eleven events, or separate copies can each listen to a different sensor/topic.

| Event name | Animation | Default MQTT topic |
| --- | --- | --- |
| `motion` | Jacketed visitor walks past lit houses; camera LED and fading footsteps mark detection | `homey/events/motion` |
| `mail_received` | Cream envelope slips into a teal mailbox; flap closes and red flag rises | `homey/events/mail_received` |
| `mail_collected` | Mailbox opens, envelope moves into a waiting hand, flag lowers | `homey/events/mail_collected` |
| `heat` | Layered flame, drifting embers, glowing floor and rising thermometer | `homey/events/heat` |
| `water` | Steel pipe drips into moving water, beside a shaded blue droplet | `homey/events/water` |
| `doorbell` | Oversized brass bell swings beside a warm porch, with expanding ringing arcs | `homey/events/doorbell` |
| `garage` | Sectional shutter rises and holds open, revealing a red car and headlights | `homey/events/garage` |
| `dishwasher_finished` | Cabinet door folds down to reveal a clean plate rack beside a miniature sink | `homey/events/dishwasher_finished` |
| `cooker_finished` | Rounded air fryer slides out a food basket beside a serving plate; steam dissipates | `homey/events/cooker_finished` |
| `washing_machine_finished` | Washer door swings open and a garment moves into the laundry basket | `homey/events/washing_machine_finished` |
| `dryer_finished` | Dryer opens and a towel joins a folded stack as warm air dissipates | `homey/events/dryer_finished` |

These proposed topics are configurable; they are not assumed to exist in your broker. The pictures represent the supplied event, not measurements or an inference about what caused it. In particular, a mailbox contact opening alone does not tell the app whether mail arrived or was collected: publish the appropriate separate event from your Homey logic.

## Install and try it

1. Connect AWTRIX NG to the same MQTT broker as your existing Homey publish actions.
2. Create a normal script named **Event trigger**, paste the complete [EventTrigger.ax](EventTrigger.ax), save, and keep it enabled. No helper files need uploading. Do not make it headless: the script draws its own animations.
3. Keep the default **MQTT topic filter** `homey/events/+` and **Event mode** `auto`.
4. In a Homey Flow, publish literal `true` to `homey/events/doorbell` when the doorbell event occurs. Use **QoS 1 and retain off**. Use the same MQTT publish action you already use for the other AWTRIX apps.
5. The app requests its display turn on receiving the event. After the configured time, normal app rotation continues. It is skipped while there is nothing to show. Firmware notifications and display power can still affect when an event is visible.

The script uses the documented [MQTT callback](https://blueforcer.github.io/awtrix-ng/tc002/guides/scripting/network/) and [`rotation.show()`](https://blueforcer.github.io/awtrix-ng/tc002/guides/scripting/device/) APIs. No Homey Flow, broker or device settings are changed by the offline build.

### Homey Flow examples

Create an event Flow for the relevant existing sensor/device. Card names depend on that integration:

| WHEN the event occurs | MQTT topic | Payload |
| --- | --- | --- |
| Motion is detected in front of the house | `homey/events/motion` | `true` |
| Your mailbox logic detects received post | `homey/events/mail_received` | `true` |
| Your mailbox logic detects post pickup | `homey/events/mail_collected` | `true` |
| Heat alarm activates | `homey/events/heat` | `true` |
| Water-leak alarm activates | `homey/events/water` | `true` |
| Doorbell is pressed | `homey/events/doorbell` | `true` |
| Garage door opens | `homey/events/garage` | `true` |
| Dishwasher finishes its cycle | `homey/events/dishwasher_finished` | `true` |
| Cooker / air fryer finishes cooking | `homey/events/cooker_finished` | `true` |
| Washing machine finishes its cycle | `homey/events/washing_machine_finished` | `true` |
| Dryer finishes its cycle | `homey/events/dryer_finished` | `true` |

For appliance completions, publish from the Homey Flow that detects the cycle finishing, using **pulse** mode. The script displays the supplied completion event; it does not infer it from power consumption or a running/not-running reading. If the appliance already publishes `finished` and `running` states, use a fixed **Event mode**, **edge** triggering, and **exact** matching with active `finished` and inactive `running`. Each next cycle rearms the completion scene.

With the default **pulse** mode, send a message for each occurrence. Repeated messages for the same event within the default three-second cooldown are ignored. A valid `false` clears that event's queued/current scene; it does not trigger another animation.

For a device that publishes its ongoing state repeatedly, choose **edge** mode and publish both `true` and `false`. It then triggers on inactive-to-active transitions. Repeated `true` readings do not keep retriggering until a valid inactive value rearms the event.

### One topic with JSON

Set **MQTT topic filter** to `homey/events` and keep **Event mode** `auto`. Publish, for example:

```json
{"event":"doorbell","active":true,"id":"doorbell-00042"}
```

Use a different ID for each real occurrence. The optional ID is a string of at most 64 bytes. IDs are scoped by event type, so different sensors can reuse the same ID for different event names. A bounded cache remembers the 16 most recent accepted event/ID pairs in memory. It helps with duplicate deliveries but is not persistent across script restarts. An inactive message can clear only its matching event:

```json
{"event":"water","active":false}
```

On a single configured topic, recognized plain event-name payloads such as `doorbell` also trigger with the default pulse mode. Use pulse mode for these occurrence messages. Unknown names, malformed/oversized JSON, invalid activity values and missing required fields are ignored. Payloads are bounded to 512 bytes. Incoming arbitrary text is not drawn on the display.

### A separate copy for an existing topic

You can install the script under separate names, for example **Front door motion** and **Garage event**. For a copy that listens to `house/garage/state`:

- Set **MQTT topic filter** to `house/garage/state` and **Event mode** to `garage`.
- Select **Trigger mode** `edge` and **Value matching** `exact`.
- Set **Exact active value** to `open` and **Exact inactive value** to `closed`.

An `open` payload then triggers the garage scene; repeated `open` stays quiet until `closed` rearms it. Exact matching ignores case and surrounding whitespace. Unknown values do not silently clear an event. For a JSON state such as `{"door":"open"}`, set **Activity JSON field** to `door`. A configured field is required in every matching mode; unrelated JSON fields do not trigger the scene.

Boolean matching also supports numeric/string 1/0, Yes/No, On/Off and check/cross symbols. With no custom field, primitive values and common `active`/`value` envelopes are supported. **Any** matching is an explicit per-message mode for nonempty event payloads, while explicit inactive values still do not trigger. Prefer Boolean or exact matching for state topics.

## Display and repeat settings

| Setting | Default | Meaning |
| --- | --- | --- |
| Display seconds | 8 | Normal event turn, 2–30 seconds |
| Alarm display seconds | 12 | Heat/water event turn, 2–60 seconds |
| Per-event cooldown seconds | 3 | Per-event repeat suppression; 0 disables it |
| Pending event lifetime seconds | 30 | Expiry for events waiting to be shown, 5–300 seconds |
| Show event labels | Off | Fixed short labels alongside compact artwork |
| Wake display for events | Off | If enabled, request display power on when an event starts |

At most one pending event of each type is kept. Multiple types can queue, up to eleven. Heat/water have first priority when the next scene is selected, then doorbell, then the other events in arrival order. An incoming event does not claim to interrupt an already visible scene or a firmware notification. Queued events expire rather than replaying old activity indefinitely.

Select acknowledges the event and clears this app's queue. Left/right keep their normal firmware navigation. The app does not change brightness, sound, saved device settings or global rotation-pause settings. If you enable **Wake display**, it turns display power on and does not automatically turn it off afterward.

**Keep the script enabled.** Disabling it in the AWTRIX UI stops its MQTT callbacks, so no event can wake it. Idle skipping is handled by the script itself.

**Use retain off for event topics.** The scripting callback exposes only topic and payload, without a retained-message flag. A retained old event can therefore look like a new event after reconnect/restart. Cooldown and in-memory IDs do not guarantee protection across a restart. For retained state inputs, use edge mode with appropriate active/inactive publishing, and expect the first active state after a fresh start to be an activation.

## Previews, source and verification

[Gallery](gallery-contact-sheet.png), [staged event showcase](eventtrigger-showcase.gif), [individual animations](animations/), and [screenshots](screenshots/).

The artwork uses an original, cohesive miniature-world style: midnight backgrounds, warm cream highlights, teal metalwork, brass accents and shaded sprites. All 52 x 16 pixels form the full-panel composition. Optional labels use a separately composed 26-pixel scene, a two-pixel gutter, and the native font on the right; sprites retain their proportions. Neutral metal greys use equal RGB channels; the blue backgrounds and teal mailbox are intentional colors.

Each four-second animation loop has its own action and resting beat. Mail arrives through the opening and disappears behind its lip; pickup reverses the direction toward the waiting person. The garage opens and pauses to show the car. Appliance scenes use the same shaded miniature-room composition: the dishwasher folds open, the air fryer slides out its basket, and laundry moves from the open washer/dryer toward a basket or towel stack. Each action settles by three seconds; only small highlights continue until the four-second loop restarts. Compact scenes keep the opening action and appliance contents at native proportions. The rework takes visual cues from the [featured Hub gallery](https://awtrix.de/scripts/all?sort=picked), including the readable silhouettes and miniature scenes in [Super Alarm Clock](https://awtrix.de/script/ybNQ4zV5qxfS); its artwork and code are original rather than copied Hub assets.

All media are **simulations from the actual generated script's Berry drawing calls**, with sample MQTT events and the official upstream font. They are not recordings of a physical TC002. The showcase stages the eleven examples in sequence; the real app does not automatically cycle through events while idle. Labelled variants let you compare the optional presentation.

Run the full repository build from the project root:

```powershell
python tools/build.py --berry $env:BERRY
```

For just this app, from `EventTrigger/`:

```powershell
python build_eventtrigger.py
& $env:BERRY tools/test_eventtrigger.be
python tools/verify.py
```

`event_core.be.inc` and `event_graphics.be.inc` are the source of truth; `EventTrigger.ax` is generated. The [implementation contract](SPEC.md) documents the event IDs and queue boundaries. Tests use a 32-bit/single-precision Berry 1.1 VM with mocked display/MQTT/rotation APIs. Artwork checks sweep both layouts every 25 ms, validate clipping and label separation, and verify deterministic loop timing. Horizontal sprite runs reduce native drawing calls; the current tests observe a peak of 150 calls per frame. This is an offline call count, not a hardware frame-rate guarantee. Offline tests and media validation do not prove physical TC002 timing, firmware resource budgets, Homey Flow wiring or real MQTT delivery. No production dependencies or existing app migrations are introduced.

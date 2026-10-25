# Event trigger: implementation contract

One standalone generated Berry app named **Event trigger**, installable as `EventTrigger.ax`, for the TC002's 52 x 16 display. Current project behavior and existing apps must remain unchanged.

## Stable scene indices and event names

0. `motion`: shaded walking visitor in front of lit houses, camera LED and fading footsteps.
1. `mail_received`: envelope arrives through the mailbox opening, disappears behind its lip, door closes and flag rises.
2. `mail_collected`: envelope is picked up from a mailbox; distinguish from arrival.
3. `heat`: shaded flames, rising embers, thermometer and red warning accents.
4. `water`: steel pipe, falling drops, shaded blue droplet and moving water.
5. `doorbell`: warm porch and oversized shaded brass bell with outward ringing arcs.
6. `garage`: sectional garage door rises, pauses open and reveals a red car/headlights.

Graphics are procedural elapsed-time animation, no external icons/downloads. Full panel by default. Optional labels use compact artwork on the left and two short fixed labels on the right. No incoming text is drawn directly. No sound by default or required sound assets.

Artwork uses original palette-indexed sprites, batched into horizontal native fill calls. Full-width composition uses 52 pixels; compact mode is independently composed at 26 pixels without horizontal scaling. The artwork clips sprites during entrance/exit and reserves the 26..27 gutter for labels beginning at x=28. Four-second deterministic loops are checked at every 25 ms phase, including the mailbox masking and the eased garage shutter.

## Files and interface

- `event_graphics.be.inc` defines `class EventArtwork`, method `paint(scene, elapsed_ms, labels)`. It clears the panel and draws a complete frame. Scene -1 means a quiet idle/manual-preview frame. It uses only documented `clear`, `font`, `text`, `pixel`, `line`, `rect_fill`, optionally `rect`, and integer/real math. No state, MQTT, rotation or time APIs inside the artwork; elapsed is supplied.
- `event_core.be.inc` declares the metadata/config header and imports, then `class EventTrigger : EventArtwork`. It implements input, bounded queue, lifecycle and `draw()` calling `self.paint(...)`.
- `build_eventtrigger.py` concatenates header/core imports, artwork class, core class and `return EventTrigger()` into `EventTrigger.ax` reproducibly. It does not alter existing app sources.
- `tools/test_eventtrigger.be` has a mocked AWTRIX environment, behavior tests and bounds checks. Its reusable prefix ends immediately before `var app = new_app({})`. `new_app(settings)` compiles `EventTrigger.ax` relative to the current directory, resets clock/mocks, and calls setup. `clock_ms` is test time. Drawing calls use arrays `text/pixel/line/fill/rect`, as in the shared renderer.

## Settings and MQTT

- `topic` text default `homey/events/+`: a single MQTT filter. Auto routing recognizes the last topic level using the seven names above. No assumed real device topics.
- `event_mode` select `auto` plus the seven event names: fixed mode allows arbitrary existing topics and separate installed copies of the same app.
- `trigger_mode` select `pulse,edge`, default `pulse`. Pulse reacts to each valid active message, subject to cooldown. Edge triggers only inactive-to-active transitions; valid inactive readings rearm it.
- `payload_field` text default empty: optional top-level field for activity; otherwise accept primitive or `{value:...}` or `{active:...}`. JSON `{event:NAME, active:true}` routes explicitly in auto mode. A recognized plain event-name string is also an active pulse in auto mode. An explicit invalid `event` field is rejected, never guessed from the topic.
- `match_mode` select `boolean,exact,any`, default `boolean`. Boolean accepts true/false, 1/0, yes/no, on/off, check/cross glyphs. Exact matches trimmed case-insensitive `active_value` (default `true`) and `inactive_value` (default `false`); unknown values are ignored, never clear. Any is explicitly event-per-message, excluding empty/malformed payloads and explicit inactive Boolean/active:false.
- `display_seconds` default 8 (2..30), `alarm_seconds` default 12 (2..60), `cooldown_seconds` default 3 (0..60), `queue_seconds` default 30 (5..300).
- `show_labels` default false. `wake_display` default false, optionally `display.power(true)` once on starting an event. Do not alter brightness, saved settings, sound or global rotation pause.
- Input is bounded (e.g. 512 bytes); optional JSON string `id` max 64 bytes deduplicated in a bounded 16-entry in-memory recent-ID cache, scoped by event name. No persistence/flash writes per event. Invalid JSON, unknown names, missing activity, invalid types do not create an event.
- Recommend QoS 1 with **retain false** for event Flows. Script callback has no retained flag: cannot distinguish a retained replay from a new no-ID event after restarting. Document that boundary honestly. State topics should use edge mode and publish both active and inactive values.

## Queue and display lifecycle

- One pending entry per scene, at most seven. Coalesce repeated pending pulses, expire pending events after `queue_seconds` using wrap-safe elapsed time. Heat/water priority 3; doorbell 2; others 1; FIFO timestamps within equal priority.
- Each accepted pulse obeys per-scene cooldown and optional ID dedup. Edge state is rearmed only by a valid inactive value. A valid inactive message removes pending events of that scene and ends a matching current scene; it never clears unrelated events.
- `should_show()` is false when there is no current or pending event. Always keep the app enabled so MQTT works while idle.
- Select the highest-priority pending event before `rotation.show()`; request once per event while hidden. `on_show()` marks it shown and starts its elapsed animation clock. Handle synchronous or deferred on_show safely. A false show result drops that request and logs once; no unbounded retry loop.
- `duration()` returns normal/alarm dwell; no rotation.pause/resume. An event arriving while a scene is displayed queues for a subsequent turn. Higher priority applies when selecting the next scene; it does not claim to preempt an already visible scene or firmware notification.
- `on_hide()` consumes the displayed event, clears its current state, and allows a later loop to show pending events. If shown manually while idle, show a quiet idle frame briefly, not a phantom event.
- Select acknowledges and clears the local event queue, then `rotation.next()`. Left/right remain firmware navigation. Events expire if they could not be displayed; no stale event is replayed later indefinitely.

## Verification and boundaries

Use the existing 32-bit/single-precision Berry 1.1 executable, real parsing and comprehensive mocks. Cover every routing/matching mode, both pulse/edge, false/rearm, malformed/oversized data, dedup/cooldown, queue bounds, priority/FIFO, expiry, clock wrap, synchronous/deferred rotation.show, rejection, acknowledgement and full drawing bounds. Capture all seven scenes and optional labels through actual generated app drawing calls. Shared Python pipeline renders with the official BDF, validates PNG/GIF pixels/timing, provenance and ZIP contents.

No broker publishes, clock installation, Homey Flow edits, Git commits/pushes or Hub publishing are authorized by this feature request. Other work may exist: preserve edits outside assigned files. Tests and simulations do not prove physical TC002 or MQTT delivery behavior.

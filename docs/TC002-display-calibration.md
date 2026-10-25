# TC002 display colors: discussion and trial settings

The browser preview and script-generated PNG/GIF files show RGB drawing values. AWTRIX's display saturation, gamma, correction and tint apply to LED output and are not represented in the web preview. See the [AWTRIX display color reference](https://blueforcer.github.io/awtrix-ng/tc002/reference/visuals/#display-colors).

During the October 2026 comparison, a photograph showed the ash tray's dark interior appearing much brighter than the preview, obscuring the ash detail. The camera's exposure and white balance can contribute. This was an observation, not a measurement establishing a firmware or panel fault.

The final suggested **trial baseline**, not an established calibration, was:

| Setting | Trial value |
| --- | --- |
| Saturation | 100% |
| Gamma | 2.4; compare 2.2 if dark detail disappears, or 2.8 if still washed out |
| Brightness | Temporarily 60 / 255 for comparison |
| Color correction | `#FFFFFF` initially |
| Color tint | `#FFFFFF` |

Higher gamma darkens dark/mid tones. An earlier suggestion of gamma 1.5 would brighten those shades and was withdrawn for this washed-out example.

Once contrast is restored, a remaining blue cast can be tested with correction `#FFF0D0`: **RGB 255, 240, 208**, or **BRG 208, 255, 240**. Keep tint white while adjusting correction. If too yellow, `#FFF0E0` raises blue to 224. These controls affect the whole display; assess the actual TC002 and neutral test colors rather than matching a camera photograph exactly.

Some app artwork intentionally uses blue-grey RGB values. No runtime palette or physical-device setting was changed during consolidation, and no final hardware calibration has been verified.

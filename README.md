# audio-switch

Switch your **default audio output** with a single key — and actually **move every
running app** to the new device — then get a fast, slick **AMD-style overlay** showing
where the sound went. Made to be bound to a **Stream Deck** (or any hotkey), but works
from the command line too.

Windows can change the default output, but it leaves apps that are **already playing**
stuck on the old device. This fixes that: it flips the default *and* re-routes every
running app in one go.

---

## Features

- One key per device (e.g. key 1 -> monitor, key 2 -> headset).
- Moves **already-running** apps to the new device (the part Windows skips).
- Animated overlay: dark panel slides in -> a thin red bar "writes" the label -> short
  hold -> red bars sweep across -> the whole thing wipes away. Fast and unobtrusive.
- Choose the **corner**; adapts to **any resolution / DPI** (ultrawide 3440x1440 included).
- Optional **dynamic colours** sampled from the screen, instead of AMD red.
- **Instant mode**: an optional resident helper so a key press doesn't pay PowerShell /
  WPF startup.
- **Zero-config installer** that downloads the dependency and lists your devices.
- No admin rights.

## Files

| File | Role |
|------|------|
| `setup.cmd` / `setup.ps1` | One-shot configurator (download svcl, pick devices, write config, make launchers). |
| `audio-switch.ps1` | One-shot switch + overlay (normal mode). |
| `audio-switch.core.ps1` | Shared library used by both entry scripts. |
| `audio-switch-daemon.ps1` | Resident helper for **instant mode**. |
| `trigger-1.cmd` / `trigger-2.cmd` | Tiny, fast triggers for instant mode (Stream Deck points here). |
| `daemon-start.vbs` / `install-daemon.cmd` | Start the daemon hidden / add it to startup. |
| `<Label>.vbs` (e.g. `Monitor.vbs`) | Generated launchers for **normal mode**. |
| `audio-switch.config.json` | Your settings (created by setup; example provided). |

## Requirements

- Windows 10 or 11, Windows PowerShell (built in).
- [`svcl.exe`](https://www.nirsoft.net/utils/sound_volume_command_line.html) (NirSoft) —
  **downloaded automatically** by the installer. Not bundled here (own license).

## Quick start

1. Put this folder somewhere permanent, e.g. `C:\Tools\audio-switch\`.
2. Double-click **`setup.cmd`** and follow the prompts (devices, labels, corner,
   colours, and optionally enable instant mode).
3. In Stream Deck add two buttons, action **System -> Open**:
   - **Normal mode:** point them at the generated `<Label>.vbs` files.
   - **Instant mode:** point them at `trigger-1.cmd` and `trigger-2.cmd`.

## Manual usage

```powershell
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 1      # key 1
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 2      # key 2
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 list   # devices + active apps
```

## Two modes

**Normal mode** — each press launches `audio-switch.ps1` (via a `.vbs` so no console
flashes). Simplest; nothing runs in the background.

**Instant mode** — a small resident process (`audio-switch-daemon.ps1`) keeps PowerShell
and the overlay **warmed up** and watches a tiny `.trigger` file. The Stream Deck key
runs `trigger-N.cmd` (a two-line batch file that writes the file), which the daemon picks
up in ~40 ms. This removes the biggest delay: per-press PowerShell/WPF startup. Enable it
in `setup.cmd`, or run `install-daemon.cmd` (adds it to startup and launches it).

## Configuration

Settings live in `audio-switch.config.json` (see `audio-switch.config.example.json`).
Missing file => built-in defaults.

| Field | Meaning |
|-------|---------|
| `slots.<n>.label` | Text shown in the overlay (displayed uppercase). |
| `slots.<n>.icon` | `monitor`, `headset`, or `speaker`. |
| `slots.<n>.id` | Exact device id (`Command-Line Friendly ID`). Tried first. |
| `slots.<n>.fragment` | Optional fuzzy fallback (a unique part of the name). |
| `slots.<n>.name` | Device name — fallback match and overlay subtitle. |
| `ui.corner` | `TopRight` (default), `TopLeft`, `BottomRight`, `BottomLeft`. |
| `ui.gapX` / `ui.gapY` | Margins from the corner, in pixels. |
| `ui.closeMs` | How long the overlay stays before it goes away (ms). |
| `ui.dynamicColors` | `true` to sample screen colours; `false` keeps AMD red. |

Matching tries `id` -> `fragment` -> `name`, so a changed device id still resolves by name.

### Dynamic colours

With `dynamicColors: true`, before each overlay the area near the chosen corner is
sampled, the most vibrant hue is picked, and the accent + sweep bars use it (the panel
stays dark). If the area is nearly grey it falls back to AMD red. Cost is a few ms.

### Tweaking the animation

Colours, speeds, and the hold are in the `<Storyboard>` in `audio-switch.core.ps1`.
Reds: `#FF564D` / `#ED1C24` / `#A10E13`; panel `#202024`->`#141418`. The ~1.25 s hold is
the gap between the end of the "write" (~0.52 s) and the start of the exit bars (~1.77 s).

## Performance / latency

What the switch actually does: set the default **first** (one call), then move running
apps **in parallel** (non-blocking), then draw the overlay — so audio never waits on the
animation, and many apps don't serialise.

Two real costs remain:

1. **Per-press PowerShell + WPF startup** (normal mode). This is usually what feels slow.
   **Instant mode** removes it by keeping everything resident.
2. **`svcl.exe` process spawns** — each `svcl` call is its own process. The default flip
   is one call; enumeration is one; app moves are fired in parallel. With many apps this
   is the remaining floor in either mode.

The log (`audio-switch.log`) records elapsed milliseconds per stage and a final
`switch issued in ...ms`, so you can see exactly where time goes.

## Multi-monitor / resolution

Positioning is derived from the Windows work area (in device-independent pixels), so it
**scales to any resolution and DPI** — there are no hardcoded pixel coordinates — and the
window is clamped to stay fully on-screen. The overlay appears on the **primary** monitor's
chosen corner. (Per-monitor / "follow the cursor" placement isn't done yet — open an issue
if you want it.)

## Troubleshooting

- **Nothing happens** — open `audio-switch.log`: resolved device, apps moved, timings, errors.
- **"svcl.exe is missing"** — run `setup.cmd`, or drop `svcl.exe` next to the scripts.
- **Instant mode not reacting** — check a PowerShell process is running
  (`audio-switch-daemon.ps1`); re-run `install-daemon.cmd`; confirm the keys call
  `trigger-*.cmd`. The daemon writes "daemon: ready" to the log on start.
- **A stubborn app won't follow** — games in *exclusive* mode (or apps that open the audio
  stream once) only re-route on their next sound. Switch before starting the sound.

## Credits & license

- Uses [NirSoft SoundVolumeCommandLine](https://www.nirsoft.net/utils/sound_volume_command_line.html)
  (`svcl.exe`) by Nir Sofer — freeware, fetched at setup time, not redistributed here.
- This project: [MIT License](LICENSE).

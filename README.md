# audio-switch

Switch your **default audio output** with a single key — and actually **move every
running app** to the new device — then get a fast, slick **AMD-style overlay** telling
you where the sound went. Built to be bound to a **Stream Deck** (or any hotkey), but
works fine from the command line too.

Windows can change the default output, but it leaves apps that are **already playing**
stuck on the old device. This tool fixes that: it flips the default *and* re-routes
each running app in one go.

---

## Features

- One key per device (e.g. key 1 -> monitor, key 2 -> headset).
- Moves **already-running** apps to the new device (the part Windows skips).
- Animated overlay: dark panel slides in -> a thin red bar "writes" the label -> short
  hold -> red bars sweep across and the whole thing wipes away. Fast and unobtrusive.
- Pick the **corner** (top-right by default) and it adapts to **any resolution / DPI**
  (tested target: 3440x1440 ultrawide).
- **Zero-config installer**: `setup.cmd` downloads the dependency and lets you pick
  your devices from a list.
- No admin rights required.

## Requirements

- Windows 10 or 11.
- Windows PowerShell (built in — nothing to install).
- [`svcl.exe`](https://www.nirsoft.net/utils/sound_volume_command_line.html) (NirSoft
  SoundVolumeCommandLine) — **downloaded automatically** by the installer. It is *not*
  bundled in this repo (it has its own freeware license).

## Quick start

1. Download this folder (or `git clone` it) somewhere permanent, e.g.
   `C:\Tools\audio-switch\`.
2. Double-click **`setup.cmd`**. It will:
   - download `svcl.exe` if needed,
   - list your output devices,
   - let you assign two of them to keys 1 and 2 (label + icon),
   - choose the overlay corner,
   - write the config and generate the Stream Deck launchers.
3. In Stream Deck, add two buttons with the action **System -> Open**, pointing at the
   two generated `.vbs` files (the installer prints their names).

That's it. Tap a key — the sound switches and the overlay appears.

## Manual usage

```powershell
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 1      # key 1
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 2      # key 2
powershell -ExecutionPolicy Bypass -File .\audio-switch.ps1 list   # show devices + active apps
```

The `.vbs` launchers run the same thing **with no console window flashing**, which is
what you want for a Stream Deck button.

## Configuration

Settings live in `audio-switch.config.json` (created by the installer; see
`audio-switch.config.example.json` for the shape). If the file is missing, the script
falls back to built-in defaults.

| Field | Meaning |
|-------|---------|
| `slots.<n>.label` | Text shown in the overlay (displayed uppercase). |
| `slots.<n>.icon` | `monitor`, `headset`, or `speaker`. |
| `slots.<n>.id` | Exact device id (`Command-Line Friendly ID`). Used first — most reliable. |
| `slots.<n>.fragment` | Optional fuzzy fallback (a unique part of the device name). |
| `slots.<n>.name` | Device display name — fallback match and overlay subtitle source. |
| `ui.corner` | `TopRight` (default), `TopLeft`, `BottomRight`, `BottomLeft`. |
| `ui.gapX` / `ui.gapY` | Margins from the corner, in pixels. |
| `ui.closeMs` | How long the overlay window stays before closing (ms). |

Device matching tries `id` -> `fragment` -> `name`, so even if a device id changes
after a reconnection, the name still resolves it.

### Tweaking the animation

Colours, speeds, and the hold duration are in the `<Storyboard>` inside the
`Show-Toast` function in `audio-switch.ps1`. The reds are `#FF564D` (light),
`#ED1C24` (AMD red), `#A10E13` (dark); the panel is the `#202024`->`#141418` gradient.
The ~1.25 s hold is the gap between the end of the "write" (~0.52 s) and the start of
the exit bars (~1.77 s).

## Performance / latency

The actual switch is just a couple of `svcl` calls and is effectively instant. The
device default is set **first** (one call), then running apps are moved, and only
**after that** does the overlay (WPF) load — so audio never waits on the animation.
Apps already on the target are skipped.

If a key press still feels slightly delayed, the cost is almost always **PowerShell
process startup**, not this script. The launchers already use `-NoProfile` to minimise
it. For *truly* instant switching you'd avoid spawning a process per press — e.g. keep
a resident listener or trigger the switch from an always-running AutoHotkey script.
The log (`audio-switch.log`) records elapsed milliseconds at each stage and a final
`SWITCH DONE in ...ms`, so you can see exactly where the time goes.

## How it works

`svcl /SetDefault` changes the default output, but Windows does **not** move streams
that are already open — that's why apps stayed on the old device. The script enumerates
every active audio stream (one `/scomma` call), sets the default, then calls
`svcl /SetAppDefault` per process id for each app not already on the target. Everything
moves together, then the overlay is drawn.

## Troubleshooting

- **Nothing happens** — open `audio-switch.log` (next to the script): it logs the
  resolved device, how many apps moved, timings, and any error.
- **"svcl.exe is missing"** — run `setup.cmd`, or drop `svcl.exe` next to the script.
- **"no output device matched"** — re-run `setup.cmd` and reselect the device.
- **A stubborn app won't follow** — some apps (games in *exclusive* mode, or apps that
  open the audio stream only once) only re-route on their next sound. Switch before
  starting the sound, or toggle the audio in that app.
- **Overlay on the wrong monitor** — it appears on the primary monitor's chosen corner.

## Credits & license

- Uses [NirSoft SoundVolumeCommandLine](https://www.nirsoft.net/utils/sound_volume_command_line.html)
  (`svcl.exe`) by Nir Sofer — freeware, fetched at setup time, not redistributed here.
- This project is released under the [MIT License](LICENSE).

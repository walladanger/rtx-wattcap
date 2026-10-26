# WATTCAP: code summary

`gpu-power-limit.cmd` is one ASCII file, 1,712 lines with Windows line endings, in three layers stacked top to bottom:

1. **Batch** runs the menu and does the actual power-limit work.
2. **PowerShell** starts the intro and makes the shortcut.
3. **C#** draws the animation.

## File layout

| Lines | Section | Language |
|---|---|---|
| 1–221 | Menu, install/apply/reset, banner | Batch |
| 222 | `<#WATTCAP#>` marker | — |
| 223–311 | `Invoke-WattCap` launcher | PowerShell |
| 312–1118 | Renderer source, kept as a text block | C# |
| 1119–1711 | Gauge icon, base64-encoded | data |
| 1712 | `Invoke-WattCap` (the call that starts it) | PowerShell |

Batch only runs code it jumps to, and everything after the marker sits past its last exit, so it never reaches it.

---

## Layer 1: batch (the actual tool)

- **Settings:** `WATTS=310`, `MATCH=3090`, `INTRO=1`, `INTRO_STYLE=invaders`.
- **Admin rights:** `net session` checks for admin. If it isn't admin, it relaunches itself elevated through PowerShell's `Start-Process -Verb RunAs`.
- **Command-line modes:** `apply`, `install`, `reset`, `shortcut`. Double-clicking with no argument gives the intro and then the menu.
- **`:apply`** is what runs at boot:
  - finds `nvidia-smi.exe`;
  - waits up to 60 s for the driver;
  - lists the GPUs;
  - runs `nvidia-smi -i N -pl 310` on every card whose name contains "3090";
  - writes a log to `C:\ProgramData\GPUPowerLimit\last-run.log`.
- **`:install`**:
  - copies the script to ProgramData;
  - creates the scheduled task (at startup, as SYSTEM, highest privileges, 30 s delay);
  - makes the shortcut;
  - applies the limit right away.
- **`:reset`**:
  - reads each card's `power.default_limit` and sets it back to that;
  - deletes the task;
  - keeps the ProgramData copy so the shortcut still works.
- **Menu:**
  - gets the escape character with `echo prompt $E | cmd` so `echo` can print colours;
  - draws the WATTCAP banner (five generated `echo` lines);
  - shows whether the boot task is installed;
  - uses `choice /c 1234IPQ` for the options.
- **`:ps`** starts PowerShell. It reads this same file (`%~f0`), finds the last `<#WATTCAP#>`, and runs everything after it. The marker is written as `'<#'+'WATTCAP#>'` in that command, so the command can't match itself.

---

## Layer 2: PowerShell (`Invoke-WattCap`)

**Shortcut mode**
- Decodes the base64 `.ico` into ProgramData.
- Creates `.lnk` shortcuts on the Desktop and in the all-users Start Menu with `WScript.Shell`.
- Sets byte `0x15 |= 0x20` in each `.lnk`, which is Windows' "Run as administrator" flag. That makes it open elevated directly and keep the icon.

**Intro mode**
- Asks `nvidia-smi` for the name, current limit, stock limit and temperature of each card.
- Builds the ticker text and picks a random seed.
- Compiles or loads the renderer (see below).
- Passes in the settings and calls `[WattCap.Intro]::Run()`.

**Compile cache**
- Takes a SHA-1 hash of the C# source and names the DLL `wattcap-intro-<hash>.dll`.
- Compiles it with `Add-Type -OutputAssembly` the first time (about 2–3 s).
- Later launches load the DLL directly (about 0.24 s).
- If the source changes, the hash changes and it recompiles.
- If writing the DLL fails, it compiles in memory instead.

---

## Layer 3: C# renderer (namespace `WattCap`)

It's limited to C# 5 and .NET Framework APIs, because that's what Windows PowerShell 5.1's `Add-Type` compiles.

### How drawing and resizing work

- **Virtual canvas:** the scenes draw into a fixed 80×45 grid of colour numbers (`byte[] vb`). 0 means transparent; the values are the terminal's 256 colours.
- **Screen buffer:** each console cell holds two pixels stacked vertically using the `▀` character (top half coloured by the text colour, bottom half by the background). That makes the screen buffer `cols × (rows-1)*2` pixels, with the bottom row left for the ticker.
- **Scaling:** `scale = min(screenW/80, screenH/45)`, centred in the window. `Resize()` builds lookup tables that map each screen pixel to a canvas pixel (nearest pixel, no smoothing).
- **Live resize:** every frame reads `Console.WindowWidth/Height`. When the size changes, it rebuilds those tables, clears the screen and redraws everything. That's why everything scales together.
- **Minimal redraw:** `Emit()` remembers what it drew last frame, one value per cell (the top colour times 256 plus the bottom colour). It only rewrites cells that changed, and only sends cursor moves and colour codes when they're actually needed. A frame takes under 1 ms to compute.

### Draw order each frame

1. The scene draws its sprites into the canvas.
2. The scene fills the full screen with its background (stars or plasma), so there are no empty bars at the sides.
3. The scaled canvas is laid on top.
4. At the end, a random-pattern dissolve.

### `Run()`

- Switches on the console's colour-code support (a Windows `SetConsoleMode` call).
- Sets UTF-8 output.
- Uses the alternate screen buffer so your console comes back afterwards.
- Hides the cursor.
- Runs at about 30 fps, timed by the clock.
- Stops when any key is pressed (Ctrl+C counts as a key).
- Restores all console settings in a `finally` block.

### Shared helpers

- 3×5 and 5×7 pixel fonts.
- `Blit` draws sprites from strings, where each character stands for a colour: body, accent, white eye, dark pupil, gold.
- `DrawLogo` draws the logo with shadow, shine and per-column wave offsets.
- A bounce easing curve for the logo drop.
- A particle system with gravity and fade for explosions and fireworks.

### `Invaders` scene

- **The robots:** 5 designs × 3 colour schemes = 15 different bots, each with two animation frames. They march side to side, bounce off the edge of whichever columns are still alive, and speed up as their numbers drop.
- **Enemy fire:** bombs drop from the lowest bot in a random column. A boss saucer crosses at t = 3 s.
- **Player autopilot:**
  - aims at the lowest bot in the nearest column, allowing for the march direction;
  - leads its shots on the boss;
  - sidesteps incoming bombs;
  - has at most 2 bullets in flight, with a 0.2 s cooldown.
- **Hit detection:** simple bounding-box checks. A hit flashes the bot white and bursts particles.
- **HUD:** the power readout is `Stock − (Stock − Watts) × kills / 15`, so it counts down to exactly 310 W.
- **Timing and ending:** if any bots are still alive at 9.5 s, they self-destruct in a chain so the intro always finishes. Once they're cleared, the logo bounces in, the subtitle types out, and fireworks go off. The whole thing ends about 4.4 s after the last bot.

### `Plasma` scene

- The field is calculated per screen pixel in canvas coordinates, so it scales with the window too. It's four sine waves (horizontal, vertical, diagonal, and circular around a random centre) plus a Gaussian hotspot drifting on a figure-of-eight path, with the edges darkened.
- The result is split into 9 colour levels. Anything at or above `Watts/Stock` becomes the amber "throttled" plateau.
- It has the same logo slide, wave, ripple and dimmed panel as the original.

---

## Assets

- **Icon:** drawn in Python with the imaging library PIL at 1024 px as a gauge arc with a greyed-out red zone past the cap, needle, hub and lightning bolt. It's saved as a multi-size `.ico` (16–256 px), 44 KB, and embedded as base64.
- **Banner:** "WATT" and "CAP" rendered separately with the pyfiglet `small` font so the white/amber colour split lands cleanly between them. The gauge art is hand-drawn. The generator escapes characters batch treats as special (`|`, `^`, etc.).

---

## Build and test tooling (not in the shipped file)

- **`build.py`:** stitches the batch part, the banner, the PowerShell, the C# and the icon into the `.cmd`. It checks the result is pure ASCII, that the marker appears exactly once, and converts line endings to Windows style.
- **Compile check:** Mono's `mcs -langversion:5` confirms the C# compiles as C# 5.
- **PowerShell 7 on Linux:**
  - checked the payload parses with zero errors;
  - ran it end to end from inside the `.cmd`;
  - confirmed the icon survives the base64 round trip byte-for-byte;
  - confirmed every `goto`/`call` target label exists.
- **Frame dumps and previews:** a `Dump()` hook simulates the run at 30 fps and writes the screen output at chosen times and window sizes. A small Python converter turned those into the PNG and GIF previews.

> **Not yet verified on real Windows.** The pieces most likely to behave differently there are the console handling, `WScript.Shell` and `schtasks`.

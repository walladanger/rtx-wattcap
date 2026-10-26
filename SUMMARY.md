# WATTCAP: RTX 3090 power limiter (project summary)

A plain-language account of this project, from the first request to the final state. Nothing from the chat is left out: every request, decision, version, test and open item is here. The exact word-for-word conversation, including every line of code as it was written, is in `transcript/transcript.md`.

- **Owner:** Warwick
- **Chat dates:** 24–25 Sept 2026 (US Eastern)
- **Status:** delivered (v4). It has not been run on real Windows yet (see "Not yet verified").

---

## 1. What it is

**WATTCAP** is one Windows file, `gpu-power-limit.cmd`. It:

1. **Sets every RTX 3090 to 310 W on every boot.** A scheduled task runs as SYSTEM at startup, with a 30-second delay.
2. **Can reset the cards to stock.** It reads each card's own default limit, sets it back and removes the boot task.
3. **Shows a live status menu** with a colour WATTCAP banner.
4. **Plays an animated intro before the menu.** This is an original pixel-art invaders game, or a plasma field. It rescales live when you resize or maximise the window.
5. **Creates desktop and Start-menu shortcuts** with a gauge icon. They open elevated.

Settings are at the top of the file:

| Setting | Default | Meaning |
|---|---|---|
| `WATTS` | `310` | Target power limit per card |
| `MATCH` | `3090` | Only cards whose name contains this are changed |
| `INTRO` | `1` | `0` turns the intro off |
| `INTRO_STYLE` | `invaders` | or `plasma` |

Command-line modes: `install`, `apply` (what the boot task runs), `reset` (also `uninstall`), `shortcut`. Double-clicking with no argument gives the intro and then the menu.

Menu keys: `[1]` install, `[2]` reset to stock, `[3]` show current limits, `[4]` desktop + Start menu shortcut, `[I]` replay invaders intro, `[P]` plasma intro, `[Q]` quit.

---

## 2. How the project unfolded

### Request 1: the basic script (24 Sept, 22:01)
> "Create me a quick script that sets my Nvidia 3090 to 310w for each card. It runs each windows 11 boot"

**v1** (`history/v1-first-script.cmd`) was a single self-installing `.cmd`. Double-click it once and it:
- relaunches itself elevated through PowerShell's `Start-Process -Verb RunAs` (`net session` is the admin check);
- copies itself to `%ProgramData%\GPUPowerLimit\`;
- creates the scheduled task `GPU Power Limit (3090)`: `/SC ONSTART /DELAY 0000:30 /RU SYSTEM /RL HIGHEST`, running `"...\gpu-power-limit.cmd" apply`;
- applies the limit immediately.

`apply`:
- finds `nvidia-smi.exe` in `System32`, or failing that `Program Files\NVIDIA Corporation\NVSMI`;
- waits up to 60 s for the driver to answer (12 tries, 5 s apart);
- lists the GPUs and runs `nvidia-smi -i N -pl 310` on each card whose name contains "3090";
- logs everything to `%ProgramData%\GPUPowerLimit\last-run.log`, ending with a table of current, min and max limits.

`uninstall` removed the task and the installed copy.

### Request 1b: reset option (typed while v1 was being built)
> "also need an option to rest to stock"

**v2** (`history/v2-with-reset.cmd`) added:
- **A menu:** `[1]` install, `[2]` reset to stock, `[3]` show current limits, `[Q]` quit.
- **Reset:** reads each matching card's `power.default_limit`, sets it back with `nvidia-smi -pl`, deletes the boot task, and at that point also deleted the ProgramData folder.
- **Show:** draw, limit, default, min and max per card, plus whether the boot task is installed.

Notes given with v2:
- **Changing the wattage:** edit `WATTS` and install again.
- **Range:** 310 W is within range for every 3090. Stock is 350 W on the Founders Edition; many partner cards go higher.
- **Tuning tools:** MSI Afterburner, EVGA Precision and similar tools that apply a power limit at startup can override this. Whichever runs last wins.
- **Testing:** not tested on Windows yet.

### Request 2: animated intro (24 Sept, 22:11)
> "can you include a /algorithmic-art within the command shell, a rolling logo scrolling or animation or both. Have this run before the menu"

The algorithmic-art skill was loaded. Its p5.js/HTML template doesn't apply to a console, so its approach was adapted: a named algorithmic idea, seeded randomness and careful tuning, rendered in the console. The chat was interrupted mid-build and resumed.

**v3** (`history/v3-plasma-intro.cmd`; intro source `history/v3-intro-plasma.ps1`) was the **"Shaved Peaks"** intro, written in PowerShell:
- **The field:** a random-seed plasma field (sums of sines, a circular ripple and a drifting hotspot).
- **The concept:** every peak above **310/350 of full brightness** is cut off flat and drawn as an amber "throttle plateau". The power cap made visible.
- **Look:**
  - three seeded colour schemes: emerald, glacier and orchid;
  - drawn with `. : ░ ▒ ▓ █` characters, the ASCII texture;
  - the edges are darkened.
- **Logo:** "RTX 3090" in a double-width block font. It slides in from the right with a rolling wave, has a drop shadow and a moving shine, and gets a ripple at about 4 s.
- **Subtitle:** "P O W E R   L I M I T  //  3 1 0 W" types out.
- **Ticker:** a bottom-row scroller with live nvidia-smi data for each card (name, current and stock limit, temperature), the target, the seed and "any key skips".
- **Timing:** about 7 s, fades in and out, any key or Ctrl+C skips.
- **Console handling:** uses the alternate screen buffer so the console is restored afterwards, hides the cursor, and switches to UTF-8 output.
- **VT fallback:** if `$Host.UI.SupportsVirtualTerminal` is false, it turns VT on through a Windows `SetConsoleMode` call.
- **Single file:** the PowerShell sits after a `<#INTRO#>` marker at the end of the `.cmd`. The batch side reads its own file and runs everything after the last marker, which is written as `'<#'+'INTRO#>'` so the command can't match itself.
- **Menu:** gained `[I]` replay intro. `INTRO=0` disables it.
- **Line-ending fix:** v1 and v2 had Linux (LF) line endings, which can break batch `goto`/`call`. From v3 on, every file has Windows (CRLF) line endings.

Bugs found and fixed while testing v3 in PowerShell 7:
- **Variable clashes:** PowerShell variable names ignore case, so `$e` and `$E`, and `$sx` and `$SX`, were the same variable. They were renamed.
- **Alias clash:** a helper named `R` collided with the built-in `r` alias (Invoke-History). It was renamed to `Rnd`.
- **Speed:** sampling every second column halved the field math. Frames went from about 25–45 ms to about 20 ms in PowerShell 7.

A 12 fps preview GIF was produced (`previews/rtx-intro-preview.gif`).

### Request 3: resizable, invaders intro, logo (24 Sept, 22:43)
> "make the animation keep size with the command window… enlarge it and resize it and the animation scale the same in unison… make a space invaders intro, but all the invaders are different versions of the Claude bot… give the command batch file a logo please. You can decide on the logo"

- **The mascot:** Claude's mascot can't be drawn, as it's a brand character. The invaders are an original squad of robots instead.
- **The genre:** the game is "invaders-style". The original arcade sprites and name are not used.

**v4, final** (`deliverable/gpu-power-limit.cmd`) moved the intro to a **C# renderer**:
- **Compiled on your PC:** PowerShell's `Add-Type` compiles it.
- **Cached:** it's saved as `wattcap-intro-<first 12 hex of SHA-1>.dll` in `%ProgramData%\GPUPowerLimit`. The first launch takes about 2–3 s; later launches about 0.24 s. It recompiles if the source changes, and compiles in memory if the DLL can't be written.
- **Limits:** C# 5 / .NET Framework 4.x, which is what Windows PowerShell 5.1 can compile.

**Resizing:**
- **Canvas and pixels:** everything is drawn on a fixed **80×45** canvas. On screen, each console cell shows two pixels using `▀` (text colour on top, background colour below).
- **Scaling:** the canvas is scaled by `min(width/80, height/45)` using nearest pixel, and centred.
- **Live resize:** every frame reads the window size, and a change triggers a full rebuild and redraw.
- **Minimal redraw:** only changed cells are rewritten, and colour codes are sent only when they change. A frame takes under 1 ms.
- **No empty bars:** the backgrounds (stars or plasma) fill the whole window.
- **Ticker:** the bottom row is the ticker in normal text.
- **Exit:** a random-pattern dissolve.
- **Loop:** about 30 fps, timed by the clock. Any key skips, and all console settings are restored in a `finally` block.

**Invaders scene:**
- **The robots:** 15 unique bots: 5 designs (antenna, visor with a scanning eye, cyclops, grille box, spider) × 3 colour schemes (magenta, cyan, lime). Each has 2 animation frames.
- **Marching:** they march and speed up as their numbers drop.
- **Enemy fire:** bombs drop from the lowest bot in a random column. A red boss saucer crosses at 3 s.
- **Your ship:** a triple-fan graphics card on autopilot. It aims at the lowest bot in the nearest column, leads its shots on the boss, dodges bombs, and fires at most 2 bullets at a time with a 0.2 s cooldown.
- **HUD:** `PWR` counts down from stock to 310 W as bots fall (`Stock − (Stock − Watts) × kills / 15`) and flashes when done. `CAP 310W X2` is shown on the right.
- **Timing and ending:**
  - any stragglers self-destruct in a chain at 9.5 s;
  - after the clear, the "RTX 3090" logo bounces in, "POWER LIMIT" and "310 W X2" type out, and fireworks go off;
  - the scene ends about 4.4 s after the last bot, about 11 s in total.

**Plasma scene:**
- Ported to C#, so it resizes too.
- Same concept, colour schemes, logo slide, wave, ripple and dimmed panel.
- Drawn as solid blocks of colour rather than the v3 ASCII characters.

**Logo, WATTCAP (designed by me as asked):**
- **Icon:** a gauge with a green-to-amber arc. The zone past the cap is dim red and hatched, and the needle stops at the cap. It has an amber hub and a lightning bolt.
  - It was drawn in Python with PIL at 1024 px and saved as a multi-size `.ico` (16–256 px, 44 KB), in `assets/`.
  - It's embedded in the `.cmd` as base64.
- **Shortcut:** `[4]`, or Install, writes the icon and creates **"WattCap RTX Power Limit"** shortcuts on the Desktop and in the all-users Start Menu.
  - They point at the ProgramData copy.
  - Setting byte `0x15 |= 0x20` in each `.lnk` sets "Run as administrator", so it opens elevated and keeps the icon.
- **Menu banner:** a colour ASCII gauge plus a "WATT"+"CAP" wordmark in white and amber, using the pyfiglet `small` font with each word rendered separately for a clean colour split.
  - The menu shows the boot-task status and the target.
  - Colours use the escape character obtained with `echo prompt $E | cmd`.
- **Window title:** `WATTCAP - RTX 3090 power limit`.
- **Reset change:** reset now keeps the ProgramData copy and icon, so the shortcut still works. It removes the task and the log.

**Tests for v4:**
- Mono `mcs -langversion:5` compiled the C# as C# 5.
- PowerShell 7 on Linux extracted the payload from the `.cmd` exactly as the batch side does. It parsed with zero errors, compiled, cached, loaded the type and rendered frames.
- Rendered frames were checked at 120×30, 80×25, 200×55, 120×20 and 150×40.
- The icon's base64 round trip was byte-identical, and every `goto`/`call` target exists.
- A resize-demo GIF shows the window growing from 84×24 to 160×42 mid-run (`previews/wattcap-intro-resize.gif`).

### Question: "did you keep the original intro too?" (24 Sept, 22:58)
The answer was: partly.
- **Kept:** the plasma concept is still there as `[P]`: seed, three colour schemes, amber clipped peaks, logo slide, wave and ripple, shine, panel, subtitle and ticker.
- **Changed:**
  - it's drawn as solid blocks instead of ASCII characters;
  - the logo is a pixel font that scales, not double-width console characters;
  - the subtitle is on two lines;
  - it resizes.
- **Replaced:** the original PowerShell version was replaced, not kept alongside.
- **Offered, not built:** a third style, `[A] ASCII plasma`, using the v3 characters but resizable.

### Requests: code summary, then as markdown (25 Sept, 19:28 / 19:30)
A layer-by-layer code summary was written and delivered as `docs/WATTCAP-code-summary.md`.

---

## 3. How the final file is built (architecture)

| Lines | Section | Language |
|---|---|---|
| 1–221 | Menu, install/apply/reset/show/shortcut, banner | Batch |
| 222 | `<#WATTCAP#>` marker | — |
| 223–311 | `Invoke-WattCap` launcher | PowerShell |
| 312–1118 | Renderer source, kept as a text block | C# |
| 1119–1711 | Gauge icon, base64 | data |
| 1712 | `Invoke-WattCap` call | PowerShell |

- **Batch `:ps` routine:** sets `WC_MODE` (`intro` or `shortcut`) and `WC_STYLE` (`invaders` or `plasma`), then runs PowerShell. PowerShell reads `%~f0`, finds the last `<#WATTCAP#>` and runs everything after it.
- **PowerShell intro mode:**
  - asks nvidia-smi for each card's name, current limit, stock limit and temperature;
  - builds the ticker and picks a random seed;
  - compiles or loads the renderer, sets its settings and calls `[WattCap.Intro]::Run()`.
- **PowerShell shortcut mode:** the icon, the shortcuts and the run-as-admin flag, as described above.
- **C#:**
  - `Intro` holds the resize and draw code, pixel fonts (3×5 and 5×7), sprite drawing, the logo, bounce easing and particles;
  - `Invaders` and `Plasma` are the two scenes;
  - `Dump()` is a test hook that writes frames at chosen times and sizes.

The source parts are in `source/`. `build.py` stitches them into the `.cmd`, checks it's pure ASCII with exactly one marker, and converts to CRLF. **Rebuilding from these sources gives a byte-identical file.** The SHA-256 of `deliverable/gpu-power-limit.cmd` is `9e0bac8d688dd72b7f7c10d3e74a5e68d6d53de4316cd095e55172f9fced983c`.

---

## 4. How to use it

1. Put `gpu-power-limit.cmd` anywhere and double-click it. Accept the admin (UAC) prompt, watch the intro (any key skips), then press `1` to install.
2. After install, use the **WattCap RTX Power Limit** shortcut. The boot task applies 310 W about 30 s after every startup. Check `C:\ProgramData\GPUPowerLimit\last-run.log` after the first reboot.
3. To go back to stock, press `2`.
4. To change the wattage or card match, edit `WATTS` or `MATCH` at the top, then install again.

---

## 5. Not yet verified, and caveats

- **Not run on real Windows yet.** The pieces most likely to differ are console colour handling in the classic console versus Windows Terminal, `WScript.Shell`, `schtasks`, and Windows PowerShell 5.1 speed and compile behaviour.
- **Tuning tools** like MSI Afterburner or EVGA Precision that apply power limits at startup can override the boot task.
- **Small windows:** below about 80×25 the canvas shrinks below 1:1, so the small text gets rough. Fractional scales make pixel widths slightly uneven.
- **Icon in Windows Terminal:** the icon shows in the classic console's title bar and taskbar. If Windows Terminal is the default terminal, its window keeps Terminal's icon, but the shortcut still shows the gauge.
- **Why the shortcut runs as admin:** it needs admin to change power limits.

## 6. Open items

- `[A] ASCII plasma` was offered as a third intro style and not built.

---

## 7. What's in this zip

| Path | Contents |
|---|---|
| `SUMMARY.md` | This summary |
| `PROJECT-RECORD.md` | Machine-readable record: project state, decisions, manifest with SHA-256, and the full text of every source file |
| `transcript/transcript.md` | Exact conversation (entries 0–483), every tool call and result verbatim |
| `transcript/transcript.json` | The same, structured |
| `transcript/images/` | Every image from the chat (rendered previews and contact sheets) |
| `deliverable/gpu-power-limit.cmd` | **Final file (v4)** |
| `source/` | Build parts: `batch_part.cmd`, `payload.ps1`, `intro.cs`, `banner.py`, `banner.bat.txt`, `icon.py`, `build.py` |
| `assets/` | `wattcap.ico`, 1024 px icon PNG, icon previews, menu preview |
| `previews/` | Resize-demo GIF (v4), plasma intro GIF (v3), rendered frames and contact sheets |
| `history/` | v1, v2 and v3 scripts plus the v3 PowerShell intro source. v1 and v2 are exact copies of what was written (LF line endings, as originally delivered). v3 was rebuilt by re-running the recorded build steps and matches the recorded length of 18,836 characters. |
| `test-tools/` | Frame-to-PNG converter, contact-sheet maker, PowerShell dump/test harnesses, and the transcript exporter used for this zip |
| `docs/WATTCAP-code-summary.md` | The code summary delivered in the chat |

## 8. Starting a new chat on this project

Create a new project, upload this zip (or its contents) as project files, and start with something like: *"Read SUMMARY.md and PROJECT-RECORD.md. This is my WATTCAP project; continue from its current state."* The exact transcript is there if any detail needs checking.

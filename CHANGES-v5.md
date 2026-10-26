# WATTCAP v5 changes

- **Power presets:** 340, 310, 275, 250, 225, 200 W, plus **[C] custom value**. Menu `[1]` opens the picker.
  Custom/preset values are range-checked against the min/max that nvidia-smi reports for your card(s) (RTX 3090: 100-350 W).
- The chosen value is passed to the boot task (`apply <watts>`) and stored in `%ProgramData%\GPUPowerLimit\watts.txt`; the menu shows "INSTALLED at N W".
- CLI: `gpu-power-limit.cmd install 275` / `apply 275`.
- **Animations (all plasma, invaders removed):**
  - Openings: peaks (Shaved Peaks), aurora, vortex, storm.
  - Closings (play on Quit): iris, sunset, shutter, cooldown.
  - Each has 3 seeded colour schemes. Openings/closings rotate each launch (state in `rotate.txt`).
  - Menu `[G]` gallery plays any single one, all openings, all closings, or everything (any key skips one, Esc stops).
  - Settings at top of the file: `INTRO`, `OUTRO` (0 = off), `INTRO_STYLE`, `OUTRO_STYLE` (auto or a scene name).
- Rebuild: `cd source && python build.py` then copy `gpu-power-limit.cmd` to `deliverable/`.
- Previous version kept at `history/v4-invaders-plasma.cmd`.
- Tested here on Windows PowerShell 5.1: payload compiles/loads, all 8 scenes render, range detection returns 100-350.
  The interactive menu and full-screen playback have not been run by hand.

# WATTCAP v6 additions (monitor, logging, profiles)

- **[M] Live monitor:** per card - load, VRAM, power vs cap, temperature bars; SM/memory clocks, fan, P-state;
  throttle reasons (POWER-CAP / THERMAL / HW-SLOWDOWN / IDLE); scrolling load, power and VRAM history graphs.
  Keys: L log on/off, P auto-protect, +/- protect temperature, R re-apply saved limits, Q quit.
- **CSV logging:** `%ProgramData%\GPUPowerLimit\monitor-log.csv` (toggle with L).
- **[S] Usage and efficiency report:** from the log, grouped by power limit under load: avg power, avg SM clock, MHz per W, % time power-capped; peak VRAM/power/temp.
- **Auto-protect:** if a card reaches the set temperature (default 83 C) the cap drops 25 W at a time (not below the card minimum) and is restored when it cools; restored on exit.
- **Override warning:** monitor flags when the live cap differs from the saved limit (e.g. Afterburner); R re-applies.
- **[F] Profiles and per-card limits:** Gaming 340 / Balanced 310 / Render 275 / Quiet 225 / Silent 200, custom per-card watts, save/delete profiles (profiles.txt).
  Saved limits live in limits.txt (`ALL=310`, `1=250`) and are what the boot task applies. Menu shows "INSTALLED - GPU1 250 W, others 310 W".
- **Boot verification:** 15 s after the boot-time apply, re-reads the caps, logs OK/MISMATCH to last-run.log and re-applies once if a tool changed them.
- CLI: `monitor`, `report`, `profiles`, `install 275`, `apply 275`.
- Tested here: payload parse/compile on PowerShell 5.1, live telemetry read from both RTX 3090s, frame render, limits file + range validation, report maths on synthetic data,
  batch per-card apply logic against a fake nvidia-smi. NOT tested by hand: full-screen interactive monitor, auto-protect on real heat, profile screens, boot verify.

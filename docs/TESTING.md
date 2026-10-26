# Testing WATTCAP

WATTCAP changes real GPU power limits, so most of the testing that matters has to happen on a machine with an RTX 3090. The automated checks below run on every push and catch build and script problems; the hardware checks are the ones that prove the tool works.

## 1. Automated checks (run in CI on every push)

| Check | What it catches | Where |
|---|---|---|
| Launcher compiles | C# errors in `WattCapLauncher.cs` and `Widget.cs` | `.github/workflows/ci.yml`, job `launcher-build` |
| Deliverable matches source | A `gpu-power-limit.cmd` that was edited by hand, or source edits that were never rebuilt | job `deliverable-drift` |
| PowerShell lint | Syntax and common-mistake errors in the `.ps1` scripts | job `powershell-lint` (PSScriptAnalyzer) |

Run the drift check yourself before committing a change to `source/`:

```
cd source
python build.py
```

Then copy the new `gpu-power-limit.cmd` into `deliverable/`. Commit both.

## 2. Logic tests (recommended next step)

Several pure functions in `source/payload.ps1` can be tested without a GPU by feeding them fake input:

- `Parse-Spec`, `Spec-Text`: profile parsing and display.
- `Heat`, `Bar`, `Spark`: colour and bar drawing for the monitor.
- `Build-MonitorLines`: one full monitor frame from sample GPU data.
- `Get-Report`: usage summary from a sample `monitor-log.csv`.
- `Spin.Update` and `Spin.Frame` in `launcher/WattCapLauncher.cs`: the icon animation model. Check that the final frame equals the static icon and that the motion never runs backwards.

Suggested tooling: [Pester](https://pester.dev) for PowerShell, and a small console harness for the C# spin model. Put the tests in `tests/` and run them from a new CI job on `windows-latest`.

## 3. Hardware checks (on a real RTX 3090)

Run these before each release. Keep a note of the GPU, driver version, and the output.

1. **Apply and reset round trip.** Note the card's default limit with `nvidia-smi -q -d POWER`. Set a limit with `[1]`, confirm it with `[3]`, then reset with `[2]`. The limit must return to the default.
2. **Boot task.** After `[1]`, check that the scheduled task `GPU Power Limit (3090)` exists and that `last-run.log` in `C:\ProgramData\GPUPowerLimit\` shows each card being set. Reboot and check again.
3. **Out-of-range input.** Enter a wattage below the minimum or above the maximum the card allows. The tool must refuse it and leave the current limit unchanged.
4. **No matching card.** Set `MATCH` to something that doesn't exist, such as `9999`. The tool must report no cards and change nothing.
5. **Missing driver.** Rename or hide `nvidia-smi.exe` temporarily. The tool must print a clear error and not crash.
6. **Live monitor.** Open `[M]` under load. Confirm the readings update, the log file grows, and `Esc` returns to the menu.
7. **Profiles.** Save a per-card profile in `[F]`, apply it, and check each card got its own value.

## 4. Launcher checks (desktop icon)

Only needed when `launcher/` changes.

1. Build with `launcher\build.cmd`. Check that `WattCapLauncher.exe` is created with no errors.
2. Run `install.ps1` once from an elevated PowerShell.
3. Click the desktop icon. Check that:
   - the icon spins up, keeps spinning while the menu opens, and fades out once the menu is up;
   - there is no UAC prompt;
   - the menu opens at the same size and position as before.
4. Check `%LOCALAPPDATA%\WattCapLauncher\launcher.log` for `schtasks /run -> 0` and a `menu window up` line.
5. Double-click the widget and repeat step 3. The widget keeps its own motion.
6. Run `uninstall.ps1` and check that the original desktop shortcut returns and the `WattCap Menu` task is removed.

## 5. Animation and visual checks

Animations are judged by eye. For each scene in `[G]` (openings and closings):

- it plays from start to finish without flicker or tearing;
- `Esc` stops it;
- it returns to the menu cleanly;
- the colours are readable on both a dark and a light console background.

## 6. Before a release

- All CI jobs pass.
- Section 3 passes on at least one RTX 3090 with a note of the driver version.
- `CHANGES-*.md` describes the change.
- The README's screenshots and version match the release.

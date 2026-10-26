# Onboarding

Welcome. This page is for someone who wants to understand, use, or change WATTCAP. Read it once, then follow the steps at the end to make your first change.

## What WATTCAP does, in one paragraph

NVIDIA cards have a power limit, measured in watts. Lowering it makes the GPU run cooler and quieter, usually for a small loss in speed. WATTCAP sets that limit on every RTX 3090 in the PC, saves it, and reapplies it at each boot through a scheduled task. It also watches the cards while they run and writes a usage log.

## Key terms

- **Stock limit:** the card's default power limit, set by NVIDIA. `nvidia-smi` reports it as the default limit.
- **Allowed range:** the lowest and highest limits the driver accepts for the card.
- **Boot task:** the scheduled task that applies the saved limit at startup.
- **Profile:** a saved set of limits, one per card.
- **Launcher:** the optional C# program in `launcher/` that animates the desktop icon and opens the menu.

## How the code is laid out

WATTCAP is three languages stacked in one file. [docs/WATTCAP-code-summary.md](WATTCAP-code-summary.md) walks through each part. In short:

1. **Batch** (`source/batch_part.cmd`): the menu, command-line modes, and the apply, install, and reset logic. It calls `nvidia-smi` directly.
2. **PowerShell** (`source/payload.ps1`): the monitor, the usage report, profiles, and the shortcut creation.
3. **C#** (`source/intro.cs`): the intro and outro animation renderer, embedded as text.

`source/build.py` joins these together into `deliverable/gpu-power-limit.cmd`. You edit `source/`, rebuild, and commit the result. You don't edit the deliverable by hand.

The launcher (`launcher/`) is separate. It's built on its own with `build.cmd` and is optional.

## Where to find things

| You want to change | Look in |
|---|---|
| The ASCII banner | `source/banner.bat.txt` |
| Menu text and keys | `source/batch_part.cmd` |
| The intro and outro animations | `source/intro.cs` |
| The monitor screen | `source/payload.ps1` (`Build-MonitorLines`) |
| The usage report | `source/payload.ps1` (`Get-Report`) |
| The default wattage and the matched card name | the first few `set` lines in `source/batch_part.cmd` |
| The desktop icon's spin | `launcher/WattCapLauncher.cs` (`Spin`, `Animate`) |
| The menu launch path | `launcher/WattCapLauncher.cs` (`LaunchCmd`) and `launcher/install.ps1` |

## Your first hour

1. **Read the setup guide** ([docs/SETUP.md](SETUP.md)) and run the script once on a test PC, or on a PC with an RTX 3090 you're happy to change.
2. **Build the deliverable.** From `source/`, run `python build.py`. Check that the output matches `deliverable/gpu-power-limit.cmd`. If it does, your build environment works.
3. **Make a small change.** Change one line of the banner in `source/banner.bat.txt`, such as the colour of the tagline. Rebuild, copy the output into `deliverable/`, run it, and check the change.
4. **Run the checks.** See [docs/TESTING.md](TESTING.md). The drift check is the one that matters most before you commit.
5. **Open a pull request.** Describe what changed and which hardware you tested on.

## Ground rules

- Test on hardware before you rely on a change. A bad limit can make a machine unstable, so reset to stock (`[2]`) when you're done testing.
- Keep `source/` as the only place you edit the script. Edits made to the deliverable will be overwritten on the next build.
- Don't commit logs or CSV files from `C:\ProgramData\GPUPowerLimit\`. They contain your machine's details.

# Setup guide

This guide gets WATTCAP running on a Windows PC with an RTX 3090, from a fresh download to a limit that survives a reboot.

## Before you start

- Windows 10 or 11.
- An RTX 3090 with a working NVIDIA driver. Check that `nvidia-smi` runs in a Command Prompt.
- An account with administrator rights.

## 1. Get the files

Download the repository as a ZIP from GitHub and extract it, or clone it:

```
git clone https://github.com/walladanger/rtx-wattcap
```

## 2. Start WATTCAP

Double-click `deliverable/gpu-power-limit.cmd` and accept the admin prompt. The window shows the banner and the menu.

If the menu says no RTX 3090 was found, see [Troubleshooting](#troubleshooting).

## 3. Set a power limit

1. Press `1`.
2. Enter a wattage. The window shows the range your card allows, so check it before you enter a value.
3. WATTCAP applies the limit to every 3090 and installs the boot task, so the limit is set again at every startup.
4. Press `3` to confirm the current limit on each card.

Start with a value about 10 to 15 percent below stock, then compare temperatures, noise, and performance under your own workload. Use `[M]` for live readings.

## 4. Check the boot task

The boot task is named `GPU Power Limit (3090)` in Task Scheduler. It runs as SYSTEM 30 seconds after startup. To confirm it works:

1. Reboot.
2. Open `C:\ProgramData\GPUPowerLimit\last-run.log`.
3. Look for a line for each card showing the limit was set.

## 5. Optional: desktop shortcut and launcher

**Shortcut only:** press `4` in the menu. This adds a desktop and Start menu shortcut with the WATTCAP logo.

**Animated launcher:** the `launcher/` folder contains a small C# program that spins the desktop icon, then opens the menu with no UAC prompt. It also adds a draggable desktop widget.

1. Build it. In `launcher\`, run `build.cmd`. This needs the .NET Framework C# compiler that ships with Windows, so no extra install is needed.
2. Copy `WattCapLauncher.exe` and the `assets\` folder to `%LOCALAPPDATA%\WattCapLauncher\`.
3. Open PowerShell **as administrator**, go to the `launcher\` folder, and run `.\install.ps1`. This registers the `WattCap Menu` task, which opens the menu elevated, and points the desktop shortcut at the launcher.
4. Click the desktop icon. The icon spins, the menu opens, and the icon fades out.

The launcher writes its log to `%LOCALAPPDATA%\WattCapLauncher\launcher.log`.

## 6. Undo everything

To return the cards to stock and remove WATTCAP's setup:

1. Press `2` in the menu. This resets each card to its default limit and removes the boot task.
2. If you installed the launcher, run `.\uninstall.ps1` from an elevated PowerShell in `launcher\`. This removes the `WattCap Menu` task, restores the original desktop shortcut, and stops the widget.

You can then delete the folder. Check `C:\ProgramData\GPUPowerLimit\` too, because it holds the installed copy and logs.

## Troubleshooting

**"nvidia-smi.exe not found"**
The NVIDIA driver isn't installed, or its tools are in an unusual location. WATTCAP looks in `System32` and `Program Files\NVIDIA Corporation\NVSMI`. Reinstall the driver, then try again.

**No RTX 3090 found**
WATTCAP matches cards by name, using the `MATCH` value at the top of the script (default `3090`). Run `nvidia-smi -L` and check the name. If your card's name differs, change `MATCH`, rebuild, and copy the new file to `deliverable/`.

**The limit doesn't survive a reboot**
Check `last-run.log`. If the line is missing, the boot task isn't installed. Press `1` again to reinstall it.

**The launcher icon doesn't spin, or opens nothing**
Check `%LOCALAPPDATA%\WattCapLauncher\launcher.log`. If it shows `schtasks /run -> 1`, the `WattCap Menu` task is missing. Run `install.ps1` again from an elevated PowerShell.

**Windows SmartScreen or antivirus blocks the script**
The `.cmd` and `.exe` aren't signed. Check that you downloaded them from this repository, then allow them in your antivirus if you're sure.

**Something else**
Open an issue on GitHub and include the `last-run.log` and `nvidia-smi -q -d POWER` output. Remove any serial numbers before posting.

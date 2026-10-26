# Revert WattCap Launcher v2: restore original desktop shortcut, remove widget autostart, stop widget.
$d = "$env:LOCALAPPDATA\WattCapLauncher"
Copy-Item "$d\WattCap RTX Power Limit.original.lnk" "$env:USERPROFILE\Desktop\WattCap RTX Power Limit.lnk" -Force
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WattCap Widget.lnk" -ErrorAction SilentlyContinue
Get-Process WattCapLauncher -ErrorAction SilentlyContinue | Stop-Process -Force

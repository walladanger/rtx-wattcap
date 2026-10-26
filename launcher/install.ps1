# WattCap Launcher v2 installer: repoints desktop shortcut (after backup) + Startup widget shortcut.
$d   = "$env:LOCALAPPDATA\WattCapLauncher"
$exe = "$d\WattCapLauncher.exe"
$lnk = "$env:USERPROFILE\Desktop\WattCap RTX Power Limit.lnk"
$ico = "$env:USERPROFILE\Pictures\Icons\Designs\rtxf1.ico,0"
$bak = "$d\WattCap RTX Power Limit.original.lnk"
if (-not (Test-Path $bak)) { Copy-Item $lnk $bak }
$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk)
$s.TargetPath = $exe; $s.Arguments = '--launch'; $s.WorkingDirectory = 'C:\ProgramData\GPUPowerLimit'
$s.IconLocation = $ico; $s.WindowStyle = 1; $s.Description = 'WattCap Launcher v2'; $s.Save()
# clear RunAsAdministrator flag (0x20 at 0x15): launcher stays unelevated, elevates the .cmd via runas
$b = [IO.File]::ReadAllBytes($lnk); $b[0x15] = $b[0x15] -band 0xDF; [IO.File]::WriteAllBytes($lnk, $b)
$st = $sh.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WattCap Widget.lnk")
$st.TargetPath = $exe; $st.Arguments = ''; $st.WorkingDirectory = $d; $st.IconLocation = $ico; $st.Description = 'WattCap Launcher v2 desktop widget'; $st.Save()

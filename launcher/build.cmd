@echo off
rem WattCap Launcher v2 build. Regenerate sprites on any machine with Python+PIL: python make_frames.py rtxf1.png
cd /d "%~dp0"
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /optimize+ /platform:x64 /win32icon:assets\rtxf1.ico /r:System.Drawing.dll /out:WattCapLauncher.exe WattCapLauncher.cs Widget.cs

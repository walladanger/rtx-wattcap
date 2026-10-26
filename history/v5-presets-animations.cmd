@echo off
setlocal EnableDelayedExpansion
:: ==========================================================================
::  WATTCAP  -  gpu-power-limit.cmd
::  Sets every RTX %MATCH% to %WATTS% W on each Windows boot.
::
::  Double-click                 -> animated intro (any key skips), then menu
::  gpu-power-limit install      -> install boot task + shortcut + apply now
::  gpu-power-limit apply        -> apply only (what the boot task runs)
::  gpu-power-limit reset        -> stock limits now + remove boot task
::  gpu-power-limit shortcut     -> desktop + Start menu shortcut with logo
::
::  Everything below the WATTCAP marker at the end is PowerShell/C#
::  (intro renderer, shortcut maker, icon). Batch never executes it.
:: ==========================================================================

set "WATTS=310"
set "MATCH=3090"
:: INTRO / OUTRO = 0 skips the opening / closing animation.
:: *_STYLE = auto (rotate) or a name: peaks aurora vortex storm | iris sunset shutter cooldown
set "INTRO=1"
set "INTRO_STYLE=auto"
set "OUTRO=1"
set "OUTRO_STYLE=auto"

set "TASK=GPU Power Limit (%MATCH%)"
set "INSTALL_DIR=%ProgramData%\GPUPowerLimit"
set "SELF=%INSTALL_DIR%\gpu-power-limit.cmd"
set "LOG=%INSTALL_DIR%\last-run.log"
set "INTRO_SELF=%~f0"

:: ---- require admin (SYSTEM task already is) -----------------------------
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

:: optional watt value after the mode:  install 275 / apply 275  (the boot task passes it)
if not "%~2"=="" (
    echo %~2| findstr /r /x "[0-9][0-9]*" >nul && set "WATTS=%~2"
)

if /i "%~1"=="apply"     goto :apply
if /i "%~1"=="install"   goto :install
if /i "%~1"=="reset"     goto :reset
if /i "%~1"=="uninstall" goto :reset
if /i "%~1"=="shortcut"  goto :shortcut

:: ---- interactive path -----------------------------------------------------
title WATTCAP - RTX %MATCH% power limit
for /f %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
if "%INTRO%"=="1" call :ps intro %INTRO_STYLE%

:menu
cls
call :banner
set "TSTAT=%ESC%[38;5;244mnot installed"
set "INSTW="
if exist "%INSTALL_DIR%\watts.txt" set /p INSTW=<"%INSTALL_DIR%\watts.txt"
schtasks /Query /TN "%TASK%" >nul 2>&1 && (
    set "TSTAT=%ESC%[38;5;41mINSTALLED"
    if defined INSTW set "TSTAT=%ESC%[38;5;41mINSTALLED at !INSTW! W"
)
echo.
echo   %ESC%[38;5;238m-----------------------------------------------------------------%ESC%[0m
echo    Boot task: %TSTAT%%ESC%[0m     per RTX %MATCH% card
echo   %ESC%[38;5;238m-----------------------------------------------------------------%ESC%[0m
echo    [1] Set power limit on every boot (pick watts)
echo    [2] Reset to stock (remove boot task)
echo    [3] Show current limits
echo    [4] Desktop + Start menu shortcut (with logo)
echo    [G] Animation gallery (play any opening / closing)
echo    [Q] Quit
echo.
choice /c 1234GQ /n /m "  Select: "
if errorlevel 6 (if "%OUTRO%"=="1" call :ps outro %OUTRO_STYLE%) & exit /b 0
if errorlevel 5 goto :gallery
if errorlevel 4 (call :ps shortcut & pause & goto :menu)
if errorlevel 3 goto :show
if errorlevel 2 goto :reset
if errorlevel 1 goto :setmenu
goto :menu

:: ---- animation gallery ------------------------------------------------------
:gallery
cls
call :banner
echo.
echo    ANIMATION GALLERY   (any key skips one, Esc stops a playlist)
echo.
echo     Openings                     Closings
echo     [1] Shaved Peaks             [5] Iris Lock
echo     [2] Aurora Curtains          [6] Retro Sunset
echo     [3] Ember Vortex             [7] Shutter
echo     [4] Storm Front              [8] Cooldown
echo.
echo     [O] All openings   [C] All closings   [A] Everything   [B] Back
echo.
choice /c 12345678OCAB /n /m "  Select: "
if errorlevel 12 goto :menu
if errorlevel 11 (call :ps play all & goto :gallery)
if errorlevel 10 (call :ps play allclose & goto :gallery)
if errorlevel 9 (call :ps play allopen & goto :gallery)
if errorlevel 8 (call :ps play cooldown & goto :gallery)
if errorlevel 7 (call :ps play shutter & goto :gallery)
if errorlevel 6 (call :ps play sunset & goto :gallery)
if errorlevel 5 (call :ps play iris & goto :gallery)
if errorlevel 4 (call :ps play storm & goto :gallery)
if errorlevel 3 (call :ps play vortex & goto :gallery)
if errorlevel 2 (call :ps play aurora & goto :gallery)
if errorlevel 1 (call :ps play peaks & goto :gallery)
goto :gallery

:: ---- pick watts -----------------------------------------------------------
:setmenu
cls
call :banner
echo.
echo    Choose the power limit for every RTX %MATCH% card:
echo.
echo     [1] 340 W
echo     [2] 310 W
echo     [3] 275 W
echo     [4] 250 W
echo     [5] 225 W
echo     [6] 200 W
echo     [C] Custom value
echo     [B] Back
echo.
choice /c 123456CB /n /m "  Select: "
if errorlevel 8 goto :menu
if errorlevel 7 goto :custom
if errorlevel 6 (set "WATTS=200" & goto :install)
if errorlevel 5 (set "WATTS=225" & goto :install)
if errorlevel 4 (set "WATTS=250" & goto :install)
if errorlevel 3 (set "WATTS=275" & goto :install)
if errorlevel 2 (set "WATTS=310" & goto :install)
if errorlevel 1 (set "WATTS=340" & goto :install)
goto :setmenu

:custom
call :getrange
echo.
if !RFOUND! equ 1 (echo    Allowed range on your card^(s^): !MINW! - !MAXW! W) else (echo    Could not read the allowed range from nvidia-smi.)
set "CW="
set /p "CW=   Enter watts (blank = cancel): "
if not defined CW goto :setmenu
echo !CW!| findstr /r /x "[0-9][0-9]*" >nul || (echo    Not a whole number. & pause & goto :custom)
if not "!CW:~4!"=="" (echo    Too many digits. & pause & goto :custom)
for /f "tokens=* delims=0" %%z in ("!CW!") do set "CW=%%z"
if not defined CW (echo    Value must be above 0. & pause & goto :custom)
if !RFOUND! equ 1 (
    if !CW! lss !MINW! (echo    !CW! W is below the minimum ^(!MINW! W^). & pause & goto :custom)
    if !CW! gtr !MAXW! (echo    !CW! W is above the maximum ^(!MAXW! W^). & pause & goto :custom)
)
set "WATTS=!CW!"
goto :install

:: reads min/max allowed limit common to all matching cards -> MINW MAXW RFOUND
:getrange
set /a MINW=0, MAXW=99999, RFOUND=0
call :find_smi >nul 2>&1 || exit /b 1
set "RNG=%TEMP%\wattcap-range.txt"
"%SMI%" --query-gpu=name,power.min_limit,power.max_limit --format=csv,noheader,nounits > "%RNG%" 2>nul
for /f "usebackq tokens=1,2,3 delims=," %%A in ("%RNG%") do (
    echo %%A | find /i "%MATCH%" >nul && (
        for /f "tokens=1 delims=. " %%L in ("%%B") do for /f "tokens=1 delims=. " %%H in ("%%C") do (
            if %%L gtr !MINW! set /a MINW=%%L
            if %%H lss !MAXW! set /a MAXW=%%H
            set /a RFOUND=1
        )
    )
)
exit /b 0

:: ---- install ------------------------------------------------------------
:install
call :getrange
if !RFOUND! equ 1 (
    if %WATTS% lss !MINW! (echo %WATTS% W is below this card's minimum ^(!MINW! W^). & pause & exit /b 1)
    if %WATTS% gtr !MAXW! (echo %WATTS% W is above this card's maximum ^(!MAXW! W^). & pause & exit /b 1)
)
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if /i not "%~f0"=="%SELF%" copy /y "%~f0" "%SELF%" >nul
>"%INSTALL_DIR%\watts.txt" echo %WATTS%

schtasks /Create /TN "%TASK%" /TR "\"%SELF%\" apply %WATTS%" /SC ONSTART /DELAY 0000:30 /RU SYSTEM /RL HIGHEST /F
if errorlevel 1 (
    echo Failed to create scheduled task.
    pause
    exit /b 1
)
echo Scheduled task "%TASK%" installed ^(runs at boot as SYSTEM, 30s delay^).
call :ps shortcut
echo.
call :apply
echo.
type "%LOG%"
echo.
pause
exit /b 0

:: ---- apply --------------------------------------------------------------
:apply
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
echo [%date% %time%] Target: %WATTS% W on GPUs matching "%MATCH%" > "%LOG%"
call :find_smi || exit /b 1
call :wait_driver || exit /b 1

set "GPULIST=%INSTALL_DIR%\gpus.txt"
"%SMI%" --query-gpu=index,name --format=csv,noheader > "%GPULIST%"

set /a HIT=0
for /f "usebackq tokens=1,* delims=," %%A in ("%GPULIST%") do (
    echo %%B | find /i "%MATCH%" >nul && (
        set /a HIT+=1
        echo --- GPU %%A:%%B >> "%LOG%"
        "%SMI%" -i %%A -pl %WATTS% >> "%LOG%" 2>&1
    )
)
if !HIT! equ 0 echo WARNING: no GPUs matched "%MATCH%". >> "%LOG%"
call :log_limits
exit /b 0

:: ---- reset to stock -----------------------------------------------------
:reset
set "TMPDIR_=%TEMP%\GPUPowerLimit"
if not exist "%TMPDIR_%" mkdir "%TMPDIR_%"
set "RLOG=%TMPDIR_%\reset.log"
echo [%date% %time%] Resetting GPUs matching "%MATCH%" to default limit > "%RLOG%"

call :find_smi || (type "%RLOG%" & pause & exit /b 1)

set "GPULIST=%TMPDIR_%\gpus.txt"
"%SMI%" --query-gpu=index,name,power.default_limit --format=csv,noheader,nounits > "%GPULIST%"

for /f "usebackq tokens=1,2,3 delims=," %%A in ("%GPULIST%") do (
    echo %%B | find /i "%MATCH%" >nul && (
        for /f "tokens=1 delims=. " %%D in ("%%C") do (
            echo --- GPU %%A:%%B  default %%D W >> "%RLOG%"
            "%SMI%" -i %%A -pl %%D >> "%RLOG%" 2>&1
        )
    )
)

echo. >> "%RLOG%"
"%SMI%" --query-gpu=index,name,power.limit,power.default_limit --format=csv >> "%RLOG%" 2>&1

schtasks /Query /TN "%TASK%" >nul 2>&1 && (
    schtasks /Delete /TN "%TASK%" /F >> "%RLOG%" 2>&1
)
if exist "%LOG%" del /q "%LOG%" >nul 2>&1
if exist "%INSTALL_DIR%\watts.txt" del /q "%INSTALL_DIR%\watts.txt" >nul 2>&1
type "%RLOG%"
echo.
echo Boot task removed. Cards are at stock and will stay stock after reboot.
echo ^(Shortcut and its copy in %INSTALL_DIR% are kept so the menu still opens.^)
pause
exit /b 0

:: ---- shortcut (CLI) -----------------------------------------------------
:shortcut
call :ps shortcut
pause
exit /b 0

:: ---- show ---------------------------------------------------------------
:show
call :find_smi || (pause & goto :menu)
echo.
"%SMI%" --query-gpu=index,name,power.draw,power.limit,power.default_limit,power.min_limit,power.max_limit --format=csv
echo.
schtasks /Query /TN "%TASK%" >nul 2>&1 && (echo Boot task: INSTALLED) || (echo Boot task: not installed)
echo.
pause
goto :menu

:: ---- helpers ------------------------------------------------------------
:find_smi
set "SMI=%SystemRoot%\System32\nvidia-smi.exe"
if not exist "%SMI%" set "SMI=%ProgramFiles%\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
if not exist "%SMI%" (
    echo ERROR: nvidia-smi.exe not found.
    if defined LOG if exist "%INSTALL_DIR%" echo ERROR: nvidia-smi.exe not found. >> "%LOG%"
    exit /b 1
)
exit /b 0

:wait_driver
:: driver may not be ready right after boot (max ~60s)
set /a TRY=0
:wait_loop
"%SMI%" -L >nul 2>&1
if not errorlevel 1 exit /b 0
set /a TRY+=1
if !TRY! geq 12 (
    echo ERROR: NVIDIA driver not responding after 60s. >> "%LOG%"
    exit /b 1
)
ping -n 6 127.0.0.1 >nul
goto :wait_loop

:log_limits
echo. >> "%LOG%"
echo Current limits: >> "%LOG%"
"%SMI%" --query-gpu=index,name,power.limit,power.min_limit,power.max_limit --format=csv >> "%LOG%" 2>&1
exit /b 0

:: Runs the PowerShell payload stored after the marker at the end of this file.
::   arg1 = intro or shortcut, arg2 = invaders or plasma
:ps
set "WC_MODE=%~1"
set "WC_STYLE=%~2"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText($env:INTRO_SELF); $m='<#'+'WATTCAP#>'; $i=$f.LastIndexOf($m); if ($i -ge 0) { Invoke-Expression $f.Substring($i + $m.Length) }"
exit /b 0

:banner
echo.
echo  %ESC%[38;5;240m    %ESC%[38;5;41m_.-%ESC%[38;5;220m''%ESC%[38;5;220m''%ESC%[38;5;208m-._%ESC%[38;5;240m   %ESC%[38;5;240m  %ESC%[38;5;252m__      ___ _____ _____ %ESC%[38;5;214m  ___   _   ___ %ESC%[0m
echo  %ESC%[38;5;41m  .'%ESC%[38;5;41m .%ESC%[38;5;220m  '  %ESC%[38;5;208m. %ESC%[38;5;196m'.%ESC%[38;5;240m  %ESC%[38;5;240m  %ESC%[38;5;252m\ \    / /_\_   _^|_   _^|%ESC%[38;5;214m / __^| /_\ ^| _ \%ESC%[0m
echo  %ESC%[38;5;41m / %ESC%[38;5;41m.%ESC%[38;5;240m      %ESC%[38;5;231m_.-'%ESC%[38;5;240m %ESC%[38;5;196m\%ESC%[38;5;240m %ESC%[38;5;240m  %ESC%[38;5;252m \ \/\/ / _ \^| ^|   ^| ^|  %ESC%[38;5;214m^| (__ / _ \^|  _/%ESC%[0m
echo  %ESC%[38;5;41m^| %ESC%[38;5;41m.%ESC%[38;5;240m    %ESC%[38;5;214m(O)%ESC%[38;5;231m'%ESC%[38;5;240m     %ESC%[38;5;196m^|%ESC%[38;5;240m%ESC%[38;5;240m  %ESC%[38;5;252m  \_/\_/_/ \_\_^|   ^|_^|  %ESC%[38;5;214m \___/_/ \_\_^|  %ESC%[0m
echo  %ESC%[38;5;240m'._____________.'%ESC%[38;5;240m%ESC%[38;5;240m  %ESC%[38;5;244mRTX %MATCH% power limiter  ::  200-340 W or custom%ESC%[0m
exit /b 0

:: ===================== PowerShell / C# payload (not batch) =====================
<#WATTCAP#>

# ==========================================================================
#  WATTCAP payload. Invoked by the batch :ps routine with
#    WC_MODE  = intro | outro | play | shortcut
#    WC_STYLE = auto | <scene name> | allopen | allclose | all
#  ASCII-only source. The C# renderer is compiled once and cached as a DLL
#  next to the install (hash-named, so edits recompile automatically).
# ==========================================================================
function Invoke-WattCap {
    $watts = 310; if ($env:WATTS -match '^\d+$') { $watts = [int]$env:WATTS }
    $match = '3090'; if ($env:MATCH) { $match = $env:MATCH }
    $mode = 'intro'; if ($env:WC_MODE) { $mode = $env:WC_MODE }
    $style = 'auto'; if ($env:WC_STYLE) { $style = $env:WC_STYLE.ToLower() }
    $root = $env:ProgramData; if (-not $root) { $root = [IO.Path]::GetTempPath() }
    $base = Join-Path $root 'GPUPowerLimit'
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }

    if ($mode -eq 'shortcut') {
        $ico = Join-Path $base 'wattcap.ico'
        [IO.File]::WriteAllBytes($ico, [Convert]::FromBase64String(($script:WattCapIcon -replace '\s', '')))
        $cmd = Join-Path $base 'gpu-power-limit.cmd'
        if ($env:INTRO_SELF -and ($env:INTRO_SELF -ne $cmd)) { Copy-Item -LiteralPath $env:INTRO_SELF -Destination $cmd -Force }
        $wsh = New-Object -ComObject WScript.Shell
        foreach ($dir in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonPrograms'))) {
            if (-not $dir) { continue }
            try {
                $lnk = Join-Path $dir 'WattCap RTX Power Limit.lnk'
                $s = $wsh.CreateShortcut($lnk)
                $s.TargetPath = $cmd
                $s.WorkingDirectory = $base
                $s.IconLocation = "$ico,0"
                $s.Description = "WATTCAP - RTX $match power limiter"
                $s.Save()
                # set "Run as administrator" (flags byte 0x15, bit 0x20) so it opens elevated with the icon
                $b = [IO.File]::ReadAllBytes($lnk); $b[0x15] = $b[0x15] -bor 0x20; [IO.File]::WriteAllBytes($lnk, $b)
                Write-Host "  shortcut: $lnk"
            } catch { Write-Host "  could not create shortcut in $dir : $($_.Exception.Message)" }
        }
        return
    }

    # ---- animations -------------------------------------------------------
    $openings = @('peaks', 'aurora', 'vortex', 'storm')
    $closings = @('iris', 'sunset', 'shutter', 'cooldown')
    $titles = @{
        peaks = 'Shaved Peaks'; aurora = 'Aurora Curtains'; vortex = 'Ember Vortex'; storm = 'Storm Front'
        iris = 'Iris Lock'; sunset = 'Retro Sunset'; shutter = 'Shutter'; cooldown = 'Cooldown'
    }

    # rotation: each launch plays the next opening / next closing in turn (state kept in rotate.txt)
    $rotFile = Join-Path $base 'rotate.txt'
    function Get-Rot([string]$kind, [string[]]$list) {
        $ix = @{ open = 0; close = 0 }
        try {
            foreach ($l in @(Get-Content -LiteralPath $rotFile -ErrorAction Stop)) {
                if ($l -match '^(open|close)=(\d+)$') { $ix[$Matches[1]] = [int]$Matches[2] }
            }
        } catch {}
        $pick = $list[$ix[$kind] % $list.Count]
        $ix[$kind] = ($ix[$kind] + 1) % $list.Count
        try { Set-Content -LiteralPath $rotFile -Value @("open=$($ix['open'])", "close=$($ix['close'])") -Encoding ASCII -ErrorAction Stop } catch {}
        return $pick
    }

    $play = @()
    if     ($style -eq 'all')      { $play = $openings + $closings }
    elseif ($style -eq 'allopen')  { $play = $openings }
    elseif ($style -eq 'allclose') { $play = $closings }
    elseif (($openings + $closings) -contains $style) { $play = @($style) }
    elseif ($mode -eq 'outro')     { $play = @(Get-Rot 'close' $closings) }
    else                           { $play = @(Get-Rot 'open' $openings) }

    $gpuLines = New-Object System.Collections.Generic.List[string]
    $stock = 350.0; $nGpu = 0
    try {
        $smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
        if (-not (Test-Path $smi)) { $smi = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe' }
        if (Test-Path $smi) {
            $rows = & $smi --query-gpu=index,name,power.limit,power.default_limit,temperature.gpu --format=csv,noheader,nounits 2>$null
            foreach ($r in @($rows)) {
                try {
                    $p = @($r -split '\s*,\s*')
                    $gpuLines.Add(('GPU{0}  {1}  {2:0} W now / {3:0} W stock  {4} C' -f $p[0], $p[1], [double]$p[2], [double]$p[3], $p[4]))
                    if ($p[1] -like "*$match*") { $nGpu++; $stock = [double]$p[3] }
                } catch {}
            }
        }
    } catch {}
    if ($gpuLines.Count -eq 0) { $gpuLines.Add('nvidia-smi not reachable') }

    if (-not ('WattCap.Intro' -as [type])) {
        $src = $script:WattCapSource
        $sha = [Security.Cryptography.SHA1]::Create()
        $h = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($src))[0..5] | ForEach-Object { $_.ToString('x2') })
        $dll = Join-Path $base "wattcap-intro-$h.dll"
        if (-not (Test-Path $dll)) {
            Get-ChildItem -Path $base -Filter 'wattcap-intro-*.dll' -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            try { Add-Type -TypeDefinition $src -OutputAssembly $dll -OutputType Library -ErrorAction Stop } catch {}
        }
        if (-not ('WattCap.Intro' -as [type]) -and (Test-Path $dll)) {
            try { Add-Type -Path $dll -ErrorAction Stop } catch {}
        }
        if (-not ('WattCap.Intro' -as [type])) { Add-Type -TypeDefinition $src }
    }

    foreach ($name in $play) {
        $seed = Get-Random -Minimum 1 -Maximum 100000
        if ($closings -contains $name) {
            $tick = ('  >>  WATTCAP  ::  limit {0} W per card  ::  {1}  ::  seed {2}  ::  any key skips, Esc stops  ' -f $watts, $titles[$name], $seed)
        } else {
            $tick = '  >>  ' + ($gpuLines -join '  ::  ') +
                    ('  ::  {0}  ::  seed {1}  ::  any key skips, Esc stops  ' -f $titles[$name], $seed)
        }
        [WattCap.Intro]::Style  = $name
        [WattCap.Intro]::Watts  = $watts
        [WattCap.Intro]::Stock  = $stock
        [WattCap.Intro]::NGpu   = $nGpu
        [WattCap.Intro]::Match  = $match
        [WattCap.Intro]::Seed   = $seed
        [WattCap.Intro]::Ticker = $tick
        if (-not $script:WattCapNoRun) { [WattCap.Intro]::Run() }
        if ([WattCap.Intro]::Abort) { break }
    }
}

$script:WattCapSource = @'
// WattCap intro renderer. C# 5 / .NET Framework 4.x compatible (Windows PowerShell 5.1 Add-Type).
// Scenes draw into a fixed 80x45 virtual canvas; every frame that canvas is scaled to the live
// console size (half-block pixels, 2 per cell) and letterboxed, so resizing rescales everything.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WattCap
{
    public static class Intro
    {
        // ---- config, set from PowerShell ----
        public static string Style = "invaders";
        public static int Watts = 310;
        public static double Stock = 350;
        public static int NGpu = 0;
        public static string Match = "3090";
        public static int Seed = 1;
        public static string Ticker = "";
        public static bool Abort = false;   // set when Esc is pressed (stops a multi-scene playlist)

        public static readonly string[] Openings = { "peaks", "aurora", "vortex", "storm" };
        public static readonly string[] Closings = { "iris", "sunset", "shutter", "cooldown" };

        const string CSI = "\u001b[";
        internal const int VW = 80, VH = 45;
        internal static readonly byte[] vb = new byte[VW * VH];
        internal static Random rng = new Random(1);
        internal static int accent = 45;

        // ---- screen state ----
        internal static int cols, rows, SW, SH;
        internal static double sc, offX, offY;
        internal static byte[] spix = new byte[0];
        static int[] mapX = new int[0], mapY = new int[0], prevKey = new int[0];
        static bool fullRedraw = true;
        static string tickSrc = "";

        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int h);
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out int m);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, int m);

        static void EnableVT()
        {
            try
            {
                IntPtr h = GetStdHandle(-11);
                int m;
                if (GetConsoleMode(h, out m)) SetConsoleMode(h, m | 0x0004 | 0x0001);
            }
            catch { }
        }

        internal abstract class Scene
        {
            public abstract void Step(double t, double dt);
            public abstract void DrawVirtual(double t);
            public abstract void DrawBackground(double t);
            public abstract double End { get; }
            public virtual void MaskVirtual(double t) { }
        }

        internal delegate int PixFn(double u, double v);

        static Scene MakeScene()
        {
            rng = new Random(Seed);
            switch (Style)
            {
                case "aurora": return new Aurora();
                case "vortex": return new Vortex();
                case "storm": return new Storm();
                case "iris": return new Iris();
                case "sunset": return new Sunset();
                case "shutter": return new Shutter();
                case "cooldown": return new Cooldown();
                default: return new Peaks();
            }
        }

        // ---- scaling --------------------------------------------------------
        internal static bool Resize(int c, int r)
        {
            if (c == cols && r == rows) return false;
            cols = c; rows = r;
            SW = c; SH = (r - 1) * 2;
            sc = Math.Min((double)SW / VW, (double)SH / VH);
            offX = (SW - VW * sc) / 2.0; offY = (SH - VH * sc) / 2.0;
            spix = new byte[SW * SH];
            mapX = new int[SW]; mapY = new int[SH];
            for (int x = 0; x < SW; x++) { int m = (int)Math.Floor((x + 0.5 - offX) / sc); mapX[x] = (m >= 0 && m < VW) ? m : -1; }
            for (int y = 0; y < SH; y++) { int m = (int)Math.Floor((y + 0.5 - offY) / sc); mapY[y] = (m >= 0 && m < VH) ? m : -1; }
            prevKey = new int[c * (r - 1)];
            fullRedraw = true;
            return true;
        }

        internal static uint Hash(int x, int y)
        {
            uint h = (uint)(x * 374761393 + y * 668265263);
            h = (h ^ (h >> 13)) * 1274126177u;
            return h ^ (h >> 16);
        }

        static string Frame(Scene s, double t)
        {
            Array.Clear(vb, 0, vb.Length);
            s.DrawVirtual(t);
            s.MaskVirtual(t);
            s.DrawBackground(t);
            for (int y = 0; y < SH; y++)
            {
                int my = mapY[y]; if (my < 0) continue;
                int row = my * VW, o = y * SW;
                for (int x = 0; x < SW; x++)
                {
                    int mx = mapX[x]; if (mx < 0) continue;
                    byte c = vb[row + mx]; if (c != 0) spix[o + x] = c;
                }
            }
            // dissolve out over the last 0.5 s
            double d = (t - (s.End - 0.5)) / 0.5;
            if (d > 0)
            {
                uint lim = (uint)(Math.Min(1.0, d) * uint.MaxValue);
                for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++)
                    if (Hash(x, y >> 1) < lim) spix[y * SW + x] = 16;
            }
            return Emit(t);
        }

        static string Emit(double t)
        {
            StringBuilder sb = new StringBuilder(cols * rows * 12);
            if (fullRedraw)
            {
                sb.Append(CSI).Append("0m").Append(CSI).Append("2J");
                for (int i = 0; i < prevKey.Length; i++) prevKey[i] = -1;
                fullRedraw = false;
            }
            int curFg = -1, curBg = -1, curR = -1, curC = -1;
            int prows = rows - 1;
            for (int r = 0; r < prows; r++)
            {
                int o0 = (r * 2) * SW, o1 = o0 + SW;
                for (int c = 0; c < cols; c++)
                {
                    int top = spix[o0 + c], bot = spix[o1 + c];
                    int key = (top << 8) | bot;
                    int ci = r * cols + c;
                    if (prevKey[ci] == key) continue;
                    prevKey[ci] = key;
                    if (curR != r || curC != c) sb.Append(CSI).Append(r + 1).Append(';').Append(c + 1).Append('H');
                    if (top == bot)
                    {
                        if (curBg != top) { sb.Append(CSI).Append("48;5;").Append(top).Append('m'); curBg = top; }
                        sb.Append(' ');
                    }
                    else
                    {
                        if (curFg != top) { sb.Append(CSI).Append("38;5;").Append(top).Append('m'); curFg = top; }
                        if (curBg != bot) { sb.Append(CSI).Append("48;5;").Append(bot).Append('m'); curBg = bot; }
                        sb.Append('\u2580');
                    }
                    curR = r; curC = c + 1;
                }
            }
            // ticker (text row, full width minus last cell)
            int tw = Math.Max(1, cols - 1);
            while (tickSrc.Length < Ticker.Length + tw) tickSrc += Ticker;
            int off = Ticker.Length > 0 ? (int)(t * 20) % Ticker.Length : 0;
            sb.Append(CSI).Append(rows).Append(";1H").Append(CSI).Append("48;5;234m").Append(CSI).Append("38;5;").Append(accent).Append('m');
            sb.Append(tickSrc.Substring(off, tw)).Append(CSI).Append("0m");
            return sb.ToString();
        }

        // ---- entry points -------------------------------------------------------
        public static void Run()
        {
            EnableVT();
            Abort = false;
            Encoding oldEnc = null; bool oldCC = false;
            try { oldEnc = Console.OutputEncoding; } catch { }
            try { oldCC = Console.TreatControlCAsInput; } catch { }
            TextWriter o = Console.Out;
            try
            {
                try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }
                try { Console.TreatControlCAsInput = true; } catch { }
                o = Console.Out;
                o.Write(CSI + "?1049h" + CSI + "?25l" + CSI + "2J");
                Scene s = MakeScene();
                cols = 0; rows = 0;
                Stopwatch sw = Stopwatch.StartNew();
                double last = 0;
                while (true)
                {
                    double t = sw.Elapsed.TotalSeconds;
                    double dt = Math.Min(0.05, t - last); last = t;
                    if (t >= s.End) break;
                    s.Step(t, dt);
                    int w = 0, h = 0;
                    try { w = Console.WindowWidth; h = Console.WindowHeight; } catch { }
                    if (w >= 20 && h >= 8)
                    {
                        Resize(w, h);
                        o.Write(Frame(s, t)); o.Flush();
                    }
                    bool skip = false;
                    try { while (Console.KeyAvailable) { if (Console.ReadKey(true).Key == ConsoleKey.Escape) Abort = true; skip = true; } } catch { }
                    if (skip) break;
                    int ms = 33 - (int)((sw.Elapsed.TotalSeconds - t) * 1000);
                    if (ms > 0) Thread.Sleep(ms);
                }
            }
            finally
            {
                o.Write(CSI + "0m" + CSI + "2J" + CSI + "?25h" + CSI + "?1049l"); o.Flush();
                try { Console.TreatControlCAsInput = oldCC; } catch { }
                try { if (oldEnc != null) Console.OutputEncoding = oldEnc; } catch { }
            }
        }

        // Test hook: simulate at 30 fps and write full ANSI frames at given times/sizes.
        public static void Dump(string dir, double[] times, int[] ws, int[] hs)
        {
            Scene s = MakeScene();
            double t = 0, dt = 1.0 / 30; int k = 0;
            while (k < times.Length && t < 60)
            {
                s.Step(t, dt);
                while (k < times.Length && t >= times[k] - 1e-9)
                {
                    cols = 0; Resize(ws[k], hs[k]);
                    File.WriteAllText(Path.Combine(dir, string.Format("f{0:000}.ans", k)), Frame(s, t));
                    k++;
                }
                t += dt;
            }
        }

        public static double SceneEnd()
        {
            Scene s = MakeScene(); double t = 0;
            while (t < 60 && t < s.End) { s.Step(t, 1.0 / 30); t += 1.0 / 30; }
            return s.End;
        }

        // ---- drawing helpers -----------------------------------------------------
        internal static void Px(int x, int y, int c)
        {
            if (x >= 0 && y >= 0 && x < VW && y < VH) vb[y * VW + x] = (byte)c;
        }

        internal static byte Ink(char ch, int body, int acc)
        {
            switch (ch)
            {
                case '#': return (byte)body;
                case '+': return (byte)acc;
                case 'o': return 231;
                case 'x': return 16;
                case 'g': return 178;
                default: return 0;
            }
        }

        internal static void Blit(string[] spr, int x, int y, int body, int acc)
        {
            for (int r = 0; r < spr.Length; r++)
                for (int c = 0; c < spr[r].Length; c++)
                {
                    byte k = Ink(spr[r][c], body, acc);
                    if (k != 0) Px(x + c, y + r, k);
                }
        }

        internal static void BlitSolid(string[] spr, int x, int y, int col)
        {
            for (int r = 0; r < spr.Length; r++)
                for (int c = 0; c < spr[r].Length; c++)
                    if (spr[r][c] != '.') Px(x + c, y + r, col);
        }

        // 3x5 font
        static readonly Dictionary<char, string[]> F3 = new Dictionary<char, string[]>();
        // 5x7 font for the logo
        static readonly Dictionary<char, string[]> F5 = new Dictionary<char, string[]>();

        static void G3(char c, string a, string b, string d, string e, string f) { F3[c] = new string[] { a, b, d, e, f }; }
        static void G5(char c, params string[] r) { F5[c] = r; }

        static Intro()
        {
            G3('A', ".#.", "#.#", "###", "#.#", "#.#"); G3('B', "##.", "#.#", "##.", "#.#", "##.");
            G3('C', ".##", "#..", "#..", "#..", ".##"); G3('D', "##.", "#.#", "#.#", "#.#", "##.");
            G3('E', "###", "#..", "##.", "#..", "###"); G3('F', "###", "#..", "##.", "#..", "#..");
            G3('G', ".##", "#..", "#.#", "#.#", ".##"); G3('H', "#.#", "#.#", "###", "#.#", "#.#");
            G3('I', "###", ".#.", ".#.", ".#.", "###"); G3('J', "..#", "..#", "..#", "#.#", ".#.");
            G3('K', "#.#", "#.#", "##.", "#.#", "#.#"); G3('L', "#..", "#..", "#..", "#..", "###");
            G3('M', "#.#", "###", "###", "#.#", "#.#"); G3('N', "##.", "#.#", "#.#", "#.#", "#.#");
            G3('O', ".#.", "#.#", "#.#", "#.#", ".#."); G3('P', "##.", "#.#", "##.", "#..", "#..");
            G3('Q', ".#.", "#.#", "#.#", "##.", ".##"); G3('R', "##.", "#.#", "##.", "#.#", "#.#");
            G3('S', ".##", "#..", ".#.", "..#", "##."); G3('T', "###", ".#.", ".#.", ".#.", ".#.");
            G3('U', "#.#", "#.#", "#.#", "#.#", "###"); G3('V', "#.#", "#.#", "#.#", "#.#", ".#.");
            G3('W', "#.#", "#.#", "###", "###", "#.#"); G3('X', "#.#", "#.#", ".#.", "#.#", "#.#");
            G3('Y', "#.#", "#.#", ".#.", ".#.", ".#."); G3('Z', "###", "..#", ".#.", "#..", "###");
            G3('0', "###", "#.#", "#.#", "#.#", "###"); G3('1', ".#.", "##.", ".#.", ".#.", "###");
            G3('2', "##.", "..#", ".#.", "#..", "###"); G3('3', "##.", "..#", ".#.", "..#", "##.");
            G3('4', "#.#", "#.#", "###", "..#", "..#"); G3('5', "###", "#..", "##.", "..#", "##.");
            G3('6', ".##", "#..", "###", "#.#", "###"); G3('7', "###", "..#", ".#.", ".#.", ".#.");
            G3('8', "###", "#.#", "###", "#.#", "###"); G3('9', "###", "#.#", "###", "..#", "##.");
            G3(' ', "...", "...", "...", "...", "..."); G3('/', "..#", "..#", ".#.", "#..", "#..");
            G3('-', "...", "...", "###", "...", "..."); G3(':', "...", ".#.", "...", ".#.", "...");
            G3('.', "...", "...", "...", "...", ".#.");

            G5('R', "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#");
            G5('T', "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..");
            G5('X', "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#");
            G5('0', ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###.");
            G5('1', "..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###.");
            G5('2', ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####");
            G5('3', "####.", "....#", "....#", ".###.", "....#", "....#", "####.");
            G5('4', "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#.");
            G5('5', "#####", "#....", "####.", "....#", "....#", "#...#", ".###.");
            G5('6', ".###.", "#....", "#....", "####.", "#...#", "#...#", ".###.");
            G5('7', "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#...");
            G5('8', ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###.");
            G5('9', ".###.", "#...#", "#...#", ".####", "....#", "....#", ".###.");
            G5('W', "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#");
            G5('A', ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#");
            G5('C', ".###.", "#...#", "#....", "#....", "#....", "#...#", ".###.");
            G5('P', "####.", "#...#", "#...#", "####.", "#....", "#....", "#....");
            G5(' ', "...", "...", "...", "...", "...", "...", "...");
        }

        internal static int Text3W(string s) { return Math.Max(0, s.Length * 4 - 1); }

        internal static void Text3(string s, int x, int y, int col)
        {
            s = s.ToUpperInvariant();
            for (int i = 0; i < s.Length; i++)
            {
                string[] g;
                if (!F3.TryGetValue(s[i], out g)) g = F3[' '];
                for (int r = 0; r < 5; r++) for (int c = 0; c < 3; c++)
                    if (g[r][c] == '#') Px(x + i * 4 + c, y + r, col);
            }
        }

        // ---- the logo ("RTX " + match) -------------------------------------------
        internal static bool[,] logoMask;
        internal static int logoW;

        internal static void BuildLogo()
        {
            string word = "RTX ";
            foreach (char ch in Match.ToUpperInvariant()) if (F5.ContainsKey(ch) && ch != ' ') word += ch;
            BuildLogo(word);
        }

        internal static void BuildLogo(string word)
        {
            List<string[]> gl = new List<string[]>();
            foreach (char ch in word) if (F5.ContainsKey(ch)) gl.Add(F5[ch]);
            int w = 0;
            for (int i = 0; i < gl.Count; i++) w += gl[i][0].Length + (i < gl.Count - 1 ? 1 : 0);
            logoW = w; logoMask = new bool[7, w];
            int x0 = 0;
            for (int i = 0; i < gl.Count; i++)
            {
                for (int r = 0; r < 7; r++) for (int c = 0; c < gl[i][r].Length; c++)
                    logoMask[r, x0 + c] = gl[i][r][c] == '#';
                x0 += gl[i][0].Length + 1;
            }
        }

        // colOff: per-column vertical offset (may be null)
        internal static void DrawLogo(int x0, int y0, int[] colOff, int baseCol, int shineCol, double shinePos, int shadowCol, int visCols = int.MaxValue, int minCol = 0)
        {
            for (int pass = 0; pass < 2; pass++)
                for (int c = 0; c < logoW; c++)
                {
                    if (c >= visCols || c < minCol) continue;
                    int oy = colOff == null ? 0 : colOff[c];
                    for (int r = 0; r < 7; r++)
                    {
                        if (!logoMask[r, c]) continue;
                        if (pass == 0) { Px(x0 + c + 1, y0 + r + oy + 1, shadowCol); continue; }
                        double sh = c - r - shinePos;
                        Px(x0 + c, y0 + r + oy, (sh >= 0 && sh < 4) ? shineCol : baseCol);
                    }
                }
        }

        internal static void Subtitle(double t0, double t, int y, int col1, int col2)
        {
            Subtitle(t0, t, y, col1, col2, "POWER LIMIT", null);
        }

        internal static void Subtitle(double t0, double t, int y, int col1, int col2, string l1, string l2)
        {
            if (l2 == null) l2 = Watts + " W" + (NGpu > 0 ? " X" + NGpu : "");
            int n = (int)Math.Floor((t - t0) / 0.045);
            if (n <= 0) return;
            string a = l1.Substring(0, Math.Min(n, l1.Length));
            Text3(a, (VW - Text3W(l1)) / 2, y, col1);
            int n2 = n - l1.Length - 3;
            if (n2 > 0) Text3(l2.Substring(0, Math.Min(n2, l2.Length)), (VW - Text3W(l2)) / 2, y + 7, col2);
        }

        internal static double Clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

        internal static double Bounce(double p)
        {
            p = Clamp01(p);
            if (p < 1 / 2.75) return 7.5625 * p * p;
            if (p < 2 / 2.75) { p -= 1.5 / 2.75; return 7.5625 * p * p + 0.75; }
            if (p < 2.5 / 2.75) { p -= 2.25 / 2.75; return 7.5625 * p * p + 0.9375; }
            p -= 2.625 / 2.75; return 7.5625 * p * p + 0.984375;
        }

        internal static double Rr(double a, double b) { return a + (b - a) * rng.NextDouble(); }

        internal static int Lvl(double n) { int k = n <= 0 ? 0 : (int)Math.Floor(n * 9); return k > 8 ? 8 : k; }

        // Paint the whole screen background: f gets canvas coordinates (may fall outside 0..VW/0..VH in the letterbox).
        internal static void Paint(PixFn f)
        {
            for (int y = 0; y < SH; y++)
            {
                double v = (y + 0.5 - offY) / sc; int o = y * SW;
                for (int x = 0; x < SW; x++) spix[o + x] = (byte)f((x + 0.5 - offX) / sc, v);
            }
        }

        internal delegate bool HideFn(int x, int y);

        // Erase canvas pixels for which hide(x,y) is true (used by closing masks)
        internal static void MaskVB(HideFn hide)
        {
            for (int y = 0; y < VH; y++) for (int x = 0; x < VW; x++)
                if (vb[y * VW + x] != 0 && hide(x, y)) vb[y * VW + x] = 0;
        }

        // Dim factor for a soft panel behind the logo (same look as the original plasma intro)
        internal static double Panel(double u, double v, double x0, double x1, double y0, double y1, double a)
        {
            if (u < x0 || u > x1 || v < y0 || v > y1) return 1;
            double fe = Math.Min(Math.Min(u - x0, x1 - u) / 5.0, Math.Min(v - y0, y1 - v) / 3.0);
            if (fe > 1) fe = 1;
            return 1 - a * (fe + 0.25) / 1.25;
        }

        // ---- particles --------------------------------------------------------------
        internal class Part { public double x, y, vx, vy, life, max; public int col; }
        internal static readonly List<Part> parts = new List<Part>();

        internal static void Burst(double x, double y, int n, double spd, int[] cols, double life)
        {
            for (int i = 0; i < n; i++)
            {
                double a = rng.NextDouble() * Math.PI * 2, v = spd * (0.3 + 0.7 * rng.NextDouble());
                Part p = new Part();
                p.x = x; p.y = y; p.vx = Math.Cos(a) * v; p.vy = Math.Sin(a) * v - spd * 0.25;
                p.max = p.life = life * (0.5 + 0.5 * rng.NextDouble());
                p.col = cols[rng.Next(cols.Length)];
                parts.Add(p);
            }
        }

        internal static void StepParts(double dt)
        {
            for (int i = parts.Count - 1; i >= 0; i--)
            {
                Part p = parts[i];
                p.vy += 26 * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt;
                if (p.life <= 0) parts.RemoveAt(i);
            }
        }

        internal static void DrawParts()
        {
            foreach (Part p in parts)
                Px((int)Math.Round(p.x), (int)Math.Round(p.y), p.life / p.max < 0.35 ? 240 : p.col);
        }
    }

    // =================================================================================
    //  Scene toolkit shared by all plasma scenes
    // =================================================================================
    internal abstract class PlasmaScene : Intro.Scene
    {
        protected const int VW = Intro.VW, VH = Intro.VH;
        protected const double TAU = Math.PI * 2;
        protected int[] off;
        protected double Dur = 7.0;

        public override double End { get { return Dur; } }
        public override void Step(double t, double dt) { }

        // global fade in / fade out of the field
        protected double G(double t) { return Intro.Clamp01(t / 0.8) * Intro.Clamp01((End - 0.3 - t) / 0.6); }

        protected int LogoX() { return (VW - Intro.logoW) / 2; }

        protected static int Pick(int n) { return Intro.rng.Next(n); }
    }

    // =================================================================================
    //  OPENING 1  Peaks: seeded field whose peaks are clipped at Watts/Stock (throttle plateau)
    // =================================================================================
    internal class Peaks : PlasmaScene
    {
        double k1, a1, k2, a2, k3, k4, a3, k5, a5, cx0, cy0, h1, h2, p1, p2, cap;
        int[] pal; int thr;

        static readonly int[][] Pals = {
            new int[] { 16, 22, 22, 28, 34, 35, 41, 77, 120 },
            new int[] { 16, 17, 17, 18, 24, 25, 31, 38, 87 },
            new int[] { 16, 53, 53, 54, 55, 91, 128, 170, 213 } };
        static readonly int[] Thr = { 214, 209, 222 };
        static readonly int[] Hi = { 120, 87, 213 };

        double R(double a, double b) { return Intro.Rr(a, b); }

        public Peaks()
        {
            Random g = Intro.rng;
            int pi = g.Next(3); pal = Pals[pi]; thr = Thr[pi]; Intro.accent = Hi[pi];
            k1 = R(1.2, 2.6); a1 = R(0.9, 1.6); k2 = R(1.0, 2.0); a2 = -R(0.7, 1.4);
            k3 = R(1.0, 3.0) * (g.NextDouble() < 0.5 ? -1 : 1); k4 = R(1.0, 2.4); a3 = R(0.9, 1.6);
            k5 = R(2.5, 5.0); a5 = R(1.4, 2.4); cx0 = R(0.2, 0.8); cy0 = R(0.2, 0.8);
            h1 = R(0.35, 0.65); h2 = R(0.55, 1.05); p1 = R(0, 6.28); p2 = R(0, 6.28);
            cap = Math.Max(0.5, Math.Min(0.97, Intro.Watts / Intro.Stock));
            Intro.BuildLogo();
            off = new int[Intro.logoW];
            Dur = 7.5;
        }

        int LogoXs(double t)
        {
            double p = Intro.Clamp01((t - 0.5) / 1.5), e = 1 - Math.Pow(1 - p, 3);
            int lt = LogoX();
            return (int)Math.Round(lt + (VW - lt + 2) * (1 - e));
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5 || G(t) < 0.3) return;
            double amp = 2.0 * Intro.Clamp01((2.9 - t) / 0.9);
            double wp = (t - 4.0) / 1.3 * (Intro.logoW + 16) - 8;
            for (int c = 0; c < off.Length; c++)
            {
                double o = amp * Math.Sin(c * 0.45 - t * 7);
                if (t > 4.0 && t < 5.3) { double d = (c - wp) / 3.0; o -= 1.4 * Math.Exp(-d * d); }
                off[c] = (int)Math.Round(o);
            }
            double g = G(t);
            int b = g > 0.7 ? 252 : (g > 0.45 ? 245 : 240), s = g > 0.7 ? 231 : 250;
            Intro.DrawLogo(LogoXs(t), 13, off, b, s, ((t - 2.3) * 40) % (Intro.logoW + 50) - 20, 235);
            if (g > 0.5) Intro.Subtitle(2.2, t, 24, 250, thr);
        }

        public override void DrawBackground(double t)
        {
            byte[] sp = Intro.spix; int SW = Intro.SW, SH = Intro.SH;
            double sc = Intro.sc, ox = Intro.offX, oy = Intro.offY, g = G(t);
            double hx = 0.5 + 0.36 * Math.Sin(t * h1 + p1), hy = 0.5 + 0.34 * Math.Sin(t * h2 + p2);
            double dimA = 0.8 * Intro.Clamp01((t - 0.6) / 1.2);
            double bx0 = LogoXs(t) - 6, bx1 = LogoXs(t) + Intro.logoW + 6, by0 = 9, by1 = 38;
            for (int y = 0; y < SH; y++)
            {
                double v = (y + 0.5 - oy) / sc, Y = v / VH;
                double sy = Math.Sin(Y * TAU * k2 + t * a2);
                double qy = (Y - hy) / 0.30, gy = Math.Exp(-qy * qy) * 0.55;
                double uy = Y * 2 - 1;
                for (int x = 0; x < SW; x++)
                {
                    double u = (x + 0.5 - ox) / sc, X = u / VW;
                    double dx = X - cx0, dy = (Y - cy0) * VH / VW;
                    double s = Math.Sin(X * TAU * k1 + t * a1) + sy
                             + Math.Sin((X * k3 + Y * k4) * TAU + t * a3)
                             + Math.Sin(Math.Sqrt(dx * dx + dy * dy) * TAU * k5 - t * a5);
                    double qx = (X - hx) / 0.17;
                    double ux = X * 2 - 1;
                    double n = (0.36 + 0.24 * s + Math.Exp(-qx * qx) * gy) * (1 - 0.38 * (ux * ux * 0.8 + uy * uy)) * g;
                    n *= Intro.Panel(u, v, bx0, bx1, by0, by1, dimA);
                    int k = n >= cap ? -1 : (n <= 0 ? 0 : (int)Math.Floor(n / cap * 9));
                    if (k > 8) k = 8;
                    sp[y * SW + x] = (byte)(k < 0 ? thr : pal[k]);
                }
            }
        }
    }

    // =================================================================================
    //  OPENING 2  Aurora: rippling vertical light curtains, logo scans in left to right
    // =================================================================================
    internal class Aurora : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 17, 23, 29, 35, 41, 84, 183, 219 },     // green into pink
            new int[] { 16, 17, 18, 19, 25, 61, 99, 141, 183 },     // blue into violet
            new int[] { 16, 23, 29, 30, 36, 72, 114, 186, 229 } };  // teal into gold
        static readonly int[] Acc = { 84, 141, 186 };
        int[] pal; double k, sp, wr;

        public Aurora()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            k = Intro.Rr(1.6, 3.2); sp = Intro.Rr(0.5, 0.95); wr = Intro.Rr(0.7, 1.3);
            Intro.BuildLogo(); off = new int[Intro.logoW];
            Dur = 7.0;
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.6 || G(t) < 0.3) return;
            for (int c = 0; c < off.Length; c++) off[c] = (int)Math.Round(1.1 * Math.Sin(c * 0.3 - t * 3.2));
            int vis = (int)((t - 0.7) * 22);
            Intro.DrawLogo(LogoX(), 13, off, 252, 231, ((t - 2.4) * 40) % (Intro.logoW + 50) - 20, 235, vis);
            if (t > 2.0) Intro.Subtitle(2.0, t, 24, 250, Intro.accent);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), dimA = 0.75 * Intro.Clamp01((t - 0.6) / 1.0);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, Y = v / VH;
                double w = Math.Sin(Y * TAU * 0.9 + t * 0.7) * wr + Math.Sin(X * TAU * 0.6 - t * 0.4) * 0.6;
                double c1 = Math.Sin(X * TAU * k + w + t * sp);
                double c2 = Math.Sin(X * TAU * k * 1.7 - w * 1.3 - t * sp * 1.3 + 1.7);
                double vert = Intro.Clamp01(1.2 - Y * 1.1);
                double n = (0.5 + 0.28 * c1 + 0.18 * c2) * (0.25 + 0.85 * vert) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 9, 38, dimA);
                int lv = Intro.Lvl(n);
                if (lv <= 1 && (Intro.Hash((int)Math.Floor(u * 2.5), (int)Math.Floor(v * 2.5)) % 173) == 0) return 245;
                return pal[lv];
            });
        }
    }

    // =================================================================================
    //  OPENING 3  Vortex: a spiral galaxy of plasma, logo rises from the bottom
    // =================================================================================
    internal class Vortex : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 52, 88, 124, 160, 166, 208, 214, 229 },   // ember
            new int[] { 16, 53, 89, 125, 161, 168, 213, 159, 231 },   // magenta into cyan
            new int[] { 16, 22, 28, 64, 70, 106, 148, 190, 231 } };   // toxic
        static readonly int[] Acc = { 214, 213, 190 };
        int[] pal; int arms; double sw, w;

        public Vortex()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            arms = 2 + Pick(3); sw = Intro.Rr(2.0, 4.0) * (Pick(2) == 0 ? 1 : -1); w = Intro.Rr(1.6, 2.6);
            Intro.BuildLogo(); off = new int[Intro.logoW];
            Dur = 7.0;
        }

        int LogoY(double t)
        {
            double p = Intro.Clamp01((t - 0.5) / 1.6), e = 1 - Math.Pow(1 - p, 3);
            return 13 + (int)Math.Round((1 - e) * 36);
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5 || G(t) < 0.3) return;
            double amp = 1.6 * Intro.Clamp01((3.4 - t) / 1.4);
            for (int c = 0; c < off.Length; c++) off[c] = (int)Math.Round(amp * Math.Sin(c * 0.5 - t * 6));
            Intro.DrawLogo(LogoX(), LogoY(t), off, 252, 231, ((t - 2.6) * 40) % (Intro.logoW + 50) - 20, 235);
            if (t > 2.6) Intro.Subtitle(2.6, t, 24, 250, Intro.accent);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), dimA = 0.8 * Intro.Clamp01((t - 1.2) / 1.0);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            double cx = 0.5 + 0.10 * Math.Sin(t * 0.5), cy = 0.5 + 0.08 * Math.Cos(t * 0.4);
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, Y = v / VH;
                double dx = X - cx, dy = (Y - cy) * VH / VW;
                double r = Math.Sqrt(dx * dx + dy * dy), a = Math.Atan2(dy, dx);
                double n = 0.40 + 0.26 * Math.Sin(a * arms + r * TAU * sw - t * w)
                         + 0.14 * Math.Sin(r * TAU * 2.6 - t * 1.8)
                         + 0.55 * Math.Exp(-(r / 0.10) * (r / 0.10));
                n *= (1.05 - 0.9 * r * r) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 9, 38, dimA);
                return pal[Intro.Lvl(n)];
            });
        }
    }

    // =================================================================================
    //  OPENING 4  Storm: interference of three drifting sources, lightning flashes, logo drops in
    // =================================================================================
    internal class Storm : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 17, 18, 24, 27, 33, 39, 81, 231 },        // electric blue
            new int[] { 16, 53, 54, 55, 92, 99, 135, 177, 231 },      // violet
            new int[] { 16, 52, 88, 124, 160, 196, 203, 217, 231 } }; // red
        static readonly int[] Acc = { 81, 177, 203 };
        int[] pal; double kk; double[] px = new double[3], py = new double[3], fa = new double[3], fb = new double[3], ph = new double[3];
        double[] ft = new double[3];

        public Storm()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            kk = Intro.Rr(3.0, 5.0);
            for (int i = 0; i < 3; i++)
            {
                fa[i] = Intro.Rr(0.3, 0.8); fb[i] = Intro.Rr(0.3, 0.8); ph[i] = Intro.Rr(0, 6.28);
                px[i] = Intro.Rr(0.15, 0.4); py[i] = Intro.Rr(0.15, 0.35);
            }
            ft[0] = Intro.Rr(1.4, 2.0); ft[1] = Intro.Rr(2.9, 3.8); ft[2] = Intro.Rr(4.5, 5.5);
            Intro.BuildLogo(); off = new int[Intro.logoW];
            Dur = 7.0;
        }

        double Flash(double t)
        {
            double f = 0;
            for (int i = 0; i < 3; i++)
                if (t >= ft[i]) f += Math.Exp(-(t - ft[i]) * 6) * (0.65 + 0.35 * Math.Sin((t - ft[i]) * 60));
            return Intro.Clamp01(f);
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5 || G(t) < 0.3) return;
            int ly = (int)Math.Round(-9 + 22 * Intro.Bounce((t - 0.5) / 1.0));
            if (Flash(t) > 0.4) ly += ((int)(t * 30) % 2 == 0) ? 1 : -1;
            for (int c = 0; c < off.Length; c++) off[c] = 0;
            Intro.DrawLogo(LogoX(), ly, off, 252, 231, ((t - 2.0) * 40) % (Intro.logoW + 50) - 20, 235);
            if (t > 2.2) Intro.Subtitle(2.2, t, 24, 250, Intro.accent);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), dimA = 0.7 * Intro.Clamp01((t - 0.6) / 1.0), fl = Flash(t);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            double[] sx = new double[3], sy = new double[3];
            for (int i = 0; i < 3; i++)
            {
                sx[i] = 0.5 + px[i] * Math.Sin(t * fa[i] + ph[i]) * 2;
                sy[i] = 0.5 + py[i] * Math.Sin(t * fb[i] + ph[i] * 1.7) * 2;
            }
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, Y = v / VH, s = 0;
                for (int i = 0; i < 3; i++)
                {
                    double dx = X - sx[i], dy = (Y - sy[i]) * VH / VW;
                    double d = Math.Sqrt(dx * dx + dy * dy);
                    s += Math.Sin(d * TAU * kk * (0.85 + 0.15 * i) - t * (1.6 + 0.5 * i));
                }
                double ux = X * 2 - 1, uy = Y * 2 - 1;
                double n = (0.32 + 0.16 * s + 0.42 * fl) * (1 - 0.3 * (ux * ux * 0.8 + uy * uy)) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 9, 38, dimA);
                return pal[Intro.Lvl(n)];
            });
        }
    }

    // =================================================================================
    //  CLOSING 1  Iris: gold ripple field, WATTCAP locks in, a circular iris snaps shut
    // =================================================================================
    internal class Iris : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 58, 94, 136, 172, 214, 220, 226, 230 },   // gold
            new int[] { 16, 53, 89, 125, 161, 204, 211, 218, 225 },   // rose
            new int[] { 16, 23, 30, 37, 44, 51, 87, 123, 159 } };     // cyan
        static readonly int[] Acc = { 220, 211, 87 };
        int[] pal; double k, a;
        const double T0 = 3.9, T1 = 5.7;

        public Iris()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            k = Intro.Rr(1.8, 2.8); a = Intro.Rr(2.4, 3.4);
            Intro.BuildLogo("WATTCAP"); off = new int[Intro.logoW];
            Dur = 6.2;
        }

        double Radius(double t)
        {
            double p = Intro.Clamp01((t - T0) / (T1 - T0));
            return p <= 0 ? -1 : 120 * Math.Pow(1 - p, 2.2);
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5) return;
            double cx = Intro.logoW / 2.0, half = (t - 0.5) * 10;
            for (int c = 0; c < off.Length; c++) off[c] = 0;
            Intro.DrawLogo(LogoX(), 13, off, 252, 231, ((t - 1.6) * 40) % (Intro.logoW + 50) - 20, 235,
                (int)Math.Ceiling(cx + half), (int)Math.Floor(cx - half));
            if (t > 1.8) Intro.Subtitle(1.8, t, 24, 250, Intro.accent, "LIMIT LOCKED", null);
            double R = Radius(t);
            if (R >= 0) Intro.MaskVB(delegate(int x, int y) { double dx = x + 0.5 - 40, dy = y + 0.5 - 22.5; return Math.Sqrt(dx * dx + dy * dy) > R; });
        }

        public override void DrawBackground(double t)
        {
            double g = Intro.Clamp01(t / 0.6), R = Radius(t), dimA = 0.75 * Intro.Clamp01((t - 0.5) / 1.0);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            Intro.Paint(delegate(double u, double v)
            {
                double dx = u - 40, dy = v - 22.5, d = Math.Sqrt(dx * dx + dy * dy);
                if (R >= 0)
                {
                    if (d > R) return 16;
                    if (d > R - 1.5) return 231;
                }
                double X = u / VW, Y = v / VH;
                double n = 0.42 + 0.20 * Math.Sin(d / 45.0 * TAU * k - t * a)
                         + 0.14 * Math.Sin((X * 1.5 + Y * 2.0) * TAU + t * 1.3)
                         + 0.10 * Math.Sin(X * TAU * 3 - t);
                n *= (1 - 0.35 * (d / 45.0) * (d / 45.0)) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 9, 38, dimA);
                return pal[Intro.Lvl(n)];
            });
        }
    }

    // =================================================================================
    //  CLOSING 2  Sunset: retro striped sun sinks behind the horizon over a wave grid
    // =================================================================================
    internal class Sunset : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 53, 89, 125, 161, 197, 203, 209, 222 },   // sunset
            new int[] { 16, 17, 54, 91, 127, 163, 207, 123, 159 },    // synthwave
            new int[] { 16, 23, 29, 35, 41, 78, 120, 157, 194 } };    // mint
        static readonly int[] Acc = { 209, 207, 120 };
        int[] pal;
        const double HZ = 29, SR = 13;

        public Sunset()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            Intro.BuildLogo("WATTCAP"); off = new int[Intro.logoW];
            Dur = 6.6;
        }

        double SunY(double t) { return 17 + 5.0 * t; }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5 || G(t) < 0.3) return;
            for (int c = 0; c < off.Length; c++) off[c] = (int)Math.Round(0.9 * Math.Sin(c * 0.4 - t * 2.5));
            Intro.DrawLogo(LogoX(), 6, off, 252, 231, ((t - 1.4) * 40) % (Intro.logoW + 50) - 20, 235, (int)((t - 0.5) * 24));
            if (t > 1.6) Intro.Subtitle(1.6, t, 16, 250, Intro.accent, "LIMIT LOCKED", null);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), cy = SunY(t);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6, dimA = 0.7 * Intro.Clamp01((t - 0.5) / 1.0);
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, lv;
                if (v >= HZ)
                {
                    if (v < HZ + 0.8) return pal[(int)Math.Round(7 * g)];
                    double q = v - HZ;
                    double band = Math.Sin(Math.Sqrt(q) * 7.0 - t * 3.0);
                    lv = 1.0 + (band > 0.55 ? 2.0 : 0.0) + 0.6 * Math.Sin(X * TAU * 6 + t * 2);
                    // sun reflection column
                    if (cy - SR < HZ && Math.Abs(u - 40) < 9 - q * 0.2 && band > -0.2) lv += 3.0;
                    return pal[Math.Max(0, Math.Min(8, (int)Math.Round(lv * g)))];
                }
                double dx = u - 40, dy = v - cy, dd = Math.Sqrt(dx * dx + dy * dy);
                lv = 1.2 + 1.6 * (1 - v / HZ) + 0.6 * Math.Sin(X * TAU * 3 + t * 0.8) + 3.0 * Math.Exp(-(dd / 22.0) * (dd / 22.0));
                if (dd <= SR)
                {
                    double fr = (v - (cy - SR)) / (2 * SR);
                    bool gap = fr > 0.5 && ((int)Math.Floor(v)) % 4 < (int)((fr - 0.5) * 9);
                    if (!gap) lv = 8 - fr * 5;
                }
                lv *= Intro.Panel(u, v, bx0, bx1, 4, 30, dimA);
                return pal[Math.Max(0, Math.Min(8, (int)Math.Round(lv * g)))];
            });
        }
    }

    // =================================================================================
    //  CLOSING 3  Shutter: cool plasma behind venetian-blind slats that snap shut top to bottom
    // =================================================================================
    internal class Shutter : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 17, 24, 31, 38, 44, 80, 123, 231 },       // ice
            new int[] { 16, 22, 28, 34, 70, 112, 154, 192, 231 },     // lime
            new int[] { 16, 52, 88, 124, 160, 196, 203, 210, 224 } }; // crimson
        static readonly int[] Acc = { 123, 154, 210 };
        int[] pal; double k1, k2, k3, a1, a2, a3;
        const double S0 = 3.2;

        public Shutter()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            k1 = Intro.Rr(1.5, 3.0); k2 = Intro.Rr(1.5, 3.0); k3 = Intro.Rr(1.0, 2.5);
            a1 = Intro.Rr(1.0, 1.8); a2 = Intro.Rr(0.8, 1.6); a3 = Intro.Rr(1.2, 2.0);
            Intro.BuildLogo("WATTCAP"); off = new int[Intro.logoW];
            Dur = 5.9;
        }

        // 0 open, 1 slat, 2 slat edge
        int Slat(double t, double v)
        {
            double j = Math.Floor(v / 3.0), jc = Math.Max(0, Math.Min(14, j)), f = v / 3.0 - j;
            double p = Intro.Clamp01((t - S0) / 1.1 - jc / 14.0 * 0.6);
            if (p <= 0) return 0;
            double ap = 1 - p, d = Math.Abs(f - 0.5) * 2;
            if (d < ap) return 0;
            return d < ap + 0.18 ? 2 : 1;
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5) return;
            for (int c = 0; c < off.Length; c++) off[c] = 0;
            Intro.DrawLogo(LogoX(), 13, off, 252, 231, ((t - 1.5) * 40) % (Intro.logoW + 50) - 20, 235, (int)((t - 0.5) * 24));
            if (t > 1.7) Intro.Subtitle(1.7, t, 24, 250, Intro.accent, "LIMIT LOCKED", null);
        }

        public override void MaskVirtual(double t)
        {
            if (t < S0) return;
            Intro.MaskVB(delegate(int x, int y) { return Slat(t, y + 0.5) != 0; });
        }

        public override void DrawBackground(double t)
        {
            double g = Intro.Clamp01(t / 0.6), dimA = 0.75 * Intro.Clamp01((t - 0.5) / 1.0);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            Intro.Paint(delegate(double u, double v)
            {
                if (t >= S0)
                {
                    int st = Slat(t, v);
                    if (st == 1) return ((int)Math.Floor(v)) % 2 == 0 ? 238 : 236;
                    if (st == 2) return 250;
                }
                double X = u / VW, Y = v / VH;
                double n = 0.42 + 0.20 * Math.Sin(X * TAU * k1 + t * a1) + 0.18 * Math.Sin(Y * TAU * k2 - t * a2)
                         + 0.16 * Math.Sin((X + Y) * TAU * k3 + t * a3);
                double ux = X * 2 - 1, uy = Y * 2 - 1;
                n *= (1 - 0.3 * (ux * ux * 0.8 + uy * uy)) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 9, 38, dimA);
                return pal[Intro.Lvl(n)];
            });
        }
    }

    // =================================================================================
    //  CLOSING 4  Cooldown: hot plasma cools front by front while the wattage counts down to the cap
    // =================================================================================
    internal class Cooldown : PlasmaScene
    {
        static readonly int[][] Hot = {
            new int[] { 16, 52, 88, 124, 160, 166, 208, 214, 229 },
            new int[] { 16, 53, 89, 125, 161, 204, 209, 215, 229 },
            new int[] { 16, 58, 94, 136, 172, 178, 214, 220, 230 } };
        static readonly int[][] Cold = {
            new int[] { 16, 17, 18, 24, 25, 31, 38, 45, 123 },
            new int[] { 16, 17, 54, 55, 61, 98, 105, 141, 189 },
            new int[] { 16, 22, 23, 29, 30, 36, 42, 49, 121 } };
        static readonly int[] Acc = { 45, 141, 49 };
        int[] hot, cold; double k1, k2, k3, k4, a1, a2, a3, a4;
        const double C0 = 1.0, C1 = 3.8;

        public Cooldown()
        {
            int v = Pick(3); hot = Hot[v]; cold = Cold[v]; Intro.accent = Acc[v];
            k1 = Intro.Rr(1.4, 2.6); k2 = Intro.Rr(1.4, 2.6); k3 = Intro.Rr(1.0, 2.2); k4 = Intro.Rr(2.0, 4.0);
            a1 = Intro.Rr(1.0, 1.8); a2 = Intro.Rr(0.8, 1.6); a3 = Intro.Rr(1.2, 2.0); a4 = Intro.Rr(1.4, 2.4);
            Dur = 6.6;
        }

        double P(double t) { double p = Intro.Clamp01((t - C0) / (C1 - C0)); return 1 - Math.Pow(1 - p, 2.2); }

        int Shown(double t) { return (int)Math.Round(Intro.Stock - (Intro.Stock - Intro.Watts) * P(t)); }

        public override void DrawVirtual(double t)
        {
            if (G(t) < 0.3) return;
            Intro.Text3("POWER NOW", (VW - Intro.Text3W("POWER NOW")) / 2, 5, 244);
            Intro.BuildLogo(Shown(t) + "W");
            int col = t < C0 ? 214 : (t < C1 ? 231 : ((int)(t * 8) % 2 == 0 && t < C1 + 0.8 ? 226 : Intro.accent));
            Intro.DrawLogo((VW - Intro.logoW) / 2, 13, null, col, 231, -99, 235);
            if (t > C1 + 0.2) Intro.Subtitle(C1 + 0.2, t, 24, 250, Intro.accent, "LIMIT SET", null);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), p = P(t), yf = -0.15 + 1.35 * p;
            double bx0 = 40 - 24, bx1 = 40 + 24, dimA = 0.7 * Intro.Clamp01(t / 0.8);
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, Y = v / VH;
                double dx = X - 0.5, dy = (Y - 0.5) * VH / VW, d = Math.Sqrt(dx * dx + dy * dy);
                double n = 0.40 + 0.18 * Math.Sin(X * TAU * k1 + t * a1) + 0.16 * Math.Sin(Y * TAU * k2 - t * a2)
                         + 0.14 * Math.Sin((X + Y) * TAU * k3 + t * a3) + 0.12 * Math.Sin(d * TAU * k4 - t * a4);
                n *= (1 - 0.6 * d * d) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 3, 39, dimA);
                double front = yf + 0.035 * Math.Sin(X * TAU * 3 + t * 2);
                if (p > 0 && p < 0.995 && Math.Abs(Y - front) < 0.022) return 231;
                return (Y < front ? cold : hot)[Intro.Lvl(n)];
            });
        }
    }
}
'@

$script:WattCapIcon = @'
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
369uiaPox52dc3R7e4eJ48lZouxAwrpkkOi5x2skC5/96UxK9ExEMktpTEtr3s6eM1+HYfUeXxX/rbe3V9Wdvzr21MiLh/y1iaPR
+QuXShCkXLJGzfQkQaL9cNQczQUneVxzY8T/vX7mJHp2RTKXsXYLFi1xDmJxclVfX19cs/AT4puXEKDmC8gdd9z4TBTHn0pnW9TC
xa8xSQw5PWMjraBUcvSc4XHHk4Y//U6V9uzMSPTsirr2z1twhGlr69BxGP39b/p+8euenh7d3PY3jt/TD9W/cOa5l/y/dDr7/i2b
X4y2bn7B13p6lhAo4Kq3+Xzz5pidBTvlEz8dCCQrmUTMnrMgXrz0aC8MK7dXC9vfcuSRR9qa6X/JHb+cTZfe3l755b335ryyvimV
Sp29ZdOGaOuWF/1kxcq9mRDy4IC10JIWPOUYGIN0MPOKPuvCnzV7vlm85CgdxfHTvosv6Otbvck5JyKyW2G9XKDvAO5bvXrUat5T
DauPL1i02J+/8IjYGJNMpTpNHEOloFh1DJeSSSBmkvDrMmho/pKjtTFmo7H2HX19qzf19vaqPQkf9sKr6+3tVStXrrQrVrx9sVHx
qlQ6ffrO/q3xlk0v6DiOROvps87vTMrvw3h7r5Rm3oLF8dz5i704ip4MJfq9+25dvW5P7f6E39irM/X2KlautMsvvDCfjtPf9P3g
vaXyGFs3vmBGR4e0IKhaxcV0IcO0RW0xLmstxhpyuTazcNFS1drWIWFYuVWZ6MN33rlmIz09mv9C+PBK4roaCQDOOu+STyjtr9RK
5wZ3bLP927dQrhSVICilG2bpMBkmB83P01qDc45UKmNnz5nvZs2Zr51z1hr3d7/pS/fCKrM3mt/47Vd6Lb29vbJy5Up75rkXv1Er
/TnPDy4xJmZocKcbHNhhyqUxbYwRkeTC6/0J08VfOFiQ6I7DOYdztrbaiXKZTNZ2dM2Wjs45KvADIhPdEdvo0/fcvroPEHp7pa6o
e4NXJZVmhp3Tfdk7xFMfF6RblKJcHGN0dNCNFQqmWilJHMe1KlRXswiHifDyqBfiCCLKeb52qSDjWnJtqq29Q7W0tCYLdRpzvzHx
1+/qu+m7MFEmrwT7II1eBSsb2aEzV1zyJu157xbhIqW8pUlYEhKGVeIoIopCbH2KzsN4WYgofD/A9338II3v+zjAmHgbsMYYVgWM
ru7r64vh1QsfJkEcu578tNMubktl9ZkGd4bW/knO2aMdzBckp+TQGIq2r7AOh7NjiOoX5Fljw8cQdXd1dOyuBx/s21k/bl8EX8ek
6WNvb69at26d7HpBy5YtC2hry7UGXV1KSKk4PuwZvgys5wlhFMex2TE09OLY+vXrq837a8Uc7KvgpxLS09Oju7u7PQ6RwadTDOnu
7vZqgp/0BnR/tMgy/r93P5xuJmAljOfZp9Ri/n8Xx2FKsmHdRwAAAABJRU5ErkJggolQTkcNChoKAAAADUlIRFIAAAEAAAABAAgG
AAAAXHKoZgAAV3hJREFUeJztvXmcHFd1t//ce6t6n10zWi1ZXmV5wcZ4kbA9AtvYhrBnyELyJgSy/CB78iYkhFcoIQtJIOQlCQmE
FwhJACuswdgBbDwgb9jG2IC825K1j6TZe6u6y++P6u7p6ekZjWQtPaN6/Gmrp7qquqq7z/ece+6590JMTExMTExMTExMzGmEONUX
cAJYjPcU0zq4U30Bx5OFaiwCEAMDA2JoaEgAbNq0yQJs2bLFntIri1nUbN68WW4B+u++WwL09fW5revXO7ZscSxAcVg4ArB5s+y/
+27Z19fntm7dambbbWBgQO0rFNrVpOeM0Qvn/mJaFqWi35LWmdL9928tzrbfwMCAGhoaEpXfqGUBCEJrG0jF6AcHBw11H+bAwIDa
PxasMDo8x2l3iRSy1+KuBOcJWIaQy5yLA4GY44dA4nCTAp4WQgiHexTLIaXkg0LZXfkRufPhh79WqD+mv7/fa3UxaEUBEAMDA7Lx
Q7vmla9bj7NXOeeudXAVzp2plMoIIUGAs1EE5pzD2tj4Y44/QgiklJXn0b/OOYzRBtiD4GHhxHeUJ+5Z2p3+fn2kOjAwoLZuXe+g
tZqoLSQAm2V//91ycHBQV7dc88qb1zvnvRrn3uicu8rzfOUAaw3OWpxzFoQVUiBACCEAhBBStKjgxixYBM4553AOiJ5HTkcKkEJK
pFQIITDWgHOPO7hNCfelZUuyD1TFYGBgQAHM1Yw9mbSAAGyWAwPbRfUDueqVr13qO/s658QvOtyVnvI86yxGa8AZIZWTQkghhHAO
Ya3GGEsYlLHWYIyhVCq2wo3FLCKccyQSSfxEEoBkMoVUEqU8hBCRMjjrrHUOnJJKCSVVRQzYjnBbrRWfu2/wa09UTlmNdE+pEJxK
OxH9/f2q6vE39L/mIiXkLzhnfl55/lJrLcZoAC2lFFJK6RwiCEqUS0UKhTylQp4gDNBhiDUa66aaATExx5tKnAkCPOWhlIefSJJK
pclkcySTKZKpNFJKnHPWGGvBKaWUkFKhtS4Lwa1I+Zl77vrvb0K1abDVAaekaXBKBKBy0wZg4ytuOl847w+BtyrPTxgdYo0xQkqh
lBLWOlEuFZgYHyM/OU6xmEeHIQ6HQCBE9KVE4X90OyJ2/zEniKpzmfrXUvU3SilS6QzZbBtt7Z2kM1mU8rDWWGuNE0Iqz/OjHJVz
3wQ+sO3ur90JUcKwvvl7sjjZplILey6/4YaOlEn+Do7fVsrr0GGAc2iplJJSiHK5xNjoMBPjoxQLeYzRCCEQQtYSMUDs7WNOLULU
jKiagHbOIqUkmcrQ1tZBR2c36UwWEM4YbQHheb6MxMN9Uij7V9vuvP0pqNQZnMRalpMmAPVe/5r+1/y0E2KL53nnhWGAtdZ4ni/B
iWKxwOGDBxgfH0aHYc3ghRBUsi8n65JjYo4JIQTOOZy1WGeRSpHLttPTt4xcth2pJFprAwjfT0hjzBiOvy1N7vvAww8/HNbbygm/
1pPxJtXwZuPGG1aIROKDUnk/7axFa6OVkkpKJSbGRzk0tI/J/DjWWJRSlQ8S4ox+zEKlKgbWGkCQTmfoWbKUzu5ehBBorbWUwvP8
BMboB4Szv7Xt7q8/UIkETnh14YkWALF582axZcsWu+Ha19wkFZ9UylsehmUDQni+L0uFAgeH9jI6cghnHbJm+LHRxywepoQgaiK0
tXfS27eCtvZOrDXOGGs83/Occxrr/vc9g7d9GKZHzifkuk7UiWGzrBY9bOi/5X1KepujogmjPU951joOHdzHoaH9aB2glI8QcZs+
ZvEjhKj0cAm6untZunwliUQKrQMjhJSe7wut9a1hvvTOBx+88/CJFIETIgDVC77mmtd0OV98Vil1UxgEFsDzfJnPT7Bv907y+fFq
P2ps+DGnFdXfvDGaRCLJshWr6epegjHGWetMIpHwjLVPWxO+9b7v3PHgieolOO4CUDX+y6+9aXlKeV/xPP+KICiHUkhfSMmhg/vY
v3cXzjmUUrHhx5zWCCGw1mKtoWfJUpavXIOUEq219v2E55wd0aF57f3bbr/nRIjAcRWA6gVuuO7mK6TyviKFWB6GWnue5xmt2bP7
eUZHDsVePyamgSghGJLJ5Fi1+izSmRw6DIxUSiGldka/897B2z9+vEVAHnmX+TEwMKCqxq+U9z8CsTwMQ+N5nlcq5nn+2ccZHTmE
5/lA3NaPianHOYfn+RSLeZ5/pmIrvq+stdYZo5TyP7ax/5ZfHhwc1NXxBMeD4xIBVMP+qvEDXVpr4/u+yucn2fHsExijUcqLDT8m
Zg6mmgSWVavPomfJUrQOnBDSKuUpY8JfOZ6RwPEQAAnYDRtu7BPJxI+kkL1ah8b3Eyqfn2Dns09grEHKuL0fEzM/BBDVDqw84yx6
epeiw9AJIazyPBXq8o33D/7Pt46HCLzYJoDA4a64/voemUx8TcpG438SYw0iNv6YmKMgshUpFXt2PcfhgwfwfF8454Q1xirhf+7q
a1915eDgoN68efOLsuEXdfDAwIBE4HyT+Jzn+VfoUGvP91U+P8GOZ5/EWI2QKi7fjYk5RqaJgOdLYwxCiB6l/P++6pWvXVqpFjxm
Oz7mA/v7+72tW7eaDf23vM/zkjcEQSn0PM8rFfLsePYJbGz8MTHHhaoIDB8ewvcTUmutpVJ9Sut/B9zAwMAxN+WPSQCqGf+rrrvl
RqW8zWFQNlIq35iQ3S88hzEaGRt/TMzxQQiElOzbvYN8fgLPU14YhNpLJG/YcO0t79u6davp7+/3juXUxyIAcuv69W7Dhhv7PCk+
46JZOIQQkj27dlAoTMbZ/piY44lzCCEx1rJ757NorVFKemFQNsr3/s+Ga26+/li7B49aAAYGBgRbtlgS3j8o5S81RlvP8+Whg/tq
/fyx8cfEHGcqlbOlUoG9u3dUJyUVOIRU6l82bnxdW2XPo2oOHJUA1Pr7+2/+Sd9LDIRBoD0vSvrt37sr9vwxMSeQarHQ6MghDh/a
j+f5UuvQKN8/23rBX27dutUMDAwclU0fzc4C4IYbBjqEUB+w1jiEkNZa9u3eQTRBbzwXV0zMiaQ6hubAvt2UinmU8qQOykYp71ev
ecVrLt+6das9mq7Bee/Y39+vtm7davLlyd/xPf8srY3xPE8ePriPfH4Cpbw46RcTczIQEq01+/fuIlqkBKSUnjH2g4Dbvn37vD3x
vARg8+bNcnBw0Fzd/6pzpJK/HYaBVUqpUjHPwaH98ai+mJiTiXMoz2N8fKQ6uE7pMDCe5/dv6H/NQKUpMK+E4LwEoKIoTiDfqzy/
w1rrpJTi4NA+tA5qq6TExMScTAQHD+ytTDcmhXMOgf3zgfUDifXr1zvmkRCcT6ggAXfdda9eZ6R8xDrjK+mJyYkxseO5J2Ljj4k5
RVSHEC9bsZqly1YRhoFJJJJK6/Bt9w5+/VPzmUnoiNbb398vARcK3qE8L4nDghOHhvZFYX+c+IuJOSU455BSMXzoAEFQRkqJjdYs
exdAJQqYkyNZrwDo7/+JHo39MUL0gqBUKojnnv7xPA6PiYk5kVSjgGjo8DK0Dq1SCmfd9fcM3nb3kaKAOSOA/v5+BbgQ80bl+33W
GiulEMMHD2BM3O0XE3OqqfQAMHxoCB1NNGqlVNI5+yvzOX5OAdi0aZMFpIN3WOucEJJyucT42Ei0Ok+c+Y+JObVUyoQLhTyTE2Mo
pZTWoUOK1/b3v3pZxfvP6qnnEgC5ZcsWe801t5wjhbzUmBCllBofHSbUwbTluWJiYk4hQiAEjA0fAhDOWespPxfCzVCL5JsyqxVX
kn9YJV6vPC+Bw1jrmBgfnVqmKyYm5tRTiQLy+QmCoIQQEhf9NwC1SL4pswpAdNBm6Zx7s7UWKaUolQoUCvl4qG9MTIshpSQMQ/KT
4yilpNEaibzm2mtvWl5ZbLRpM6CpAFRXKL3mmu+dI6W4zBjtpJRqcmKstkpvTExM6xCNyYeJsVGcc8I5a5TntVvlvQpmbwY0FYC7
7767Gv5vVMpP4Jx1zpGfGI/D/5iYVqSWDJwkDEOEVA7AOvsKgL6+vqZm21QAqjs73CYAIZUrl8sUi/mo8i8O/2NiWg4hBGEYUihM
IoWQxhpwXL1+/UBi69atTfMATQXg1ltvtevXDyRwYoOxBimELJeLaB2H/zExrUq02palVMgjhJTWGCelXNvZOb4WcM2GCTcTACmE
cB1L88uFYJWz1gkhRKmQxzkbC0BMTItSmZuPYsVWAauUSjjfuwRqg/qmMUMAqjOMSivWKqUyzjnnHKJYyMft/5iYVqaSB6hF61K6
qEbArQcYGho6sgBUd7LCXSKERAicMZowDCLvH7f/Y2JalmhsQMVeQTjncM5dAs0TgbPWAQjccgQgpLPWonVIPPgnJqb1qdrrlMMW
SwHRbHTgDAGoVg05Jy531iJABEE5TgDGxCwAokSgo1wqIoSQxhiA86655jWdzQqCZi/od05UT2itiaf8iolZMDisqR8B7LwgME2H
BDcKgHjf+97nrr56II1gZcXohW1+bExMTIsyZbPOSSFTIiVXAmzevHnuCCCaZHQsDayy1iKEEOVSIe4CjIlZAFS7AkulQqUkGKeU
Snu4VTCzK7BpE8DzfCcQ4dSW2PBjYhYWUzYbTd0nw2Z7zZoDcLjY6mNiFgnONbfneFaPmJjTmGNaUjhm4XKkNI6r/S/mdCAWgMWC
iJI/ovK8SrX3VgDGOIxxs2Z0HCAFKE/WNECI6Nh6YYiqy477HcScAmIBWICIirFXLdnZyLBNaLDGYa3DVUo+PE+CiPZJ5Xyy7T7O
uqZ5XSEEYWCYHA0jQQG0js4nBUglEFLg+RKlBFJGc9E5V33EqrDQiAVgASCEoLoAk7UOHVh0aDHaIVVkkJl2n86laXIdCTqXplmy
PA3A6vM7UJ7AakvXkhQdS5I44xAIqkO7Ii2wKCko5TVDewpIIVASdj07QSmvKeQ1e56fpFw0HNhTID8RUsxrjKlcgydJJGWDKMSR
QqsTC0ArIkBWPLw1jrCsCQOLAPyUontFhr41bSxbm6P3jBy9q7J0L8+Q7fBJZzyEBE9JcBZnIguUOGxoI4Otvc2UAETTSEJbR4Ll
a3LRMBAsL9nYixKR8DhjCQPL5FjI4QNFDu4tsu+FPHtfyLPn+Tz7dkfCYC14vsBPSDw/ejdnYzFoRWIBaBXqjN6ElmJRY40l3Z5g
2VntrLygi7WXdLP0zBx9q9vIdiTwPMCBMw4TWowxFPNh5NFdZODVloIgMnyJQDO1rfLWWKLcQIgjKJva66JitLJyLikFbR0+3UuS
rLukE08JrHEU85r9L+TZt6vAUz8e4+kfj7F7Z56x4QAHJFOKREIiqmISi0FLEAvAKUZUQuaq0TvnaOtJcd6GZay9tJuzLu+l94wc
6ZyPwGG1xQSWUj6Mxn8TJe5EZW54IUXFeGc+gIowTN/W+LeqdBXMdg6tHTrUkYC4SuJQCtack+Ocde3037SMoGg4dKDE9h+MsP3R
UX74/RH27SlirauJQTU3EYvBqSMWgFNA1VCtcZQnQ6x1tC1Jce7VS1l37XLOvryXnpUZpBLossUEhsJYUPPoUoimhl6Xrz/x1y+m
vz/OEZQsZRtFD1IKepeluOn1K7np9SsZPlTmiR+O8r1th3js4SkxSGcUvi+xLhKDmJNLLAAnkaq3D8uGsGRIZj3O3biMi25Yxdqq
0UuBLhlKk7qy+mtk8FJFpnasczI5BHIex1YlZK4KsWkRRf12IZBq6rUwsISlaFBKJqPYuKmPa1/Rx/ChMo//cIx7B4f43r2HGTkc
4PmSdFpF0ZCJheBkEQvASUDIyCTKkyHOObpW5rj0NWtY/8qV9K1tx09KdDEyepxDykoXW905HLOPyKj12c/jWuY6z9HhZhWC6rUI
AahoD2Mc+YkQ4SCd8Xj5pj6u2dTL/j1FHn7gMF//8l6eeXqCMHTkch5KiVgITgKxAJxA6g1fSMHZG5Zx8c2rOXfjMtqWpDCBISxp
wmIUMteH9ZFVR/54NqN1ldePZNBH8ugzrrvumPmIRfN9phtvfbPBVsQAHD1LErz+zau48ZZl/PCRUe76xgG2DR5ibDQk1xYLwYkm
FoATQDPDv+pnz+Psq5aiPEFQ0BRGA6SsGEXDmi3VVV5mi9iPxovXG//RHCfqhOeIx7j6eoLm56p/LRKDqEGjQ8dYOcRTcOXV3Wy8
poennpjgi7fu5tvfGmJsLIwjghNILADHkWaGf2XF8IUUlCejzL2S1TY9zLTyI3t9McfrU/tFBlY9/7GE/vUadKQIorFHYbZ9Gl8T
AjwVvVM+r8HBmWuzvPu963jzwEq+eOse7rpzSgikFNg4WXjciAXgOFDN6gcFjXNw1oZlXPmz53PWVUsRsiIIVAWiar4zjaF5W35q
/2bHNLkaHG6awb6Ydn/TZN8Rj5q7WdIYEVT3lxUBLZUspaJl7dosf/zedbz5LSv54q27ufPOg0xOanK5KGSys655GzNfYgF4kUgl
0IEhLBqWruviuv/vYs65ZgVCVA3fzUjoTWd2QTiaXr1mRn68En6iiQDNvylxdBEBEDWNEJRKhlLRcNbaDO957zp+8i0r+di/7OCe
e4aRSpBLS0xcR/CiiAXgGBFSgIPiaJlcX4b+31jPS95wNn5KUZ4Mah5NNDXwub26q7P8+Xj8Zipx/LL9zZi6tiPnCKbfx8x9Z/Ym
VCsQq0nRckUI1pyV46N/vY5nt+3hvR8b4vtPFmjPKnw/zg8cK7EAHAPSEwR5DQIuedM5bHjHhXStaqM8EVCeCKNRc8zePTfTOI8t
zJ++5UQb/Sy46WIAc3v8I3UfNu4vcLXcSlg0dNpJbtnYTv+lOf7v1kP8/a2HODSm6Wrz4mjgGIhnBDoKonJbQWG4TNfqNt74d/3c
8qcbyPSkKYyWo31U1MJtNE9H82h+tu11h047/oj7n2Jm3vnc+85ICla9f8M5DIJeEdApNOOTFhy8+5eWcvdHzuLmq9o4NKoxNkqw
xsyfWADmiVQCExrCoualb13HT/2/G1n78hUURkoYbWpZ/UbjnN3wZ6/pc3Wvt7KxH4n6wUZHygXMdrwALJDEssIWMU7gVX6148Mh
56xM8OW/PJN/+J0VJH3JeMFUehVi5kMsAPNAKkFpPCDdneJ1H+7n+j++EpVQFMcDpJIIIXFiurEebRQw1+unmkZv3Pho3Gd23JzH
1Hv/+n0cguW2RApLtGwV4ByeEhRLjmLR8s43L+E7f38WL78ww8FRXSmhPto7Pf2IBWAORKVipThS5sxrVjLwiVdx5jUrKYyUsZWJ
MKYZrGju8ecTBcy3GdCwcdrzUyUes9UAHCn8n3ufqvcXZDH0ujLaNfSmuKjHQALjo5pzViS4/QNn8vtvWcJ43hJoh4qjgTmJBWAW
hBIYbdElzdXvegk/8Xf9ZLpTlMaDKNyfsVT6zJD+aKKA6uvUvd6sGdCYC2ieF3hxy7jP5qVnyMyMjFt9InNm+D93M2Bm27/KSltA
uUras+L9pymnoxINRLMk/c27lvOff7yKtrRiPG/wYxGYlVgAmiA9STAZksj6vObDm7j6nZeiSxodmAav32igotYUaLbPXFFA4z7H
asDNROhYz3J844rpn8gRxYDI+3e6kE4XYhC1yUmmnbL2gUXzFjoXRQM/+YoO7v7gmVx5fpqhUY3vxSLQjFgAGpCepHC4SN+FPbzx
E69izTUrKQyXcSJqVDY4nhnP62m+/eS19WeKyfyqCo6VZrmC+R03s+0PoHCsdAWoc/jTvD9MRQR17+spwfio5uzlCW778zW845Yu
hg6HlbEXR31bi5pYAOqQSlAaLXPeq9fy6r9/Je1ntFEaLSPqvMfMkLxJKks0GviUL21u+I1lMPURQeXvpnmA+VPnKGd9HM3JZ4b2
M8N/6l6bb1MAojJmg6DXlck6M+X9G0N/y/S/627SU4J8wZCUgo//5nL+7Bf7yJcsrpI3iImIC4EARJTwKxwucdFPr2PTe68mLGqC
yRBZ6XOqBsXVH7ebOpT6wpzqD9s1KdBrrASs7TvzcuZkunlNXUl1ii6Hw7kpryorsbMV4PuiaaZdAApq04pLqo41Cq0F1I3iq714
DMzMVtRfT7XbL4VluS1hGxN/1VO4uj8ajL/6XElBqC1BCH/ytqUs7/b5tX/YRyYpSHgCE48liAWgOoV1WAx5+buv5JKfvSAatWcd
QsmauU8Zq2j4u3KeynMx7a8pXMO26fvPuKoZx8+Gc9EaAAJARuGv7ymUHxmAAExoKkYL+ZESNJkWPDJER1tngmTawznwvWhqcGtc
9KiuO2Bcrc0tK3MRNruD+Xn8aXcTXS+ClbZA0lnC2bx/4zaa7VPJCwDjhzVvv6mT1Ut83vZ3exjJWzLJWAROawGoGX8h5Jr3bODi
n1lH8XCxNudelcba/Jl/R8+mD9MVODH1g5xpAI1RwFxGX3lXAc4KnI2mCFdKkEh6+JXZdnVZUxwPOXiwxMj+AvueGycsGXY/NYY1
DmcdB3ZORgYsGt8hGma7dFWGdNZDh5bV57SRzXksPyND34oMvUuTtLX7ZHJeRVgsOrBRIZQDpECKmSP96u94euQx0/sboB1NtwvQ
NeNnumFPP22zdtm05wLwJIxPGG68IseX3nMGr3//LsYKsQictgLQaPwX/tQ68geLKG+qBdvMa00z8Iaw/8hNgaOJAure01Fbzcf3
FX7Sq4023PfcOHseH2HfM+Psf3acQ3vyFMZCSvkwGiDjQFVzGAI8XzX12NXreOqxkcrknILH7juIdZHQJNOKXLvPkqUpzjgrx5qz
cpx7QTtnrMnS0emjZDQHYFA22EpJ7tEl3KY+9ZW2iHIuEoD616qGXq0Gmq0p4Or+rjvOU4KxkZArzk/zlT85g9e9fxfjp7kInJYC
UG/8L3/PBtb/1DoKwyVkZU28+nZ+s9C/mUDMtylQv22uyAIqnt5BIqlIpDycdYzsyrP3yRGeuv8Au7ePcHh3ntJkiKsYuvIlSknS
Ob/+4qeu8whtd+V7U/dVae87F83lPzEWMnKozOOPjoKDZFrRtyzF2nNyvPTqHs5b387qtVnSSUlYtpTLBmcdnhQI0cT70+j9Bb0u
oMOFdd6/Sehfb9zU7dMoBtOOifbzPcH4uOaK89J89T2reN2f7z6tReD0E4Bpxr+RC35qHYXhYkMt/0xPHb02VwNgap+5mgINlzKD
qrdXSpDM+UghGNk9yfMPDfHkd/ex87HDTB4u45zDS0i8hCLTkagdS2U5rmOeNcc1jjOcwvMEnu/VEoHWOob2Fdm9M893vnWAbJvH
Oee3c+XGHi6/qpu1Z2dJ+JJSwaBDOzMqcNOfeDiWu+JUfrFZmF8vYPUCUWfkzZsJU1GEpyoicG6Kr/7RKl7/l7tP2+bAaScAQgjC
YsiG92zg/J9aR3G4hJwl2XekSKByRmYO5Z1jko+616ftWzF8LyFJZRRBXvPMvQf44f+8wFP37mfycAkhBIm0It0WeXdnI49uT9JY
+JrA1G3zE5JEMpoL3BrHjx4Z4QcPDpPNeVx0aQfXv2oZV27opmdJAl22FIsmSh7Kmd5/lSuStWYq8dcY1jd69WZJQBr2gZmi4Co5
gXHDFeel+Mq7V/H6v9rNZNmS8MRpNdPQaSUAQgmKh4tc9e6rueBn11M8WECpqU7h2ULyxrb6zIz+kcbnz4wCqq87B1iHn5AkswlG
9+Z57Gt7+f6Xn2P/k6MYbUlmvMjLO7DOtdSceI2rAmeyXm1u/4fuG+bBe4dZvjLFq25Zxitu6OOsc7Lo0FLKG5QQSBl9clkMS21p
9j7/ZoJA3es07lt/gQ2vVbZ5SjBWEYH/+r0V3Pj+3WgDSk7XksXMaSMA0pOURkus+5n1XPDWC6Nsf6XNj2tu3I0iUI9rMPuZke3s
TYHq39bYyONnU4ztneTeTz/BD778HKP7CngJSSLj1dbSO1le/sVSL07ZnAcCDh8K+OTHnue/PreLTdf38eaBlaw7v40wMJSKFicl
yyiRcC7y/tNOSPNQn4a/ZzQFaB4RNAiCL6PmwMYLMnzkbX28818PkEvJWlNxsXNaCID0JMXDRc569dlseO/LCScDpg3mqXPojSF8
4w6Nhj67cMx+nDFRGz/dmWR8f577P/14ZPh78ySzPpnORC0XsJB/g1Ux8H1BMuljjOO/v7yXb39riFde38fAW1Zw3rp2EvkSnaUy
WjZ4/8a2fLOQvunfTGvzz2b8VfX3pGB8wvBLr+pksmj5rU8O0duh0Av5w58ni14AhBIEEwF9ly3lyj+6Gl0McTaaZioy4IqRCaiP
0qv+e84uvhkGPnvXoIgOwFhHui2BLmoe+cIz3PuJ7Qy/MEEy55PtSuIWkLefL85NLffV0REJwVe/spe77jzAm3/qDN79xg5yvYrJ
MQuubkZjx/Quv+rJ6l+fy/PPZfzVJ5XnSsLEmOE3bu7iyT0B/3znGD1tEm2O4wfRgizuqmghsIEh2ZVi459dh9+ewgR22kwR9Sbu
Khmpqd/TLHX5dW/ROJqvavqNTVVjosrCdEeSnd/bz63v+ja3ve8B8oeLZLuTKC9aLHSxh531QgCCT358Bzf/yhN86isjpJKCTFKg
Tb1RN4b+NDdqZtuHmcZfGwAxtU0QGUOpbPnwL/SyaX2a0bxFLW4LWdwCIACrLRv+9Fra1nYSTAZUv9E5jVjU/36mG/18RKCxaWoN
JNsT6MDwrb96iK2//m32/ugwma4kypenheE3UhWCri6f/SOat/35Lt747p08vSugvcPDmoauzEZv37R9D9EywzCn8TceU3kIHMZE
pdWf+bVlnNHtUwrdop5ZaNEKgFCS8liJC99xKSuuW015tISoJP2qJSgzjbjOuMV0o4d6oz+SCET720r1XrIzyfP37OVzv/RNHv6P
J0hkfBIZ77Q0/EaMcSQ8QW+nxx0PTHDdbzzHP209RDolSPoCrasG3GDYMNOIaTTuIxg/9f9G+0oBpcCxosfjo2/rRZvp3/NiY1EK
gFCCYLzMiv41rH/HpZTHpoy/Sn2Iz7TtzUXANoT2zUVgCqMdXspDeJLBv3mIL//m3YzumiDTHbXzXQt15Z1qnANtHJ1tinJoedff
7eWNf7KToRFNe85Da9tgsI1evtm2ZmE/szym7+tJGJ80vOqyDO95XRfDkxZvkYYBi08ApMCUDdnlOV72no0VLztzIo+5DXl+IjCz
ORD9bYwj1ZVidM8kX3rnnTz06e0kMj5eysOeDqnlY8SYaAxBb6fH1x+Y4Lrffp5vfG88ahI4KslRx4wvbD7GX7fr1PO68zH9eCVg
csLyR6/t4rWXZRjJm9psxIuJRXdLAnDa8tL3bCSzvA1dNpWZfGZOwNkYstczLaSfRQSm9p16Yq0g1ZXkqTue54tv/wb7HjkYeX0X
e/35UI0Guts8DoxqXv9/XuD9nxoil5T4SmCrWflGY59v2O/m2F7d4JjqtTHwTz/fyxk9HsVFmA9YVAIglCQYLXHWW9azvH8N5fFS
ZaGOmR57phjMPannbCJQ3953AvysxyOf3s433r2NoKBJtPmx1z8GtHGkfEE2LXnvJ4f45b/fQ1k7Er5A68pOcxm/bfb6LMdVt1k3
7YchiRYqXdXj8Vdv7qEYuEU3pdiiEQAhBboY0n5uN+t/7aUEkyHIme3+xmTf9IfANk0ONo8EqtutBeFJ/KzPd//iAb77V98jkfNR
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
'@

Invoke-WattCap

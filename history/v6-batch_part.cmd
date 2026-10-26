@echo off
setlocal EnableDelayedExpansion
:: ==========================================================================
::  WATTCAP  -  gpu-power-limit.cmd
::  Power limiter, live monitor and logger for NVIDIA RTX cards.
::
::  Double-click                 -> animated intro (any key skips), then menu
::  gpu-power-limit install 275  -> install boot task at 275 W + shortcut
::  gpu-power-limit apply        -> apply saved limits (what the boot task runs)
::  gpu-power-limit apply 275    -> apply 275 W to every card, once
::  gpu-power-limit reset        -> stock limits now + remove boot task
::  gpu-power-limit monitor      -> live monitor (load, VRAM, power, clocks)
::  gpu-power-limit report       -> usage and efficiency report from the log
::  gpu-power-limit profiles     -> profiles and per-card limits
::  gpu-power-limit shortcut     -> desktop + Start menu shortcut with logo
::
::  Everything below the WATTCAP marker at the end is PowerShell/C#
::  (monitor, intro renderer, shortcut maker, icon). Batch never executes it.
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
set "LIMITS=%INSTALL_DIR%\limits.txt"
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

:: optional watt value after the mode: install 275 / apply 275 (applies to every card)
set "ARGW="
if not "%~2"=="" (
    echo %~2| findstr /r /x "[0-9][0-9]*" >nul && set "ARGW=1" && set "WATTS=%~2"
)

if /i "%~1"=="apply"     goto :apply_boot
if /i "%~1"=="install"   goto :install
if /i "%~1"=="reset"     goto :reset
if /i "%~1"=="uninstall" goto :reset
if /i "%~1"=="shortcut"  goto :shortcut
if /i "%~1"=="monitor"   (call :ps monitor & exit /b 0)
if /i "%~1"=="report"    (call :ps report & exit /b 0)
if /i "%~1"=="profiles"  goto :cli_profiles

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
    if defined INSTW set "TSTAT=%ESC%[38;5;41mINSTALLED - !INSTW!"
)
echo.
echo   %ESC%[38;5;238m-----------------------------------------------------------------%ESC%[0m
echo    Boot task: %TSTAT%%ESC%[0m     per RTX %MATCH% card
echo   %ESC%[38;5;238m-----------------------------------------------------------------%ESC%[0m
echo    [1] Set power limit on every boot (pick watts)
echo    [2] Reset to stock (remove boot task)
echo    [3] Show current limits
echo    [4] Desktop + Start menu shortcut (with logo)
echo    [M] Live monitor  (load, VRAM, power, clocks, throttle, logging)
echo    [S] Usage and efficiency report (from the monitor log)
echo    [F] Profiles and per-card limits
echo    [G] Animation gallery (play any opening / closing)
echo    [Q] Quit
echo.
choice /c 1234MSFGQ /n /m "  Select: "
if errorlevel 9 goto :quit
if errorlevel 8 goto :gallery
if errorlevel 7 goto :profiles_menu
if errorlevel 6 (call :ps report & goto :menu)
if errorlevel 5 (call :ps monitor & goto :menu)
if errorlevel 4 (call :ps shortcut & pause & goto :menu)
if errorlevel 3 goto :show
if errorlevel 2 goto :reset
if errorlevel 1 goto :setmenu
goto :menu

:profiles_menu
call :ps profiles
if errorlevel 10 call :after_profile
goto :menu

:quit
if "%OUTRO%"=="1" call :ps outro %OUTRO_STYLE%
exit /b 0

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
echo    ^(different limits per card: use [F] Profiles and per-card limits^)
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
>"%LIMITS%" echo ALL=%WATTS%
>"%INSTALL_DIR%\watts.txt" echo %WATTS% W
call :mktask || (pause & exit /b 1)
call :ps shortcut
echo.
set "ARGW="
call :apply
echo.
type "%LOG%"
echo.
pause
exit /b 0

:: copies this script to ProgramData and creates the boot task (runs "apply", which reads limits.txt)
:mktask
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if /i not "%~f0"=="%SELF%" copy /y "%~f0" "%SELF%" >nul
schtasks /Create /TN "%TASK%" /TR "\"%SELF%\" apply" /SC ONSTART /DELAY 0000:30 /RU SYSTEM /RL HIGHEST /F
if errorlevel 1 (
    echo Failed to create scheduled task.
    exit /b 1
)
echo Scheduled task "%TASK%" installed ^(runs at boot as SYSTEM, 30s delay^).
exit /b 0

:: ---- profiles / per-card limits (PowerShell UI writes limits.txt, applies now, exits 10) ----
:cli_profiles
call :ps profiles
if errorlevel 10 call :after_profile
exit /b 0

:after_profile
schtasks /Query /TN "%TASK%" >nul 2>&1 || call :mktask
exit /b 0

:: ---- apply --------------------------------------------------------------
:apply_boot
call :apply
:: give the driver / other tools time to settle, then verify the limit stuck (and fix once if not)
ping -n 16 127.0.0.1 >nul
call :ps verify
exit /b 0

:apply
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
echo [%date% %time%] Applying power limits to GPUs matching "%MATCH%" > "%LOG%"
call :find_smi || exit /b 1
call :wait_driver || exit /b 1

set "GPULIST=%INSTALL_DIR%\gpus.txt"
"%SMI%" --query-gpu=index,name --format=csv,noheader > "%GPULIST%"

set /a HIT=0
for /f "usebackq tokens=1,* delims=," %%A in ("%GPULIST%") do (
    echo %%B | find /i "%MATCH%" >nul && (
        set /a HIT+=1
        set "GW=%WATTS%"
        if not defined ARGW if exist "%LIMITS%" (
            for /f "usebackq tokens=1,2 delims==" %%P in ("%LIMITS%") do if /i "%%P"=="ALL" set "GW=%%Q"
            for /f "usebackq tokens=1,2 delims==" %%P in ("%LIMITS%") do if "%%P"=="%%A" set "GW=%%Q"
        )
        echo --- GPU %%A:%%B  target !GW! W >> "%LOG%"
        "%SMI%" -i %%A -pl !GW! >> "%LOG%" 2>&1
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
if exist "%LIMITS%" del /q "%LIMITS%" >nul 2>&1
if exist "%INSTALL_DIR%\watts.txt" del /q "%INSTALL_DIR%\watts.txt" >nul 2>&1
type "%RLOG%"
echo.
echo Boot task removed. Cards are at stock and will stay stock after reboot.
echo ^(Shortcut, monitor log and the copy in %INSTALL_DIR% are kept so the menu still opens.^)
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
::   arg1 = mode, arg2 = style or scene. Returns the PowerShell exit code.
:ps
set "WC_MODE=%~1"
set "WC_STYLE=%~2"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText($env:INTRO_SELF); $m='<#'+'WATTCAP#>'; $i=$f.LastIndexOf($m); if ($i -ge 0) { Invoke-Expression $f.Substring($i + $m.Length) }"
exit /b %errorlevel%

:banner
echo.
@@BANNER@@
exit /b 0

:: ===================== PowerShell / C# payload (not batch) =====================
<#WATTCAP#>

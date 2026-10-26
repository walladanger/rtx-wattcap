@echo off
setlocal EnableDelayedExpansion
:: ============================================================
::  gpu-power-limit.cmd
::  Sets every RTX 3090 to %WATTS% W on each Windows boot.
::
::  Double-click           -> install startup task + apply now
::  gpu-power-limit apply  -> apply only (what the task runs)
::  gpu-power-limit uninstall -> remove task + installed copy
:: ============================================================

set "WATTS=310"
set "MATCH=3090"
set "TASK=GPU Power Limit (%MATCH%)"
set "INSTALL_DIR=%ProgramData%\GPUPowerLimit"
set "SELF=%INSTALL_DIR%\gpu-power-limit.cmd"
set "LOG=%INSTALL_DIR%\last-run.log"

:: ---- require admin (SYSTEM task already is) -----------------
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

if /i "%~1"=="apply"     goto :apply
if /i "%~1"=="uninstall" goto :uninstall

:: ---- install ------------------------------------------------
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if /i not "%~f0"=="%SELF%" copy /y "%~f0" "%SELF%" >nul

schtasks /Create /TN "%TASK%" /TR "\"%SELF%\" apply" /SC ONSTART /DELAY 0000:30 /RU SYSTEM /RL HIGHEST /F
if errorlevel 1 (
    echo Failed to create scheduled task.
    pause
    exit /b 1
)
echo Scheduled task "%TASK%" installed ^(runs at boot as SYSTEM, 30s delay^).
echo.
call :apply
echo.
type "%LOG%"
echo.
pause
exit /b 0

:: ---- apply --------------------------------------------------
:apply
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
echo [%date% %time%] Target: %WATTS% W on GPUs matching "%MATCH%" > "%LOG%"

set "SMI=%SystemRoot%\System32\nvidia-smi.exe"
if not exist "%SMI%" set "SMI=%ProgramFiles%\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
if not exist "%SMI%" (
    echo ERROR: nvidia-smi.exe not found. >> "%LOG%"
    exit /b 1
)

:: wait for driver to come up (max ~60s)
set /a TRY=0
:wait_driver
"%SMI%" -L >nul 2>&1
if errorlevel 1 (
    set /a TRY+=1
    if !TRY! geq 12 (
        echo ERROR: NVIDIA driver not responding after 60s. >> "%LOG%"
        exit /b 1
    )
    ping -n 6 127.0.0.1 >nul
    goto :wait_driver
)

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

echo. >> "%LOG%"
echo Current limits: >> "%LOG%"
"%SMI%" --query-gpu=index,name,power.limit,power.min_limit,power.max_limit --format=csv >> "%LOG%" 2>&1
exit /b 0

:: ---- uninstall ----------------------------------------------
:uninstall
schtasks /Delete /TN "%TASK%" /F
echo Task removed. Limits return to default on next reboot.
pause
rmdir /s /q "%INSTALL_DIR%" & exit /b 0

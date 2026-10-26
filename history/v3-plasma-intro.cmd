@echo off
setlocal EnableDelayedExpansion
:: ============================================================
::  gpu-power-limit.cmd
::  Sets every RTX 3090 to %WATTS% W on each Windows boot.
::
::  Double-click               -> animated intro, then menu
::                                (any key skips the intro)
::  gpu-power-limit install    -> install boot task + apply now
::  gpu-power-limit apply      -> apply only (what the task runs)
::  gpu-power-limit reset      -> stock limits now + remove task
:: ============================================================

set "WATTS=310"
set "MATCH=3090"
set "TASK=GPU Power Limit (%MATCH%)"
set "INSTALL_DIR=%ProgramData%\GPUPowerLimit"
set "SELF=%INSTALL_DIR%\gpu-power-limit.cmd"
set "LOG=%INSTALL_DIR%\last-run.log"
:: INTRO=0 skips the animated intro
set "INTRO=1"
set "INTRO_SELF=%~f0"

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
if /i "%~1"=="install"   goto :install
if /i "%~1"=="reset"     goto :reset
if /i "%~1"=="uninstall" goto :reset

:: ---- intro (interactive path only) ------------------------
if "%INTRO%"=="1" call :intro

:: ---- menu ---------------------------------------------------
:menu
cls
echo ==========================================
echo   RTX %MATCH% power limit
echo ==========================================
echo   [1] Set %WATTS% W on every boot (install)
echo   [2] Reset to stock (remove boot task)
echo   [3] Show current limits
echo   [I] Replay intro
echo   [Q] Quit
echo.
choice /c 123IQ /n /m "Select: "
if errorlevel 5 exit /b 0
if errorlevel 4 (call :intro & goto :menu)
if errorlevel 3 goto :show
if errorlevel 2 goto :reset
if errorlevel 1 goto :install
goto :menu

:: ---- install ------------------------------------------------
:install
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

:: ---- reset to stock -----------------------------------------
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
type "%RLOG%"
echo.
echo Boot task removed. Cards are at stock and will stay stock after reboot.
pause
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%" & exit /b 0
exit /b 0

:: ---- show ---------------------------------------------------
:show
call :find_smi || (pause & goto :menu)
echo.
"%SMI%" --query-gpu=index,name,power.draw,power.limit,power.default_limit,power.min_limit,power.max_limit --format=csv
echo.
schtasks /Query /TN "%TASK%" >nul 2>&1 && (echo Boot task: INSTALLED) || (echo Boot task: not installed)
echo.
pause
goto :menu

:: ---- helpers ------------------------------------------------
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

:intro
:: Runs the PowerShell block stored after the marker at the end of this file.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText($env:INTRO_SELF); $m='<#'+'INTRO#>'; $i=$f.LastIndexOf($m); if ($i -ge 0) { Invoke-Expression $f.Substring($i + $m.Length) }"
exit /b 0

:: ================= PowerShell intro payload (not batch) =================
<#INTRO#>
# ------------------------------------------------------------------
#  "Shaved Peaks" - a seeded plasma field whose crests are clipped at
#  WATTS/stock. Anything that would exceed the cap flattens into the
#  amber throttle plateau. The logo rolls in over it; a GPU ticker
#  scrolls underneath. Any key skips.
#  Pure ASCII source; block glyphs are built from code points.
# ------------------------------------------------------------------
$E = [char]27

# ---- VT support (Win11 conhost / Windows Terminal) ---------------
$vtOK = $false
try { $vtOK = [bool]$Host.UI.SupportsVirtualTerminal } catch {}
if (-not $vtOK -and -not $IntroNoRun) {
    try {
        Add-Type -Namespace GPL -Name Con -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out int m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, int m);
'@
        $hOut = [GPL.Con]::GetStdHandle(-11); $mode = 0
        [void][GPL.Con]::GetConsoleMode($hOut, [ref]$mode)
        $vtOK = [GPL.Con]::SetConsoleMode($hOut, ($mode -bor 4))
    } catch {}
}
if (-not $vtOK -and -not $IntroNoRun) { return }

# ---- inputs from the batch side ----------------------------------
$watts = 310; if ($env:WATTS -match '^\d+$') { $watts = [int]$env:WATTS }
$match = '3090'; if ($env:MATCH) { $match = $env:MATCH }

# ---- live GPU info for the ticker --------------------------------
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
$cap = [Math]::Max(0.5, [Math]::Min(0.97, $watts / $stock))

# ---- seed + tunables ---------------------------------------------
$seed = Get-Random -Minimum 1 -Maximum 100000
if ($env:INTRO_SEED -match '^\d+$') { $seed = [int]$env:INTRO_SEED }
$rng = New-Object System.Random $seed
function Rnd([double]$a, [double]$b) { $a + ($b - $a) * $rng.NextDouble() }
function Sgn { if ($rng.NextDouble() -lt 0.5) { -1 } else { 1 } }

$palettes = @(
    @{ n = 'emerald'; c = @(0, 22, 22, 28, 34, 35, 41, 77, 120);   thr = 214; hi = 120 },
    @{ n = 'glacier'; c = @(0, 17, 17, 18, 24, 25, 31, 38, 87);    thr = 209; hi = 87  },
    @{ n = 'orchid';  c = @(0, 53, 53, 54, 55, 91, 128, 170, 213); thr = 222; hi = 213 }
)
$pal = $palettes[$rng.Next(0, $palettes.Count)]

$f1 = Rnd 0.06 0.15;  $a1 = Rnd 0.9 1.6
$f2 = Rnd 0.20 0.38;  $a2 = -(Rnd 0.7 1.4)
$k3 = (Rnd 5 12) * (Sgn); $k4 = Rnd 12 30; $a3 = Rnd 140 260
$kr = Rnd 16 30;      $ar = Rnd 220 360
$h1 = Rnd 0.35 0.65;  $h2 = Rnd 0.55 1.05; $p1 = Rnd 0 6.283; $p2 = Rnd 0 6.283

# ---- canvas --------------------------------------------------------
if ($IntroW) { $cw = $IntroW; $ch = $IntroH } else {
    $ws = $Host.UI.RawUI.WindowSize; $cw = $ws.Width; $ch = $ws.Height
}
$W = [Math]::Min($cw - 1, 150); $H = [Math]::Min($ch, 44)
if ($W -lt 50 -or $H -lt 16) { return }
$ox = [int][Math]::Floor(($cw - 1 - $W) / 2); $oy = [int][Math]::Floor(($ch - $H) / 2)
$PH = $H - 1                                   # last row = ticker

$SIN = New-Object 'double[]' 1024
for ($i = 0; $i -lt 1024; $i++) { $SIN[$i] = [Math]::Sin(2 * [Math]::PI * $i / 1024) }

$rcx = (Rnd 0.2 0.8) * $W; $rcy = (Rnd 0.2 0.8) * $PH
$rad = New-Object 'int[]' ($W * $PH)
$vig = New-Object 'double[]' ($W * $PH)
for ($y = 0; $y -lt $PH; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
        $dx = $x - $rcx; $dy = ($y - $rcy) * 2.1
        $rad[$y * $W + $x] = [int]([Math]::Sqrt($dx * $dx + $dy * $dy) * $kr / 4)
        $ux = ($x / ($W - 1)) * 2 - 1; $uy = ($y / ($PH - 1)) * 2 - 1
        $vig[$y * $W + $x] = 1 - 0.38 * ($ux * $ux * 0.8 + $uy * $uy)
    }
}
$sx = New-Object 'double[]' $W; $ax = New-Object 'int[]' $W; $gx = New-Object 'double[]' $W

# ---- glyphs --------------------------------------------------------
$B = [string][char]0x2588
$ramp = @(' ', '.', ':', [string][char]0x2591, [string][char]0x2591, [string][char]0x2592,
          [string][char]0x2592, [string][char]0x2593, $B, $B)
$esc = New-Object 'string[]' 14
for ($i = 1; $i -le 8; $i++) { $esc[$i] = "$E[38;5;$($pal.c[$i])m" }
$esc[9]  = "$E[38;5;$($pal.thr)m"             # throttle plateau
$esc[12] = "$E[38;5;235m"                     # logo shadow
$esc[13] = "$E[38;5;252m"                     # subtitle text

# 5-row pixel font
$font = @{
    'R' = @('#### ', '#   #', '#### ', '#  # ', '#   #')
    'T' = @('#####', '  #  ', '  #  ', '  #  ', '  #  ')
    'X' = @('#   #', ' # # ', '  #  ', ' # # ', '#   #')
    '3' = @('#### ', '    #', ' ### ', '    #', '#### ')
    '0' = @(' ### ', '#   #', '#   #', '#   #', ' ### ')
    '9' = @(' ### ', '#   #', ' ####', '    #', ' ### ')
    ' ' = @('   ', '   ', '   ', '   ', '   ')
}
$word = 'RTX ' + ($match -replace '[^RTX0-9 ]', '')
$pix = @('', '', '', '', '')
$chars = $word.ToCharArray()
for ($i = 0; $i -lt $chars.Count; $i++) {
    $g = $font[[string]$chars[$i]]; if (-not $g) { continue }
    for ($r = 0; $r -lt 5; $r++) { $pix[$r] += $g[$r]; if ($i -lt $chars.Count - 1) { $pix[$r] += ' ' } }
}
$PW = $pix[0].Length
$SCL = if ($PW * 2 + 6 -le $W) { 2 } else { 1 }
$LW = $PW * $SCL
$mask = New-Object 'bool[]' ($LW * 5)
for ($r = 0; $r -lt 5; $r++) { for ($c = 0; $c -lt $LW; $c++) {
    $mask[$r * $LW + $c] = ($pix[$r][[int][Math]::Floor($c / $SCL)] -eq '#') } }
$off = New-Object 'int[]' $LW
$lxT = [int][Math]::Floor(($W - $LW) / 2)
$ly = [int][Math]::Floor($PH * 0.40) - 3

$sub = "POWER LIMIT  //  $watts W"
if ($nGpu -gt 0) { $sub += "  x$nGpu" }
$sub = ($sub.ToCharArray() -join ' ')
$subX = [int][Math]::Floor(($W - $sub.Length) / 2); $subY = $ly + 7

$tick = '  >>  ' + ($gpuLines -join '  ::  ') +
        ('  ::  target {0} W per card ({1:0}% of stock)  ::  seed {2} / {3}  ::  any key skips  ' -f
         $watts, ($cap * 100), $seed, $pal.n)
while ($tick.Length -lt $W * 2) { $tick += $tick }

$TEND = 7.0
$sb = New-Object System.Text.StringBuilder (($W * $H) * 4)

function Clamp01([double]$v) { if ($v -lt 0) { 0.0 } elseif ($v -gt 1) { 1.0 } else { $v } }

function Render-Frame([double]$t) {
    # global envelope
    $g = (Clamp01 ($t / 0.8)) * (Clamp01 (($TEND - $t) / 0.6))

    # logo slide + roll
    $pS = Clamp01 (($t - 0.5) / 1.5)
    $ez = 1 - [Math]::Pow(1 - $pS, 3)
    $lx = [int]($lxT + ($W - $lxT + 2) * (1 - $ez))
    $amp = 2.0 * (Clamp01 ((2.9 - $t) / 0.9))
    $wp = ($t - 4.0) / 1.3 * ($PW + 16) - 8
    for ($c = 0; $c -lt $LW; $c++) {
        $pc = [Math]::Floor($c / $SCL)
        $o = $amp * [Math]::Sin($pc * 0.30 - $t * 7)
        if ($t -gt 4.0 -and $t -lt 5.3) { $d = ($pc - $wp) / 3.0; $o -= 1.4 * [Math]::Exp(-$d * $d) }
        $off[$c] = [int][Math]::Round($o)
    }
    $logoOn = ($t -gt 0.5 -and $g -gt 0.25)
    $dimA = 0.78 * (Clamp01 (($t - 0.6) / 1.2))
    $shine = (($t - 2.3) * 55) % ($LW + 70) - 25
    if ($g -gt 0.7) { $esc[10] = "$E[38;5;250m"; $esc[11] = "$E[38;5;231m" }
    elseif ($g -gt 0.45) { $esc[10] = "$E[38;5;244m"; $esc[11] = "$E[38;5;250m" }
    else { $esc[10] = "$E[38;5;239m"; $esc[11] = "$E[38;5;242m" }
    $nSub = [int][Math]::Floor((Clamp01 (($t - 2.2) / 1.2)) * $sub.Length)
    if ($g -lt 0.4) { $nSub = 0 }

    # separable field terms
    $ti = [int]($t * $a3); $rp = [int]($t * $ar)
    $cx = $W / 2 + $W * 0.36 * [Math]::Sin($t * $h1 + $p1)
    $cy = $PH / 2 + $PH * 0.34 * [Math]::Sin($t * $h2 + $p2)
    $sgx = $W * 0.17; $sgy = $PH * 0.30
    for ($x = 0; $x -lt $W; $x++) {
        $sx[$x] = [Math]::Sin($x * $f1 + $t * $a1)
        $ax[$x] = [int]($x * $k3)
        $q = ($x - $cx) / $sgx; $gx[$x] = [Math]::Exp(-$q * $q)
    }
    $bx0 = $lx - 6; $bx1 = $lx + $LW + 5; $by0 = $ly - 3; $by1 = $subY + 2
    $bandTop = $ly - 3; $bandBot = $ly + 7

    [void]$sb.Clear()
    for ($y = 0; $y -lt $PH; $y++) {
        [void]$sb.Append("$E[$($y + 1 + $oy);$($ox + 1)H")
        $syv = [Math]::Sin($y * $f2 + $t * $a2)
        $ayv = [int]($y * $k4) + $ti
        $q = ($y - $cy) / $sgy; $gyv = [Math]::Exp(-$q * $q) * 0.55
        $row = $y * $W
        $inBand = $logoOn -and $y -ge $bandTop -and $y -le $bandBot
        $inBoxY = $logoOn -and $y -ge $by0 -and $y -le $by1
        $isSub = ($y -eq $subY -and $nSub -gt 0)
        $last = -1; $kp = -1
        for ($x = 0; $x -lt $W; $x++) {
            $k = -1; $chr = $null
            if ($inBand -and $x -ge $lx -and $x -lt $lx + $LW) {
                $c = $x - $lx
                $lr = $y - $ly - $off[$c]
                if ($lr -ge 0 -and $lr -lt 5 -and $mask[$lr * $LW + $c]) {
                    $sh = $c - $lr * $SCL - $shine
                    if ($sh -ge 0 -and $sh -lt 4 * $SCL) { $k = 11 } else { $k = 10 }
                    $chr = $B
                } elseif ($c -ge $SCL) {
                    $lr2 = $y - $ly - $off[$c - $SCL] - 1
                    if ($lr2 -ge 0 -and $lr2 -lt 5 -and $mask[$lr2 * $LW + $c - $SCL]) { $k = 12; $chr = $B }
                }
            }
            if ($k -lt 0 -and $isSub -and $x -ge $subX -and $x -lt $subX + $nSub) {
                $chr = [string]$sub[$x - $subX]; if ($chr -ne ' ') { $k = 13 }
            }
            if ($k -lt 0 -and $kp -ge 0 -and ($x -band 1)) { $k = $kp; $chr = $ramp[$k] }
            elseif ($k -lt 0) {
                $i = $row + $x
                $s = $sx[$x] + $syv + $SIN[($ax[$x] + $ayv) -band 1023] + $SIN[($rad[$i] - $rp) -band 1023]
                $n = (0.36 + 0.24 * $s + $gx[$x] * $gyv) * $vig[$i] * $g
                if ($inBoxY -and $x -ge $bx0 -and $x -le $bx1) {
                    $fe = [Math]::Min([Math]::Min($x - $bx0, $bx1 - $x) / 5.0, [Math]::Min($y - $by0, $by1 - $y) / 2.0)
                    if ($fe -gt 1) { $fe = 1 }
                    $n *= 1 - $dimA * ($fe + 0.25) / 1.25
                }
                if ($n -ge $cap) { $k = 9 }
                elseif ($n -le 0) { $k = 0 }
                else { $k = [int][Math]::Floor($n / $cap * 9) }
                if ($chr -eq $null) { $chr = $ramp[$k]; $kp = $k } else { $kp = -1 }
            } else { $kp = -1 }
            if ($k -gt 0 -and $k -ne $last) { [void]$sb.Append($esc[$k]); $last = $k }
            [void]$sb.Append($chr)
        }
    }

    # ticker
    $o = [int]($t * 20) % ($tick.Length - $W)
    [void]$sb.Append("$E[$($H + $oy);$($ox + 1)H$E[48;5;234m$E[38;5;$($pal.hi)m")
    [void]$sb.Append($tick.Substring($o, $W)).Append("$E[0m")
    return $sb.ToString()
}

# ---- run -----------------------------------------------------------
if (-not $IntroNoRun) {
    $oldEnc = [Console]::OutputEncoding
    $oldCC = $false; try { $oldCC = [Console]::TreatControlCAsInput } catch {}
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
        try { [Console]::TreatControlCAsInput = $true } catch {}
        [Console]::CursorVisible = $false
        $out = [Console]::Out
        $out.Write("$E[?1049h$E[2J")
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $t = $sw.Elapsed.TotalSeconds
            if ($t -ge $TEND) { break }
            $out.Write((Render-Frame $t)); $out.Flush()
            $skip = $false
            try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); $skip = $true } } catch {}
            if ($skip) { break }
            $ms = [int](33 - ($sw.Elapsed.TotalSeconds - $t) * 1000)
            if ($ms -gt 0) { Start-Sleep -Milliseconds $ms }
        }
    } finally {
        [Console]::Out.Write("$E[0m$E[2J$E[?1049l")
        try { [Console]::CursorVisible = $true } catch {}
        try { [Console]::TreatControlCAsInput = $oldCC } catch {}
        [Console]::OutputEncoding = $oldEnc
    }
}


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

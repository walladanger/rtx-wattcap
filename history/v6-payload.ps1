
# ==========================================================================
#  WATTCAP payload. Invoked by the batch :ps routine with
#    WC_MODE  = intro | outro | play | shortcut | monitor | report | profiles | verify
#    WC_STYLE = auto | <scene name> | allopen | allclose | all   (animation modes)
#  ASCII-only source. The C# renderer is compiled once and cached as a DLL
#  next to the install (hash-named, so edits recompile automatically).
# ==========================================================================

$script:Base = $null
$script:Smi = $null
$script:MatchStr = '3090'
$script:DefaultW = 310

function Find-Smi {
    $s = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    if (-not (Test-Path $s)) { $s = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe' }
    if (Test-Path $s) { return $s }
    return $null
}

function Num($s) {
    $d = 0.0
    if ([double]::TryParse(([string]$s).Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}

# All cards whose name matches, with live telemetry
function Get-Gpus {
    if (-not $script:Smi) { return @() }
    $q = 'index,name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,power.limit,power.default_limit,power.min_limit,power.max_limit,clocks.sm,clocks.mem,fan.speed,pstate,clocks_throttle_reasons.sw_power_cap,clocks_throttle_reasons.hw_thermal_slowdown,clocks_throttle_reasons.sw_thermal_slowdown,clocks_throttle_reasons.hw_slowdown,clocks_throttle_reasons.gpu_idle'
    $rows = & $script:Smi "--query-gpu=$q" '--format=csv,noheader,nounits' 2>$null
    $out = New-Object System.Collections.ArrayList
    foreach ($r in @($rows)) {
        $p = @(([string]$r) -split '\s*,\s*')
        if ($p.Count -lt 21) { continue }
        if ($p[1] -notlike "*$($script:MatchStr)*") { continue }
        [void]$out.Add([pscustomobject]@{
            Index = [int]$p[0]; Name = $p[1]
            Load = (Num $p[2]); MemLoad = (Num $p[3]); VramUsed = (Num $p[4]); VramTotal = (Num $p[5])
            Temp = (Num $p[6]); Power = (Num $p[7]); Limit = (Num $p[8]); Default = (Num $p[9])
            MinL = (Num $p[10]); MaxL = (Num $p[11]); Sm = (Num $p[12]); Mem = (Num $p[13]); Fan = (Num $p[14])
            PState = $p[15]
            CapPwr = ($p[16] -eq 'Active')
            Thermal = (($p[17] -eq 'Active') -or ($p[18] -eq 'Active'))
            HwSlow = ($p[19] -eq 'Active')
            Idle = ($p[20] -eq 'Active')
        })
    }
    return @($out)
}

function Set-Limit([int]$idx, [int]$w) {
    $o = & $script:Smi -i $idx -pl $w 2>&1
    return ($LASTEXITCODE -eq 0)
}

# ---- saved limits: limits.txt holds ALL=<w> and/or <gpu index>=<w> -------------
function Read-Limits {
    $h = @{}
    $f = Join-Path $script:Base 'limits.txt'
    if (Test-Path $f) {
        foreach ($l in @(Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)) {
            if ($l -match '^\s*(ALL|\d+)\s*=\s*(\d+)\s*$') { $h[$Matches[1].ToUpper()] = [int]$Matches[2] }
        }
    }
    return $h
}

function Want-Limit($h, [int]$idx) {
    if ($h.ContainsKey("$idx")) { return [int]$h["$idx"] }
    if ($h.ContainsKey('ALL')) { return [int]$h['ALL'] }
    return [int]$script:DefaultW
}

function Limits-Summary($h) {
    $keys = @($h.Keys | Where-Object { $_ -ne 'ALL' } | Sort-Object { [int]$_ })
    if ($keys.Count -eq 0) { if ($h.ContainsKey('ALL')) { return "$($h['ALL']) W" }; return '' }
    $parts = @($keys | ForEach-Object { "GPU$_ $($h[$_]) W" })
    if ($h.ContainsKey('ALL')) { $parts += "others $($h['ALL']) W" }
    return ($parts -join ', ')
}

function Write-Limits($h) {
    $lines = @()
    if ($h.ContainsKey('ALL')) { $lines += "ALL=$($h['ALL'])" }
    foreach ($k in @($h.Keys | Where-Object { $_ -ne 'ALL' } | Sort-Object { [int]$_ })) { $lines += "$k=$($h[$k])" }
    Set-Content -LiteralPath (Join-Path $script:Base 'limits.txt') -Value $lines -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $script:Base 'watts.txt') -Value (Limits-Summary $h) -Encoding ASCII
}

# ---- boot-time verification: did the limit stick? fix once if not ---------------
function Start-Verify {
    $log = Join-Path $script:Base 'last-run.log'
    $want = Read-Limits
    $argw = $false
    if ($env:ARGW) { $argw = $true }
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $out = @('', "[$stamp] VERIFY (boot check)")
    foreach ($g in @(Get-Gpus)) {
        $w = $script:DefaultW
        if (-not $argw) { $w = Want-Limit $want $g.Index }
        if ([math]::Abs($g.Limit - $w) -le 1) { $out += "GPU$($g.Index): $([int]$g.Limit) W = wanted $w W  OK"; continue }
        $out += "GPU$($g.Index): $([int]$g.Limit) W but wanted $w W  MISMATCH (another tool changed it?) - re-applying"
        $ok = Set-Limit $g.Index $w
        Start-Sleep -Seconds 2
        $now = @(Get-Gpus | Where-Object { $_.Index -eq $g.Index })
        if ($now.Count -gt 0) { $out += "GPU$($g.Index): now $([int]$now[0].Limit) W  (set ok=$ok)" }
    }
    try { Add-Content -LiteralPath $log -Value $out -Encoding ASCII } catch {}
}

# ---- rendering helpers ------------------------------------------------------
$script:CSI = ([string][char]27) + '['

function Col([int]$n) { return $script:CSI + '38;5;' + $n + 'm' }
function Rst { return $script:CSI + '0m' }

function Heat([double]$f) { if ($f -lt 0.6) { return 41 }; if ($f -lt 0.85) { return 214 }; return 196 }

function Bar([double]$frac, [int]$w, [int]$col) {
    if ($frac -lt 0) { $frac = 0 }; if ($frac -gt 1) { $frac = 1 }
    $n = [int][math]::Round($frac * $w)
    return (Col $col) + ([string][char]0x2588 * $n) + (Col 238) + ([string][char]0x2591 * ($w - $n)) + (Rst)
}

function Spark($vals, [double]$max, [int]$n, [int]$col) {
    $arr = @($vals)
    if ($arr.Count -gt $n) { $arr = $arr[($arr.Count - $n)..($arr.Count - 1)] }
    if ($max -le 0) { $max = 1 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append((Col $col))
    foreach ($v in $arr) {
        $i = [int][math]::Floor(($v / $max) * 7.999)
        if ($i -lt 0) { $i = 0 }; if ($i -gt 7) { $i = 7 }
        [void]$sb.Append([string][char](0x2581 + $i))
    }
    [void]$sb.Append((Rst))
    return $sb.ToString()
}

function Throttle-Text($g) {
    $t = @()
    if ($g.CapPwr) { $t += 'POWER-CAP' }
    if ($g.Thermal) { $t += 'THERMAL' }
    if ($g.HwSlow) { $t += 'HW-SLOWDOWN' }
    if ($g.Idle) { $t += 'IDLE' }
    return $t
}

# Builds one full monitor frame (array of lines, ANSI coloured). Pure function so it can be tested.
function Build-MonitorLines($gpus, $hist, $want, $flags, [int]$W, [int]$H) {
    $L = New-Object System.Collections.Generic.List[string]
    $g0 = Col 252; $dim = Col 244; $r = Rst
    $L.Add(' ' + (Col 214) + 'WATTCAP LIVE MONITOR' + $dim + '   RTX ' + $script:MatchStr + '   ' + (Get-Date).ToString('HH:mm:ss') + $r)
    $L.Add('')
    if ($W -lt 60) { $L.Add(' Window too narrow - widen it to at least 60 columns.'); return $L }
    $bw = [math]::Max(10, [math]::Min(40, $W - 44))
    $spn = [math]::Max(10, $W - 10)
    $needFull = 3 + 12 * @($gpus).Count + 3
    $compact = ($H -lt $needFull)
    if (@($gpus).Count -eq 0) { $L.Add(' No matching GPUs found (nvidia-smi not reachable or name does not match).') }
    foreach ($g in @($gpus)) {
        $i = $g.Index
        $L.Add(' ' + (Col 45) + ('GPU{0}' -f $i) + $g0 + '  ' + $g.Name + $dim + ('   {0}   {1:0} C   fan {2:0}%' -f $g.PState, $g.Temp, $g.Fan) + $r)
        $lf = $g.Load / 100.0
        $L.Add((' ' + $dim + 'Load  ' + $r) + (Bar $lf $bw (Heat $lf)) + ($g0 + (' {0,4:0}%' -f $g.Load)) + $r)
        $vf = 0; if ($g.VramTotal -gt 0) { $vf = $g.VramUsed / $g.VramTotal }
        $L.Add((' ' + $dim + 'VRAM  ' + $r) + (Bar $vf $bw (Heat $vf)) + ($g0 + (' {0:0} / {1:0} MiB ({2:0}%)' -f $g.VramUsed, $g.VramTotal, ($vf * 100))) + $r)
        $pf = 0; if ($g.Limit -gt 0) { $pf = $g.Power / $g.Limit }
        $L.Add((' ' + $dim + 'Power ' + $r) + (Bar $pf $bw (Heat $pf)) + ($g0 + (' {0:0} W / cap {1:0} W' -f $g.Power, $g.Limit)) + $r)
        $tf = $g.Temp / 100.0
        $L.Add((' ' + $dim + 'Temp  ' + $r) + (Bar $tf $bw (Heat ($g.Temp / 90.0))) + ($g0 + (' {0:0} C' -f $g.Temp)) + $r)
        $L.Add(' ' + $dim + 'Clock ' + $g0 + ('SM {0:0} MHz   MEM {1:0} MHz   stock cap {2:0} W   allowed {3:0}-{4:0} W' -f $g.Sm, $g.Mem, $g.Default, $g.MinL, $g.MaxL) + $r)
        $w = Want-Limit $want $i
        if ([math]::Abs($g.Limit - $w) -le 1) { $ls = (Col 41) + 'OK' } else { $ls = (Col 196) + ('CHANGED - saved limit is {0} W, something overrode it (press R to re-apply)' -f $w) }
        if ($flags.Prot -and $flags.Reduced.ContainsKey($i)) { $ls = (Col 214) + ('AUTO-PROTECT lowered the cap (saved {0} W)' -f $w) }
        $L.Add(' ' + $dim + 'Limit ' + $g0 + ('now {0:0} W, saved {1} W   ' -f $g.Limit, $w) + $ls + $r)
        $tt = @(Throttle-Text $g)
        if ($tt.Count -eq 0) {
            if ($g.Load -gt 5) { $ts = (Col 41) + 'none - running at full speed' } else { $ts = $dim + 'none' }
        } else {
            $ts = (Col 214) + ($tt -join ' + ')
            if ($g.CapPwr) { $ts += $dim + '   (your power limit is holding the clocks back)' }
        }
        $L.Add(' ' + $dim + 'Throttle ' + $r + $ts + $r)
        $hh = $hist[$i]
        if ($null -ne $hh) {
            $L.Add(' ' + $dim + 'Load  ' + $r + (Spark $hh.Load 100 $spn 45))
            if (-not $compact) {
                $L.Add(' ' + $dim + 'Power ' + $r + (Spark $hh.Pwr ([math]::Max(1, $g.MaxL)) $spn 214))
                $L.Add(' ' + $dim + 'VRAM  ' + $r + (Spark $hh.Vram ([math]::Max(1, $g.VramTotal)) $spn 171))
            }
        }
        if (-not $compact) { $L.Add('') }
    }
    $logS = 'OFF'; if ($flags.Log) { $logS = 'ON' }
    $prS = 'OFF'; if ($flags.Prot) { $prS = 'ON' }
    $L.Add(' ' + (Col 252) + '[L]' + $dim + ' log ' + $logS + '   ' + (Col 252) + '[P]' + $dim + ' auto-protect ' + $prS + ' (' + $flags.ProtTemp + ' C)   ' + (Col 252) + '[+/-]' + $dim + ' temp   ' + (Col 252) + '[R]' + $dim + ' re-apply   ' + (Col 252) + '[Q]' + $dim + ' quit' + $r)
    if ($flags.Msg) { $L.Add(' ' + (Col 220) + $flags.Msg + $r) }
    return $L
}

function Log-Throttle($g) {
    $t = @(); if ($g.CapPwr) { $t += 'PWRCAP' }; if ($g.Thermal) { $t += 'THERMAL' }; if ($g.HwSlow) { $t += 'HWSLOW' }; if ($g.Idle) { $t += 'IDLE' }
    if ($t.Count -eq 0) { return 'none' }
    return ($t -join '|')
}

function Start-Monitor {
    $CSI = $script:CSI
    $logFile = Join-Path $script:Base 'monitor-log.csv'
    $want = Read-Limits
    $hist = @{}
    $flags = @{ Log = $false; Prot = $false; ProtTemp = 83; Msg = ''; Reduced = @{} }
    $lastChg = @{}
    $msgAt = Get-Date
    $oldEnc = $null; $oldCC = $false
    try { $oldEnc = [Console]::OutputEncoding } catch {}
    try { $oldCC = [Console]::TreatControlCAsInput } catch {}
    $o = [Console]::Out
    $lastW = 0; $lastH = 0
    try {
        try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
        try { [Console]::TreatControlCAsInput = $true } catch {}
        $o = [Console]::Out
        $o.Write($CSI + '?1049h' + $CSI + '?25l' + $CSI + '2J')
        $nextPoll = [DateTime]::MinValue
        $gpus = @()
        $quit = $false
        while (-not $quit) {
            $now = Get-Date
            if ($now -ge $nextPoll) {
                $nextPoll = $now.AddMilliseconds(1000)
                $gpus = @(Get-Gpus)
                foreach ($g in $gpus) {
                    $i = $g.Index
                    if (-not $hist.ContainsKey($i)) {
                        $hist[$i] = @{ Load = (New-Object System.Collections.ArrayList); Pwr = (New-Object System.Collections.ArrayList); Vram = (New-Object System.Collections.ArrayList) }
                    }
                    $hh = $hist[$i]
                    [void]$hh.Load.Add($g.Load); [void]$hh.Pwr.Add($g.Power); [void]$hh.Vram.Add($g.VramUsed)
                    foreach ($k in 'Load', 'Pwr', 'Vram') { while ($hh[$k].Count -gt 400) { $hh[$k].RemoveAt(0) } }

                    # auto-protect: step the cap down while hot, back up (to the saved value) once cool
                    if ($flags.Prot) {
                        $age = 999.0
                        if ($lastChg.ContainsKey($i)) { $age = ($now - $lastChg[$i]).TotalSeconds }
                        $saved = Want-Limit $want $i
                        if ($g.Temp -ge $flags.ProtTemp -and $age -ge 10) {
                            $new = [int][math]::Max($g.MinL, [math]::Round($g.Limit) - 25)
                            if ($new -lt [int][math]::Round($g.Limit)) {
                                if (Set-Limit $i $new) {
                                    $flags.Reduced[$i] = $true; $lastChg[$i] = $now
                                    $flags.Msg = ('{0}  GPU{1} hit {2:0} C: cap lowered to {3} W' -f $now.ToString('HH:mm:ss'), $i, $g.Temp, $new); $msgAt = $now
                                }
                            }
                        } elseif ($flags.Reduced.ContainsKey($i) -and $g.Temp -le ($flags.ProtTemp - 10) -and $age -ge 20) {
                            $new = [int][math]::Min($saved, [math]::Round($g.Limit) + 25)
                            if (Set-Limit $i $new) {
                                $lastChg[$i] = $now
                                if ($new -ge $saved) { $flags.Reduced.Remove($i) }
                                $flags.Msg = ('{0}  GPU{1} cooled to {2:0} C: cap raised to {3} W' -f $now.ToString('HH:mm:ss'), $i, $g.Temp, $new); $msgAt = $now
                            }
                        }
                    }
                    if ($flags.Log) {
                        try {
                            if (-not (Test-Path $logFile)) {
                                [IO.File]::WriteAllText($logFile, "time,gpu,util_gpu,util_mem,vram_used_mib,vram_total_mib,temp_c,power_w,limit_w,sm_mhz,mem_mhz,fan_pct,pstate,throttle`r`n")
                            }
                            $line = ('{0},{1},{2:0},{3:0},{4:0},{5:0},{6:0},{7:0.0},{8:0},{9:0},{10:0},{11:0},{12},{13}' -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $i, $g.Load, $g.MemLoad, $g.VramUsed, $g.VramTotal, $g.Temp, $g.Power, $g.Limit, $g.Sm, $g.Mem, $g.Fan, $g.PState, (Log-Throttle $g))
                            [IO.File]::AppendAllText($logFile, $line + "`r`n")
                        } catch {}
                    }
                }
                if ($flags.Msg -and ($now - $msgAt).TotalSeconds -gt 12) { $flags.Msg = '' }
            }

            $w = 0; $h = 0
            try { $w = [Console]::WindowWidth; $h = [Console]::WindowHeight } catch {}
            if ($w -lt 20) { $w = 80 }; if ($h -lt 8) { $h = 30 }
            $sb = New-Object System.Text.StringBuilder
            if ($w -ne $lastW -or $h -ne $lastH) { [void]$sb.Append($CSI + '2J'); $lastW = $w; $lastH = $h }
            $lines = Build-MonitorLines $gpus $hist $want $flags $w $h
            $n = 0
            foreach ($ln in $lines) {
                if ($n -ge $h - 1) { break }
                [void]$sb.Append($CSI + ($n + 1) + ';1H' + $ln + $CSI + 'K')
                $n++
            }
            [void]$sb.Append($CSI + ($n + 1) + ';1H' + $CSI + 'J')
            $o.Write($sb.ToString()); $o.Flush()

            $redraw = $false
            for ($s = 0; $s -lt 10 -and -not $quit -and -not $redraw; $s++) {
                while ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    $c = ([string]$k.KeyChar).ToUpper()
                    if ($k.Key -eq 'Escape' -or $c -eq 'Q' -or $k.KeyChar -eq [char]3) { $quit = $true }
                    elseif ($c -eq 'L') {
                        $flags.Log = -not $flags.Log
                        if ($flags.Log) { $flags.Msg = 'Logging to ' + $logFile } else { $flags.Msg = 'Logging stopped' }
                        $msgAt = Get-Date; $redraw = $true
                    }
                    elseif ($c -eq 'P') {
                        $flags.Prot = -not $flags.Prot
                        if (-not $flags.Prot) {
                            foreach ($gi in @($flags.Reduced.Keys)) { [void](Set-Limit $gi (Want-Limit $want $gi)) }
                            $flags.Reduced = @{}
                            $flags.Msg = 'Auto-protect off, saved limits restored'
                        } else { $flags.Msg = ('Auto-protect on: lowers the cap 25 W at a time above {0} C' -f $flags.ProtTemp) }
                        $msgAt = Get-Date; $redraw = $true
                    }
                    elseif ($c -eq '+' -or $c -eq '=') { if ($flags.ProtTemp -lt 95) { $flags.ProtTemp++ }; $redraw = $true }
                    elseif ($c -eq '-') { if ($flags.ProtTemp -gt 60) { $flags.ProtTemp-- }; $redraw = $true }
                    elseif ($c -eq 'R') {
                        $want = Read-Limits
                        foreach ($g in $gpus) { [void](Set-Limit $g.Index (Want-Limit $want $g.Index)) }
                        $flags.Reduced = @{}
                        $flags.Msg = 'Saved limits re-applied'; $msgAt = Get-Date
                        $nextPoll = [DateTime]::MinValue; $redraw = $true
                    }
                }
                if (-not $redraw -and -not $quit) { Start-Sleep -Milliseconds 100 }
            }
        }
    } finally {
        foreach ($gi in @($flags.Reduced.Keys)) { try { [void](Set-Limit $gi (Want-Limit $want $gi)) } catch {} }
        try { $o.Write($CSI + '0m' + $CSI + '2J' + $CSI + '?25h' + $CSI + '?1049l'); $o.Flush() } catch {}
        try { [Console]::TreatControlCAsInput = $oldCC } catch {}
        try { if ($oldEnc) { [Console]::OutputEncoding = $oldEnc } } catch {}
    }
}

# ---- usage / efficiency report from monitor-log.csv ---------------------------------
function Get-Report([string]$csv) {
    $rows = @(Import-Csv -LiteralPath $csv)
    $o = New-Object System.Collections.Generic.List[string]
    if ($rows.Count -eq 0) { $o.Add('The log is empty.'); return $o }
    $first = $rows[0].time; $last = $rows[$rows.Count - 1].time
    $o.Add(('Samples: {0}   from {1}   to {2}' -f $rows.Count, $first, $last))
    $o.Add('')
    foreach ($gp in ($rows | Group-Object gpu | Sort-Object { [int]$_.Name })) {
        $a = @($gp.Group)
        $pv = ($a | ForEach-Object { Num $_.vram_used_mib } | Measure-Object -Maximum).Maximum
        $pt = ($a | ForEach-Object { Num $_.temp_c } | Measure-Object -Maximum).Maximum
        $pp = ($a | ForEach-Object { Num $_.power_w } | Measure-Object -Maximum).Maximum
        $o.Add(('GPU{0}: peak VRAM {1:0} MiB, peak power {2:0} W, peak temp {3:0} C' -f $gp.Name, $pv, $pp, $pt))
        $busy = @($a | Where-Object { (Num $_.util_gpu) -ge 70 })
        if ($busy.Count -eq 0) { $o.Add('   no samples with load >= 70% yet - run a game or render with logging on [L].'); $o.Add(''); continue }
        $o.Add('   Under load (>= 70%), grouped by power limit:')
        $o.Add('   limit    samples   avg load   avg power   avg SM clock   MHz per W   time power-capped')
        foreach ($lg in ($busy | Group-Object limit_w | Sort-Object { [int]$_.Name } -Descending)) {
            $b = @($lg.Group)
            $al = ($b | ForEach-Object { Num $_.util_gpu } | Measure-Object -Average).Average
            $ap = ($b | ForEach-Object { Num $_.power_w } | Measure-Object -Average).Average
            $ac = ($b | ForEach-Object { Num $_.sm_mhz } | Measure-Object -Average).Average
            $cap = @($b | Where-Object { $_.throttle -match 'PWRCAP' }).Count * 100.0 / $b.Count
            $eff = 0; if ($ap -gt 0) { $eff = $ac / $ap }
            $o.Add(('   {0,4} W  {1,7}   {2,7:0}%   {3,7:0} W   {4,9:0} MHz   {5,9:0.0}   {6,10:0}%' -f $lg.Name, $b.Count, $al, $ap, $ac, $eff, $cap))
        }
        $o.Add('')
    }
    $o.Add('How to read it: a higher SM clock at the same load means more speed. MHz per W is the efficiency.')
    $o.Add('"time power-capped" is how often your limit held the clocks back. Log a session at each limit to compare.')
    return $o
}

function Start-Report {
    $csv = Join-Path $script:Base 'monitor-log.csv'
    Clear-Host
    Write-Host ''
    Write-Host '  WATTCAP usage and efficiency report' -ForegroundColor Yellow
    Write-Host ''
    if (-not (Test-Path $csv)) {
        Write-Host '  No log yet. Open the Live monitor [M], press L to start logging, use your GPU'
        Write-Host '  (game / render / AI job), and run this report again. Switch power limits between'
        Write-Host '  sessions to compare them.'
    } else {
        foreach ($l in (Get-Report $csv)) { Write-Host ('  ' + $l) }
        Write-Host "  Log file: $csv"
    }
    Write-Host ''
    Write-Host '  Press any key...'
    try { [void][Console]::ReadKey($true) } catch {}
}

# ---- profiles and per-card limits -------------------------------------------------------
function Parse-Spec([string]$spec) {
    $h = @{}
    foreach ($part in ($spec -split ';')) {
        if ($part -match '^\s*(ALL|\d+)\s*=\s*(\d+)\s*$') { $h[$Matches[1].ToUpper()] = [int]$Matches[2] }
    }
    return $h
}

function Spec-Text($h) {
    $keys = @($h.Keys | Where-Object { $_ -ne 'ALL' } | Sort-Object { [int]$_ })
    $parts = @()
    if ($h.ContainsKey('ALL')) { $parts += "ALL=$($h['ALL'])" }
    foreach ($k in $keys) { $parts += "$k=$($h[$k])" }
    return ($parts -join ';')
}

function Read-Profiles {
    $f = Join-Path $script:Base 'profiles.txt'
    $p = [ordered]@{}
    if (Test-Path $f) {
        foreach ($l in @(Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)) {
            if ($l -match '^([^|]+)\|(.+)$') { $p[$Matches[1].Trim()] = $Matches[2].Trim() }
        }
    }
    if ($p.Count -eq 0) {
        $p['Gaming'] = 'ALL=340'; $p['Balanced'] = 'ALL=310'; $p['Render'] = 'ALL=275'; $p['Quiet'] = 'ALL=225'; $p['Silent'] = 'ALL=200'
        Save-Profiles $p
    }
    return $p
}

function Save-Profiles($p) {
    $lines = @($p.Keys | ForEach-Object { "$_|$($p[$_])" })
    Set-Content -LiteralPath (Join-Path $script:Base 'profiles.txt') -Value $lines -Encoding ASCII
}

# validates a limits table against each card's allowed range; returns error strings
function Test-Limits($h, $gpus) {
    $err = @()
    foreach ($g in @($gpus)) {
        $w = Want-Limit $h $g.Index
        if ($w -lt $g.MinL) { $err += "GPU$($g.Index): $w W is below the minimum ($([int]$g.MinL) W)" }
        if ($w -gt $g.MaxL) { $err += "GPU$($g.Index): $w W is above the maximum ($([int]$g.MaxL) W)" }
    }
    return $err
}

function Apply-Limits($h, $gpus) {
    $err = Test-Limits $h $gpus
    if ($err.Count -gt 0) { foreach ($e in $err) { Write-Host "  $e" -ForegroundColor Red }; return $false }
    Write-Limits $h
    foreach ($g in @($gpus)) {
        $w = Want-Limit $h $g.Index
        $ok = Set-Limit $g.Index $w
        if ($ok) { Write-Host ("  GPU{0}: {1} W applied" -f $g.Index, $w) -ForegroundColor Green } else { Write-Host ("  GPU{0}: could not set {1} W" -f $g.Index, $w) -ForegroundColor Red }
    }
    return $true
}

function Start-Profiles {
    $changed = $false
    while ($true) {
        $gpus = @(Get-Gpus)
        $profiles = Read-Profiles
        $cur = Read-Limits
        Clear-Host
        Write-Host ''
        Write-Host '  WATTCAP profiles and per-card limits' -ForegroundColor Yellow
        Write-Host ''
        $cs = Limits-Summary $cur; if (-not $cs) { $cs = 'none saved (stock or script default)' }
        Write-Host "  Boot setting now: $cs"
        foreach ($g in $gpus) { Write-Host ("    GPU{0}  {1}  live cap {2:0} W   allowed {3:0}-{4:0} W" -f $g.Index, $g.Name, $g.Limit, $g.MinL, $g.MaxL) -ForegroundColor DarkGray }
        Write-Host ''
        $names = @($profiles.Keys)
        for ($i = 0; $i -lt $names.Count; $i++) {
            $h = Parse-Spec $profiles[$names[$i]]
            Write-Host ("   [{0}] {1,-12} {2}" -f ($i + 1), $names[$i], (Limits-Summary $h))
        }
        Write-Host ''
        Write-Host '   [C] Custom limit per card     [S] Save current as a profile'
        Write-Host '   [D] Delete a profile          [B] Back'
        Write-Host ''
        $k = (Read-Host '  Select').Trim()
        if ($k -eq '' -or $k -match '^[Bb]$') { break }
        if ($k -match '^\d+$' -and [int]$k -ge 1 -and [int]$k -le $names.Count) {
            $h = Parse-Spec $profiles[$names[[int]$k - 1]]
            Write-Host ''
            if (Apply-Limits $h $gpus) { $changed = $true; Write-Host '  Saved - it will be applied on every boot.' -ForegroundColor Green }
            [void](Read-Host '  Press Enter')
        }
        elseif ($k -match '^[Cc]$') {
            $h = @{}
            Write-Host ''
            foreach ($g in $gpus) {
                $def = Want-Limit $cur $g.Index
                while ($true) {
                    $v = (Read-Host ("  GPU{0} watts ({1:0}-{2:0}, Enter = {3})" -f $g.Index, $g.MinL, $g.MaxL, $def)).Trim()
                    if ($v -eq '') { $w = $def } elseif ($v -match '^\d{1,4}$') { $w = [int]$v } else { Write-Host '  Whole number please.' -ForegroundColor Red; continue }
                    if ($w -lt $g.MinL -or $w -gt $g.MaxL) { Write-Host ('  Must be {0:0}-{1:0} W.' -f $g.MinL, $g.MaxL) -ForegroundColor Red; continue }
                    $h["$($g.Index)"] = $w; break
                }
            }
            Write-Host ''
            if (Apply-Limits $h $gpus) {
                $changed = $true; Write-Host '  Saved - it will be applied on every boot.' -ForegroundColor Green
                $nm = (Read-Host '  Save as a profile? Name (Enter = no)').Trim() -replace '[|;=]', ''
                if ($nm) { $profiles[$nm] = Spec-Text $h; Save-Profiles $profiles }
            }
            [void](Read-Host '  Press Enter')
        }
        elseif ($k -match '^[Ss]$') {
            if ($cur.Count -eq 0) { Write-Host '  Nothing saved yet to store.' -ForegroundColor Red }
            else {
                $nm = (Read-Host '  Profile name').Trim() -replace '[|;=]', ''
                if ($nm) { $profiles[$nm] = Spec-Text $cur; Save-Profiles $profiles; Write-Host "  Saved profile $nm" -ForegroundColor Green }
            }
            [void](Read-Host '  Press Enter')
        }
        elseif ($k -match '^[Dd]$') {
            $d = (Read-Host '  Number to delete').Trim()
            if ($d -match '^\d+$' -and [int]$d -ge 1 -and [int]$d -le $names.Count) { $profiles.Remove($names[[int]$d - 1]); Save-Profiles $profiles }
        }
    }
    return $changed
}

# ---- compile / load the C# renderer (cached as a hash-named DLL) -------------------------
function Ensure-Type {
    if ('WattCap.Intro' -as [type]) { return }
    $src = $script:WattCapSource
    $sha = [Security.Cryptography.SHA1]::Create()
    $h = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($src))[0..5] | ForEach-Object { $_.ToString('x2') })
    $dll = Join-Path $script:Base "wattcap-intro-$h.dll"
    if (-not (Test-Path $dll)) {
        Get-ChildItem -Path $script:Base -Filter 'wattcap-intro-*.dll' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        try { Add-Type -TypeDefinition $src -OutputAssembly $dll -OutputType Library -ErrorAction Stop } catch {}
    }
    if (-not ('WattCap.Intro' -as [type]) -and (Test-Path $dll)) {
        try { Add-Type -Path $dll -ErrorAction Stop } catch {}
    }
    if (-not ('WattCap.Intro' -as [type])) { Add-Type -TypeDefinition $src }
}

function Invoke-WattCap {
    $watts = 310; if ($env:WATTS -match '^\d+$') { $watts = [int]$env:WATTS }
    $match = '3090'; if ($env:MATCH) { $match = $env:MATCH }
    $mode = 'intro'; if ($env:WC_MODE) { $mode = $env:WC_MODE }
    $style = 'auto'; if ($env:WC_STYLE) { $style = $env:WC_STYLE.ToLower() }
    $root = $env:ProgramData; if (-not $root) { $root = [IO.Path]::GetTempPath() }
    $base = Join-Path $root 'GPUPowerLimit'
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -Force | Out-Null }
    $script:Base = $base
    $script:MatchStr = $match
    $script:DefaultW = $watts
    $script:Smi = Find-Smi

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

    if ($mode -eq 'verify') { Start-Verify; return }
    if ($mode -eq 'report') { if (-not $script:WattCapNoRun) { Start-Report }; return }
    if ($mode -eq 'profiles') {
        if ($script:WattCapNoRun) { return }
        if (-not $script:Smi) { Write-Host '  nvidia-smi not found.'; Start-Sleep -Seconds 2; return }
        if (Start-Profiles) { exit 10 }
        return
    }
    if ($mode -eq 'monitor') {
        if ($script:WattCapNoRun) { return }
        if (-not $script:Smi) { Write-Host '  nvidia-smi not found.'; Start-Sleep -Seconds 2; return }
        Ensure-Type
        [WattCap.Intro]::EnableVT()
        Start-Monitor
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
        if ($script:Smi) {
            $rows = & $script:Smi --query-gpu=index,name,power.limit,power.default_limit,temperature.gpu --format=csv,noheader,nounits 2>$null
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

    Ensure-Type

    # the animations show the saved limit (first card's value) when one exists
    $lim = Read-Limits
    if ($lim.Count -gt 0) { $watts = Want-Limit $lim 0 }

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

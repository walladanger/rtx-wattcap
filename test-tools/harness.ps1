$IntroNoRun = $true; $IntroW = 120; $IntroH = 30
$env:INTRO_SEED = $args[0]
. ./intro.ps1
$times = 0.3,1.0,1.6,2.6,3.6,4.6,6.9
foreach ($t in $times) {
  $sw=[Diagnostics.Stopwatch]::StartNew(); $f = Render-Frame $t; $ms=$sw.ElapsedMilliseconds
  [IO.File]::WriteAllText("frames/s$($args[0])_t$t.ans", $f)
  "t=$t  ${ms}ms  len=$($f.Length)"
}
"palette=$($pal.n) cap=$cap"

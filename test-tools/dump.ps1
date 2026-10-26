# usage: dump.ps1 -Dll path -Style peaks -Seed 4213 -Spec "0.5@100x30,3@100x30"  -> writes frames\f000.ans ...
param([string]$Dll, [string]$Style='peaks', [int]$Seed=4213, [string]$Spec, [string]$Out='frames', [int]$Watts=310, [int]$Stock=350)
Add-Type -Path $Dll
[WattCap.Intro]::Style=$Style; [WattCap.Intro]::Seed=$Seed; [WattCap.Intro]::NGpu=2; [WattCap.Intro]::Watts=$Watts; [WattCap.Intro]::Stock=$Stock
[WattCap.Intro]::Ticker='  >>  GPU0  NVIDIA GeForce RTX 3090  310 W now / 350 W stock  ::  test ticker  '
$t=@(); $w=@(); $h=@()
foreach ($e in $Spec.Split(',')) { $a=$e.Split('@'); $t+= [double]$a[0]; $wh=$a[1].Split('x'); $w+=[int]$wh[0]; $h+=[int]$wh[1] }
New-Item -ItemType Directory -Force $Out | Out-Null
Remove-Item "$Out\*.ans" -ErrorAction SilentlyContinue
[WattCap.Intro]::Dump((Resolve-Path $Out).Path, [double[]]$t, [int[]]$w, [int[]]$h)
"end=$([WattCap.Intro]::SceneEnd())"

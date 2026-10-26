$IntroNoRun = $true; $IntroW = 120; $IntroH = 30; $env:INTRO_SEED = '4213'
. ./intro.ps1
# sample ticker data standing in for 2x 3090 (no GPU in this sandbox)
$tick = '  >>  GPU0  NVIDIA GeForce RTX 3090  310 W now / 350 W stock  41 C  ::  GPU1  NVIDIA GeForce RTX 3090  310 W now / 350 W stock  39 C  ::  target 310 W per card (89% of stock)  ::  seed 4213 / orchid  ::  any key skips  '
while ($tick.Length -lt $W * 2) { $tick += $tick }
$sub = ("POWER LIMIT  //  310 W  x2".ToCharArray() -join ' '); $subX = [int][Math]::Floor(($W - $sub.Length) / 2)
for ($n = 0; $n -lt 84; $n++) { [IO.File]::WriteAllText(("gif/f{0:000}.ans" -f $n), (Render-Frame ($n / 12.0))) }

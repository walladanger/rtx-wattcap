# Renders ANSI frames produced by [WattCap.Intro]::Dump into PNGs and a contact sheet (Windows PowerShell 5.1, System.Drawing).
# usage: ans2png.ps1 -Dir frames -Cols 100 -Rows 30 -Sheet sheet.png -Labels "a,b,c"
param([string]$Dir, [int]$Cols=100, [int]$Rows=30, [string]$Sheet, [int]$Per=2, [string]$Labels="")
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Drawing; using System.Text.RegularExpressions; using System.IO;
public static class Ans {
  static Color C(int n){
    if(n<16){int[][] b={new[]{0,0,0},new[]{128,0,0},new[]{0,128,0},new[]{128,128,0},new[]{0,0,128},new[]{128,0,128},new[]{0,128,128},new[]{192,192,192},new[]{128,128,128},new[]{255,0,0},new[]{0,255,0},new[]{255,255,0},new[]{0,0,255},new[]{255,0,255},new[]{0,255,255},new[]{255,255,255}};return Color.FromArgb(b[n][0],b[n][1],b[n][2]);}
    if(n<232){n-=16;int[] lv={0,95,135,175,215,255};return Color.FromArgb(lv[n/36],lv[(n/6)%6],lv[n%6]);}
    int v=8+(n-232)*10;return Color.FromArgb(v,v,v);}
  public static Bitmap Render(string s,int cols,int rows,int cw,int ch){
    Color[,] bg=new Color[rows,cols],fg=new Color[rows,cols];char[,] tx=new char[rows,cols];
    Color dbg=Color.FromArgb(12,12,12),dfg=Color.FromArgb(204,204,204);
    for(int y=0;y<rows;y++)for(int x=0;x<cols;x++){bg[y,x]=dbg;fg[y,x]=dfg;tx[y,x]=' ';}
    int r=0,c=0;Color f=dfg,b=dbg;
    foreach(Match m in Regex.Matches(s,"\u001b\\[([\\d;?]*)([A-Za-z])|(.)",RegexOptions.Singleline)){
      if(m.Groups[3].Success){char k=m.Groups[3].Value[0];if(k=='\n'){r++;c=0;continue;}if(r>=0&&r<rows&&c>=0&&c<cols){tx[r,c]=k;fg[r,c]=f;bg[r,c]=b;}c++;continue;}
      string a=m.Groups[1].Value;char cmd=m.Groups[2].Value[0];
      if(cmd=='H'){string[] p=a.Split(';');r=(p.Length>0&&p[0]!=""?int.Parse(p[0]):1)-1;c=(p.Length>1&&p[1]!=""?int.Parse(p[1]):1)-1;}
      else if(cmd=='J'){}
      else if(cmd=='m'){string[] p=a==""?new[]{"0"}:a.Split(';');for(int i=0;i<p.Length;i++){int v=p[i]==""?0:int.Parse(p[i]);if(v==0){f=dfg;b=dbg;}else if(v==38&&i+2<p.Length){f=C(int.Parse(p[i+2]));i+=2;}else if(v==48&&i+2<p.Length){b=C(int.Parse(p[i+2]));i+=2;}}}
    }
    Bitmap bmp=new Bitmap(cols*cw,rows*ch);
    using(Graphics g=Graphics.FromImage(bmp)){
      Font font=new Font("Consolas",ch*0.6f,GraphicsUnit.Pixel);
      for(int y=0;y<rows;y++)for(int x=0;x<cols;x++){
        using(SolidBrush bb=new SolidBrush(bg[y,x]))g.FillRectangle(bb,x*cw,y*ch,cw,ch);
        char k=tx[y,x];
        if(k=='\u2580'){using(SolidBrush fb=new SolidBrush(fg[y,x]))g.FillRectangle(fb,x*cw,y*ch,cw,ch/2);}
        else if(k!=' '){using(SolidBrush fb=new SolidBrush(fg[y,x]))g.DrawString(k.ToString(),font,fb,x*cw,y*ch);}
      }}
    return bmp;}
}
'@ -ReferencedAssemblies System.Drawing
$files = Get-ChildItem $Dir -Filter *.ans | Sort-Object Name
$labs = $Labels -split ','
$bmps=@(); $i=0
foreach($f in $files){ $bm=[Ans]::Render([IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8),$Cols,$Rows,6,12)
  $g=[Drawing.Graphics]::FromImage($bm); if($i -lt $labs.Count -and $labs[$i]){ $g.DrawString($labs[$i],(New-Object Drawing.Font('Consolas',11)),[Drawing.Brushes]::Yellow,4,2) }; $g.Dispose()
  $bmps+=$bm; $i++ }
$w=$bmps[0].Width; $h=$bmps[0].Height; $rowsN=[math]::Ceiling($bmps.Count/$Per)
$S=New-Object Drawing.Bitmap(($w*$Per+8*($Per-1)),($h*$rowsN+8*($rowsN-1)))
$g=[Drawing.Graphics]::FromImage($S); $g.Clear([Drawing.Color]::FromArgb(60,60,60))
for($k=0;$k -lt $bmps.Count;$k++){ $g.DrawImage($bmps[$k],(($k%$Per)*($w+8)),([math]::Floor($k/$Per)*($h+8))) }
$S.Save($Sheet,[Drawing.Imaging.ImageFormat]::Png); "saved $Sheet $($S.Width)x$($S.Height)"

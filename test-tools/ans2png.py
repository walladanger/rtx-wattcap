import re, sys
from PIL import Image, ImageDraw, ImageFont
def c256(n):
    if n < 16:
        base=[(0,0,0),(128,0,0),(0,128,0),(128,128,0),(0,0,128),(128,0,128),(0,128,128),(192,192,192),(128,128,128),(255,0,0),(0,255,0),(255,255,0),(0,0,255),(255,0,255),(0,255,255),(255,255,255)]
        return base[n]
    if n < 232:
        n-=16; lv=[0,95,135,175,215,255]; return (lv[n//36],lv[(n//6)%6],lv[n%6])
    v=8+(n-232)*10; return (v,v,v)
def render(path, out, cols=120, rows=30, cw=8, chh=16, fs=13):
    s=open(path,encoding='utf-8').read()
    grid=[[(' ',(204,204,204),(12,12,12)) for _ in range(cols)] for _ in range(rows)]
    r=c=0; fg=(204,204,204); bg=(12,12,12)
    for m in re.finditer(r'\x1b\[([\d;?]*)([A-Za-z])|(.)', s, re.S):
        if m.group(3) is not None:
            ch=m.group(3)
            if ch=='\n': r+=1; c=0; continue
            if 0<=r<rows and 0<=c<cols: grid[r][c]=(ch,fg,bg)
            c+=1; continue
        a,cmd=m.group(1),m.group(2)
        if cmd=='H':
            p=[int(x) if x else 1 for x in a.split(';')] if a else [1,1]; r,c=p[0]-1,p[1]-1
        elif cmd=='m':
            p=[int(x) for x in a.split(';') if x!=''] or [0]
            i=0
            while i<len(p):
                if p[i]==0: fg=(204,204,204); bg=(12,12,12)
                elif p[i]==38: fg=c256(p[i+2]); i+=2
                elif p[i]==48: bg=c256(p[i+2]); i+=2
                i+=1
    f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',fs)
    img=Image.new('RGB',(cols*cw,rows*chh),(12,12,12)); d=ImageDraw.Draw(img)
    for y in range(rows):
        for x in range(cols):
            t,fgc,bgc=grid[y][x]
            d.rectangle([x*cw,y*chh,x*cw+cw-1,y*chh+chh-1],fill=bgc)
            if t=='█': d.rectangle([x*cw,y*chh,x*cw+cw-1,y*chh+chh-1],fill=fgc)
            elif t=='\u2580': d.rectangle([x*cw,y*chh,x*cw+cw-1,y*chh+chh//2-1],fill=fgc)
            elif t!=' ': d.text((x*cw,y*chh),t,font=f,fill=fgc)
    img.save(out)
if __name__=='__main__':
    import glob
    for p in sorted(glob.glob(sys.argv[1])): render(p, p.replace('.ans','.png'))

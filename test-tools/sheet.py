import sys
sys.path.insert(0,'.')
from ans2png import render
from PIL import Image, ImageDraw
def sheet(items, out, per_row=2, pad=12):
    ims=[]
    for f,c,r,label in items:
        png=f.replace('.ans','.png'); render(f,png,cols=c,rows=r); im=Image.open(png)
        d=ImageDraw.Draw(im); d.text((4,2),label,fill=(255,255,0)); ims.append(im)
    rowsl=[ims[i:i+per_row] for i in range(0,len(ims),per_row)]
    W=max(sum(i.size[0] for i in r)+pad*(len(r)-1) for r in rowsl); H=sum(max(i.size[1] for i in r) for r in rowsl)+pad*(len(rowsl)-1)
    S=Image.new('RGB',(W,H),(60,60,60)); y=0
    for r in rowsl:
        x=0
        for im in r: S.paste(im,(x,y)); x+=im.size[0]+pad
        y+=max(i.size[1] for i in r)+pad
    S.save(out); print(out,S.size)
if __name__=='__main__':
    import json; sheet(json.loads(sys.argv[1]), sys.argv[2], int(sys.argv[3]) if len(sys.argv)>3 else 2)

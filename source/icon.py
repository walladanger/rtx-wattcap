from PIL import Image, ImageDraw, ImageFilter
import math
S=1024
def make(cap=310/350):
    im=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(im)
    # tile
    d.rounded_rectangle([24,24,S-24,S-24],radius=200,fill=(17,19,24,255),outline=(58,63,74,255),width=14)
    cx,cy,R,Wd=512,600,360,96
    # arc segments: semicircle 180->360 (PIL: clockwise from +x, y down => top half)
    def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
    G,Y,Rd=(52,208,127),(245,197,66),(229,72,77)
    steps=240
    for i in range(steps):
        f0=i/steps; f1=(i+1)/steps+0.002
        if f0<cap:
            c=lerp(G,Y,f0/cap) if f0<cap*0.75 else lerp(Y,(245,140,50),(f0-cap*0.75)/(cap*0.25))
        else:
            c=(110,36,40)   # clipped zone: dim red
        d.arc([cx-R,cy-R,cx+R,cy+R],180+180*f0,180+180*f1,fill=c+(255,),width=Wd)
    # hatch the clipped zone
    for k in range(6):
        f=cap+(1-cap)*(k+0.5)/6; a=math.radians(180+180*f)
        r0,r1=R-Wd+8,R-8
        d.line([cx+r0*math.cos(a),cy+r0*math.sin(a),cx+r1*math.cos(a)+10,cy+r1*math.sin(a)-6],fill=(229,72,77,255),width=10)
    # cap tick
    a=math.radians(180+180*cap)
    d.line([cx+(R-Wd-30)*math.cos(a),cy+(R-Wd-30)*math.sin(a),cx+(R+26)*math.cos(a),cy+(R+26)*math.sin(a)],fill=(255,255,255,255),width=18)
    # needle (tapered)
    L=R-40; w=30
    tip=(cx+L*math.cos(a),cy+L*math.sin(a))
    px,py=-math.sin(a),math.cos(a)
    d.polygon([(cx+px*w,cy+py*w),tip,(cx-px*w,cy-py*w),(cx-60*math.cos(a),cy-60*math.sin(a))],fill=(240,242,245,255))
    # hub
    d.ellipse([cx-70,cy-70,cx+70,cy+70],fill=(245,166,35,255)); d.ellipse([cx-30,cy-30,cx+30,cy+30],fill=(17,19,24,255))
    # bolt
    bx,by=512,780
    bolt=[(bx+40,by-70),(bx-70,by+40),(bx-5,by+40),(bx-40,by+150),(bx+80,by+15),(bx+12,by+15),(bx+55,by-70)]
    d.polygon(bolt,fill=(245,166,35,255))
    return im
im=make()
im.save('wattcap_1024.png')
ico_sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)]
im.resize((256,256),Image.LANCZOS).save('wattcap.ico',sizes=ico_sizes)
# preview strip
strip=Image.new('RGBA',(256+128+64+48+32+16+60*1,256),(40,40,40,255)); x=0
for s in [256,128,64,48,32,16]:
    strip.paste(im.resize((s,s),Image.LANCZOS),(x,256-s)); x+=s+10
strip.save('icon_preview.png')
import os; print(os.path.getsize('wattcap.ico'),'bytes')

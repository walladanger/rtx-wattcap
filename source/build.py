import base64, textwrap
b=open('batch_part.cmd').read()
b=b.replace("::   %1 = intro ^| shortcut     %2 = invaders ^| plasma\n","::   arg1 = intro or shortcut, arg2 = invaders or plasma\n")
b=b.replace('@@BANNER@@',open('banner.bat.txt').read().rstrip('\n'))
cs=open('intro.cs').read(); assert "\n'@" not in cs
ico=base64.b64encode(open('wattcap.ico','rb').read()).decode()
p=open('payload.ps1').read()
p+="\n$script:WattCapSource = @'\n"+cs.rstrip('\n')+"\n'@\n"
p+="\n$script:WattCapIcon = @'\n"+'\n'.join(textwrap.wrap(ico,100))+"\n'@\n\nInvoke-WattCap\n"
full=(b+p).replace('\r\n','\n')
assert full.count('<#WATTCAP#>')==1
full.encode('ascii')
open('gpu-power-limit.cmd','w',newline='').write(full.replace('\n','\r\n'))
print(len(full),'chars', max(len(l) for l in full.split('\n')),'max line')

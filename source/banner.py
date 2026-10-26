import pyfiglet
wa=pyfiglet.figlet_format('WATT',font='small').split('\n')[:4]
ca=pyfiglet.figlet_format('CAP',font='small').split('\n')[:4]
ww=max(len(l) for l in wa); wa=[l.ljust(ww) for l in wa]
word=[a+c for a,c in zip(wa,ca)]
# gauge: list of lines, each a list of (text,color)
G,Y,O,R,N,H,F=41,220,208,196,231,214,240
gauge=[
 [("    ",F),("_.-",G),("''",Y),("''",Y),("-._",O)],
 [("  .'",G),(" .",G),("  '  ",Y),(". ",O),("'.",R)],
 [(" / ",G),(".",G),("      ",F),("_.-'",N),(" ",F),("\\",R)],
 [("| ",G),(".",G),("    ",F),("(O)",H),("'",N),("     ",F),("|",R)],
 [("'._____________.'",F)],
]
W=17
def pad(segs):
    n=sum(len(t) for t,_ in segs); return segs+[(" "*(W-n),F)]
split=word[0].find('_   ___')   # approx start of 'C'
cstart=ww
lines=[]
for i in range(5):
    segs=pad(gauge[i])+[("  ",F)]
    if i<4:
        wl=word[i]
        segs+= [(wl[:cstart],252),(wl[cstart:],214)]
    else:
        segs+= [("RTX %MATCH% power limiter  ::  target %WATTS% W/card",244)]
    lines.append(segs)
def bat(t):
    return t.replace('^','^^').replace('|','^|').replace('&','^&').replace('<','^<').replace('>','^>')
out=[]
for segs in lines:
    s='echo  '
    for t,c in segs:
        s+='%ESC%[38;5;'+str(c)+'m'+(bat(t) if '%' not in t else t)
    s+='%ESC%[0m'
    out.append(s)
open('banner.bat.txt','w').write('\n'.join(out)+'\n')
# ANSI preview with sample values
E='\x1b'
prev=''
for r,segs in enumerate(lines):
    prev+=E+'[%d;1H'%(r+2)+'  '
    for t,c in segs:
        prev+=E+'[38;5;%dm'%c+t.replace('%MATCH%','3090').replace('%WATTS%','310')
    prev+=E+'[0m'
menu=['','  '+'-'*62,'   Boot task: INSTALLED    target 310 W  x RTX 3090','  '+'-'*62,
'   [1] Set 310 W on every boot (install)','   [2] Reset to stock (remove boot task)','   [3] Show current limits',
'   [4] Desktop + Start menu shortcut (with logo)','   [I] Replay intro     [P] Plasma intro','   [Q] Quit','','  Select: ']
for i,m in enumerate(menu): prev+=E+'[%d;1H'%(8+i)+E+'[38;5;250m'+m+E+'[0m'
open('frames/banner.ans','w').write(prev)
print('\n'.join(out))

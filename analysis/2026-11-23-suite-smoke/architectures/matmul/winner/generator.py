from candidate_tools import baseline,load,mac,store,mul,issue

def solve(ws,mode,trace=False):
    ops=[];ld=[];end={};first={};need=[];started=[0];sd=[];fin=[];base=0
    for z,w in enumerate(ws):
        for u in range(16):
            k=15-u if z%2 else u
            pairs=[(r,j) for j in range(w) for r in range(2)] if mode==0 else [(r,j) for h in range(0,w,2) for r in range(2) for j in range(h,min(w,h+2))]
            if mode==2:pairs=[(r,j) for r in range(2) for j in range(w)]
            for r,j in pairs:
                d=r*16+base+j;a=(z-1 if u==0 and z else z,k,r);b=(z,k,2+j)
                for p in (a,b):
                    if p not in end:ld.append(p)
                    end[p]=len(ops)+1
                ops.append((a,b,d,u));need.append(len(ld));started.append(started[-1]+(u==0))
                if u==15:sd.append(d);fin.append(len(ops))
        base+=w
    n=len(ops);m=len(ld);rel=[0]*(n+1);deaths=[0]*(n+1)
    for e in end.values():rel[e]+=1
    deaths=rel[:]
    for i in range(n):rel[i+1]+=rel[i]
    init=(0,0,0,0);front=[init];par={init:None};cost=0
    while front:
        nf=[]
        for s in front:
            i,j,v,h=s
            if v==len(sd):
                if not trace:return cost
                steps=[]
                while par[s] is not None:
                    s,c=par[s];steps.append(c)
                free=list(range(1,16));regs={};acc={};i=j=v=0;sch=[];offset=[sum(ws[:z]) for z in range(len(ws))]
                for t,c in enumerate(reversed(steps)):
                    if c==0:
                        p=ld[j];j+=1;z,k,x=p;d=free.pop();regs[p]=d;sch.append((t,'A' if x<2 else 'B',d,k,x if x<2 else offset[z]+x-2))
                    if c==1:
                        a,b,d,u=ops[i];i+=1;ra=regs[a];rb=regs[b]
                        for p in (a,b):
                            if end[p]==i:free.append(regs.pop(p))
                        if not u:acc[d]=free.pop()
                        sch.append((t,'M',acc[d],ra,rb,u))
                    if c==2:
                        d=sd[v];v+=1;r=acc.pop(d);sch.append((t,'S',r,d));free.append(r)
                return sch
            live=j-rel[i]+started[i]-v;hh=(h*2)&3;opts=[]
            if j<m and live<15 and not h&2:opts.append(((i,j+1,v,hh),0))
            if i<n and j>=need[i] and live+(ops[i][3]==0)-deaths[i+1]<=15:
                d=ops[i][2]
                if not ((h&1 and ops[i-1][2]==d) or (h&2 and ops[i-1-(h&1)][2]==d)):opts.append(((i+1,j,v,hh+1),1))
            if v<len(sd) and fin[v]<=i-(h&1)-((h>>1)&1):opts.append(((i,j,v+1,hh),2))
            if h:opts.append(((i,j,v,hh),3))
            for ns,c in opts:
                if ns not in par:par[ns]=(s,c) if trace else 1;nf.append(ns)
        front=nf;cost+=1
    return 100000

def build():
    c=baseline();A=[8*(16*(i%2)+k)+i//2 for i in range(16) for k in range(16)];B=[256+8*(2*k+j%2)+j//2 for k in range(16) for j in range(16)];C=[512+8*(16*(i%2)+j)+i//2 for i in range(16) for j in range(16)];c['layout']['inputs']=A+B;c['layout']['outputs']=C
    opts=[]
    for mode in range(3):
        costs={w:solve([w],mode) for w in range(2,7)}
        def visit(p,n):
            if not n:opts.append((sum(costs[w] for w in p),tuple(p),mode))
            for w in costs:
                if w<=n:visit(p+[w],n-w)
        visit([],16)
    best=min((solve(ws,mode),ws,mode) for _,ws,mode in sorted(opts)[:12]);sch=solve(best[1],best[2],True);out=[]
    for t,op,*args in sch:
        for l in range(8):
            if op in ('A','B'):
                d,k,x=args;ins=load(d,A[(2*l+x)*16+k] if op=='A' else B[16*k+(2*l+x)%16])
            elif op=='M':
                d,a,b,u=args;ins=mac(d,a,b,d) if u else mul(d,a,b)
            else:
                r,d=args;ins=store(r,C[(2*l+d//16)*16+(2*l+d%16)%16])
            out.append(issue(t,l,ins))
    c['schedule']=out;return c
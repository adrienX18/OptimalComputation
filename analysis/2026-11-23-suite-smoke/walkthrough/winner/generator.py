from candidate_tools import baseline,load,mac,store,issue,seed
from itertools import combinations
import random

def build():
 rng=random.Random(seed());c=baseline()
 def cls(a,b):
  if (a^b)&1:
   if a&1:a,b=b,a
   return ((b-a)%16)//2
  return 8+4*(a%2)+min((a-b)%16,(b-a)%16)//2-1
 blocks={}
 for n in (4,5):
  for r in combinations(range(16),n):
   if min(r)>1:continue
   es=list(combinations(r,2));mask=sum(1<<x for x in set(cls(*e) for e in es));blocks.setdefault((n,mask),(r,es))
 best=None
 for (n,m),x in blocks.items():
  for (N,M),y in blocks.items():
   if m|M==65535:
    key=(n+N,-min(m.bit_count(),M.bit_count()))
    if best is None or key<best[0]:best=key,[x,y]
 bs=best[1]
 def plan(h):
  ts=[[],[]]
  for j in sorted(range(16),key=lambda j:sum(cls(*e)==j for r,es in bs for e in es)):
   if j in (11,15) and h!=(j-11)//4:continue
   i,e=min(((i,e) for i,(r,es) in enumerate(bs) for e in es if cls(*e)==j),key=lambda x:len(ts[x[0]]));ts[i].append(e)
  for p in (0,1):
   i,e=min(((i,(a,a)) for i,(r,_) in enumerate(bs) for a in r if a%2==p),key=lambda x:len(ts[x[0]]));ts[i].append(e)
  return ts
 def template(es):
  rows=sorted(set(a for e in es for a in e));n=len(rows);m=len(es);sp=15-n-m;assert sp>=0
  best=None
  for trial in range(1800):
   q=rng.choice([1,2,2,4]);T=q*(n+m)+rng.choice([1,1,2,q,q+1]);order=rows[:];rng.shuffle(order)
   extra=order[:min(sp,n)] if q>1 else [];reg={a:i+1 for i,a in enumerate(rows)};dup={a:n+m+i+1 for i,a in enumerate(extra)}
   gaps=[0]*q;g=T-2*n*q
   if g<0:continue
   if trial%3:gaps[-1]=g
   else:
    for _ in range(g):gaps[rng.randrange(q)]+=1
   at=[];st=0
   for k in range(q):
    if rng.random()<.25:rng.shuffle(order)
    at.append({a:st+2*i for i,a in enumerate(order)});st+=2*n+gaps[k]
   ls={v for d in at for v in d.values()};slots=set(range(T))-ls-{(t-2)%T for t in ls}
   if len(slots)<m*q:continue
   opts={}
   for k in range(q):
    for i,(a,b) in enumerate(es):
     lo=max(at[k][a],at[k][b])+1
     def end(a):
      z=k+1+(a in dup);return at[z%q][a]+T*(z//q)
     hi=min(end(a),end(b))-1
     opts[k,i]=[v for v in range(lo,hi+1) if v%T in slots]
   if not all(opts.values()):continue
   match={}
   def fit(j,seen):
    for v in opts[j]:
     t=v%T
     if t in seen:continue
     seen.add(t)
     if t not in match or fit(match[t][0],seen):match[t]=(j,v);return True
    return False
   if not all(fit(j,set()) for j in sorted(opts,key=lambda j:len(opts[j]))):continue
   mt=dict(match.values());
   if any(mt[(k+1)%q,i]+(T if k+1==q else 0)-mt[k,i]<3 for k in range(q) for i in range(m)):continue
   def times(k,i):return k//q*T+mt[k%q,i]
   last=max(times(15,i) for i in range(m));used={times(k,i) for k in range(16) for i in range(m) if times(k,i)>=times(15,0)-2*T};used.update((16//q-1)*T+v for d in at for v in d.values())
   sts=[]
   for i in sorted(range(m),key=lambda i:times(15,i)):
    a,b=es[i];v=times(15,i)+3
    for e in ([(a,b)] if a==b else [(a,b),(b,a)]):
     while v in used:v+=1
     sts.append((v,i,e));used.add(v)
   end=max(v for v,i,e in sts)+1
   if best is None or end<best[0]:best=end,q,T,at,mt,reg,dup,sts
  if best is None:
   T=n+m+2;best=16*T+2*m,1,T,[{a:i for i,a in enumerate(rows)}],{(0,i):n+i for i in range(m)},reg,{},[(16*T+2*i+j,i,e) for i,(a,b) in enumerate(es) for j,e in enumerate([(a,b)] if a==b else [(a,b),(b,a)])]
  return best
 ins=[8*(16*(r%2)+k)+r//2 for r in range(16) for k in range(16)];outs=[None]*256;s=[]
 for h in (0,1):
  tiles=plan(h);temps=list(map(template,tiles))
  for l in range(4*h,4*h+4):
   t=cnt=0
   def row(a):return (a+2*l)%16
   for es,(end,q,T,at,mt,reg,dup,sts) in zip(tiles,temps):
    for k in range(16):
     z=t+k//q*T;d=k%q
     def rr(a):return dup.get(a,reg[a]) if k%2 else reg[a]
     for a,v in at[d].items():s.append(issue(z+v,l,load(rr(a),ins[16*row(a)+k])))
     for i,(a,b) in enumerate(es):
      dst=len(reg)+i+1;s.append(issue(z+mt[d,i],l,mac(dst,rr(a),rr(b),dst if k else 0)))
    for v,i,(a,b) in sts:
     addr=256+8*cnt+l;cnt+=1;outs[16*row(a)+row(b)]=addr;s.append(issue(t+v,l,store(len(reg)+i+1,addr)))
    t+=end
 assert None not in outs;c['layout']=dict(inputs=ins,outputs=outs,scratch=[]);c['schedule']=sorted(s,key=lambda x:(x['cycle'],x['lane']));return c
import candidate_tools as T

def build():
    c = T.baseline()
    sched = []
    L = [7, 5, 3, 1, 6, 4, 2, 0]
    for l in range(8):
        R = lambda k: k + 1
        xa, xb, ya, yb, Oa, Ob, E = 9, 10, 11, 12, 13, 14, 15
        Eb = 8
        seq = [T.load(xa, 8 + l), T.load(xb, 16 + l)]
        for j in range(8):
            k = L[(j + l) % 8]
            seq.append(T.load(R(k), k))
        seq += [T.mul(ya, xa, xa), T.mul(yb, xb, xb)]
        seq += [T.mac(Oa, R(7), ya, R(5)), T.mac(Ob, R(7), yb, R(5))]
        seq += [T.mac(Oa, Oa, ya, R(3)), T.mac(Ob, Ob, yb, R(3))]
        seq += [T.mac(Oa, Oa, ya, R(1)), T.mac(Ob, Ob, yb, R(1))]
        seq += [T.mac(E, R(6), ya, R(4)), T.mac(Eb, R(6), yb, R(4))]
        seq += [T.mac(E, E, ya, R(2)), T.mac(Eb, Eb, yb, R(2))]
        seq += [T.mac(E, E, ya, R(0)), T.mac(Eb, Eb, yb, R(0))]
        seq += [T.mac(Oa, Oa, xa, E), T.mac(Ob, Ob, xb, Eb)]
        seq += [T.store(Oa, 24 + l), T.store(Ob, 32 + l)]
        ready = {}
        wb = set()
        comps = []
        t = 0
        for ins in seq:
            k = ins['kind']
            lat = 1 if k in ('load', 'store') else 3
            srcs = []
            for f in ('left', 'right', 'accumulator', 'source'):
                if f in ins:
                    srcs.append(ins[f])
            while True:
                ok = all(ready.get(s, 0) <= t for s in srcs if s != 0)
                if 'destination' in ins:
                    d = ins['destination']
                    ok = ok and ready.get(d, 0) <= t and (t + lat) not in wb
                    ok = ok and sum(1 for x in comps if x > t) < 3
                if ok:
                    break
                t += 1
            sched.append(T.issue(t, l, ins))
            if 'destination' in ins:
                ready[ins['destination']] = t + lat
                wb.add(t + lat)
                comps.append(t + lat)
            t += 1
    key = None
    for k, v in c.items():
        if isinstance(v, list) and v and isinstance(v[0], dict) and 'instruction' in v[0]:
            key = k
    c[key] = sched
    return c

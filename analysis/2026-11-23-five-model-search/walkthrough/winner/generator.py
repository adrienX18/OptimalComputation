from candidate_tools import baseline, load, store, mul, mac, issue, seed
from random import Random


def build():
    rng = Random(seed())
    # SSA nodes: coefficients, then each point's computation.
    deps = [()] * 8
    kinds = [0] * 8
    def node(k, *ds):
        i = len(deps)
        deps.append(ds)
        kinds.append(k)
        return i
    xs, ys = [], []
    for p in range(2):
        x = node(0)
        xs.append(x)
        q = 7
        for k in range(6, 1, -1):
            q = node(2, q, x, k)
        s = node(1, x, x)
        lo = node(2, 1, x, 0)
        ys.append(node(2, q, s, lo))
    n = len(deps)
    bits = [1 << i for i in range(n)]
    full = (1 << n) - 1
    pre = [sum(1 << j for j in set(ds)) for ds in deps]
    lat = [3 if k else 1 for k in kinds]
    use = [0] * n
    for ds in deps:
        for j in ds:
            use[j] += 1
    for y in ys:
        use[y] += 1

    def template(h, bans, budget):
        # The two stores are issued at h-2 and h-1. All loads and
        # arithmetic precede them, with the last MAC no later than h-4.
        end = h - 3
        due = [h - 4] * n
        due[ys[0]] = h - 5
        for i in range(n-1, -1, -1):
            for j in deps[i]:
                due[j] = min(due[j], due[i] - lat[j])
        overdue = [sum(bits[i] for i in range(n) if due[i] < t) for t in range(end+1)]
        masks = [full] * end
        for i in range(8):
            for t in bans[i]:
                masks[t] &= ~bits[i]
        order = sorted(range(n), key=lambda i: due[i] * rng.uniform(.4, 1.1) + rng.uniform(0, 13))
        dead = set()
        path = []
        def dfs(t, mask, a, b, left):
            nonlocal budget
            if not left:
                return True
            if budget <= 0 or t >= end or end-t < left or overdue[t] & ~mask:
                return False
            key = (t, mask, a, b)
            if key in dead:
                return False
            budget -= 1
            avail = masks[t] & ~mask
            ready = mask & ~(a | b)
            for i in order:
                bit = bits[i]
                if not avail & bit or pre[i] & ~ready or (not kinds[i] and b):
                    continue
                path.append((t, i))
                if dfs(t+1, mask | bit, bit if kinds[i] else 0, a, left-1):
                    return True
                path.pop()
                if budget <= 0:
                    return False
            if end-t > left and dfs(t+1, mask, 0, a, left):
                return True
            dead.add(key)
            return False
        if dfs(0, 0, 0, 0, n):
            return path

    chosen = None
    for h, tries in [(29, 36), (30, 30), (31, 18), (32, 16), (33, 12), (34, 12), (35, 8)]:
        for rep in range(tries):
            bans = [set() for _ in range(8)]
            paths = []
            for pair in range(4):
                path = template(h, bans, 4800 if rep < tries//2 else 12500)
                if path is None:
                    break
                paths.append(path)
                for t, i in path:
                    if i < 8:
                        bans[i].add(t)
            if len(paths) == 4:
                chosen = paths
                break
        if chosen is not None:
            break

    if chosen is None:
        return fallback(rng)
    c = baseline()
    inputs = list(range(8)) + [None]*16
    outputs = [None]*16
    bank_use = [[0]*8 for _ in range(h)]
    for path in chosen:
        for t, i in path:
            if i < 8:
                bank_use[t][i] += 2
    nextrow = [1]*8
    def alloc(t):
        row = bank_use[t]
        b = min(range(8), key=row.__getitem__)
        assert row[b] < 2
        row[b] += 1
        a = nextrow[b]*8 + b
        nextrow[b] += 1
        return a
    schedule = []
    for lane in range(8):
        refs = use[:]
        regs = [0]*n
        free = set(range(1, 16))
        for t, i in chosen[lane//2]:
            args = [regs[j] for j in deps[i]]
            for j in deps[i]:
                refs[j] -= 1
                if refs[j] == 0:
                    free.add(regs[j])
            d = min(free)
            free.remove(d)
            regs[i] = d
            if i < 8:
                op = load(d, inputs[i])
            elif not kinds[i]:
                p = lane + 8*xs.index(i)
                inputs[8+p] = alloc(t)
                op = load(d, inputs[8+p])
            else:
                op = (mul if kinds[i] == 1 else mac)(d, *args)
            schedule.append(issue(t, lane, op))
        for p, i in enumerate(ys):
            t = h-2+p
            idx = lane + 8*p
            outputs[idx] = alloc(t)
            schedule.append(issue(t, lane, store(regs[i], outputs[idx])))
    c['layout'].update(inputs=inputs, outputs=outputs, scratch=[])
    c['schedule'] = sorted(schedule, key=lambda v: (v['cycle'], v['lane']))
    return c


def fallback(rng):
    c = baseline()
    # Deterministic hazard-free serial progression within each lane pair.
    # Start pairs two cycles apart so identical coefficient reads never overlap.
    inp, out = c['layout']['inputs'], c['layout']['outputs']
    schedule = []
    for l in range(8):
        t = l//2
        for k in range(8):
            schedule.append(issue(t, l, load(k+1, inp[k])))
            t += 1
        for p in (l, l+8):
            schedule.append(issue(t, l, load(9, inp[8+p])))
            t += 1
            schedule.append(issue(t, l, mul(10, 9, 9)))
            t += 1
            schedule.append(issue(t, l, mac(11, 2, 9, 1)))
            t += 1
            q = 8
            for k in range(6, 1, -1):
                schedule.append(issue(t, l, mac(12, q, 9, k+1)))
                t += 3
                q = 12
            schedule.append(issue(t, l, mac(12, q, 10, 11)))
            t += 3
            schedule.append(issue(t, l, store(12, out[p])))
            t += 1
    # Reassign point and output banks to avoid overlaps with late coefficient reads.
    uses = [[0]*8 for _ in range(80)]
    for v in schedule:
        op = v['instruction']
        if op['kind'] == 'load' and op['address'] in inp[:8]:
            uses[v['cycle']][op['address']%8] += 1
    newinp, newout = inp[:], out[:]
    for v in schedule:
        op = v['instruction']
        if op['kind'] == 'store' or (op['kind'] == 'load' and op['address'] not in inp[:8]):
            row = uses[v['cycle']]
            b = min(range(8), key=row.__getitem__)
            row[b] += 1
            a = 256 + 8*v['lane'] + b
            if op['kind'] == 'store':
                p = out.index(op['address'])
                a += 128 + 64*(p//8)
                newout[p] = a
            else:
                p = inp.index(op['address'])
                a += 64*((p-8)//8)
                newinp[p] = a
            op['address'] = a
    c['layout'].update(inputs=newinp, outputs=newout, scratch=[])
    c['schedule'] = sorted(schedule, key=lambda v: (v['cycle'], v['lane']))
    return c

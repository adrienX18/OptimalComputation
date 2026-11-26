from candidate_tools import baseline, load, store, mul, mac, issue

def build():
    b = baseline()
    s = []
    for L in range(8):
        def I(t, ins):
            s.append(issue(t, L, ins))
        # coefficient c[k] -> register k+1, rotated so each bank has one load per cycle
        for t in range(8):
            k = (L + t) % 8
            I(t, load(k + 1, k))
        I(8, load(9, 8 + L))    # xA
        I(9, load(10, 16 + L))  # xB
        I(10, mac(11, 8, 9, 7))    # a3A = c7*xA+c6
        I(11, mac(12, 6, 9, 5))    # a2A
        I(12, mul(13, 9, 9))       # x2A
        I(13, mac(14, 8, 10, 7))   # a3B
        I(14, mac(15, 6, 10, 5))   # a2B
        I(15, mul(8, 10, 10))      # x2B -> r8
        I(16, mac(7, 4, 9, 3))     # a1A -> r7
        I(17, mac(6, 4, 10, 3))    # a1B -> r6
        I(18, mac(5, 2, 9, 1))     # a0A -> r5
        I(19, mac(4, 11, 13, 12))  # m1A -> r4
        I(20, mac(3, 14, 8, 15))   # m1B -> r3
        I(21, mac(9, 2, 10, 1))    # a0B -> r9
        I(22, mac(11, 4, 13, 7))   # m2A -> r11
        I(23, mac(12, 3, 8, 6))    # m2B -> r12
        I(25, mac(14, 11, 13, 5))  # m3A -> r14
        I(26, mac(15, 12, 8, 9))   # m3B -> r15
        I(28, store(14, 24 + L))
        I(29, store(15, 32 + L))
    s.sort(key=lambda e: (e['cycle'], e['lane']))
    key = 'schedule'
    for k, v in b.items():
        if isinstance(v, list) and v and isinstance(v[0], dict) and 'cycle' in v[0]:
            key = k
    b[key] = s
    return b

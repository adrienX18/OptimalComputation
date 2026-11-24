from candidate_tools import baseline, load, store, add, mac, issue


def build():
    c = baseline()
    a = lambda i,j: 16*j+i
    b = lambda i,j: 272+16*j+i
    y = lambda i: 544+i
    c['layout']['inputs'] = ([a(i,j) for i in range(16) for j in range(16)]
                             + list(range(256,272))
                             + [b(i,j) for i in range(16) for j in range(16)])
    s = []
    for lane in range(8):
        def emit(t, op):
            s.append(issue(t,lane,op))

        peer = lane ^ 4
        rows = [peer, peer+8, lane, lane+8]
        cols = [8*(lane//4)+(lane%4+k)%8 for k in range(8)]
        for k,j in enumerate(cols):
            emit(k,load(k+1,256+j))
        for k,j in enumerate(cols):
            for q,i in enumerate(rows):
                t = 8+8*k+2*q
                r = 9+q
                emit(t,load(13,a(i,j)))
                emit(t+1,mac(r,13,k+1,r if k else 0))

        emit(72,store(9,560+lane))
        emit(73,store(10,568+lane))
        emit(74,load(1,560+peer))
        emit(75,load(2,568+peer))
        emit(76,add(9,11,1))
        emit(77,add(10,12,2))
        emit(79,store(9,y(lane)))
        emit(80,load(14,b(lane,lane)))
        emit(119,load(14,b(lane,lane+8)))
        emit(120,store(10,y(lane+8)))

        for half in range(2):
            cols = [8*half+(lane+k)%8 for k in range(8)]
            start = 81 if half == 0 else 121
            for k,j in enumerate(cols[1:],1):
                emit(start+k-1,load(k,y(j)))
            t = start+7
            for k,j in enumerate(cols):
                for q in range(2):
                    first = k == 0 and q == 0
                    if not first:
                        emit(t,load(13,b(lane+8*q,j)))
                        t += 1
                    r = 11+q
                    emit(t,mac(r,14 if first else 13,k if k else 9+half,r if half or k else 0))
                    t += 1
        emit(159,store(11,528+lane))
        emit(161,store(12,536+lane))

    c['schedule'] = sorted(s,key=lambda e:(e['cycle'],e['lane']))
    return c

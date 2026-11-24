#!/usr/bin/env python3
"""Three descriptive smoke-study figures; one seed gives no repeat-based CI."""
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tempfile

os.environ.setdefault('MPLCONFIGDIR', str(Path(tempfile.gettempdir())/'optimal-matplotlib'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm
from matplotlib.lines import Line2D
from matplotlib.text import Text
import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE/'figures'
MODELS = ['fable', 'opus', 'sonnet', 'astra', 'sol']
LABELS = ['Fable 5.2', 'Opus 5.5', 'Sonnet 5.5', 'Astra 6.2', 'Sol 6.2']
TASKS = ['matmul', 'polynomial', 'gram', 'two-stage']
NAMES = ['Matrix multiplication', 'Polynomial', 'Gram', 'Two-stage']
LAYOUT = []


def table(name):
    with (HERE/name).open(newline='') as stream:
        return list(csv.DictReader(stream))


def title(fig, text, subtitle):
    fig.suptitle(text, x=.04, y=.98, ha='left', fontsize=16, weight='bold')
    fig.text(.04, .935, subtitle, va='top', fontsize=10, color='#444444')


def save(fig, name):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    overflow = []
    for artist in fig.findobj(match=Text):
        if artist.get_visible() and artist.get_text() and not artist.get_clip_on():
            box = artist.get_window_extent(renderer)
            if box.x0 < -2 or box.y0 < -2 or box.x1 > fig.bbox.x1+2 or box.y1 > fig.bbox.y1+2:
                overflow.append(artist.get_text())
    assert not overflow, overflow
    LAYOUT.append(dict(figure=name, overflowing_labels=overflow))
    when = datetime(2026,11,24,tzinfo=timezone.utc)
    fig.savefig(OUT/(name+'.png'), dpi=200)
    fig.savefig(OUT/(name+'.pdf'), metadata={'CreationDate':when,'ModDate':when})
    fig.savefig(OUT/(name+'.svg'), metadata={'Date':when.isoformat()})
    path = OUT/(name+'.svg')
    path.write_text('\n'.join(line.rstrip() for line in path.read_text().splitlines())+'\n')
    plt.close(fig)


def main():
    OUT.mkdir(exist_ok=True)
    runs, attempts, kernels = table('runs.csv'), table('attempts.csv'), table('kernel-checks.csv')
    assert len(runs)==80 and len(attempts)==240
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,
        'axes.spines.top':False,'axes.spines.right':False,'figure.facecolor':'white',
        'svg.hashsalt':'suite-smoke-20261123','pdf.fonttype':42})

    cases = list(dict.fromkeys(r['instance'] for r in runs))
    lookup = {(r['instance'],r['model']):r for r in runs}
    values = np.array([[float(lookup[c,m]['baseline_ratio']) for m in MODELS] for c in cases])
    fig, ax = plt.subplots(figsize=(11,10))
    fig.subplots_adjust(left=.31,right=.89,top=.875,bottom=.12)
    heat = ax.imshow(values, norm=LogNorm(1, values.max()), cmap='viridis', aspect='auto')
    names = []
    for c in cases:
        r=lookup[c,MODELS[0]]
        bank_word = 'bank' if r['initial_banks']=='1' else 'banks'
        setting = 'energy; free hardware' if r['objective']=='energy-proxy-v1' else f"latency; {r['initial_lanes']} lanes / {r['initial_banks']} {bank_word}"
        names.append(f"{NAMES[TASKS.index(r['task'])]} · {setting}")
    ax.set_yticks(range(16), names, fontsize=9)
    ax.set_xticks(range(5), LABELS)
    ax.tick_params(length=0)
    for i,c in enumerate(cases):
        for j,m in enumerate(MODELS):
            v=values[i,j]
            mark='*' if int(lookup[c,m]['interrupted']) else ''
            ax.text(j,i,f'{v:.1f}×{mark}',ha='center',va='center',
                    color='white' if v<np.sqrt(values.max()) else 'black',fontsize=10)
    for y in (3.5,7.5,11.5):
        ax.axhline(y,color='white',linewidth=3)
    bar=fig.colorbar(heat,ax=ax,fraction=.045,pad=.03)
    ticks=[v for v in (1,2,5,10,20,50) if v<=values.max()]
    bar.set_ticks(ticks, labels=[f'{v}×' for v in ticks])
    bar.set_label('Baseline score / final incumbent score (log color scale)')
    title(fig,'1 · Observed improvement after three scheduled slots',
          'One seed (11) per case/model. Ratios compare scores within a row; higher is better.')
    fig.text(.04,.04,'1× means the baseline was retained. * A slot was interrupted; the partial loop remains in the comparison.\nLatency uses abstract cycles; energy uses a proxy. No confidence intervals are estimable from one repeat.',fontsize=9)
    save(fig,'01_quality')

    outcomes=['Certified','Filtered response','Code limit','Invalid JSON','Simulation failed',
              'Range unproved','API error','Proof timeout','Interrupted']
    colors=['#009E73','#D55E00','#CC79A7','#F0E442','#0072B2','#E69F00','#777777','#56B4E9','#DDDDDD']
    fig, ax=plt.subplots(figsize=(12,6.5))
    fig.subplots_adjust(left=.13,right=.97,top=.84,bottom=.30)
    left=np.zeros(5)
    for category,color in zip(outcomes,colors):
        counts=np.array([sum(r['model']==m and r['outcome']==category for r in attempts) for m in MODELS])
        ax.barh(range(5),counts,left=left,color=color,label=category,edgecolor='white',
                hatch='///' if category=='Interrupted' else None)
        for i,n in enumerate(counts):
            if n>=2: ax.text(left[i]+n/2,i,str(n),ha='center',va='center',fontsize=9)
        left+=counts
    assert np.all(left==48)
    ax.set_yticks(range(5),LABELS);ax.invert_yaxis();ax.set_xlim(0,48)
    ax.set_xticks([0,12,24,36,48]);ax.set_xlabel('Scheduled slots (16 cases × 3 per model)')
    ax.legend(loc='upper center',bbox_to_anchor=(.5,-.22),ncol=3,frameon=False,fontsize=9)
    title(fig,'2 · All outcomes, including failures and interruptions',
          'Exact counts from this smoke run. Certification and optimization are different outcomes.')
    fig.text(.04,.025,'Range/proof limits are inconclusive, not counterexamples. Interrupted slots are censored.\nThese dependent attempts and heterogeneous cases are not independent statistical replicates; no CIs are shown.',fontsize=9)
    save(fig,'02_outcomes')

    fig,axs=plt.subplots(1,2,figsize=(14,6.5))
    fig.subplots_adjust(left=.1,right=.98,top=.80,bottom=.28,wspace=.42)
    left=np.zeros(5)
    for slot,color in zip(range(4),['#BBBBBB','#0072B2','#009E73','#E69F00']):
        counts=np.array([sum(r['model']==m and int(r['first_final_best'])==slot for r in runs) for m in MODELS])
        axs[0].barh(range(5),counts,left=left,color=color,label='Baseline retained' if slot==0 else f'Slot {slot}',edgecolor='white')
        for i,n in enumerate(counts):
            if n:axs[0].text(left[i]+n/2,i,str(n),ha='center',va='center',fontsize=9)
        left+=counts
    assert np.all(left==16)
    axs[0].set_yticks(range(5),LABELS);axs[0].invert_yaxis();axs[0].set_xlim(0,16)
    axs[0].set_xticks([0,4,8,12,16]);axs[0].set_xlabel('Cases (fixed set of 16)')
    axs[0].set_title('a  Slot first reaching the final incumbent',loc='left',fontsize=11)
    axs[0].legend(loc='upper center',bbox_to_anchor=(.5,-.20),ncol=2,frameon=False,fontsize=9)
    rng=np.random.default_rng(11)
    for i,task in enumerate(TASKS):
        subset=[r for r in kernels if r['task']==task]
        values=[float(r['seconds']) for r in subset]
        for r,y in zip(subset,rng.uniform(-.15,.15,len(subset))+i):
            stopped=r['status']!='completed' or r['exit_code']!='0'
            axs[1].scatter(float(r['seconds']),y,marker='x' if stopped else 'o',
                           color='#D55E00' if stopped else '#0072B2',s=25,alpha=.7)
        axs[1].plot(np.median(values),i,'|',color='black',markersize=22,markeredgewidth=2)
    axs[1].set_yticks(range(4),[f'{name} (n={sum(r["task"]==task for r in kernels)})' for task,name in zip(TASKS,NAMES)])
    axs[1].invert_yaxis();axs[1].set_xscale('log');axs[1].set_xlabel('Active kernel seconds (log scale)')
    axs[1].set_title('b  Every recorded proof-check duration',loc='left',fontsize=11)
    axs[1].legend(handles=[Line2D([],[],marker='|',color='black',linestyle='',label='Median',markersize=13),
        Line2D([],[],marker='x',color='#D55E00',linestyle='',label='Timed out / interrupted')],
        loc='upper center',bbox_to_anchor=(.5,-.2),frameon=False,fontsize=9)
    title(fig,'3 · A short search horizon and substantial verification work',
          'Left: descriptive case counts, not a stopping-rule test. Right: one host, including terminated checks.')
    fig.text(.04,.03,'All cases and recorded checks are displayed; no confidence intervals or cross-task significance tests.\nProof time is host computation, not the latency or energy score of the proposed design.',fontsize=9)
    save(fig,'03_search_and_verification')
    provenance=dict(matplotlib=matplotlib.__version__,numpy=np.__version__,layout=LAYOUT,
        inputs={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in HERE.glob('*.csv')},
        script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (OUT/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
    print('Rendered three figures in PNG, SVG and PDF; label bounds checked.')


if __name__=='__main__':
    main()

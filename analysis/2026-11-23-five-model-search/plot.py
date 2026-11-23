#!/usr/bin/env python3
"""Render reproducible scientific figures from the small, tracked analysis tables."""
import argparse
from collections import Counter
import csv
from datetime import datetime
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import tempfile

os.environ.setdefault('MPLCONFIGDIR', str(Path(tempfile.gettempdir()) / 'optimal-matplotlib'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from matplotlib.text import Text
import numpy as np
from scipy.stats import binomtest

HERE = Path(__file__).resolve().parent
MODELS = ['fable', 'opus', 'sonnet', 'astra', 'sol']
LABELS = ['Fable 5.2', 'Opus 5.5', 'Sonnet 5.5', 'Astra 6.2', 'Sol 6.2']
COLORS = dict(zip(MODELS, ['#0072B2', '#D55E00', '#009E73', '#CC79A7', '#E69F00']))
SEEDS = [11, 23, 37, 53, 71]
MARKERS = ['o', 's', '^', 'v', 'P']
STYLES = ['-', '--', ':', '-.', (0, (3, 1, 1, 1, 1, 1))]
OUTCOMES = ['Certified', 'Refusal', 'Invalid JSON', 'Code limit', 'Generator', 'Simulation', 'Unproved range', 'API error']
OUTCOME_COLORS = ['#D7EADB', '#D55E00', '#CC79A7', '#7B3294', '#595959', '#0072B2', '#E69F00', '#000000']
LETTERS = ['', 'R', 'J', 'L', 'G', 'S', 'U', 'E']
INTERVALS = []
LAYOUT = []
SCOPE = 'Polynomial degree 7, 16 points | 8 lanes / 8 banks | 5 repeats per model, 50 attempts per repeat'
MEDIAN_NOTE = 'Diamonds: median. Whiskers: 93.75% nonparametric median CI (= min–max of 5 runs); points show every run.'


def read_csv(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def median_ci(values):
    """Exact sign-test interval: coverage >= 1 - 2*(1/2)**5, under iid runs.

    Ties may make coverage conservative. This is NOT a 95% mean interval.
    Using whole-run summaries avoids pretending sequential attempts are iid.
    """
    values = np.asarray(values, dtype=float)
    if values.shape != (5,) or not np.isfinite(values).all():
        raise ValueError('Exactly five finite run-level values are required.')
    return float(np.median(values)), float(values.min()), float(values.max())


def record_ci(metric, model, values, attempt=''):
    mid, low, high = median_ci(values)
    INTERVALS.append(dict(metric=metric, model=model, attempt=attempt, n=5,
        method='order-statistic median', confidence=0.9375, estimate=mid, lower=low, upper=high))
    return mid, low, high


def success_ci(k):
    ci = binomtest(k, 5).proportion_ci(confidence_level=.95, method='exact')
    return k/5, float(ci.low), float(ci.high)


def outcome(row):
    category = row['category']
    if category == 'certified':
        return 0
    if category == 'proposal-error':
        if row['finishReason'] == 'content_filter':
            return 1
        return 3 if row['detail'] == 'Generator exceeds code_bytes.' else 2
    return {'generator-failed': 4, 'simulation-failed': 5,
            'range-not-proved': 6, 'api-error': 7}[category]


def model_legend():
    return [Patch(facecolor=COLORS[m], label=label) for m, label in zip(MODELS, LABELS)]


def seed_legend():
    return [Line2D([], [], marker=mark, color='#555555', markerfacecolor='white',
                   linestyle='none', label=f'Seed {seed}', markersize=6)
            for mark, seed in zip(MARKERS, SEEDS)]


def style_axis(ax, xlabel=None, ylabel=None):
    ax.spines[['top', 'right']].set_visible(False)
    ax.grid(axis='x', alpha=.16, zorder=0)
    ax.set_axisbelow(True)
    if xlabel:
        ax.set_xlabel(xlabel)
    if ylabel:
        ax.set_ylabel(ylabel)


def heading(fig, title, note=SCOPE):
    fig.suptitle(title, x=.02, ha='left', y=.985, fontsize=16, weight='bold')
    fig.text(.02, .936, note, fontsize=10, color='#444444', va='top')


def footer(fig, text):
    fig.text(.02, .015, text, fontsize=9, color='#444444', va='bottom')


def dots(ax, rows, value, metric, xlabel, limits=None):
    for j, model in enumerate(MODELS):
        selected = sorted([r for r in rows if r['model'] == model], key=lambda r: int(r['seed']))
        values = [value(r) for r in selected]
        mid, low, high = record_ci(metric, model, values)
        ax.errorbar(mid, j, xerr=[[mid-low], [high-mid]], color='#222222',
                    capsize=4, linewidth=1.5, fmt='D', markersize=5, zorder=3)
        for i, x in enumerate(values):
            ax.scatter(x, j+(i-2)*.085, marker=MARKERS[i], s=32, facecolors='white',
                       edgecolors=COLORS[model], linewidths=1.25, zorder=4)
    ax.set_yticks(range(5), LABELS)
    ax.set_ylim(4.5, -.5)
    if limits:
        ax.set_xlim(*limits)
    style_axis(ax, xlabel)


def save(fig, output, name, title):
    # Fixed metadata and SVG salt make repeated rendering deterministic.
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    frame = fig.bbox
    overflow = []
    for artist in fig.findobj(match=Text):
        if artist.get_visible() and artist.get_text() and not artist.get_clip_on():
            box = artist.get_window_extent(renderer)
            if box.x0 < frame.x0-2 or box.y0 < frame.y0-2 or box.x1 > frame.x1+2 or box.y1 > frame.y1+2:
                overflow.append(artist.get_text())
    legends = list(fig.legends) + [ax.get_legend() for ax in fig.axes if ax.get_legend() is not None]
    overlaps = sum(a.get_window_extent(renderer).overlaps(b.get_window_extent(renderer))
                   for i, a in enumerate(legends) for b in legends[i+1:])
    LAYOUT.append(dict(figure=name, overflowingText=overflow, overlappingLegends=overlaps))
    when = datetime.fromisoformat('2026-11-23T13:51:13+00:00')
    fig.savefig(output / (name+'.png'), dpi=240, metadata={'Title': title, 'Software': 'OptimalComputation analysis'})
    fig.savefig(output / (name+'.svg'), metadata={'Title': title, 'Date': when.isoformat(), 'Creator': 'OptimalComputation analysis'})
    # Matplotlib leaves spaces at the ends of SVG path lines; normalize them
    # without changing the drawing, so generated text stays diff-clean.
    svg = output / (name+'.svg')
    svg.write_text('\n'.join(line.rstrip() for line in svg.read_text().splitlines())+'\n')
    fig.savefig(output / (name+'.pdf'), metadata={'Title': title, 'CreationDate': when,
                                                'ModDate': when, 'Creator': 'OptimalComputation analysis'})
    plt.close(fig)


def plot_all(data, output):
    INTERVALS.clear()
    LAYOUT.clear()
    metrics = json.loads((data/'metrics.json').read_text())
    runs = read_csv(data/'runs.csv')
    attempts = read_csv(data/'attempts.csv')
    curves = read_csv(data/'convergence.csv')
    timeline = read_csv(data/'timeline.csv')
    examples = json.loads((data/'winner-schedules.json').read_text())
    assert len(runs) == 25 and len(attempts) == len(curves) == 1250
    assert Counter(outcome(a) for a in attempts) == {0:1033, 1:109, 2:11, 3:34, 4:16, 5:30, 6:14, 7:3}
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10,
        'axes.titlesize': 11, 'axes.labelsize': 10, 'xtick.labelsize': 9, 'ytick.labelsize': 9,
        'figure.facecolor': 'white', 'axes.facecolor': 'white', 'svg.hashsalt': 'optimal-five-model-20261123',
        'pdf.fonttype': 42, 'ps.fonttype': 42, 'savefig.facecolor': 'white'})
    output.mkdir(parents=True, exist_ok=True)

    # 1. Actual execution, queueing and complete accounting; these are census data.
    fig = plt.figure(figsize=(14, 9))
    gs = fig.add_gridspec(2, 2, width_ratios=[3.7, 1.4], height_ratios=[4.6, 1],
                          left=.15, right=.98, top=.87, bottom=.17, wspace=.2, hspace=.3)
    ax = fig.add_subplot(gs[0, 0]); active = fig.add_subplot(gs[1, 0]); info = fig.add_subplot(gs[:, 1])
    changes = []
    for i, r in enumerate(timeline):
        start, end = float(r['startSeconds'])/3600, float(r['endSeconds'])/3600
        ax.barh(i, end-start, left=start, height=.7, color=COLORS[r['model']])
        changes.extend([(start, 1), (end, -1)])
    ax.set_yticks(range(25), [f"{r['model'].title()} · {r['seed']}" for r in timeline], fontsize=8)
    ax.invert_yaxis(); ax.set_xlim(0, 5.6); style_axis(ax, ylabel='Model · fixed seed')
    ax.set_title('a  All 25 scheduled loops completed', loc='left')
    x, y, count = [0], [0], 0
    for t, change in sorted(changes):
        count += change; x.append(t); y.append(count)
    assert max(y) == 5 and count == 0
    active.step(x, y, where='post', color='#333333'); active.fill_between(x, y, step='post', alpha=.1, color='#333333')
    active.set_xlim(0, 5.6); active.set_ylim(0, 5.5); active.set_yticks([0, 1, 3, 5])
    style_axis(active, 'Hours since batch launch', 'Active loops')
    info.axis('off')
    info.text(0, .97, 'Complete archived accounting', weight='bold', fontsize=12, va='top')
    info.text(0, .89, '25 / 25 loops\n1,250 / 1,250 attempt slots\n\n1,247 model responses\n3 API-error records\n\n1,033 certified submissions\n217 other outcomes\n\n83,816 inventoried files\n979.5 MB (decimal)\n\nAll stored hashes verified\n5 h 26 min elapsed', va='top', linespacing=1.65)
    heading(fig, '1 · Execution and archive coverage')
    fig.legend(handles=model_legend(), loc='lower center', bbox_to_anchor=(.5,.065), ncol=5, frameon=False)
    footer(fig, 'Descriptive census, not a sample: no confidence intervals. Timeline includes startup; concurrency is measured from launch records.')
    save(fig, output, '01_execution', 'Execution and archive coverage')

    # 2. Preserve the five observations; exact success intervals show small-n uncertainty.
    fig, axs = plt.subplots(1, 3, figsize=(15, 6))
    fig.subplots_adjust(left=.1, right=.98, top=.83, bottom=.27, wspace=.55)
    dots(axs[0], runs, lambda r: float(r['bestCycles']), 'final_best_cycles', 'Final best latency (cycles) ↓', (20,85))
    axs[0].set_title('a  Final certified latency', loc='left')
    refs = [('Naive baseline',1520), ('Scheduling heuristic*',204), ('Hand reference*',63), ('Best found here',30), ('General I/O lower bound',5)]
    for i, (label, value) in enumerate(refs):
        axs[1].scatter(value, i, s=55, marker='D' if i==4 else 'o', color='#555555' if i!=3 else '#0072B2')
        axs[1].annotate(f'{value:,}', (value,i), xytext=(7,0), textcoords='offset points', va='center', fontsize=9)
    axs[1].set_yticks(range(5), [x[0] for x in refs]); axs[1].set_ylim(4.5,-.5)
    axs[1].set_xscale('log'); axs[1].set_xlim(3,4000)
    axs[1].set_xticks([5,30,100,1000], ['5','30','100','1,000'])
    style_axis(axs[1], 'Latency / bound (cycles; log scale)')
    axs[1].set_title('b  Fixed reference values', loc='left')
    for j, model in enumerate(MODELS):
        k = sum(float(r['bestCycles'])<=30 for r in runs if r['model']==model)
        mid, low, high = success_ci(k)
        INTERVALS.append(dict(metric='reach_30_by_50', model=model, attempt=50, n=5,
            method='Clopper-Pearson binomial', confidence=.95, estimate=mid, lower=low, upper=high))
        axs[2].errorbar(mid*100,j,xerr=[[(mid-low)*100],[(high-mid)*100]],fmt='o',color=COLORS[model],capsize=4)
        axs[2].annotate(f'{k}/5', (mid*100,j), xytext=(-5,-16) if k else (4,-16), textcoords='offset points', ha='right' if k else 'left')
    axs[2].set_yticks(range(5), LABELS); axs[2].set_ylim(4.5,-.5); axs[2].set_xlim(-5,105)
    style_axis(axs[2], 'Runs reaching ≤30 cycles (%) ↑')
    axs[2].set_title('c  Success fraction + exact 95% CI', loc='left')
    heading(fig, '2 · Strong improvement does not establish optimality')
    fig.legend(handles=seed_legend(), loc='lower center', bbox_to_anchor=(.5,.12), ncol=5, frameon=False)
    footer(fig, MEDIAN_NOTE+'\nPanel c: 5/5 gives a 95% CI of 47.8–100%, not certainty. *Historical timings; see report for certification provenance.')
    save(fig, output, '02_quality', 'Final quality and uncertainty')

    # 3. Pointwise median inference across whole trajectories; no iid-attempt fiction.
    fig, axs = plt.subplots(2, 3, figsize=(14, 8.8))
    fig.subplots_adjust(left=.07, right=.98, top=.87, bottom=.13, wspace=.25, hspace=.4)
    for ax, model, label in zip(axs.flat, MODELS, LABELS):
        matrix = np.array([[1520]+[float(r['bestCycles']) for r in curves if r['model']==model and int(r['seed'])==s] for s in SEEDS])
        for values, style in zip(matrix, STYLES):
            ax.step(range(51), values, where='post', color=COLORS[model], alpha=.45, linewidth=1, linestyle=style)
        mids, lows, highs = [], [], []
        for i in range(51):
            mid, low, high = record_ci('best_so_far_cycles',model,matrix[:,i],i)
            mids.append(mid); lows.append(low); highs.append(high)
        ax.fill_between(range(51),lows,highs,step='post',color=COLORS[model],alpha=.14)
        ax.step(range(51),mids,where='post',color=COLORS[model],linewidth=2.4)
        ax.axhline(30, color='#444444', linewidth=.8, linestyle=':')
        ax.set_yscale('log'); ax.set_ylim(25,1800); ax.set_xlim(0,50)
        ax.set_yticks([30,100,500,1520],['30','100','500','1,520'])
        ax.set_title(label, loc='left', color=COLORS[model], weight='bold')
        style_axis(ax, 'Completed attempts', 'Best latency (cycles; log) ↓')
    ax=axs.flat[5]; ax.axis('off')
    handles=[Line2D([],[],color='#444444',linewidth=2.4,label='Median best-so-far'),
             Patch(facecolor='#888888',alpha=.2,label='93.75% pointwise median CI')]
    handles += [Line2D([],[],color='#555555',linestyle=style,linewidth=1,label=f'Seed {s}') for style,s in zip(STYLES,SEEDS)]
    ax.legend(handles=handles, loc='upper left', frameon=False, fontsize=10)
    ax.text(.04,.15,'Identical trajectories overlap.\nAttempt 0 is the certified baseline.\nThe 30-cycle line is a found result,\nnot a proved lower bound.',transform=ax.transAxes,fontsize=10,linespacing=1.5)
    heading(fig, '3 · Most of the improvement arrived in the first few attempts')
    footer(fig, 'Whole runs are the sampling units (n=5/model). Bands equal observed min–max and have ≥93.75% pointwise median coverage under iid runs; not simultaneous bands.')
    save(fig,output,'03_convergence','Best-so-far convergence')

    # 4. Retrospective efficiency, clearly distinguished from an online stopping rule.
    fig,axs=plt.subplots(1,3,figsize=(14,6))
    fig.subplots_adjust(left=.09,right=.98,top=.83,bottom=.27,wspace=.36)
    dots(axs[0],runs,lambda r:float(r['bestFirstAttempt']),'attempt_to_eventual_best','Attempt first reaching eventual best ↓',(0,36))
    dots(axs[1],runs,lambda r:float(r['secondsToBest'])/60,'minutes_to_eventual_best','Cumulative attempt time (min) ↓',(0,70))
    dots(axs[2],runs,lambda r:(50-float(r['bestFirstAttempt']))*2,'percent_after_eventual_best','Attempts after eventual best (%)',(0,100))
    for ax,title in zip(axs,['a  Iterations needed','b  Time needed','c  Remaining budget without improvement']):ax.set_title(title,loc='left')
    heading(fig,'4 · Final-best timing and later budget use are retrospective measures')
    fig.legend(handles=seed_legend(),loc='lower center',bbox_to_anchor=(.5,.12),ncol=5,frameon=False)
    footer(fig,MEDIAN_NOTE+'\nSonnet timing targets its own 33–75-cycle best, not 30. Time excludes startup/queueing. 1,119/1,250 later attempts is descriptive, not an online stop rule.')
    save(fig,output,'04_timing','Timing and stagnation')

    # 5. Pooling distinct hashes differs from the distribution of within-run diversity.
    fig,axs=plt.subplots(1,2,figsize=(13,6))
    fig.subplots_adjust(left=.11,right=.96,top=.83,bottom=.27,wspace=.4)
    for i,model in enumerate(MODELS):
        m=metrics['models'][model]; unique=m['uniqueCertifiedCandidates']; repeats=m['repeatCertifiedCandidates']
        axs[0].barh(i,unique,color=COLORS[model],height=.58)
        axs[0].barh(i,repeats,left=unique,color='#DDDDDD',height=.58,hatch='//',edgecolor='#BBBBBB')
        axs[0].text(m['certified']+3,i,f"{unique} / {m['certified']}",va='center',fontsize=9)
    axs[0].set_yticks(range(5),LABELS);axs[0].set_ylim(4.5,-.5);axs[0].set_xlim(0,290)
    axs[0].set_title('a  Pooled certified submissions: unique / total',loc='left')
    style_axis(axs[0],'Certified submissions (count)')
    dots(axs[1],runs,lambda r:100*int(r['uniqueCertifiedCandidates'])/int(r['certified']),
         'within_run_unique_percent','Distinct structures / certified submissions (%) ↑',(0,105))
    axs[1].set_title('b  Diversity within each independent run',loc='left')
    heading(fig,'5 · A high certification count can be repeated submission of the same design')
    handles=[Patch(facecolor='#555555',label='First distinct structure'),Patch(facecolor='#DDDDDD',hatch='//',label='Repeated structure')]+seed_legend()
    fig.legend(handles=handles,loc='lower center',bbox_to_anchor=(.5,.10),ncol=4,frameon=False)
    footer(fig,'Panel a: exact pooled counts, no CI. Panel b: '+MEDIAN_NOTE+'\nUniqueness removes only identifiers and serialization order; register/layout changes still count. This is not algorithmic diversity.')
    save(fig,output,'05_repetition','Structural diversity and repetition')

    # 6. Operation census and representative issue schedules, not fitted causal effects.
    fig=plt.figure(figsize=(14,8))
    gs=fig.add_gridspec(2,2,left=.14,right=.98,top=.86,bottom=.21,width_ratios=[1,1.4],wspace=.28,hspace=.45)
    ax=fig.add_subplot(gs[:,0]); fast=[r for r in runs if int(r['bestCycles'])==30]
    assert len(fast)==20 and all(int(r['scheduleSize'])==224 for r in fast)
    selected=[fast[0]]+[r for r in runs if r['model']=='sonnet']
    op_fields=['loads','stores','multiplications','multiplyAdds']; op_labels=['Load','Store','Multiply','Multiply-add']; op_colors=['#0072B2','#009E73','#E69F00','#CC79A7']
    left=np.zeros(6)
    for field,label,color in zip(op_fields,op_labels,op_colors):
        vals=np.array([int(r[field]) for r in selected]);ax.barh(range(6),vals,left=left,color=color,label=label,height=.62);left+=vals
    ax.set_yticks(range(6),['All 20 winners at 30 cycles']+[f"Sonnet seed {r['seed']} · {r['bestCycles']} cycles" for r in selected[1:]])
    ax.set_ylim(5.5,-.5);ax.set_xlim(0,420)
    for i,v in enumerate(left):ax.text(v+5,i,str(int(v)),va='center')
    style_axis(ax,'Instructions in retained winner (count)');ax.set_title('a  Operation composition',loc='left')
    for row,model in enumerate(['fable','sonnet']):
        example=examples[model];a=fig.add_subplot(gs[row,1])
        for kind,color in zip(['load','store','multiply','multiplyAdd'],op_colors):
            ops=[v for v in example['schedule'] if v['instruction']['kind']==kind]
            a.scatter([v['cycle'] for v in ops],[v['lane'] for v in ops],marker='s',s=13,color=color)
        a.axvline(example['cycles'],color='#444444',linestyle=':',linewidth=1)
        a.set_xlim(-1,80);a.set_ylim(-.7,7.7);a.set_yticks([0,2,4,6,7])
        a.set_title(f"{'b' if row==0 else 'c'}  {model.title()} seed {example['seed']}, attempt {example['attempt']}: {example['cycles']} cycles",loc='left')
        style_axis(a,'Issue cycle (completion is later)','Hardware lane')
    heading(fig,'6 · Shared operation counts, different arithmetic and schedules')
    fig.legend(handles=[Patch(facecolor=c,label=l) for l,c in zip(op_labels,op_colors)],loc='lower center',bbox_to_anchor=(.5,.09),ncol=4,frameon=False)
    footer(fig,'Exact instruction counts and issue events for saved, certified winners; no sampling CI. Vertical lines show final completion.\nThe schedule examples illustrate mechanisms; they do not isolate the causal effect of one optimization.')
    save(fig,output,'06_designs','Winner instruction composition and schedules')

    # 7. Mutually exclusive outcomes and correctly clustered acceptance uncertainty.
    fig,axs=plt.subplots(1,2,figsize=(15,6.4),gridspec_kw={'width_ratios':[1.7,1]})
    fig.subplots_adjust(left=.08,right=.98,top=.83,bottom=.28,wspace=.32)
    counts=np.array([[sum(r['model']==m and outcome(r)==o for r in attempts) for o in range(8)] for m in MODELS])
    image=axs[0].imshow(counts,cmap='Blues',vmin=0,vmax=250,aspect='auto')
    for i in range(5):
        for j in range(8):axs[0].text(j,i,str(counts[i,j]),ha='center',va='center',color='white' if counts[i,j]>135 else '#222222')
    axs[0].set_xticks(range(8),OUTCOMES,rotation=35,ha='right');axs[0].set_yticks(range(5),LABELS)
    axs[0].set_title('a  Exact counts; each row totals 250',loc='left')
    fig.colorbar(image,ax=axs[0],fraction=.028,pad=.025,label='Attempt count')
    dots(axs[1],runs,lambda r:int(r['certified'])*2,'run_certified_percent','Certified attempts within a run (%) ↑',(0,105))
    axs[1].set_title('b  Run-level certification fractions',loc='left')
    heading(fig,'7 · Provider refusals and invalid candidates are different outcomes')
    fig.legend(handles=seed_legend(),loc='lower center',bbox_to_anchor=(.5,.095),ncol=5,frameon=False)
    footer(fig,'Panel a: descriptive census, no CI. Panel b: '+MEDIAN_NOTE+'\n“Unproved range” means all public fixtures passed but safety was not certified; it is not a proved counterexample.')
    save(fig,output,'07_outcomes','Failure decomposition and certification')

    # 8. Keep the order of dependent attempts visible instead of hiding bursts in totals.
    fig,axs=plt.subplots(5,1,figsize=(14,10),sharex=True)
    fig.subplots_adjust(left=.085,right=.99,top=.88,bottom=.16,hspace=.52)
    for ax,model,label in zip(axs,MODELS,LABELS):
        matrix=np.array([[outcome(r) for r in attempts if r['model']==model and int(r['seed'])==s] for s in SEEDS])
        ax.imshow(matrix,cmap=ListedColormap(OUTCOME_COLORS),vmin=-.5,vmax=7.5,aspect='auto',extent=(.5,50.5,4.5,-.5),interpolation='nearest')
        for i in range(5):
            for j in range(50):
                o=matrix[i,j]
                if o:ax.text(j+1,i,LETTERS[o],ha='center',va='center',fontsize=6,color='white' if o in (1,3,4,5,7) else '#222222')
        ax.set_yticks(range(5),SEEDS);ax.set_ylabel('Seed');ax.set_title(label,loc='left',color=COLORS[model],weight='bold')
        ax.set_xticks([1,10,20,30,40,50])
    axs[-1].set_xlabel('Attempt number (each row is a dependent sequence)')
    heading(fig,'8 · Failure sequences expose refusal bursts and repeated size-limit failures')
    fig.legend(handles=[Patch(facecolor=c,label=(LETTERS[i]+' · ' if i else '')+label) for i,(label,c) in enumerate(zip(OUTCOMES,OUTCOME_COLORS))],
               loc='lower center',bbox_to_anchor=(.5,.05),ncol=4,frameon=False)
    footer(fig,'Every attempt is shown exactly once; no smoothing or independence assumption, and no CI. Green cells are certified; letters identify other outcomes.')
    save(fig,output,'08_sequences','Sequential attempt outcomes')

    # 9. Run-level resource use; cost missingness must not appear as zero cost.
    fig,axs=plt.subplots(2,2,figsize=(14,9))
    fig.subplots_adjust(left=.1,right=.97,top=.87,bottom=.18,wspace=.35,hspace=.5)
    dots(axs[0,0],runs,lambda r:float(r['outputTokens'])/1000,'output_ktokens_per_run','Reported output per 50-slot run (1,000 tokens)',(0,500))
    dots(axs[0,1],runs,lambda r:float(r['apiSeconds'])/60,'api_minutes_per_run','Total API time per 50-slot run (min)',(0,125))
    dots(axs[1,0],runs,lambda r:float(r['medianApiSeconds']),'median_call_seconds_per_run','Median API call within each run (s)',(0,170))
    for ax,title in zip([axs[0,0],axs[0,1],axs[1,0]],['a  Output tokens include reported reasoning','b  API time includes error calls','c  Median call latency within each run']):ax.set_title(title,loc='left')
    ax=axs[1,1]
    for i,model in enumerate(MODELS):
        cost=metrics['models'][model]['costEstimateSumUSD']
        if cost is None:ax.text(2,i,'N/A — no stored price estimate',va='center',fontsize=9,color='#666666')
        else:
            ax.scatter(cost,i,color=COLORS[model],s=45);ax.annotate(f'${cost:.2f}',(cost,i),xytext=(7,0),textcoords='offset points',va='center')
    ax.set_yticks(range(5),LABELS);ax.set_ylim(4.5,-.5);ax.set_xlim(0,53)
    style_axis(ax,'Sum of stored estimates across 250 slots (USD)')
    ax.set_title('d  Partial SDK cost estimates, not invoices',loc='left')
    heading(fig,'9 · Equal attempt budgets do not imply equal resource use')
    fig.legend(handles=seed_legend(),loc='lower center',bbox_to_anchor=(.5,.085),ncol=5,frameon=False)
    footer(fig,MEDIAN_NOTE+'\nTokens are reported usage (3 API-error calls may omit usage). Times overlap across runs. Panel d is a descriptive sum; unknown costs are not zeros.')
    save(fig,output,'09_resources','Resource use and cost missingness')

    # 10. The two byte budgets are distinct. Plot actual values, including rejected code.
    fig,axs=plt.subplots(2,3,figsize=(14,9))
    fig.subplots_adjust(left=.07,right=.98,top=.86,bottom=.17,wspace=.28,hspace=.45)
    for ax,model,label in zip(axs.flat,MODELS,LABELS):
        matrix=np.array([[float(r['promptBytes'])/1000 for r in attempts if r['model']==model and int(r['seed'])==s] for s in SEEDS])
        for values in matrix:ax.plot(range(1,51),values,color=COLORS[model],alpha=.3,linewidth=.8)
        med=np.median(matrix,axis=0);lo=matrix.min(axis=0);hi=matrix.max(axis=0)
        ax.fill_between(range(1,51),lo,hi,color=COLORS[model],alpha=.12);ax.plot(range(1,51),med,color=COLORS[model],linewidth=2)
        for i in range(50):record_ci('prompt_kbytes',model,matrix[:,i],i+1)
        ax.axhline(32,color='#333333',linestyle='--',linewidth=1)
        ax.set_title(label,loc='left',color=COLORS[model],weight='bold');ax.set_ylim(0,34);ax.set_xlim(1,50)
        style_axis(ax,'Attempt number','Prompt size (1,000 bytes)')
    ax=axs.flat[5]
    for j,model in enumerate(MODELS):
        selected=[r for r in attempts if r['model']==model and r['outputCodeBytes']]
        for r in selected:
            size=float(r['outputCodeBytes'])/1000
            offset=((int(r['seed'])*53+int(r['attempt'])*17)%101/100-.5)*.6
            ax.scatter(size,j+offset,s=7,color='#D55E00' if size>8 else COLORS[model],alpha=.4,marker='x' if size>8 else 'o')
    ax.axvline(8,color='#333333',linestyle='--',linewidth=1)
    ax.set_yticks(range(5),[m.title() for m in MODELS]);ax.set_ylim(4.6,-.6);ax.set_xlim(left=0)
    ax.set_title('Generated code: 34 Sol rejections >8 kB',loc='left')
    style_axis(ax,'Code bytes / 1,000 (parsed responses only)')
    heading(fig,'10 · Prompt memory stayed within budget; code size caused separate failures')
    fig.legend(handles=[Line2D([],[],color='#555555',linewidth=2,label='Median prompt'),
        Patch(facecolor='#999999',alpha=.2,label='93.75% pointwise median CI (= min–max)'),
        Line2D([],[],color='#333333',linestyle='--',label='Configured byte limit'),
        Line2D([],[],marker='x',color='#D55E00',linestyle='none',label='Oversized code')],loc='lower center',bbox_to_anchor=(.5,.075),ncol=2,frameon=False)
    footer(fig,'Five prompt trajectories per panel; no history rows were dropped. Maximum prompt: 29,861/32,000 bytes.\nCode scatter is descriptive and shows dependent attempts; refusals/unparseable JSON have no code-size measurement. No output-token-length finish occurred.')
    save(fig,output,'10_limits','Prompt and code-size budgets')

    with (output/'intervals.csv').open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(INTERVALS[0]),lineterminator='\n')
        writer.writeheader();writer.writerows(INTERVALS)
    input_files=['metrics.json','runs.csv','convergence.csv','attempts.csv','timeline.csv','winner-schedules.json']
    metadata=dict(sourceRevision=metrics['source']['revision'],
        plotScriptSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        analysisScriptSha256=hashlib.sha256((data/'analyze.py').read_bytes()).hexdigest(),
        inputHashes={name:hashlib.sha256((data/name).read_bytes()).hexdigest() for name in input_files},
        packages={name:importlib.metadata.version(name) for name in ['matplotlib','numpy','scipy','Pillow']},
        medianMethod='[minimum, maximum] of five iid runs; >=93.75% coverage for the population median',
        binaryMethod='95% two-sided Clopper-Pearson, n=5 independent runs, threshold <=30 by attempt 50',
        caveats='Pointwise, exploratory, unadjusted. Independence/exchangeability assumed across runs, never across within-run attempts. No workload-population inference.',
        figureFiles=[p.name for p in sorted(output.iterdir()) if p.suffix in ('.png','.pdf','.svg')])
    (output/'provenance.json').write_text(json.dumps(metadata,indent=2)+'\n')
    (output/'layout-check.json').write_text(json.dumps(LAYOUT,indent=2)+'\n')
    print(f'Wrote 10 figures in PNG, SVG and PDF, {len(INTERVALS)} interval records, and provenance metadata.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data',type=Path,default=HERE)
    parser.add_argument('--output',type=Path,default=HERE/'figures')
    args=parser.parse_args()
    plot_all(args.data,args.output)


if __name__=='__main__':
    main()

#!/usr/bin/env python3
"""Draw the saved winners and baseline comparisons; needs no raw run archive."""
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
from matplotlib.colors import ListedColormap, BoundaryNorm
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, FancyBboxPatch
from matplotlib.text import Text
import numpy as np

HERE = Path(__file__).resolve().parent
OP_NAMES = ['Idle', 'Load', 'Store', 'Add', 'Multiply', 'Multiply-add']
OPS = ['idle', 'load', 'store', 'add', 'multiply', 'multiplyAdd']
COLORS = ['#eeeeee', '#0072B2', '#D55E00', '#CC79A7', '#E69F00', '#009E73']
LAYOUT = []


def read(p):
    return json.loads(p.read_text())


def table(p):
    with p.open(newline='') as f:
        return list(csv.DictReader(f))


def save(fig, folder, name):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    overflow = []
    for text in fig.findobj(match=Text):
        if text.get_visible() and text.get_text() and not text.get_clip_on():
            b = text.get_window_extent(renderer)
            if b.x0 < -2 or b.y0 < -2 or b.x1 > fig.bbox.x1+2 or b.y1 > fig.bbox.y1+2:
                overflow.append(text.get_text())
    assert not overflow, overflow
    when = datetime(2026, 11, 24, tzinfo=timezone.utc)
    for ext, metadata in [('png', {}), ('svg', {'Date': when.isoformat()}),
                          ('pdf', {'CreationDate': when, 'ModDate': when})]:
        p = folder/'figures'/f'{name}.{ext}'
        fig.savefig(p, dpi=180, metadata=metadata)
        if ext == 'svg':
            p.write_text('\n'.join(s.rstrip() for s in p.read_text().splitlines())+'\n')
    plt.close(fig)
    LAYOUT.append(dict(figure=name, overflowing_labels=overflow))


def title(fig, heading, sub):
    fig.suptitle(heading, x=.045, y=.985, ha='left', fontsize=17, weight='bold')
    fig.text(.045, .945, sub, fontsize=10, va='top', color='#444444')


def box(ax, xy, wh, text, color='#e8f4f0', fontsize=10):
    x, y = xy
    w, h = wh
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=.012',
                              facecolor=color, edgecolor='#5b6c70', lw=1.1))
    ax.text(x+w/2, y+h/2, text, ha='center', va='center', fontsize=fontsize)


def arrow(ax, a, b):
    ax.annotate('', xy=b, xytext=a, arrowprops={'arrowstyle': '->', 'color': '#334e58', 'lw': 1.4})


def issue_plot(ax, folder, part, stats, label):
    candidate = read(folder/'walkthrough'/part/'candidate.json')
    cycles = stats['cycles']
    raster = np.zeros((candidate['configuration']['lanes'], cycles), dtype=int)
    for e in candidate['schedule']:
        assert raster[e['lane'], e['cycle']] == 0
        raster[e['lane'], e['cycle']] = OPS.index(e['instruction']['kind'])
    ax.imshow(raster, aspect='auto', interpolation='nearest', cmap=ListedColormap(COLORS),
              vmin=-.5, vmax=5.5, extent=(-.5, cycles-.5, 7.5, -.5), rasterized=True)
    ax.set_yticks(range(8))
    ax.set_ylabel('Lane')
    ax.set_xlabel(f'Issue cycle (local scale; completion at {cycles:,})')
    ax.set_title(label, loc='left', fontsize=11)


def legend(fig, y=.035):
    fig.legend(handles=[Patch(facecolor=c, label=n) for c,n in zip(COLORS, OP_NAMES)],
               loc='lower center', bbox_to_anchor=(.5,y), ncol=6, frameon=False, fontsize=9)


def polynomial(folder):
    stats = read(folder/'walkthrough/architecture.json')
    curves = table(folder/'convergence.csv')
    curves = [r for r in curves if r['model']=='sol']
    seeds = sorted({int(r['seed']) for r in curves})
    values = np.array([[1520]+[int(r['bestCycles']) for r in curves if int(r['seed'])==seed] for seed in seeds])
    assert values.shape == (5, 51) and np.all(values[:,2:]==30)
    fig, axs = plt.subplots(1,2,figsize=(13,5.8),gridspec_kw={'width_ratios':[1.4,1]})
    fig.subplots_adjust(left=.08,right=.97,top=.80,bottom=.27,wspace=.26)
    colors = ['#0072B2','#D55E00','#009E73','#CC79A7','#E69F00']
    for ax, limit in zip(axs,[50,5]):
        for seed, data, color in zip(seeds,values,colors):
            ax.step(range(51),data,where='post',color=color,alpha=.8,lw=1.5,label=f'Seed {seed}')
            if limit==5:
                ax.scatter(np.arange(6),data[:6],s=24,facecolors='none',edgecolors=color)
        ax.step(range(51),np.median(values,axis=0),where='post',color='black',lw=2.2,ls='--',label='Median of 5 seeds')
        ax.axhline(1520,color='#777777',ls=':',lw=1.8,label='Original baseline')
        ax.set_yscale('log');ax.set_ylim(25,2100);ax.set_xlim(0,limit)
        ax.set_yticks([30,100,500,1520],[30,100,500,'1,520'])
        ax.set_xlabel('Completed attempt slots (0 = baseline)');ax.set_ylabel('Best certified cycles (log scale)')
        ax.grid(axis='y',alpha=.18)
    axs[0].set_title('All 50 slots',loc='left',fontsize=11)
    axs[1].set_title('First five slots, enlarged',loc='left',fontsize=11)
    axs[1].set_xticks(range(6))
    title(fig,'Sol: every repeat reaches 30 cycles by attempt two',
          'Four models tie in final quality. Sol is selected by the fewest median attempts to its final best.')
    handles,labels=axs[0].get_legend_handles_labels()
    fig.legend(handles,labels,loc='lower center',bbox_to_anchor=(.5,.09),ncol=4,frameon=False,fontsize=9)
    fig.text(.045,.035,'All five observed repeats shown; coincident trajectories overlap. Post-selection display, not an inferential confidence interval.\nThe illustrated design below is seed 11, attempt 2: 1,520 → 35 → 30 cycles. Modeled latency, not measured hardware time.',fontsize=9)
    save(fig,folder,'11_winner_progress')

    fig=plt.figure(figsize=(14,11))
    grid=fig.add_gridspec(3,2,left=.065,right=.97,bottom=.145,top=.86,height_ratios=[1.25,.6,1],hspace=.54,wspace=.28)
    left,right=fig.add_subplot(grid[0,0]),fig.add_subplot(grid[0,1])
    for ax in (left,right):ax.set_xlim(0,1);ax.set_ylim(0,1);ax.axis('off')
    left.set_title('a  Naive baseline: one lane, one point at a time',loc='left',fontsize=11)
    box(left,(.06,.74),(.88,.19),'Load x; construct x, x², …, x⁷',color='#edf1f6')
    box(left,(.06,.41),(.88,.20),'Materialize powers in scratch memory\nReload powers and coefficients; accumulate terms',color='#edf1f6')
    box(left,(.06,.07),(.88,.20),'Store result; repeat for all 16 points\n7 of 8 provisioned lanes remain idle',color='#edf1f6')
    arrow(left,(.5,.74),(.5,.62));arrow(left,(.5,.41),(.5,.28))
    right.set_title('b  Sol winner: two points per lane × eight lanes',loc='left',fontsize=11)
    box(right,(.05,.79),(.90,.16),'Load coefficients once per lane; reuse for x[lane] and x[lane+8]')
    box(right,(.02,.38),(.47,.24),'Upper polynomial\nq = c₇\nq ← q·x + cₖ, k = 6,…,2',fontsize=10)
    box(right,(.58,.38),(.40,.24),'Independent work\ns = x²\nt = c₁·x + c₀',fontsize=10)
    box(right,(.20,.02),(.60,.18),'One final multiply-add: y = q·s + t\nStore each result directly',fontsize=10)
    arrow(right,(.25,.79),(.25,.63));arrow(right,(.77,.79),(.77,.63))
    arrow(right,(.25,.38),(.4,.21));arrow(right,(.77,.38),(.6,.21))
    ax=fig.add_subplot(grid[1,:]);ax.axis('off')
    b,w=stats['baseline'],stats['winner']
    rows=[['Completion (modeled cycles)',f"{b['cycles']:,}",f"{w['cycles']:,}",'50.7× baseline / winner'],
          ['Issued instructions',f"{b['instructions']:,}",f"{w['instructions']:,}",'75.4% fewer'],
          ['Loads / stores',f"{b['counts']['load']} / {b['counts']['store']}",f"{w['counts']['load']} / {w['counts']['store']}",'Coefficient reuse; no scratch'],
          ['Scratch slots / active lanes','128 / 1','0 / 8','Same 8-lane, 8-bank machine']]
    t=ax.table(cellText=rows,colLabels=['Measured property','Baseline','Sol winner','Interpretation'],loc='center',cellLoc='left',colWidths=[.27,.18,.18,.37]);t.auto_set_font_size(False);t.set_fontsize(10);t.scale(1,1.5)
    issue_plot(fig.add_subplot(grid[2,0]),folder,'baseline',b,'c  Full baseline issue schedule')
    issue_plot(fig.add_subplot(grid[2,1]),folder,'winner',w,'d  Full winner issue schedule')
    title(fig,'Polynomial architecture: reuse coefficients and overlap independent work',
          'Sol · seed 11 · attempt 2. Boxes summarize the saved program; grids are the actual saved instructions.')
    legend(fig,.065)
    fig.text(.045,.025,'The issue grids have different time scales; one colored cell is an issued instruction, not its full execution duration.\nBoth designs are certified. The formula was cross-checked symbolically from the schedules; no global-optimality claim.',fontsize=9)
    save(fig,folder,'12_winner_architecture')


def smoke(folder):
    stats=read(folder/'walkthrough/architecture.json')
    runs=[r for r in table(folder/'runs.csv') if r['model']=='astra']
    curves=[r for r in table(folder/'convergence.csv') if r['model']=='astra']
    fig,axs=plt.subplots(4,4,figsize=(15,13))
    fig.subplots_adjust(left=.075,right=.965,top=.88,bottom=.14,wspace=.40,hspace=.56)
    names={'matmul':'Matrix multiply','polynomial':'Polynomial','gram':'Gram product','two-stage':'Two-stage map'}
    for ax,r in zip(axs.flat,runs):
        rs=[c for c in curves if c['instance']==r['instance']]
        ys=[float(c['best_score']) for c in rs]
        ax.step(range(4),ys,where='post',lw=2,color='#0072B2');ax.scatter(range(4),ys,s=20,color='#0072B2')
        ax.axhline(float(r['baseline']),color='#777777',ls=':')
        ax.set_yscale('log');ax.set_xticks(range(4));ax.set_xlabel('Attempt slot')
        unit='Proxy units' if r['unit']!='cycles' else 'Cycles'
        ax.set_ylabel(unit+' (log scale)');ax.grid(axis='y',alpha=.15)
        bank_word='bank' if r['initial_banks']=='1' else 'banks'
        config='free hardware · energy' if r['objective']=='energy-proxy-v1' else f"{r['initial_lanes']} lanes / {r['initial_banks']} {bank_word}"
        ax.set_title(names[r['task']]+'\n'+config,loc='left',fontsize=10)
        ax.text(.97,.86,f"{ys[0]:,.0f} → {ys[-1]:,.0f}\n{float(r['baseline_ratio']):.1f}×",transform=ax.transAxes,ha='right',va='top',fontsize=9)
        if r['instance']=='gram-latency-8x8':
            ax.set_facecolor('#eef8f1')
    title(fig,'Astra across the smoke suite: performance versus attempt count',
          'Chosen by 11 of 16 case-wise first places (including ties). One seed per case; each panel keeps its own objective and scale.')
    fig.legend(handles=[Line2D([],[],color='#0072B2',marker='o',label='Best certified score so far'),
                        Line2D([],[],color='#777777',ls=':',label='Original baseline'),
                        Patch(facecolor='#eef8f1',label='Architecture example below')],
               loc='lower center',bbox_to_anchor=(.5,.075),ncol=3,frameon=False)
    fig.text(.045,.03,'Slot zero is the baseline. Lower is better; latency and energy are not averaged. Energy cases may choose different hardware.\nDescriptive observations only: no repeat-based confidence intervals, cross-task significance test or general model ranking.',fontsize=9)
    save(fig,folder,'04_winner_progress')

    fig=plt.figure(figsize=(14,13))
    grid=fig.add_gridspec(3,2,left=.065,right=.97,bottom=.145,top=.88,height_ratios=[.8,1, .8],hspace=.49,wspace=.3)
    for col,part in enumerate(['baseline','winner']):
        ax=fig.add_subplot(grid[0,col]);ax.axis('off');ax.set_xlim(0,1);ax.set_ylim(0,1)
        if part=='baseline':
            ax.set_title('a  Baseline: calculate all 256 ordered pairs',loc='left',fontsize=11)
            box(ax,(.05,.64),(.90,.24),'For each (i,j): load A[i,k] and A[j,k]\nAccumulate 16 products on lane 0',color='#edf1f6')
            box(ax,(.05,.14),(.90,.27),'Write scratch; reload; copy to output\nCompute G[i,j] and G[j,i] separately\n4,096 multiply-adds; 8,448 loads',color='#edf1f6')
        else:
            ax.set_title('b  Astra: calculate 136 unordered pairs once',loc='left',fontsize=11)
            box(ax,(.05,.64),(.90,.24),'Tile pairs across eight lanes; reuse loaded rows\n17 dot products per lane × 16 terms')
            box(ax,(.05,.14),(.90,.27),'Write each off-diagonal sum to both G[i,j] and G[j,i]\nNo scratch; overlap loads and accumulation\n2,176 multiply-adds; 1,280 loads')
        arrow(ax,(.5,.64),(.5,.42))
    palette=['#0072B2','#E69F00','#009E73','#CC79A7','#D55E00','#56B4E9','#84754E','#555555']
    cmap=ListedColormap(palette);norm=BoundaryNorm(np.arange(-.5,8.5),8)
    for col,part in enumerate(['baseline','winner']):
        ax=fig.add_subplot(grid[1,col]);data=np.array(stats[part]['output_lanes']).reshape(16,16)
        ax.imshow(data,cmap=cmap,norm=norm,interpolation='nearest')
        ax.set_xticks([0,4,8,12,15]);ax.set_yticks([0,4,8,12,15]);ax.set_xlabel('Output column j');ax.set_ylabel('Output row i')
        ax.set_title(('c  Baseline' if col==0 else 'd  Winner')+': lane writing each G[i,j]',loc='left',fontsize=11)
        ax.plot([-.5,15.5],[-.5,15.5],color='white',lw=1,ls='--')
        if col==1:assert np.array_equal(data,data.T)
    fig.legend(handles=[Patch(facecolor=c,label=f'Lane {i}') for i,c in enumerate(palette)],
               loc='center',bbox_to_anchor=(.52,.36),ncol=8,frameon=False,fontsize=9)
    issue_plot(fig.add_subplot(grid[2,0]),folder,'baseline',stats['baseline'],'e  Baseline: 22,016 cycles · 13,312 instructions')
    issue_plot(fig.add_subplot(grid[2,1]),folder,'winner',stats['winner'],'f  Winner: 478 cycles · 3,712 instructions')
    title(fig,'Gram architecture: exploit symmetry and reuse row values',
          'Astra · seed 11 · attempt 3 · 8 lanes / 8 banks. G = A Aᵀ for a 16 × 16 signed16 input matrix.')
    legend(fig,.07)
    fig.text(.045,.028,'Output ownership and issue events are decoded from the saved schedules, not inferred from the model’s claims.\nThe issue grids use different time scales. No scratch in the winner; all 256 logical outputs are still written.\n46.1× modeled latency improvement; 72.1% fewer instructions. One selected case, not an average across the suite.',fontsize=9)
    save(fig,folder,'05_winner_architecture')


def main():
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,
        'axes.spines.right':False,'figure.facecolor':'white','svg.hashsalt':'optimal-walkthrough-v1','pdf.fonttype':42})
    for name,draw in [('2026-11-23-five-model-search',polynomial),('2026-11-23-suite-smoke',smoke)]:
        folder=HERE/name
        LAYOUT.clear();draw(folder)
        inputs=[folder/'convergence.csv',folder/'runs.csv']+sorted((folder/'walkthrough').rglob('*.json'))
        provenance=dict(matplotlib=matplotlib.__version__,numpy=np.__version__,layout=LAYOUT.copy(),
            script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            inputs={str(p.relative_to(folder)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
        (folder/'figures/walkthrough-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
    print('Rendered four walkthrough figures in PNG/SVG/PDF; all text bounds checked.')


if __name__=='__main__':
    main()

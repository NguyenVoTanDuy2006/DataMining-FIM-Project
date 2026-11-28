"""Draw compact report figures from the saved CSV summaries; never run mining."""
import csv
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/report/members/tv2/figures'
OUT.mkdir(parents=True, exist_ok=True)
plt.rcParams.update({'font.size': 7, 'axes.titlesize': 7, 'legend.fontsize': 6})

def read(name):
    with (ROOT / f'results/benchmarks/{name}/summary.csv').open(encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))

def save(fig, name):
    fig.savefig(OUT / f'{name}.png', dpi=300, bbox_inches='tight')
    plt.close(fig)

data = read('processes')
for count in (False, True):
    fig, axes = plt.subplots(2, 2, figsize=(3.45, 3.7), layout='constrained')
    for ax, name in zip(axes.flat, ('retail', 'chess', 'mushroom', 'T10I4D100K')):
        rows = sorted((r for r in data if r['dataset'] == name), key=lambda r: -float(r['minsup']))
        x = [100 * float(r['minsup']) for r in rows]
        if count:
            ax.plot(x, [int(r['n_itemsets']) for r in rows], 'o-', ms=2.5, color='#238b45')
        else:
            for prefix, label, color in [('julia', 'Set', '#2171b5'), ('optimized', 'BitVector', '#238b45'), ('spmf', 'SPMF', '#d95f02')]:
                ax.plot(x, [float(r[f'{prefix}_median_seconds']) for r in rows], 'o-', ms=2.5, label=label, color=color)
                ax.fill_between(x, [float(r[f'{prefix}_min_seconds']) for r in rows], [float(r[f'{prefix}_max_seconds']) for r in rows], alpha=.12, color=color)
        ax.set_title(name)
        ax.set_xticks([x[0], x[3], x[-1]])
        ax.invert_xaxis()
        ax.set_yscale('log')
        ax.grid(alpha=.2)
        ax.tick_params(labelsize=6)
    if not count:
        fig.legend(*axes.flat[0].get_legend_handles_labels(), loc='outside upper center', ncol=3)
    fig.supxlabel('Minimum support (%)', fontsize=7)
    fig.supylabel('Frequent itemsets (log)' if count else 'Whole-process time (s, log)', fontsize=7)
    save(fig, 'counts' if count else 'runtime')

rows = read('peak_ram')
fig, ax = plt.subplots(figsize=(3.45, 2.5), layout='constrained')
for offset, prefix, label, color in [(-.18, 'baseline', 'Set', '#2171b5'), (.18, 'optimized', 'BitVector', '#238b45')]:
    y = [float(r[f'{prefix}_median_mib']) for r in rows]
    errors = [[v-float(r[f'{prefix}_min_mib']) for v,r in zip(y,rows)], [float(r[f'{prefix}_max_mib'])-v for v,r in zip(y,rows)]]
    ax.bar([i+offset for i in range(4)], y, width=.36, yerr=errors, capsize=2, label=label, color=color)
ax.set_xticks(range(4), [r['dataset'] for r in rows], rotation=15)
ax.tick_params(axis='x', labelsize=6)
ax.set_ylabel('Peak RSS (MiB)')
ax.legend(ncol=2)
save(fig, 'ram')

rows = read('scalability')
fig, ax = plt.subplots(figsize=(3.45, 2.6), layout='constrained')
for backend, label, color in [('set','Set','#2171b5'),('bitvector','BitVector','#238b45')]:
    group = sorted((r for r in rows if r['backend']==backend), key=lambda r:int(r['n_transactions']))
    y = [1000*float(r['median_seconds']) for r in group]
    errors = [[v-1000*float(r['min_seconds']) for v,r in zip(y,group)], [1000*float(r['max_seconds'])-v for v,r in zip(y,group)]]
    ax.errorbar([int(r['n_transactions']) for r in group], y, yerr=errors, marker='o', ms=3, capsize=2, label=label, color=color)
ax.set(xlabel='Transactions', ylabel='Mining time (ms)')
ax.tick_params(labelsize=6)
ax.grid(alpha=.2)
ax.legend()
save(fig, 'scale')

rows = read('transaction_length')
fig, axes = plt.subplots(2, 1, figsize=(3.45, 3.5), layout='constrained', sharex=True)
for backend, label, color in [('set','Set','#2171b5'),('bitvector','BitVector','#238b45')]:
    group = sorted((r for r in rows if r['backend']==backend), key=lambda r:int(r['transaction_length']))
    x = [int(r['transaction_length']) for r in group]
    y = [1000*float(r['median_seconds']) for r in group]
    errors = [[v-1000*float(r['min_seconds']) for v,r in zip(y,group)], [1000*float(r['max_seconds'])-v for v,r in zip(y,group)]]
    axes[0].errorbar(x,y,yerr=errors,marker='o',ms=3,capsize=2,label=label,color=color)
axes[0].set_yscale('log')
axes[0].set_ylabel('Mining time (ms, log)')
axes[0].legend(ncol=2)
axes[1].plot(x, [int(r['n_itemsets']) for r in group], 'o-', color='#756bb1',ms=3)
axes[1].set(xlabel='Mean transaction length (items)', ylabel='Frequent itemsets', xticks=x)
for ax in axes:
    ax.grid(alpha=.2)
save(fig, 'length')
print(f'Saved five report figures to {OUT}')

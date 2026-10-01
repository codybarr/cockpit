"""Disposable UI trials; requires ui-diagnostic.patch applied and a research app built.
No CGEvent posting, global hotkey registration, or permissions changes.
"""
import argparse
import csv
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--app', default='/tmp/CockpitResearch.app/Contents/MacOS/Cockpit')
parser.add_argument('--output', required=True)
parser.add_argument('--fixture', default='/tmp/cockpit-ui-fixture/files')
parser.add_argument('--runs', type=int, default=3)
parser.add_argument('--cycles', type=int, default=60)
parser.add_argument('--background', action='store_true')
parser.add_argument('--baseline-only', action='store_true')
args = parser.parse_args()
out = Path(args.output)
out.mkdir(parents=True, exist_ok=True)
fixture = Path(args.fixture).resolve()
fixture.mkdir(parents=True, exist_ok=True)
for i in range(50_000):
    (fixture / f'Quarterly Report {i:05d}.pdf').touch(exist_ok=True)
assert sum(1 for p in fixture.iterdir() if p.name.startswith('Quarterly Report')) == 50_000


def cpu_seconds(value):
    parts = value.split(':')
    return sum(float(p) * 60 ** i for i, p in enumerate(reversed(parts)))

summaries = []
resources = []
for run in range(1, args.runs + 1):
    variants = ['baseline'] if args.background or args.baseline_only else (['baseline', 'cached'] if run % 2 else ['cached', 'baseline'])
    for variant in variants:
        name = f'{"background-" if args.background else ""}{variant}-{run}'
        output = out / f'{name}.csv'
        if output.exists() or Path(str(output) + '.error').exists():
            raise RuntimeError(f'Refusing to overwrite prior run {output}')
        if args.background:
            (fixture / 'Background Report.txt').unlink(missing_ok=True)
        env = dict(os.environ, COCKPIT_UI_BENCHMARK='1', COCKPIT_UI_CYCLES=str(args.cycles),
                   COCKPIT_UI_FIXTURE=str(fixture), COCKPIT_UI_DATABASE=str(out / f'{name}.sqlite'),
                   COCKPIT_UI_OUTPUT=str(output), COCKPIT_CACHE_ICONS='1' if variant == 'cached' else '0',
                   COCKPIT_UI_BACKGROUND='1' if args.background else '0', COCKPIT_UI_IDLE_MS='5000')
        print(f'Start {name}', flush=True)
        start = time.monotonic()
        samples = []
        with (out / f'{name}.log').open('w') as log:
            process = subprocess.Popen([args.app], env=env, stdout=log, stderr=log)
            while process.poll() is None:
                if time.monotonic() - start > 180:
                    process.terminate()
                    raise RuntimeError(f'{name}: timeout')
                ps = subprocess.run(['ps', '-p', str(process.pid), '-o', 'rss=', '-o', 'time=', '-o', '%cpu='], capture_output=True, text=True)
                fields = ps.stdout.split()
                if len(fields) == 3:
                    samples.append({'elapsed_s': time.monotonic() - start,
                                    'rss_kib': int(fields[0]), 'cpu_seconds': cpu_seconds(fields[1]), 'ps_cpu_percent': float(fields[2])})
                time.sleep(1)
        if process.returncode or not output.exists() or Path(str(output) + '.error').exists():
            raise RuntimeError(f'{name}: failed; inspect {name}.log / .error')
        with output.open() as f:
            rows = list(csv.DictReader(f))
        assert len(rows) == args.cycles * 46, (name, len(rows))  # 24 keys + 20 selections + invoke + empty
        # Retain first-use data in raw CSV, but report warm cycles separately.
        for phase, selected in [('first_cycle', [r for r in rows if int(r['cycle']) == 0]),
                                ('warm', [r for r in rows if int(r['cycle']) >= 5])]:
            for operation in ['invoke', 'input', 'selection', 'empty']:
                group = [r for r in selected if r['operation'] == operation]
                if not group:
                    continue
                result = {'trial': name, 'phase': phase, 'operation': operation, 'n': len(group)}
                for metric in ['dispatch_ms', 'controller_ms', 'graph_ms', 'draw_proxy_ms']:
                    values = sorted(float(r[metric]) for r in group if r[metric])
                    if values:
                        result[metric] = {'median': statistics.median(values),
                                          'p95': values[math.ceil(.95 * len(values)) - 1],
                                          'p99': values[math.ceil(.99 * len(values)) - 1], 'max': max(values)}
                summaries.append(result)
        resource = {'trial': name, 'elapsed_s': time.monotonic() - start,
                    'sampled_peak_rss_kib': max(s['rss_kib'] for s in samples),
                    'last_sample_cpu_seconds': samples[-1]['cpu_seconds'],
                    'metadata': json.loads(Path(str(output) + '.metadata.json').read_text()),
                    'samples': samples}
        resources.append(resource)
        (out / 'ui-summary.json').write_text(json.dumps(summaries, indent=2) + '\n')
        (out / 'ui-resources.json').write_text(json.dumps(resources, indent=2) + '\n')
        print(f'PASS {name}: {len(rows)} checked interactions, {resource["elapsed_s"]:.1f}s', flush=True)
print('All trials passed; endpoint remains CPU draw proxy, NOT screen presentation.', flush=True)

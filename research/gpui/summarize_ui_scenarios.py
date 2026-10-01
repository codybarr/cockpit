"""Per-scenario warm CPU draw-proxy summaries for the fixed 46-event cycle.
Usage: python3 summarize_ui_scenarios.py data/paired data/search-fastpath
Endpoint is not frame submission or screen presentation.
"""
import csv
import json
import math
from pathlib import Path
import statistics
import sys

output = []
for folder in sys.argv[1:]:
    for path in sorted(Path(folder).glob('*.csv')):
        groups = {}
        with path.open() as file:
            for row in csv.DictReader(file):
                if int(row['cycle']) < 5 or row['operation'] != 'input':
                    continue
                slot = int(row['sample']) % 46
                scenario = 'apps' if slot <= 6 else 'filename-hit' if slot <= 13 else 'filename-no-match'
                groups.setdefault(scenario, []).append(row)
        for scenario, rows in groups.items():
            values = sorted(float(row['draw_proxy_ms']) for row in rows)
            output.append({
                'variant_folder': str(Path(folder).name), 'trial': path.stem,
                'scenario': scenario, 'n': len(rows),
                'draw_proxy_p95_ms': values[math.ceil(.95 * len(values)) - 1],
                'draw_proxy_p99_ms': values[math.ceil(.99 * len(values)) - 1],
                'controller_median_ms': statistics.median(float(row['controller_ms']) for row in rows),
            })
print(json.dumps(output, indent=2))

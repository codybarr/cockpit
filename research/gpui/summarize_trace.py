"""Summarize xctrace time-profile XML; CPU samples, NOT interaction latency.
Usage: python3 summarize_trace.py exported-time-profile.xml
Categories are inclusive and overlap; do not add their percentages.
"""
import collections
import json
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
ids = {e.attrib['id']: e for e in root.iter() if 'id' in e.attrib}

def resolve(e):
    return ids[e.attrib['ref']] if 'ref' in e.attrib else e

categories = {
    'SwiftUI/SwiftUICore/AttributeGraph': lambda names, binaries: bool(set(binaries) & {'SwiftUI', 'SwiftUICore', 'AttributeGraph'}),
    'query controller': lambda names, _: any('LauncherController.updateQuery' in n for n in names),
    'matching/ranking': lambda names, _: any('ApplicationSearch.' in n or 'FilenameSearchSnapshot.' in n for n in names),
    'panel presentation': lambda names, _: any('LauncherPanelController.present' in n for n in names),
    'panel resize': lambda names, _: any('LauncherPanelController.resize' in n for n in names),
    'icons': lambda names, _: any('iconForFile' in n or 'resultIcon' in n for n in names),
}
threads = collections.Counter()
inclusive = collections.Counter()
leaves = collections.Counter()
costs = collections.Counter()
main_costs = collections.Counter()
rows = 0
main_ms = 0
for row in root.iter('row'):
    thread = resolve(row.find('thread')).attrib.get('fmt', '')
    weight = int(resolve(row.find('weight')).text) / 1_000_000
    backtrace = row.find('backtrace')
    frames = [] if backtrace is None else [resolve(f) for f in resolve(backtrace).findall('frame')]
    names = [f.attrib.get('name', '') for f in frames]
    binaries = [resolve(f.find('binary')).attrib.get('name', '') for f in frames if f.find('binary') is not None]
    rows += 1
    threads[thread] += weight
    if thread.startswith('Main Thread'):
        main_ms += weight
    if names:
        leaves[names[0]] += weight
    for n in set(names):
        if 'Cockpit_main' != n and ('Launcher' in n or 'ApplicationSearch.' in n or 'Filename' in n):
            inclusive[n] += weight
    for category, predicate in categories.items():
        if predicate(names, binaries):
            costs[category] += weight
            if thread.startswith('Main Thread'):
                main_costs[category] += weight
print(json.dumps({
    'rows': rows,
    'sampled_cpu_ms': sum(threads.values()),
    'sampled_main_thread_ms': main_ms,
    'threads_ms': threads,
    'inclusive_categories_ms': costs,
    'inclusive_main_categories_ms': main_costs,
    'top_app_frames_inclusive_ms': inclusive.most_common(25),
    'top_leaf_frames_ms': leaves.most_common(20),
}, indent=2))

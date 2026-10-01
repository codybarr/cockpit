# Controlled Launcher trials: native search path, not GPUI, dominates the observed stall

Second checkpoint for [research: evaluate GPUI for faster Launcher interactions](https://github.com/codybarr/cockpit/issues/30).

**Resolution: retain the Swift/AppKit/SwiftUI foundation. Prioritize the native no-match search fix; do not build a GPUI spike on the evidence collected so far.** The human approved concluding the evaluation with these gaps explicitly retained and the native findings tracked separately. This is not certification of end-to-end ADR-0004 compliance. Actual global-hotkey delivery, screen presentation, GPU/energy use and a working live-FSEvents workload remain unmeasured or blocked.

## What was measured

Disposable release app, separate bundle identity `com.codybarr.Cockpit.Research`, ad-hoc signed; no global hotkey, settings/login registration, System actions or access to the personal filename index. Same machine as the first report: M3 Pro, macOS 27.0 beta, Xcode 26.2. Main display mode reports nominal **120 Hz**, not a guarantee of the adaptive display's instantaneous refresh. Thermal state reported nominal in all completed trials. Power/battery configuration was not recorded.

The real FilenameIndex enumerates 50,000 actual empty synthetic PDF files and persists SQLite; matching uses its real in-memory snapshot. Standard filename-result cap (100) and ranking unchanged. Three fixed built-in application candidates and no Settings panes keep the app workload deterministic. Execution integrations are constructed but never invoked. Setup and initial indexing are outside interaction samples. A separate five-second pause allows idle sampling before the loop.

Each of 60 cycles: invoke/show, 24 individual input events across `safari`, `'report`, `'zzznomatch`, 20 Down Arrow events, and one native delete-to-empty event. Select-all and broad-query setup are untimed. NSEvent keyDown events are posted to NSApplication's queue and pass through the real LauncherPanel and NSTextView/SwiftUI binding. Character content varies but printable events use the same synthetic key code; this is not physical-key/IME testing. Neither global-hotkey OS delivery nor WindowServer input delivery is exercised. Query and selection outcomes are asserted, not assumed. No new permissions granted.

An NSViewRepresentable probe observes the expected query/result-count/selection/visibility signature in the SwiftUI graph, then its NSView draw callback. Endpoint is **matching-state CPU draw observation**, not complete Launcher paint, frame submission, compositor presentation, or pixels on screen. The extra marker and targeted controller/event timing hooks have overhead shared by all variants. The runner does not force synchronous layout/display. It serializes measured interactions with at least an 8 ms post-completion pause; rapid queued/coalesced typing remains a separate workload. Invoke timings do not isolate activation from focus; focus is asserted after invocation, not timed as a distinct event.

Per-run summaries discard cycles 0–4 as warm-up, leaving **1,320 input** and **1,100 selection** samples per trial. Invoke/empty have only 55 samples; their p99 values are essentially maxima and not robust tail estimates. Nearest-rank percentiles; three baseline trials, two completed icon-cache trials, three native-search trials. Raw first-use cycles are retained but OS caches were not flushed; no claim of cold-cache performance. No bootstrap confidence intervals.

## Main result

Milliseconds, warm CPU draw proxy, ranges across completed trials:

| Variant | Input p95 | Input p99 | Selection p95 | Selection p99 |
| --- | --- | --- | --- | --- |
| unchanged search, uncached icons (3 trials) | 56.98–57.20 | 58.99–59.55 | 9.34–9.39 | 10.40–13.15 |
| unchanged search, path-cached icons (2 trials) | 57.11–57.96 | 59.22–60.26 | 7.30–7.37 | 7.98–8.06 |
| ASCII no-match early return, uncached icons (3 trials) | 9.36–9.78 | 13.09–13.18 | 9.42–9.77 | 11.20–13.14 |

For the no-match typing scenario alone (605 warm samples per trial, including its short-query prefix states), baseline p95 **58.05–58.53 ms** / p99 **59.56–60.33 ms** versus search-candidate p95 **5.81–6.16 ms** / p99 **6.89–7.61 ms**. App-query and matching-filename scenarios do not show a comparable change. Their per-scenario sample counts are smaller than the aggregate input count, so interpret tail estimates accordingly.

The no-match controller's measured median dominates the baseline scenario (~50–52 ms); ordinary app and filename-hit controller work is sub-ms. Icon caching reduces selection cost by roughly 2 ms p95, but does not touch the large input spike. This falsifies the hypothesis that the observed no-match stall needs a different renderer. No conclusion about GPUI's relative speed is made: GPUI was not built or measured.

## Tight regression loop and candidate

One command, with the research regression test added:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  COCKPIT_RUN_BENCHMARKS=1 swift test -c release \
  --filter PerformanceBenchmarks.testNoMatchFilenameQueriesMeetControllerBudget
```

Baseline: **FAIL**, controller p95 **56.215 ms**, exceeding the 16 ms query budget before any UI work. Candidate: **PASS**, p95 **0.00625 ms** on the final targeted run. The original matching-fixture acceptance benchmark also passes. ASCII/short-query differential examples and a canonical-equivalent Hangul fallback test pass. Logs are in `data/tests/`. This is a research candidate, not a production fix or exhaustive Unicode correctness proof.

Cause: FilenameSearchSnapshot compactMaps query trigrams to existing posting lists. When none exist, it falls back to `.contains` over every candidate. For an ASCII query of at least three bytes, absence of every trigram proves no substring match is possible. Candidate returns [] for this case only; short queries and non-ASCII/canonical-equivalent fallback remain unchanged. It does not alter match limits, ranking, positive results or threading. Unicode fallback and some partially-overlapping no-match queries can still be expensive; they are not solved by this narrow candidate.

`native-no-match-candidate.patch` contains the candidate plus regression/correctness tests. Apply independently of the UI harness in a clean worktree to reproduce the controller test. Production hardening should consider randomized/differential coverage and explicit ranking/query semantics; do not replace the Unicode path indiscriminately with byte-trigram absence checks.

## Resource evidence and limits

Runner samples ps RSS and cumulative CPU seconds at one-second intervals. Total CPU includes process setup, indexing, five seconds of idle, warm-up and measured interactions; last sample may omit up to a second. Not Instruments peak allocation/physical footprint, energy, GPU utilization or normalized active/idle CPU benchmarking.

- Unchanged search, uncached: last sampled CPU **44.47–47.33 seconds** over approximately 84–85-second trials.
- Icon cache: **41.61–42.31 CPU seconds**, approximately 83–84-second trials.
- Native no-match candidate: **21.24–21.40 CPU seconds**, approximately 60.8-second trials; workload remains the same but completes sooner.
- Sampled peak RSS: first unchanged trial ~**210.8 MiB**; later unchanged trials ~**164.7–165.7 MiB**; cached ~**164.9–165.2 MiB**; search candidate ~**157.1–164.9 MiB**. Early OS/framework cache effects and one-second sampling prevent a strong memory-improvement claim.
- Main-to-fixture-ready includes indexing and an intentional 500 ms wait: ~**1.27–1.41 seconds**. Not production cold-start/input-ready latency.
- Final instrumented executable: **1,177,248 bytes**; research app ~**2,572 KiB on disk**. Not an uninstrumented production/GPUI size comparison.

No idle power/energy advantage or GPU improvement is claimed.

## Failed/excluded experiments

- Overall paired run hit the shell's 480-second limit during the third cached trial; no completed CSV exists for that trial. It was excluded. Three uncached and two cached trials completed with 2,760 asserted interactions each.
- An Instruments `--launch` attempt resolved to a duplicate installed-app process rather than the intended research build. That new duplicate was terminated; the original installed process was left running. Trace is invalid for this experiment and excluded. Use explicit PID attachment for further profiling. No claims are derived from that trace.
- Existing real-filesystem test `FilenameIndexTests.testRefreshesAfterFilesystemEvents` times out with the candidate **and with the original FilenameIndex source restored**. An independent background experiment used real FSEvents and repeatedly wrote a synthetic new file, but the file never became searchable; the harness correctly failed rather than reporting the trial as valid. Consequently **no background-indexing performance or freshness result is claimed**. Diagnosis is separate: missing event delivery/processing on this environment, not established as a GPUI or early-return regression. Research app logs include a nonfatal sandbox-extension warning at startup; its relevance is unproven.

The background failure is a concrete blocker to measuring Cockpit's live-index responsiveness and meeting ADR-0004 freshness. No permissions were requested to work around it, and no architecture decision was changed.

## Reproduce in a disposable worktree

Sources are still based on clean Cockpit `5413a66a8a99d0dd8cb44121f0f9d97311888ba4`; these assets deliberately keep instrumentation outside production source directories on the published research branch.

```sh
# Create a separate worktree from the published research branch, then cd into it.
git apply research/gpui/ui-diagnostic.patch
cp research/gpui/LauncherBenchmark.swift Sources/Cockpit/LauncherBenchmark.swift
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
Scripts/create-app.sh research-ui /tmp/CockpitResearch.app
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.codybarr.Cockpit.Research' /tmp/CockpitResearch.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Cockpit Research' /tmp/CockpitResearch.app/Contents/Info.plist
codesign --force --sign - /tmp/CockpitResearch.app
python3 research/gpui/run_ui_trials.py --output /tmp/ui-paired --runs 3 --cycles 60

# Then apply only the search candidate, rebuild/copy/re-sign the same research app,
# and compare uncached icons; never run a stale binary.
git apply research/gpui/native-no-match-candidate.patch
Scripts/create-app.sh research-ui /tmp/CockpitResearch.app
# Repeat the identifier/name overrides and ad-hoc signing above (create-app resets them).
python3 research/gpui/run_ui_trials.py --output /tmp/ui-search --baseline-only --runs 3 --cycles 60
```

These commands take keyboard focus and create 50,000 empty files in `/tmp/cockpit-ui-fixture/files`, plus per-trial SQLite databases in the output folder. Do not run in a production checkout. Shell timeout should exceed nine minutes for the full paired sequence, or run fewer trials separately. Successful raw CSVs and summaries are published under `data/paired/` and `data/search-fastpath/`; no SQLite databases, personal data or raw Instruments traces uploaded. Final harness adds metadata/freshness validation beyond the quiet measured revision; the measured interaction path is unchanged.

## Next decisions

1. [perf: avoid full filename scans for absent ASCII trigrams](https://github.com/codybarr/cockpit/issues/31) — promote the bounded native candidate with regression coverage, separately from this planning/research effort.
2. [bug: diagnose real FSEvents filename-index refresh failures](https://github.com/codybarr/cockpit/issues/32) — establish real event delivery/processing before treating background-indexing latency as meaningful.
3. If architecture evaluation remains open after native fixes, measure real hotkey/input-to-screen presentation, rapid coalesced input and resources on the identified release. Revisit GPUI only for a residual perceptible bottleneck that cheaper native changes do not remove.

Keeping the current stack has strong support for the observed workload. It does not establish that every Cockpit interaction is instant or that GPUI could never improve another workload.

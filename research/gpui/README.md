# GPUI feasibility and preliminary Cockpit baseline

Status: **evaluation concluded with human approval: retain the current stack and prioritize native fixes**. See [controlled Launcher trials and resolution](ui-findings.md) for the follow-up evidence, tested no-match candidate, FSEvents blocker, and explicit measurement gaps. No production migration or ADR changes. The remainder below preserves the initial checkpoint; its pending-work list is historical, not a claim that those measurements were completed.

Origin: [research: evaluate GPUI for faster Launcher interactions](https://github.com/codybarr/cockpit/issues/30).

## Evaluated sources

Cockpit clean revision: `5413a66a8a99d0dd8cb44121f0f9d97311888ba4`. Uncommitted application-catalog changes in the main worktree were excluded.

GPUI: Zed source revision `f8c2cc844057540ca1eac7de4f19f50d7597dead` (2026-10-01 upstream commit date). This is a **source snapshot**, not proof that the published crates expose exactly the same APIs. Its GPUI manifest says 0.2.2; gpui_platform says 0.1.0. Pin the git revision for any spike; do not use README's wildcard dependencies.

Primary-source links, all pinned:

- [GPUI README](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui/README.md): hybrid immediate/retained model, Metal rendering on macOS, standalone Application, latest stable Rust, explicitly pre-1.0 and frequently breaking APIs. On this snapshot, macOS glyph rendering needs gpui_platform's font-kit feature.
- [GPUI manifest](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui/Cargo.toml), [platform manifest](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui_platform/Cargo.toml): Apache-2.0 framework licensing; Rust workspace crates, layout (Taffy), image/SVG/font systems, scheduler, HTTP abstractions and AccessKit. Do not infer the entire Zed application's license applies to GPUI. A resolved dependency/license inventory remains necessary before distribution.
- [Metal renderer](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui_apple/src/metal_renderer.rs): CAMetalLayer, GPU pipelines, glyph/sprite atlas, up to three drawables, command-buffer presentation. Metal-compatible GPU required; source selects lower-power GPUs on Intel. This does **not** establish lower latency, memory or energy than SwiftUI.
- [Shader build](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui_apple/build.rs): default shader compilation invokes xcrun metal/metallib; runtime_shaders alternative exists. Full Xcode is the documented build prerequisite.
- [Workspace deployment target](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/.cargo/config.toml): 10.15.7. This is a build setting, **not a verified standalone minimum-OS support guarantee**. No inherent macOS 13 conflict identified, but validate the complete dependency closure and run on macOS 13 before adoption. Minimum Metal feature/hardware coverage beyond the renderer's device check was not established.
- [macOS window backend](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui_macos/src/window.rs): PopUp uses a nonactivating NSPanel, popup level, all-Spaces/full-screen auxiliary behavior; native input bridge implements NSTextInputClient; display/scaling and AccessKit adapter exist.
- [macOS platform backend](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui_macos/src/platform.rs): run installs its own NSApplication delegate and enters app.run; initialization uses regular activation policy.
- [Embedded app API](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui/src/app.rs): run_embedded **exists**, but requires a Platform whose run returns immediately. The stock macOS backend does not satisfy that shape. A raw NSView handle and a renderer from_layer constructor are not a supported turnkey Swift-owned-panel integration.
- [Input example](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui/examples/input.rs): selection, marked text, UTF-16 conversion, clipboard and editing are application responsibilities; do not equate input plumbing with NSTextField parity.
- [Accessibility guide](https://github.com/zed-industries/zed/blob/f8c2cc844057540ca1eac7de4f19f50d7597dead/crates/gpui/src/_accessibility.rs): AccessKit integration is real. Stable element IDs, roles, properties and accessible actions must be supplied; VoiceOver parity requires testing, not an assumption that accessibility is absent or automatic.

## Current-stack evidence

Environment: Apple M3 Pro, 11 CPU/14 GPU cores, 18 GB RAM; internal 3024×1964 Liquid Retina XDR display; macOS 27.0 build 26A428. Display refresh configuration was not recorded, so no frame-duration claim is made. Xcode 26.2 (17C52), Apple Swift 6.2.3, Instruments 26.0; process-local DEVELOPER_DIR override, no global developer-setting changes. This beta OS is not the macOS 13 compatibility test.

The default Command Line Tools Swift 6.4 / macOS 27 SDK failed to compile SwiftUI State because SwiftUIMacros was missing. Using the installed full Xcode fixes the release build. Original release PerformanceBenchmarks passes. This toolchain failure was not treated as a product regression or a GPUI advantage.

### Release controller fixture (not rendered UI)

Disposable diagnostic patch expands the existing test to 1,000 samples per operation and writes raw CSV outside timed regions. Three successful release runs; nearest-rank p95/p99 computed per run. 50,000 synthetic filenames; the existing snapshot caps matches at 100. Warm identical query `'report`; mocked workspace/catalog; no hosting view, event delivery, actual window, layout, icons, SQLite queries, live indexing or GPU presentation. Setup/index construction is outside the timing. No generalization to cold or mixed queries.

| Operation | p95 range across runs | p99 range across runs |
| --- | --- | --- |
| query controller | 0.264–0.278 ms | 0.280–0.325 ms |
| selection mutation | 0.00117–0.00121 ms | 0.00125 ms |
| invoke state reset | 0.000292–0.000334 ms | 0.000334 ms |

These show controller work has substantial headroom **in this fixture**, not that Cockpit meets ADR-0004's real hotkey/input latency targets. Very small state-mutation timings are near timer/runtime overhead and not user-visible gains. Raw data: controller-samples.csv; summaries: controller-summary.json; patch: controller-diagnostic.patch.

Reproduce in an isolated worktree at the clean revision:

```sh
git apply research/gpui/controller-diagnostic.patch
# Use a fresh output file for each run: the patch appends CSV.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  COCKPIT_RUN_BENCHMARKS=1 GPUI_SAMPLES_PATH=/tmp/controller-run-1.csv \
  swift test -c release --filter PerformanceBenchmarks
```

The patch is intentionally diagnostic, uses forced file operations, and is not proposed for production tests.

### Interactive installed-app CPU profile

Attached Time Profiler for 60 seconds to the existing installed Cockpit process. Human confirmed repeated show/hide, app typing/erase, filename results, no-match queries and rapid selection. No permissions were changed by the agent. The workload was human-driven, not a recorded deterministic query sequence. Filename-index size, query distribution and background indexing load were not measured.

Installed binary UUID: `18487F0D-86CD-3CCD-82D0-EC54B989080F`; SHA-256 `bbd2e27c55b0651ce36dc1773e455fd2a9d8cc960171e9f412702281097bea1c`; bundle version `local`. Its build flags and source revision are unknown. It differs from the clean release binary, so this is **diagnostic attribution, not the controlled release baseline**.

2,658 nominal 1 ms sampled weights; 2,334 on main thread. Inclusive categories (overlap; do not sum):

| Main-thread stack category | Sampled weight | Share of main-thread sampled weight |
| --- | --- | --- |
| SwiftUI/SwiftUICore/AttributeGraph | 1,446 ms | 62.0% |
| result icons | 205 ms | 8.8% |
| query controller | 57 ms | 2.4% |
| matching/ranking | 38 ms | 1.6% |
| panel presentation | 26 ms | 1.1% |
| specifically symbolized panel resize | 2 ms | 0.09% |

Includes system/library work and sampling artifacts (e.g. syscall traps); weights are not exact elapsed operation time. Optimized/inlined symbols may underattribute categories. SwiftUI includes state propagation, layout and drawing, not just GPU rasterization. A scheduleResize closure accounts for 55 ms inclusive but resize itself only 2 ms; source/inlining and call-tree inspection are needed before attributing that difference. No >250 ms potential-hang records; this does not rule out 16–50 ms target misses. No event-to-present intervals or per-operation percentiles were captured.

One post-capture process snapshot: 49,968 KiB RSS (~48.8 MiB), ps reports 0.0% CPU at that instant. Not idle average, peak, GPU, energy or startup evidence. No GPUI memory/resource comparison was run.

Reproduction commands (replace PID):

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun xctrace record --template 'Time Profiler' --attach PID \
  --time-limit 60s --output installed-interactions.trace
xcrun xctrace export --input installed-interactions.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output time-profile.xml
python3 research/gpui/summarize_trace.py time-profile.xml
```

Sanitized aggregate: installed-trace-summary.json. Raw .trace (~29 MB), export XML and logs are preserved locally at `/Users/cody/projects/cockpit/.build/research/gpui-evidence/` (gitignored; save elsewhere before cleaning .build). They contain machine/environment metadata and potentially user data; **not uploaded automatically**.

## Compatibility/risk matrix

“Present in source” is not “verified for Cockpit.”

| Requirement | Evidence / gap | Adoption risk |
| --- | --- | --- |
| Nonactivating panel/focus | GPUI PopUp NSPanel exists; Cockpit currently uses borderless NSPanel plus explicit app activation, not the nonactivating style | Validate exact key-focus, dismiss/restore and activation behavior; popup level differs from Cockpit status-bar level |
| Global hotkey, no extra consent | Cockpit uses Carbon RegisterEventHotKey; GPUI action bindings are not evidence of OS-global hotkeys | Retain native bridge; no Accessibility/Input Monitoring shortcut |
| Spaces/full-screen/displays | Backend has all-Spaces/full-screen auxiliary flags and display support | Test macOS 13+, external displays, scale changes and focus manually |
| Keyboard navigation | GPUI actions/key bindings/list elements available | Reimplement wrap, reveal hint, shortcuts and selection scrolling; measure presented highlight |
| Launchpad editing/IME | NSTextInputClient bridge plus substantial input example | Test composition, Unicode/graphemes, selection, clipboard, dead keys and candidate-window placement |
| VoiceOver | AccessKit adapter/semantics APIs exist | Explicit text/result semantics and actions; verify announcement/focus and editing parity |
| Appearance/scaling | Window appearance/text/display APIs exist | Recreate current matte appearance; test Retina/non-Retina and accessibility display preferences |
| Menu bar/settings/login | GPUI menus exist, not proof of Cockpit NSStatusItem/SMAppService parity | Retain Swift settings/integrations or write ObjC/Rust bridge |
| File opening/System actions | Platform URL methods exist, not full Cockpit execution/consent semantics | Keep native NSWorkspace and least-privilege System action implementation |
| Filename index | SQLite storage is independent, implementation is Swift/FSEvents | Keep behind explicit ABI; copying index/ranking into Rust changes the benchmark and adds correctness burden |
| Signed/notarized macOS 13+ | Ordinary native binary model is plausible | Validate deployment targets, resources, hardened runtime, nested libs, codesign/notary/stapling pipeline |
| Maintenance/licenses | Pre-1.0 warnings; Apache-2.0 GPUI manifests | Pin revisions, dependency-license audit, upgrades/rebases, Rust/Swift toolchain ownership |

## Three paths

Effort figures are rough planning estimates for one engineer familiar with Cockpit, not measured schedules.

1. **Optimize current stack (first choice).** Keep all integrations/index/ranking. Profile icon work; test cache/preload/invalidation, reduce broad state publications/list reconstruction and unnecessary layout, optionally a native AppKit result surface if SwiftUI is demonstrably expensive. Do not change ranking/result limits to make the UI comparison look faster. A focused profiling/optimization experiment may take days; expected user-visible benefit remains unmeasured.
2. **Swift shell + GPUI surface.** Preserve filename index, catalog, settings and System actions behind a C-compatible boundary; define owned UTF-8/result buffers, release callbacks, immutable snapshots, main-thread affinity and cancellation/generation IDs. Avoid double state sources. Stock macOS app/run-loop ownership is a blocker to turnkey embedding despite run_embedded API. A custom platform/view adapter or maintained fork is likely investigation work, not assumed impossibility. Feasibility alone could take days–weeks; production maintenance unknown. No evidence it is cheaper than replacing only the current SwiftUI list with AppKit.
3. **Rust/GPUI shell.** GPUI owns event loop/window and Launcher state. Keep Swift services via FFI initially, or port them later as separately justified work. Reimplement hotkey/menu/status/login/settings/focus/text/accessibility and packaging; preserve SQLite format/FSEvents semantics/consent. Roughly weeks–months for feature parity and hardening, with uncertainty. A faster matcher from a Rust port must not be credited to GPUI rendering.

All GPUI adoption reopens ADR-0001. ADR-0002's local Spotlight-independent index and ADR-0003's macOS 13+, least-privilege and signed/notarized integration remain requirements; ADR-0004 remains the performance target. No ADR changed.

## Decision gate and remaining work

**Stop before building a GPUI spike for now.** The profile makes view/icon work a credible cost center, but neither proves perceptible latency nor predicts GPUI's improvement. Native optimizations could remove the same cost without a second framework. This is a provisional recommendation, not rejection of GPUI or proof of current-stack adequacy.

Proposed threshold to agree **before** a comparison: at least one configured display-frame interval AND ≥25% improvement in p95 event-to-present latency on an interaction that currently misses its target or demonstrably hitches; reproducible across runs; p99 no regression; feature parity and acceptable memory/idle-energy envelope. At 60 Hz one interval is 16.7 ms; at 120 Hz 8.3 ms. Beating sub-ms controller calls alone is not justification. Resource regression tolerances still need agreement.

To finish this ticket:

1. Build/install an identified clean release without overwriting the user's installed app unintentionally. Instrument hotkey callback/dispatch, first-responder readiness, Launchpad input, matching/ranking, state updates, layout/icon resolution and submission; correlate presentation with compositor/Metal/System Trace where possible. If actual screen presentation is unavailable, label submission proxy explicitly and do not silently substitute it.
2. Record refresh rate, fixture/index size, result count, thermal/power state and fixed query sequence. Cold startup separate; ≥1,000 warm samples per interaction per run across several runs (more for stable p99 confidence), normal/rapid typing, empty/no-match, repeated show/hide, selection and live background indexing. Add real SQLite/FSEvents index workload, not fixture only.
3. Measure current-stack CPU/GPU, RSS/peak, idle/active energy, startup and binary/app size. Evaluate native icon/state/layout optimization against the same baseline.
4. If target misses remain dominated by view work, get approval for a disposable minimal GPUI Launcher prototype. Freeze ranking/search through the same Swift backend/recorded snapshots; identical result counts/icons/rendering/text semantics. Benchmark equivalent release builds on the same environment and disclose embedding differences. Measure resources and parity, not FPS alone.
5. Then resolve retain/optimize versus bounded prototype versus migration, with source-linked uncertainties and any follow-up decision tickets. Do not attach this investigation to the already-completed v1 specification map without redrawing its destination.

<!-- cspell:ignore lupa -->
# Headless testing

Calculations, build edits and UI control checks can run without opening PoB or sending desktop input. Use an isolated build loaded through `src/HeadlessWrapper.lua`; saved player builds do not need to be changed.

The wrapper uses real zlib compression for imports and compressed jewel data. Windows uses the bundled `runtime/zlib1.dll`; Linux needs the system zlib library. Headless jewel loading leaves binary caches untouched unless caching is explicitly requested.

Run the calculation suite with `busted --lua=luajit`, and the MCP protocol suite with `node --test spec/AI/*.test.cjs`.

If a LuaJIT executable is unavailable, Python with the optional `lupa` package can run individual headless Lua scripts from the repository root. For example, `python tools/run_headless_lupa.py tools/benchmark_atlas_report.lua`. Script arguments follow the script path. Some scripts require additional Lua modules, such as LuaFileSystem (`lfs`) for the full UI suite. This runs the selected script with normal filesystem access; use isolated fixtures and output directories.

## Render and exercise controls

Install Pillow for Python, then run from the repository root:

```sh
python tools/check_headless_ui.py --lua luajit
```

On Windows, pass the full path to a LuaJIT executable if it is outside PATH. The runner configures the repository's Lua modules and runtime DLLs automatically.

Each run produces a fresh directory under `artifacts/headless-ui` containing PNG frames, draw records, contrast, clipping and overlap audits, input logs and source hashes. CI runs the same checks and uploads this evidence. The checker verifies source hashes before capture, after capture and after rendering; changes require a fresh run. Rendering uses up to four worker processes; `--workers 1` runs serially.

The 1,560 captured states cover native build-tab navigation, AI goals and connection controls, candidate review/apply/undo, side-by-side changes and metrics, explanations, Atlas search, allocation/removal/avoidance, undo/redo, direct mechanic filtering, routes, minimap, presets, comparison, history, pan/zoom, version switching, notes, sharing and resizing. Atlas checks also cover the map modifier explorer, currency picker, reroll estimator, saved targets and map drafts. Crafting checks cover project creation, working-item persistence, the graphical workbench, inline currency search and modifier inspection, favorites, item history, affix and target pickers, differences, recipe comparisons, Allflame choices, manual editing, simulation results, cancellation and distributions. Loot-filter checks include the mapping and flask example scenes. Search and inspected-modifier state must survive resizing; keyboard focus and Escape are checked. Recovery checks include the workspace, timeline and hover inspection. Sizes are 1280×720, 1024×768 and 960×640. Clicks, dropdown selection, keyboard focus and text entry go through native control and popup input handlers. Deliberately unreadable/clipped text and overlapping controls must fail the audit's self-test.

Planning tools support Tab / Shift+Tab, Enter and visible keyboard focus. Escape dismisses the focused editor or dropdown first, then the dialog. Alt+1/2/3 switches AI/Atlas/crafting within the planning workspace. Ctrl+F focuses Atlas search; Ctrl+Z and Ctrl+Shift+Z undo/redo planning changes when a text editor is not focused. Stock build-tab shortcuts remain unchanged.

`Modules.HeadlessUI` provides the reusable drawing/input adapter for additional control scenarios. It uses PoB's bundled bitmap-font metrics and glyph atlases. Bundled textures loaded during a scenario are rendered with their draw tint. Older untracked textures and non-ASCII glyphs are recorded as placeholders, so these frames validate control layout and text including the official Atlas sprite crops, rather than GPU rendering or operating-system dialogs. Clipboard operations remain inside the test process.

Recovery performance can also be tested without a desktop: `CalcsTab:BuildOutput(true)` queues the same background work used after desktop edits; `Modules.RecoveryTasks.tick` advances it. `HeadlessUI.install({interactiveRecovery=true})` opts UI frames into the desktop's deferred recovery path; `ui:restore()` restores the prior setting. The ordinary headless calculation path stays synchronous for deterministic build and AI tests.

From `src`, run `luajit ../tools/benchmark_map_rerolls.lua` to measure the Atlas map reroll estimator with 500 unsuccessful rolls, or add `stress` for 20,000. It reports CPU time, cold data loading, the 95th percentile and maximum background-slice CPU time, and checks cancellation after at least 100 rolls. The benchmark avoids every eligible modifier to force the full attempt count; these timings are machine-specific and do not prove desktop frame times.

`python tools/check_update_manifest.py` checks the content hashes of files listed in the updater manifest. It uses the updater's exact and LF-to-CRLF hash rules; it does not verify that every required file is listed or that remote URLs are reachable. CI runs this check and its regression tests. Before committing, run `python tools/check_update_manifest.py --git-index` after staging to check the exact staged manifest and files, even if the working copy has newer edits.

`python update_manifest.py` generates `manifest-updated.xml` for review. It preserves the current manifest's download sources and previously published files, and stops if an existing file is missing. Review additions and removals explicitly before using `--in-place`; generation does not verify that remote files are available. `python tools/test_update_manifest.py` checks source, file-retention and platform behavior.

For a read-only passive-tree interaction benchmark, run from `src`:

```sh
luajit ../tools/benchmark_tree_ui.lua /path/to/build.xml 5
```

It loads the build into memory, focuses an adjacent small or notable passive, and sends mouse events to allocate and remove it. It checks that the build revision is restored and reports recorded calculation components for both changes. The CPU times include the headless drawing recorder and are not desktop frame times; compare like-for-like runs and validate responsiveness in the desktop separately. The optional cycle count is 1–20.

Add `desktop-recovery` after the cycle count to exercise deferred recovery using the supplied build's settings. Use `deferred-recovery` instead to enable 32 recovery trials over 60 seconds in memory as a stress scenario. When recovery is enabled, the benchmark waits for results after allocation and removal. It reports the number, total CPU time and worst CPU time of additional recovery frames, as well as worker slice timings including work done during the initial click and update frames. Zero additional frames therefore does not necessarily mean no recovery work ran. Without either argument, ordinary synchronous headless calculation is used. The fixture is never saved.

Add `skill-profile` after either recovery mode to record the number and inclusive CPU time of active-skill calculations and their environment, tree-modifier, skill-modifier, defence and offence components. Nested calculations can overlap in those totals, and the instrumentation adds overhead; use it to locate work, not as an uninstrumented latency measurement.

To profile the node-power heatmap separately, run `luajit ../tools/benchmark_node_power.lua /path/to/build.xml 30` from `src`. It loads the build without saving, enables the heatmap, and reports CPU time per power slice and frame plus whether calculation finished within the requested frames (1–1000). This uses a running CPU clock so time-sliced work can yield during a frame; the default headless UI clock remains deterministic. CPU timings include headless drawing capture and are not desktop frame times.

For calculation-focused measurements, add `no-capture` after `skill-profile` to the tree interaction benchmark, or after the frame count to the node-power benchmark. This suppresses image and text drawing calls, avoiding the headless recorder's allocations. It measures CPU work without drawing and cannot show desktop rendering cost or validate visual output. Compare both modes when investigating a frame spike.

The node-power calculator skips the Full DPS roll-up when the selected metric does not use it; tree hover comparisons and the Full DPS metric still calculate the roll-up. On one synthetic six-group build, 20 paired headless Life comparisons took 71 ms without the roll-up and 499 ms with it. Across five adjacent nodes, all 415 tested non-Full-DPS metric comparisons and the combined offence/defence values matched. A separate 30-frame headless run completed 98 Life calculations without the roll-up versus 47 when forcing it. These are bounded CPU measurements without drawing calls, not evidence of desktop frame rates or whole-build latency.

For a controlled Full DPS comparison, add `no-capture life include-all` to enable all existing skill groups for Full DPS in memory and measure Life node power. Append `force-full` to measure the previous unnecessary roll-up on the same fixture. Both modes report the number of node evaluations; neither saves the fixture. Use `full-dps` in place of `life` to measure the Full DPS metric itself.

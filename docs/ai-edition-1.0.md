<!-- cspell:ignore lupa -->
# AI Edition 1.0 release review

This is the working acceptance checklist, not a completed release announcement.
The installed application and personal builds are outside this release workspace.

## Filters

- [x] Edit item tiers directly, including movement, ordering, new tiers and removal of overrides.
- [x] Reuse and share local rule modules between profiles.
- [x] Review changes, undo/redo edits and recover interrupted drafts.
- [x] Organise item families and explain provable rule priority conflicts.
- [x] Configure campaign weapon/defence families and browse compiled source sections.
- [x] Reach every shared catalogue result through paging.
- [x] Test clipboard items, configure scene levels and revisit sample history.
- [x] Save named exact example sets and reusable appearance palettes in the build.
- [x] Style selected categories in place and review complete file changes.
- [x] Page through saved examples and test separate items without overwriting the sets.
- [x] Expand shared colour/sound styling and preview every supported icon shape.
- [x] Choose colours visually with exact RGBA entry and Ruthless opacity validation.
- [ ] Review remaining offline filter workflows against the current game and reference tools, including validation in the game client.

## Crafting

- [x] Browse modifiers with tiers, weights, groups and exclusion explanations.
- [x] Edit target groups directly, with clear AND/OR and property requirements.
- [x] Target identified starting synthesised implicits, with ambiguity checks for overlapping identities.
- [x] Inspect recipe branches visually and edit routes without numeric guesswork.
- [x] Keep experimental items in a named local inventory.
- [x] Show native weapon DPS, attack rate, critical chance and Ward in item comparisons.
- [x] Use native weapon and defence minimums as saved crafting goals and recipe stop conditions.
- [x] Compare methods and explore success/budget and spending distributions.
- [x] Save per-resource quotes, reuse them across gear guides and share them with native/MCP simulations.
- [x] Report modeled ingredient and service quantities separately from spending, with an illustrated resource browser.
- [x] Apply quality enchantments with native item state, recipe goals and resource costs.
- [ ] Complete and validate current crafting coverage, including incomplete socket, corruption and league mechanics and their probabilities.
- [ ] Model raw-stat precision when displayed endpoints are rounded. For example, the pinned 3.30.0.4 `LifeRegeneration2` modifier stores 126–480 life per minute, while PoB displays 2.1–8 life per second. Matching single-stat flat life and mana, and percentage life and energy-shield regeneration tiers sample per-minute integers when the raw bounds fit the displayed range and render to its endpoints. This includes rounded Essence regeneration bounds in the pinned data, though their current availability has not been established; other raw-stat formats remain incomplete. Uniform raw rolls and actual in-game distributions remain unverified.
- [ ] Validate mixed Eldritch and synthesised implicits in the Locus against the live game; both use experimental replacement models. Vaal Orb replacement of an identified Eldritch or synthesised implicit uses an assumed uniform choice; ambiguous synthesised groups remain unavailable.
- [x] Keep empirical assumptions visible; never present unknown weights as facts.

## Atlas

- [x] Save desired and avoided nodes and select mechanic notables together.
- [x] Preview/recalculate all desired targets, with explicit apply and pause controls. Changing the route mode makes a preview unusable until the original mode is restored or the route is recalculated.
- [x] Summarise mechanic investment, small nodes, blocking and keystone tradeoffs.
- [x] Compare saved plans visually and preserve exact tree versions.
- [ ] Compare the current Atlas with the live game. GGG's 3.30.0c export commit is bundled for Standard and Ruthless, and `tools/check_atlas_release.py` verifies all four source files and both generated graphs. The live game has not been checked.
- [x] Make an experimental Genesis Tree planner available from Atlas plan tools, with search, connected paths, choices and build-persisted allocations.
- [ ] Validate Genesis allocation and choice rules, point limits and layout against the live game. The planner shows the published 16-point Equipment maximum as a reference, while point costs and other branch limits remain unverified. All node icons, node frames, womb artwork and the 3.30.0.4 Genesis background are bundled. The current graph uses the pinned 3.30.0.4 client export and standard passive-tree orbit geometry; background alignment and frame-state selection are inferred and need live-game confirmation.

## Shared experience

- [x] Consistent planning typography, buttons, spacing, navigation and empty states.
- [ ] Explain unavailable actions and conflicting choices before execution.
- [x] Keep invalid forms editable and explain validation errors without source paths.
- [x] Show stale dependencies after gear, craft or Atlas targets change.
- [x] Keep linked character, crafting, filter and farming plans easy to navigate.
- [x] Complete repeated native navigation at 960, 1024 and 1280 widths.
- [x] Verify save/reopen, undo, portable bundles and local MCP workflows.
- [ ] Review final screenshots, run required CI and verify the updater manifest.
- [ ] Verify the release candidate in the native desktop renderer without modifying the installed application or personal builds.

Hosted economy feeds, community discovery/heatmaps, cloud sharing and automatic
account uploads are separate service work. Their absence does not justify a
placeholder that pretends to provide those results offline.

## Anoint sorting performance

The anoint selector requests Full DPS for candidate calculations only when that sort is selected. Other sorts use their ordinary calculation. `tools/benchmark_anoint_sort.lua` compares the sorted order and every value against the previous behavior for a supplied read-only build, using 30 anointable nodes and several metrics. On a synthetic geared multi-skill fixture, non-Full-DPS sorts took 0.08–0.11 seconds versus 0.60–0.99 seconds with the previous calculation; Full DPS still runs the full calculation. These are bounded headless CPU measurements, not native desktop frame times or evidence of improved passive-tree click latency.

## Timeless Jewel dialog

The dialog adapts its width at 960, 1024 and 1280 pixels. Headless checks cover the common, Militant Faith and Reclaimed Malevolence layouts, including spacing between the Militant Faith selectors. Native desktop rendering remains unverified. Generate and Reset have a one-step list undo/redo for each jewel type while the dialog is open; undoing Reset restores the two lists, not search results or other controls. Switching jewel types retains their list drafts in that dialog. Only the selected jewel type and its lists are saved with the build; other drafts and undo history are discarded when the dialog closes.

## Timeless Jewel fallback weights

Regenerating fallback weights now preserves the scaling divisor when reusing a parsed modifier; previously some generated weights could become 100 times larger on the second run. The generator also skips Full DPS calculations for other selected metrics. `tools/benchmark_timeless_weights.lua` compares repeated generated weights against the prior calculation mode on a supplied read-only build. In one synthetic multi-skill run, Life, Combined DPS and projectile avoidance each produced identical weights while their generation fell from about 3 seconds to 0.4–0.9 seconds of headless CPU time. This does not measure native desktop latency or establish passive-tree click improvements.

## Portable desktop startup check

On November 22, a portable package built from commit `31f37cb7383ecc56c8a68096a6babd60f8feb768` matched all 3,171 Windows manifest entries. A fresh extraction passed `tools/smoke_portable_windows.py`: it reached an unnamed build, exited cleanly, and created its settings and builds folder inside that extraction. This verifies startup for that source revision, not interactive desktop rendering or the release candidate.

On November 22, a portable package built from commit `b0489cc6f854dffb2b0dc3335d22f9924b72b0f3` passed `tools/smoke_portable_windows.py` in a fresh extraction. It reached an unnamed build, exited cleanly and created its settings and builds folder inside that extraction. The installed application and personal builds were not used for the smoke test.

This is a startup check, not a native UI acceptance test. A separate interactive attempt could not activate the portable window in Windows computer-use, so its rendering and workflows remain unverified in the desktop renderer.

On November 22, a fresh portable package from commit `7a956cd8935fdd0ac7c10cbf0ea965ad07eddc3e` also reached an unnamed build and created settings and a builds folder inside its extraction. The package builder verified the manifest while building, and the ZIP integrity check passed. A visible launch still could not be activated by computer-use after refreshing the window and retrying. The isolated copy was closed; the installed application and personal builds were not used. This confirms startup for that source revision but does not verify its rendered workflows.

## Remaining release work

On November 21, checkpoint `c01b653665460c577f141bbe7742abb37b22051f` passed
[Run Tests](https://github.com/nexus671/PathOfBuilding-AI-Edition/actions/runs/44958840825)
and [Spell Checker](https://github.com/nexus671/PathOfBuilding-AI-Edition/actions/runs/44958840800).
The local source-stable headless audit recorded 2,307 frames with no audit failures,
and the updater manifest checked 3,165 entries without errors. The Atlas release
check matched the official 3.30.0c Standard and Ruthless exports and both generated
graphs. These checks do not validate the live game or native GPU rendering; later
commits require their own checks. This checkpoint is not a 1.0 release.

The [3.30.0d patch notes](https://www.pathofexile.com/forum/view-thread/4017726)
introduce Originator's Exalted Orbs for rare maps, including Nightmare Maps, and
Primordial Exalted Orbs that reveal a random exotic Exalted Orb. They also
change two Genesis Tree currency passives. The November 20 RePoE 3.30.0.4 export adds both currency records. Filter class and drop-level metadata and the crafting catalogue now use that snapshot; its map bases and map modifier pool match 3.30.0.3. The latest official Atlas export is 3.30.0c. Recheck future exports and validate map-crafting eligibility and modifiers in game.
The notes do not specify outcome weights. Originator previews use a labelled experimental model, with unsupported removal branches reported instead of silently skipped. Validate eligibility, Nightmare interactions and outcome weights in game.


On November 19, checkpoint `cd50961573dfe54caa830a0d45d237f13ddf6dd2` passed
[Run Tests](https://github.com/nexus671/PathOfBuilding-AI-Edition/actions/runs/44619732759)
and [Spell Checker](https://github.com/nexus671/PathOfBuilding-AI-Edition/actions/runs/44619733012).
The hosted tests included the generated crafting-import sweep, planning workflow,
headless UI and update-manifest checks. Later commits need their own checks.
This checkpoint does not establish full 1.0 parity or live-game verification.

An earlier checkpoint, `4d410c005d95f84adf7f19cdb76f8669ebdc775f`, passed
[Run Tests](https://github.com/nexus671/PathOfBuilding-AI-Edition/actions/runs/43447147022)
and [Spell Checker](https://github.com/nexus671/PathOfBuilding-AI-Edition/actions/runs/43447146999).
It passed 1,237 Lua tests, 48 Node tests, the MCP save/reopen workflow and 906
source-stable UI views. Its 2,426 updater entries and CI artifact source hashes
were verified against that commit.

Preview 31 preserves the Twice Corrupted marker through native item import,
tainted crafting, manual edits, saved projects and MCP. This does not add second
corruption outcomes to the labelled 3.29 crafting model. The UI audit now distinguishes overlay tooltips from button
content, with positive tooltip and deliberately broken clipping fixtures.

The next review recovers complete, unique assignments of up to two corrupted
implicits from pasted item text. It preserves independent rolls and recognises
reordered lines without mistaking unchanged natural implicits for Vaal modifiers.
Ambiguous or unsupported identities block implicit odds checks with an explanation;
they do not silently produce a zero-percent result. Older saved states can recover
missing identities from their source item. A seven-base, 140-item diagnostic
recovered every generated example with matching text and target identities.

Preview 17 makes bench, Essence and Harvest choices reflect the working
item. Bench and Essence execution share their precondition helpers with the
menus; Harvest choices use the native eligible pool. Resistance swaps exclude
fractures, locked suffixes, conflicting groups and missing tiers. Valid selections
survive list changes and switching currencies. MCP retains future planning IDs
while reporting current availability and reasons.

The initial seven-base diagnostic found 54 invalid offered first choices;
the corrected probe applied all 105 offered first choices without errors. A
bounded availability benchmark measured at most 0.6 ms mean per check. Focused
engine, catalogue and native selection tests pass. Full local validation passed
1,140 Lua tests and 687 source-stable UI states without audit failures. The real
MCP workflow verifies availability metadata on both normal and rare inputs.
Exact-commit CI passed for preview 17, and its source hashes were verified.

Preview 18 extends shared prerequisites to Bestiary conversions and meta
crafts, Ducats, memory currencies, Dominance, Binding and Veiled Orbs. The expanded
seven-base probe previously offered 162 actions that failed engine prerequisites.
It now applies 340 available actions without errors, excluding crafts that require
a separately configured donor. Positive tests preserve eligible crafts, including
locked-source Bestiary conversions. A ten-seed sweep then found a native item
serialization error for independently rolled corruption implicits. Rolled implicit
lines now preserve each value without passing a range table to the scalar-only
serializer; Eldritch and Blessed Orb lines use the same conversion. The corrected
sweep applied all 3,400 actions without errors. Local validation passed 1,144 Lua
tests, the real MCP workflow and 696 source-stable UI states without audit
failures. Exact-commit CI passed, and its artifact source hashes were verified.

Preview 19 adds Omen of Connections with currency artwork, availability
checks, undo and two-resource costs. Socket-service metadata lets MCP discover
the action and costs; the native guide can combine a Harvest enchantment and
guaranteed linking. Socket bench and Omen calculations return a single exact
model outcome instead of a sampling interval. The MCP schema also accepts
multi-value Blessed Orb rolls, with matching native validation. Local validation passed 1,151 Lua tests, 43 Node tests, the full MCP save/reopen
workflow and 711 source-stable UI states without audit failures. Exact-commit
CI passed, and its artifact source hashes were verified.

A follow-up modifier audit found that all 44 tested multi-line affixes reused
the first roll on later lines. Native item crafting, plain import inference,
bench modifiers and workbench comparisons now share the same range renderer.
The corrected audit has no mismatches; scalar and legacy singleton rolls retain
uniform behavior. The regression matrix also verifies native item round trips.

Before this review, a read-only saved-build benchmark returned equivalent synchronous and
background results in 3.93 and 4.87 seconds, with a 250 ms snapshot and a 38 ms
worst worker slice. Earlier runs measured about 3.9 seconds each, with 18-37 ms
worst slices after adding checkpoints, versus 142-163 ms before them. These
bounded, variable measurements do not establish sustained desktop
responsiveness or exclude a performance regression. Snapshot creation and
occasional initialization pauses still need attention.

Preview 20 replaces full active-item reparsing during AI snapshots with
read-only capture. Unusual range normalization uses an isolated native parse;
regular native file saves keep their existing path. Revision hashing uses the
captured tree while retaining legacy XML normalization and hashes. It also
avoids composing a full snapshot when only the revision is needed.

The 264-item saved-build check preserves every XML byte, the legacy hash and
active item objects. A separate catalogue comparison passed all 1,333 unique
items without XML mismatches. Focused tests cover range rounding, variants,
whitespace/entities, source edits and notes restoration on failure. The command
`luajit ../tools/check_snapshot_equivalence.lua path/to/build.xml`, run from
`src`, repeats the saved-build proof without writing the supplied file.
The read-only headless click benchmark `python tools/run_headless_lupa.py --filesystem tools/benchmark_tree_ui_responsiveness.lua path/to/build.xml 5 deferred-recovery` measures a passive click, the following update frame, per-skill cost-warning probes and deferred recovery slices. Probe times include their nested work and are part of, not additional to, BuildOutput time. Omit `deferred-recovery` to use the build configuration, or use `desktop-recovery` for desktop-style deferred recovery with the saved configuration. It checks that the build revision is restored and never saves the supplied file. Draw-command capture and instrumentation add overhead; these figures do not measure native desktop frame time.

A paired run captured the same 476,247 XML bytes and legacy revision in 119 ms,
versus 282 ms for the legacy path; a revision-only check took 91 ms. The idle
planning benchmark measured a 101 ms snapshot, 3.79 seconds synchronous,
3.53 seconds background and an 18 ms worst worker slice, with equivalent
calculations. These bounded timings do not prove sustained desktop responsiveness.

Local validation passed 1,155 Lua tests, the full MCP workflow and 711
source-stable UI states without audit failures. Exact-commit CI passed, and its
artifact source hashes were verified.

Preview 21 adds a native resource-price editor with searchable currency
artwork, recipe-resource and quoted-resource views, source/date metadata and
copying between gear projects. Quotes persist in builds and portable bundles.
Native simulation, recipe comparison, fossil optimization and MCP use the same
resource aliases and explicit action-override rules. Zero means free; a missing
quote remains unknown. Unit changes require clearing quotes rather than
relabeling their values. Bench and other aggregate prices are labelled as whole
actions; the editor does not invent ingredient quantities or fetch live prices.

Local review passed 1,162 Lua tests, 44 Node tests, ModCache regeneration and
the real MCP workflow. Regression checks cover zero/missing prices, aliases for
all six influence currencies, overrides, project reuse and empty dictionaries.
The final local and CI passes covered 732 source-stable UI states without audit
failures. Exact-commit CI passed, and all artifact source hashes were verified.

Preview 22 checks the recovery worker's time budget before every
simulation step. Previously it checked only once per eight steps, allowing a
batch of expensive events to exceed the frame budget. Five paired native
build edits preserve all recovery outputs, individual trial data and timeline
data. The worst worker slice fell from 53 ms to 32 ms in that bounded run;
total work remained similar. Individual events and collection pauses can
still exceed the budget, and sustained desktop responsiveness remains unproven.

The read-only command `luajit ../tools/benchmark_tree_responsiveness.lua
path/to/build.xml 5`, run from `src` with the headless Lua environment, reports
allocation, normal calculation and recovery-worker times. It restores each
passive edit and checks the original revision without saving the supplied file.

Preview 23 adds source-matched bench ingredients and exposes them in
native quotes, recipe costs and MCP inspection. Independent and runtime joins
agree on 3,541 of 3,737 ordinary craft/class cases, plus 368 of 390 Rune Dagger
and Warstaff cases. Other costs stay unknown. Conflicting quote aliases are
rejected before a project is admitted, and empty quote books retain the working
unit. A bounded 100-project validation probe took 17 ms.

Fossil comparison now has artwork, selectable subsets, a chance/interval plot,
cost and chance sorting, explicit unknown costs, quote provenance and CSV export.
The mixed priced/unpriced ordering is consistent, and selection does not spend
currency. Configuration retains existing choices, rejects duplicates and does
not assume an unrevealed Tangled outcome. Local review passed 1,168 Lua tests,
44 Node tests and the real MCP workflow. Exact-commit CI passed 1,169 Lua tests
and 759 source-stable UI states, including incomplete saved fossil configuration
recovery. Updater and artifact source hashes were verified.

Preview 24 isolates action totals from shared resource quotes. The
reproduced case changed an Alchemy-priced bench craft from 1 to 7 chaos even
though the recipe never executed Alchemy. The scoped override leaves it at 1;
an actual Alchemy action uses 7. Global resource-price overrides remain global,
zero action totals remain free, and results report applied override counts.

Native recipe comparisons now accept property-only goals, retain invalid price
input with a readable error, and use the same scoped totals. Simulation cost is
shown near the top of its summary. Crafted-mod removal and one/three-modifier
bench reforges use pinned service quantities. The added regressions cover
caller immutability, missing units, non-finite values, CSV provenance and exact
fossil-subset overrides. Inspection, performed actions and simulation steps
expose their price keys for MCP clients. Four-fossil Allflame override keys also
survive checkpoint save/reopen. Local review passed 1,174 Lua tests, 45 Node
tests, the real MCP workflow and 780 source-stable UI states without audit
failures. Exact-commit follow-up CI passed after the test-host fix below.

The first preview 24 CI run passed the Lua, Node, UI and ModCache checks but
timed out during the MCP filter test. A Linux reproduction exposed draw commands
accumulating in the headless test host across polling frames. The host now uses
the recorder's frame boundary and the workflow rejects unbounded command counts.
The instrumented full workflow passed with at most 13,054 retained commands,
versus 5.77 million before the diagnostic run was stopped. This fixes the test
host; it does not establish sustained desktop performance. Follow-up CI passed.

Preview 25 fixes result refinement switching from a saved recipe to the
currently selected action. Refined runs retain the captured item, recipe, targets,
seed, quotes and budget while increasing only trials. The simulation header names
the selected action, and result summaries identify saved recipes. Calculation
buttons prevent duplicate jobs; closing a workbench cancels its own calculation.
Captured result setups survive layout changes, while older results without a
captured setup require a fresh simulation before refinement.

Preview 26 retains simulation, fossil and action-odds results in transient
build-owned analysis sessions. Rebuilt views reconnect to the running calculation;
results remain available after navigation discards an old view cache. Background
fossil comparisons do not interrupt another tool. Asynchronous errors retain raw
diagnostic details while showing readable messages in the UI. Build initialization
and shutdown clear analysis state and cancel crafting work because PoB reuses its
build-mode object across files.
Running and completed Atlas route previews are also cleared on a build change.

The current review resets save-state labels across reused builds and scopes working
craft drafts by project. Project removal and undo preserve inventory, checkpoint,
quotes, order and working drafts; cleanup targets only the removed project.
Reviewed MCP removals identify what is removed and retain recovery files. Applying
an edit carries compatible working drafts and removal undo forward without changing
the original build's undo state. Saved recipes use their own starting state even
after manual working-item edits. Native screens cover empty lists, restoration,
inventory and large-text removal notices.

The next save-state review covers target edits, simulation fields and accepted
advanced configurations. Merely opening or navigating a saved craft stays clean,
as do cancelled dialogs and directly kept resource quotes. Other unfinished
settings keep their working-draft marker when quotes are saved.

Repeat cross-tool performance and recovery checks. Close source-verified socket, corruption and league gaps without
inventing missing weights. The [coverage guide](crafting-coverage.md) identifies
incomplete mechanics and model assumptions; this is not a full-parity release.

An Atlas starting-route pass shares distance calculations and classifies only
eligible notables. Five paired runs on both empty and progressed 3.29.3 and 3.30
preview plans produced identical routes. After warm-up, the measured generation
time ranged from 33-62 ms, compared with 111-154 ms before the change. These are
bounded headless measurements, not proof of sustained desktop responsiveness.

Repeated Atlas searches reuse decoded node text while checking for changed node
and choice text. In paired headless runs, batches of 50 identical-result searches
on 3.29.3 and the 3.30 preview took 48-329 ms, compared with 155-450 ms before
the change across All, Maps and Breach filters. Individual search latency and
native desktop responsiveness still need interactive measurement.

A November 21 tree responsiveness investigation measured 10 skill-cost warning
probes per recalculation on a synthetic geared build. Three headless update frames
took 60-101 ms, including 21-43 ms in warning probes; these timings include draw
capture and profiling overhead, and do not establish desktop responsiveness.
Reusing rejected warning-probe environments reduced some measured times but changed
a nested Toxic Rain damage cache in the Mirage Archer comparison fixture. A guard
for proxies, minions and global triggers passed the five bundled build comparisons,
but its coverage of other interactions is not established, so it was not shipped.
Reusing the existing main-skill output did not reduce the synthetic probe count.
Continue performance work with full-output and nested-cache comparisons, including
triggered and proxy builds, before enabling reuse. A November 22 follow-up measured 10 initialization and 10 partial calculation calls in each of five synthetic geared-build updates; inclusive initialization took 16-38 ms and partial calculations 9-19 ms with profiling overhead. Reusing the initial base modifier databases while creating fresh probe environments changed a Mirage Archer nested Toxic Rain cache (CombinedDPS 1,202,294.56 versus 1,200,971.43), so that prototype was rejected. This does not establish the cause or safe reuse conditions. The tree UI benchmark now has an optional warning-probe breakdown for further investigation.

A November 23 read-only comparison on a saved 3.30 build tested recycling per-node modifier lists inside warning-only calculations. It passed the current scalar-output and nested-cache comparisons on that build and the five bundled fixtures, but did not improve the measured timings: across 15 captured clicks each, baseline median BuildOutput was 96 ms and the candidate was 108 ms; update-frame medians were 141 ms and 157 ms. Results varied substantially and include headless capture and profiling overhead. The candidate was discarded. The optional warning profile now groups measured allocation-frame probes by skill name to help locate future work; its inclusive timings are not desktop frame times.

Timed flask and tincture projections now use the recovery worker's checkpoints
during their native calculation. A read-only two-cycle saved-build comparison
preserved the recovery outputs, individual trials, trace and original revision.
Its longest slices were 8.9-10.6 ms after the change and 11.4-12.2 ms before;
other runs have had larger, variable pauses. These bounded results do not prove
that all long slices or desktop stalls are eliminated.

The headless UI adapter can opt into desktop-style deferred recovery. A real
passive-node input test exposed an automatic-level ordering issue: the displayed
level could advance after the calculation captured the prior level. Recalculation
now resolves the estimate first and rechecks it if the output changes extra
passive points. Tests compare deferred and synchronous results after a click.

Atlas search now reuses its cached mechanic classification as well as decoded
text. In paired headless batches of 50 searches across All, Breach and Threads
on the 3.29.3 and 3.30 preview trees, result IDs and ordering matched. Four
timed batches per case took 52-108 ms after the change and 130-190 ms before.
These bounded measurements do not establish native desktop responsiveness.

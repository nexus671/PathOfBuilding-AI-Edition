# Connected planning tools

Open AI builds, Atlas, Crafting or Journey to enter the planning workspace. **Tools** in the top bar searches planning pages, saved Atlas plans, crafting projects, Journey milestones, gear goals, resources and leveling stages, and filter profiles and personal rules as well as performance diagnostics and portable bundles. Journey searches include notes and guide text; filter rule searches include their conditions and actions. Select a result to open it; working crafting and filter drafts remain available.

Choose **Search base filter rules** in Tools to search the selected profile's base filter, including imported filters. The catalogue loads when you open it. Selecting a result opens that rule in the filter editor; edits create a personal override.

## Same-base vendor review

**Tools > Same-base vendor review** groups copied normal, magic, rare and unique equipment by its identified base. A complete set may yield one Orb of Chance under the [3.30 patch notes](https://www.pathofexile.com/forum/view-thread/4013680); the review shows complete sets, remaining items and missing rarities for the next set. Two-Toned Boots require both defence properties so their base variants can be distinguished. Each paste represents a different item; items can also appear in other vendor reviews, so avoid counting them twice. Base identification and special item eligibility are not verified in game, so check the vendor offer. The list stays available while the current build is open, but is not saved with it. Remove, Clear and Paste can be undone or redone while the review remains open. AI clients can use `review_same_base_vendor_items` with the same copied texts; no stash is read.

## Same-name rare review

**Tools > Gem quality planner** reads a copied active or support gem and calculates the Gemcutter's Prisms needed for a target up to 20%. Corrupted gems cannot use prisms; higher targets need a different method. Copy the guide or choose **Add to Journey** to keep a gem milestone with the build, then save the build. The milestone records the observed starting quality and does not track later gem changes or spending. For an eligible uncorrupted level-20 support gem, **Compare quality routes** also offers the [one-Prism vendor recipe](https://www.poewiki.net/wiki/Gemcutter%27s_Prism): it returns a level-1, 20% quality gem that must be releveled. Verify the vendor offer and special gem properties in game. The selected route is what gets copied or added to Journey. MCP `plan_gem_quality` provides the same calculation and a milestone draft without an ID; AI clients can add an ID and use the reviewed Journey proposal flow to keep it. The corruption reference shows historical conditional Vaal ranges, related bundled Vaal gem candidates, and the 3.30 Lens state and caps. Eligibility beyond corruption state, Lens outcomes and all odds remain unverified; the Lens can destroy the gem. It does not simulate a corruption or transformation.

**Tools > Same-name rare review** compares identified rare items pasted from the game. Matching pairs can yield Chaos Orbs and triples can yield Exalted Orbs under the [3.30 vendor recipe](https://www.pathofexile.com/forum/view-thread/4013680). The review prioritizes triples and then pairs without reusing an entry. Select a name to see its pasted bases and remove an individual entry. Each paste counts as a separate item; verify the actual items and vendor offer in game. The working list stays available when the review is reopened while the same build is open; it is cleared when the current build closes or reloads and is not saved in the build. The review does not read the stash and accepts copied items up to a 4 MiB total. The `review_same_name_rares` MCP tool accepts copied item text and returns the same grouping for AI clients; its request shares the 256 KiB desktop bridge limit.

## Performance and background upgrades

**Tools > Performance diagnostics** shows observed last, mean and worst processing times, ordered by the worst slice. Main calculation, detailed calculation and comparison setup are shown separately within the overall build recalculation. Refresh after an interaction, or copy the timings when reporting a slowdown. Reset clears session measurements only.

**Journey > Gear > Measure upgrades** calculates candidates between frames. You can navigate to another tool while it works; the button shows completion counts and its tooltip shows the current phase. Cancel discards unfinished work and retains completed measurements. Editing the source build invalidates the ranking.

The worker restores the active build and calculation cache after every yield. Native edit identities avoid hashing the full build every frame; an exact XML revision check still runs before publishing results and before applying a proposal. Background work is cooperative: initial snapshots and some native loading/calculation operations can still pause input. Diagnostics report those pauses rather than promising a frame-rate target.

Developers can run `luajit ../tools/benchmark_planning.lua` from `src`, optionally supplying a build XML path. It reads the fixture without saving it and compares synchronous and background results, elapsed processing time and worst slice.

## Crafting recovery and spending

Written crafting guides can contain as many steps and goals as fit in the build's crafting metadata. The combined saved crafting data has a 2 MiB size guard; executable simulation recipes still have their own bounded limits.

In a saved project's **Plan** tab, **Browse guide steps** searches instructions, stop conditions and failure notes. Filter by completion status, page through long guides and select any step to edit it, mark it done or to do, or remove it after confirmation. You can undo the last removal while the browser stays open, provided the guide steps have not changed since. Editing preserves its progress; changing a modeled instruction asks before removing its guide link and leaves the saved recipe intact. Use this editor when a text edit would otherwise discard step details. Save the build to persist those changes.

In **Journey**, a linked gear goal or milestone shows its crafting-guide progress and next unfinished step. **Open guide** lets you update those steps without leaving Journey; **Open linked plan** still opens the crafting workbench. Step progress does not automatically mark the gear as owned.

In **Crafting > Simulate recipe > Recipe routes**, select a step and open **Failure recovery**. Choose to continue along the failure route, stop for inspection, restart from the starting item, or set the item aside for salvage. Written recovery instructions stay with that step.

An unwanted roll counts as a failed step when its target or property conditions are unmet. With the successful-action condition, a supported currency use can succeed even though the final item is unfinished.

Restarting acquires another hypothetical starting item, adds its supplied starting-item cost and returns to step 1. The total action budget still limits loops. Enter a realistic base cost: zero means no acquisition cost is counted. Salvage ends the trial without inventing resale proceeds.

**Results / distribution** displays mean spending plus median, 90th and 99th percentile spending. Every executed action needs a supplied price in the same currency. These percentiles include unsuccessful and budget-capped trials; they are not the cost of guaranteed success. Successful-trial statistics remain separately labeled in the detail list. Run more trials to reduce sampling uncertainty.

## Survival stress tests

In **Survival charts**, choose a preset and select **New scenario**. Review its assumptions, then create a separate configuration set. Mapping pack stress, repeated boss hits, hits plus continuous damage, and resource pressure supplement the existing presets.

Damage scales from the active configuration's raw hit inputs. These are editable stress tests, not named-monster models or readiness guarantees. Check damage, penetration, enemy level, conditional buffs, flask policies and skill costs before running. The scenario description states the interval, scaling and continuous damage assumptions.

## Atlas stages and requirements

Use **Atlas > Stages & strategy** to label a plan Starter, Intermediate or Final and link its previous saved plan. The progression view orders refunds and allocations while preserving connectivity and the supplied point budget, including granted points. If a direct route fails, it tries a rebuild and, where relevant, a temporary path to a point-granting node. It labels extra refunds and reports when it cannot find a sequential route with the available budget. Routes are valid transitions, not minimum-refund solutions; refund currency prices are not assumed.

The strategy tab records maps and rolling requirements, map supplies and consumables, character/unlock requirements, mechanics or modifiers to avoid, and a dated setup estimate with currency and source. Record Threads for 3.30 strategies or Scarabs for older versions. Select **Use in Atlas draft**, then **Keep plan** and save the build. Estimates do not automatically spend or reserve Journey resources.

Linked stages must use the same Atlas version and cannot form a cycle. Saved Atlas plans have a total metadata size guard rather than an eight-plan count limit.

## Portable bundles

**Tools > Export / import complete bundle** copies native character XML and saved planning data together: items, skills, passive trees, configuration sets, notes, crafting guides and working checkpoints, Atlas stages/strategies, and Journey acquisition and leveling plans.

Keep working drafts before exporting. Paste and inspect a bundle to see its contents, then **Review as new build**. Native proposal review calculates it before you choose Apply. It opens as an unsaved new build and does not overwrite the source file.

Bundles have a version and corruption checksum, with a 16 MiB size guard. Imports retain recorded price dates, recipe assumptions and references; they do not refresh external data. Native builds also retain their normal save/export behavior.

For AI-proposed Journey replacements, the Changes page lists added, edited, removed and reordered entries, including ledger removals. Reviewing does not apply the candidate; use Apply and then build Save to keep it.

<!-- cspell:ignore Ukatoa Katakohi -->
<!-- cspell:ignore RRBG -->
# Native crafting

Open **AI builds → Crafting**, or choose **Items → Crafting plan**. Create a project with a starting item and explicit item level, then choose **Open workbench**.

The workbench tabs separate **Craft**, **Targets**, **Simulate**, and **Settings**. Crafting runs locally. AI builds, Atlas and crafting projects share a persistent planning workspace; switching pages preserves an Atlas draft. Equipped gear changes only through the desktop preview and review flow.

The **Rules** button shows the crafting rules version. Click it to review supported methods and assumptions. Choosing a newer character or Atlas tree does not change the crafting rules.

Plain item copies can be imported when their complete modifier identities and rolls resolve uniquely. Advanced copy text helps preserve identities. Missing item levels, overlapping modifier tiers and values the engine cannot reconstruct require an explicit choice; the importer does not guess. For a structured starting state through MCP, use the corresponding blank base as the starting text.

## Emulate an item

**Find currencies** opens search beside the working item. Filter by category, favorite actions, and select one to return to the tray. Search takes keyboard focus; arrow keys browse results and Enter selects an available action. Escape clears focus first, then returns to the tray. Hover a currency for its purpose and current prerequisites. Bench, Essence and Harvest choices follow the working item's slots, modifiers and rarity. The selected choice is retained while valid; a changed item cannot leave the dropdown pointing at a removed choice.

The item card groups prefixes and suffixes, shows slot usage, and marks fractured (**F**) and crafted (**C**) modifiers. Click a modifier to inspect its ranges, tags and required level beside the item, select a relevant action, or use it as a target. Group tiers compare required levels within the eligible modifier group; special modifiers keep their data names.

Weapon cards show native local DPS, its damage-type breakdown, attacks per second and critical chance. Armour cards include Ward. These properties also appear in saved-item comparisons; **Preview in build** calculates their character effects.

**Settings** contains advanced method configuration, **Allflame settings**, and **Edit hypothetical item**. The Craft tab keeps the currency tray, selected action, apply/undo and history controls together. In the hypothetical item editor, **Set socket layout** lets you choose observed or planned colours and links without consuming currency. Existing Abyss sockets must be retained and cannot be linked.

Search **Find currencies** for **replace quality** to apply a Harvest quality enchantment. The choices show the required Lifeforce amount and colour. The new enchantment replaces the previous one; affixes, socket colours and quality remain. **Targets → Item properties** can require a particular Harvest enchantment. These goals and enchanted inventory items also travel through MCP and saved projects.

**Targets → Item properties** can also require a Shaper, Elder, Warlord, Hunter, Crusader or Redeemer influence. This target is available to saved recipes and MCP. Gwennen's modeled random-influence outcome assumes equal chances among eligible types; the odds and eligibility are unverified.

**Set sockets and link them** is a combined bench preparation: it sets the requested socket count if necessary, then links those sockets. When the count already matches, estimates charge only the linking cost. Corrupted items include the corresponding Vaal Orb surcharge. Resource estimates use the state before each action.

For Bestiary prefix/suffix swaps, use **Craft settings** to enter the red beast's level. The simulator uses that level for the added modifier and keeps the item's level unchanged. If no beast level is set, it uses item level and shows a warning. This rule is based on [community research](https://www.poewiki.net/wiki/Beastcrafting) and has not been verified in the current game. AI inspection can supply the same action and page through its potential modifiers using `beastOffset`. The list reflects current influence and tags before removal; it is not a probability or a guarantee that a modifier can be added. Use simulation for the full action.

**Bestiary: maximum links** links the existing sockets without adding any. It uses one Black Mórrigan and one Craicic Sand Spitter; supply a price for each beast or a whole-action quote to estimate cost. The model currently supports non-unique, uncorrupted equipment with ordinary sockets.

Search **Find currencies** for **white sockets** to use the 3.30 bench craft. It turns supported sockets white without changing their links, for one Orb of Scouring and, on corrupted items, one Vaal Orb. Published 3.30 base implicit changes are also included. Supplemental crafting data remains pinned to 3.29.3.6 where not explicitly updated; see **Coverage** for its limits.

The standard Orb of Annulment uses the 3.30 rule: **Cannot roll Attack/Caster Modifiers** does not protect those modifiers from removal. Fractures and prefix/suffix locks still protect their applicable modifiers. Other 3.30 crafting changes are not yet fully modelled.

Full **Prefixes/Suffixes Cannot Be Changed** crafts use four Divine Orbs plus one Sacred Orb for weapons, four Divine Orbs plus four Blessed Orbs for armour and quivers, or four Divine Orbs plus eight Exalted Orbs for jewellery. Saved action-price overrides still replace the calculated total when used.

**Orbs of Binding** are no longer generated in 3.30. Existing orbs still work, so the planner retains the action for legacy supplies.

Find **Omen of Trichromatism (RGB)** in **Find currencies** to use one Omen and one
Chromatic Orb together. It guarantees at least one red, green and blue socket on
an uncorrupted item with at least three ordinary sockets, preserving their links.
Recipes can combine it with Omen of Connections for linked RGB goals. Placement
and additional colours use the stated socket-model assumptions; a three-socket
item gets exactly one of each colour. Three-socket calculations enumerate all
six placements under the uniform-position assumption; larger items use labelled
sampling. Undo restores the previous item; saved working crafts retain the action,
and simulation results report both ingredient quantities.

**Allflame settings** is unavailable for actions without a supported Allflame
transition, including Omen combinations and bench services. Its tooltip explains
the restriction before an unsupported profile can be entered.

**Item history** previews earlier items and the changes between them; restoring one undoes all subsequent actions. **Before / after** in Settings compares the working item with its recipe starting state. Drag the divider to give more space to the controls or item. Working state, favorites and history survive tool switches and resizing during the session.

In **Targets**, use **Find target modifiers** to browse tiers, item levels, weights, groups and tags. The table explains blocked modifiers and shows conditional draw chances. These describe one ordinary affix draw, rather than the selected currency or a complete recipe. The same explanations are available through AI inspection.

Select an icon in the currency tray, then click the item card or **Apply to item**. The card shows the base artwork, rarity, sockets, defences and modifiers; applied currency counts appear on the tray. Other methods remain in the dropdown, with their choices below it. **Settings** opens recipe controls, donor/fossil configuration and the reproducible random seed. **Configure fossil combination / donor item** accepts up to four fossils or a second item for Awakener and recombination. A Tangled Fossil requires the effect already revealed by the socketed resonator.

**Undo currency** reverses an action; **Reset item** restores the starting state. Veiled Exalted Orbs leave an unfinished choice: select **Choose an unveil** and pick an offered modifier before previewing. For a magic or rare jewel, open the hypothetical item editor and select **Record jewel unveil choices** to enter observed or hypothetical options, including a fractured veil. Offer probabilities and acquisition are not simulated. An imprint belongs to this starting item and can be restored once.

The experimental **Jeweller's Orb** action can change the socket count on uncorrupted equipment and be included in a recipe. **Calculate** lists each possible count without sampling, under the model's assumptions. It uses historical community weapon weights for all bases, excludes the existing count, and assumes quality raises only the maximum-count chance. Socket and link retention, these weights, and the quality model are unverified; treat estimated costs and chances as illustrative. Newly added sockets are white. Fully socketed items and Abyss sockets are not eligible for this model.

The experimental **Orb of Fusing** action rerolls links while retaining socket colours. Its link-group distribution starts from a [historical 100,000-orb test at 20% quality](https://www.reddit.com/r/pathofexile/comments/75t1c9/i_used_100000_fusings_for_science_statistics/), with assumptions for shorter items, other quality values and excluding the previous layout. Current game odds are unverified. **Calculate** enumerates possible layouts exactly under this model; the resulting probability is still an estimate of game behavior. Fully linked five- and six-socket items and Abyss sockets are not eligible.

For gloves, **Edit hypothetical item → Set socket enchantments** lets you choose up to three observed or hypothetical Katakohi modifiers and preview the result in your build. This replaces existing enchantments and removes excess sockets from the end. Recognized imported enchantments are selected automatically. You can also choose them as enchantment targets when planning other crafts; identify any unrecognized imported enchantments before using those targets. AI inspection returns the same catalogue and accepts these modifier IDs in the hypothetical state and enchantment targets. The Ducat's random outcomes and their probabilities are not yet simulated.

**Ukatoa's Ducat** replaces the implicits on a supported non-unique amulet with a random Eldritch implicit. Synthesized amulets are supported; fixed-implicit and influenced bases are excluded. The side and tier 1-4 probabilities are assumed equal and are not verified. The modifier pool uses pinned weights verified against the local 3.30 client; review estimates accordingly.

Existing current and legacy corrupted jewel implicits can be inspected, matched as implicit targets and saved when their identity is unambiguous. Identical current and legacy descriptions remain unresolved rather than guessed. Abyss, cluster and non-unique Prismatic jewel Vaal outcomes use an experimental model with assumed branch odds and rare-modifier counts; its unique-jewel outcome is treated as no change. Other jewel Vaal outcomes and unique transformations are not yet simulated. The Locus model for non-unique corrupted jewels is also experimental; see [coverage and assumptions](crafting-coverage.md).

Vaal Orbs can corrupt supported non-unique flasks and change quality by -10 to +10, up to 40%. The simulation assumes equal integer weights; those odds are not verified. Corrupted flasks cannot be modified with ordinary currency.

The engine covers core currencies, bench modifiers, essences, fossils, Harvest tag crafts and resistance swaps, fractures, influence slams, Awakener, Dominance, veiled choices, Bestiary, Eldritch crafting, quality, catalysts, selected Ducats, corruption and selected tainted currencies. Jewels, flasks and tinctures have their own affix limits; flasks and tinctures remain magic. Cluster jewels need a known small-passive skill.

Harvest resistance swaps include modeled elemental counterparts for supported Incursion glove, helmet and amulet hybrids. The modifier mapping and selection odds are not verified in game; the destination must match the item's base and level.

Unpredictable recombination can choose either base, retains that base's item level, and later actions continue on that base. Small-pool counts use preliminary 3.30 community observations; larger pools and special cases still use older estimates. Modifier selection uses assumed square-root spawn weights, with 1000 for crafted and non-rollable modifiers. Results are not verified game odds. See [coverage and assumptions](crafting-coverage.md) for missing or incomplete methods.

Recombination and Awakener recipes consume a donor on each attempt. **Resource prices** lists the configured donor separately, identified by a short fingerprint of its exact item text. Enter its cost in the same unit as the other prices; until then, total spending is unpriced. A whole-action price override covers both the service or currency and the donor. Changing the donor text creates a new quote key, so review its price after editing it.

Results and comparisons carry model notes for recipes using outdated recombination odds or historical Allflame. Charts provide the same notes through **Model notes**; sampling intervals do not measure these rule uncertainties.

Crafting results record the selected build tree as context. The tree version does not select the crafting rules: **crafting data** identifies the separate dataset used for the model.

Use a blank base or item text PoB can identify. Unresolved explicit modifiers are rejected. If an imported implicit cannot be identified, the workbench explains which calculations are unavailable. Try advanced item text with modifier ranges or another starting item. MCP clients can also supply a known structured implicit state.

**Orb of Remembrance** samples published observations. Memory strands restrict tiers for applicable currencies; **Orb of Unravelling** consumes the remaining strands to attempt upgrades. Foulborn Augmentation, Regal and Exalted orbs add a separate tier bias. Their estimates and uncertain cases are listed under **Rules**. Import counts with a `Memory Strands: 82` line or continue the structured state returned by MCP; native PoB item text alone does not retain this property.

Item-property goals can require a minimum number of actual Abyssal sockets. This checks the socket layout rather than the modifier text. Hollow Fossil socket placement and restoration use the experimental assumptions described in **Rules & sources**.

If an equipment Vaal reroll produces the rare outcome, the model marks its socket layout unknown because that reroll is not simulated. The unknown marker survives working-state saves; socket-dependent actions and build previews stay unavailable until you use **Set socket layout** on the Craft page to enter an observed or hypothetical result. Accepting the edit sets a new recipe starting state. Simulated item text is omitted while sockets are unknown.

**Locus of Corruption** can destroy the hypothetical item. Destruction stops that trial, retains its currency spending and prevents previewing a nonexistent item. **Undo currency** still restores the prior emulated state.

**Predictable recombination (observed odds)** needs the game's displayed success percentage for the exact inputs and selected modifiers. Add one exact target for each selected modifier, with at least one from each input, then configure the donor and percentage. MCP accepts explicit `selectedMods.left` and `selectedMods.right` ID lists. For recipe simulations, include the exact recipient as `observedRecipientState`, including its `origin` from the crafting state; the simulator checks it at execution and reports mismatches. Older recipes need a new observation. The model preserves the chosen base's item level and treats failure as destruction. It fits a shared constant to your observation; its base shares remain estimates. It cannot independently calculate the game's displayed percentage.

**Allflame settings** models the 3.29 league, which did not immediately return to core in 3.30. Use it for historical or hypothetical plans. Choose ship upgrades for the pinned 3.29 client data; **Observed override** accepts recorded settings. After applying currency, select a ghost and inspect its item card before keeping it. Recipes prefer the most matching target groups. Existing imprints are consumed. Kishara offers four retained-modifier choices; Tzamoto attempts to reset Intangibility, with destruction modeled as an assumed 50/50 branch.

**Edit hypothetical item** stages modifier additions, removals, replacements, rolls, fractures and basic properties. Keeping edits sets a new recipe start and clears the recorded currency sequence; Cancel discards them.

For recipes, Allflame prefers the outcome matching the most captured target groups, with ties keeping the first. A manually selected ghost is recorded as a fixed choice index; after collapse it keeps the only outcome. Costs include one currency use and one Sulphur charge, rather than charging for every ghost. These are conditional models with stated assumptions, not verified server probabilities. MCP supplies the same values in `action.allflame` and receives bounded `choices` with each emulated result.

## Set targets

Add a modifier on **Targets**. **Edit target groups** manages required groups (AND) and alternatives within each group (OR). Select a group to edit its counts, rolls and conditions; **Item properties** opens a shorter form for shared final-item conditions and preserves the modifier groups:

- Required or excluded modifiers, matching counts and minimum roll percentages.
- Explicit or implicit modifiers, and how many groups must match.
- Specific fractured or crafted modifiers, open affix slots, affix/fracture counts, quality, sockets, links, corruption, memory strands and Intangibility.

**Weapon and defence goals**, inside **Item properties**, sets minimum physical/elemental/chaos/total weapon DPS, attack rate, critical chance, Armour, Evasion, Energy Shield and Ward. These use PoB's native local item calculations before character bonuses. Blank fields impose no condition; every supplied minimum must pass, and a stat from an incompatible item type cannot match. Decimal thresholds are supported. Recipes stop when the calculated stats meet the goal, which can happen before maximum quality because native damage values round. MCP inspection returns `nativeStats`; supply minimums as `requirements.nativeStats`, for example `{"PhysicalDPS":300,"AttackRate":1.5}`. They persist with recipes, inventory workflows and portable guides.

**Socket colours** accepts one to six exact colours, such as `RRBG`. Order does not matter; repeated letters require that many sockets. Choose **In one linked group** when all requested colours must be linked together. White sockets count as white, rather than substitutes for other colours. These conditions work in action odds, fossil comparisons, saved recipes, repeated-action stop conditions and MCP requests (`socketColours`, `linkedColours`).

Roll percentage means the position within a modifier's native range. For several sampled values, every value must meet the threshold. An unfinished unveil never counts as a completed target.

## Simulate a recipe

Set trials and the action budget. **Simulate action** repeats the action until its conditions match or the budget ends. **Keep actions as recipe** retains the emulator sequence. **Recipe routes** edits attempts and success/failure destinations, including bounded loops. **Add recipe step** adds common currency, base-specific bench crafts and Essences, fossil combinations, and tagged Harvest actions directly, even when a later step needs an item state the current item has not reached yet. Select a fossil step and choose **Edit fossils** to change its combination without losing its routes. Replacing a step with the emulator action also preserves its routing and conditions. The step is checked against the item when it runs. **Simulate saved recipe** uses its captured initial state.

**Flow graph** displays the recipe as currency cards. Drag a success (**S**) or failure (**F**) port onto a step or Finish. Undo/Redo restores route edits; **Edit selected step** opens its detailed conditions. Keep the recipe in its editor to persist changes.

Jobs run in the background. **Cancel crafting job** stops them. Results include success frequency, a 95% Wilson sampling interval, attempted and executed action counts, currency uses, failed transitions and missing prices. Attempts include modeled transitions that failed; only executed transitions use resources in this model. **Results / distribution** shows action counts, spending percentiles, route visits and final modifier frequencies. Up to ten successful items are retained for a separate build preview. Choose **Keep target** to add one to the crafting guide without equipping it; use build **Save** to persist it. Each retained item's cost is shown when all steps in that trial were priced, even if a different trial used an unpriced action. Aggregate spending remains unavailable until all executed actions are priced. Successful-trial percentiles exclude failures; all-trial spending includes them. Trials stopped by the budget are reported separately.

**Simulate → Resource prices** lists the currencies needed by the selected action and saved recipe. Enter prices per unit, add a source and quote date, or copy quotes from another project. Saved quotes also work through MCP. Zero means free; blank means unknown. Changing the common unit clears action overrides and the starting-item cost rather than converting them.

Recipe resources include possible state-dependent costs across branches and loops. This can list a resource that a particular run never spends; the simulation reports actual usage for each run.

Verified bench recipes use their actual ingredients. Unmatched services keep a whole-action price. **Action override** replaces the total for the selected action only; other recipe steps retain their resource quotes. The result says when an override was unused. **Base cost** adds the starting-item cost to every trial. Spending divided by observed successes is a model estimate, not a guaranteed game cost. Zero observed successes does not establish impossibility.

Results list modeled ingredients and service uses separately from spending, with
totals and averages across all trials. A total-price override changes spending,
not the number of currencies, fossils or Sulphur used. Rejected transitions use
no resources; executed crafts still count when their outcome fails or destroys
the item. Starting-item costs remain separate. Open **Results / distribution →
Resources used** to browse currencies with artwork, search by name and inspect
each quantity. A **Service** entry means the model has no verified ingredient
breakdown for that action.

MCP simulation results expose the same list in `resourceUsage`, with `key`,
`name`, `kind`, `amount` and `meanPerTrial`. The older `currencySpent` field
retains its costing buckets for compatibility.

Crafted-mod removal uses one Orb of Scouring. The supported one-mod and three-mod bench reforges use eight and three Chaos Orbs respectively, following the pinned recipe data. Their normal item prerequisites still apply.

**Explore charts** shows cumulative success and completed-trial distributions by attempts, executed actions or supplied spending. Attempts include failed modeled transitions; executed actions exclude them. Older results without executed-action counts must be rerun for those charts. Hover to inspect, click to pin, or copy the data as CSV. The CSV includes the chart mode, unit, model notes, omitted routes and any recorded failed-transition count. **Compare recipes → Compare charts** overlays captured routes. Failed and capped trials stay in the denominator; unpriced routes are omitted from spending charts.

**Run more trials** repeats that result's captured recipe, starting item, targets,
seed and quotes. Only the trial count increases. Later edits to the working item,
action or form do not change this refinement. Start a new simulation to use those
edits. The Simulate tab names the selected action; **Simulate saved recipe** uses
the saved steps and original starting item. Calculation buttons pause while a job
is running. **Close** or **Back to projects** cancels a job started in that workbench.

Calculations and results survive window resizing, text-size changes and navigation
between planning tabs. Background fossil comparisons stay available through
**Fossil results** without opening a popup over another tool. Opening another build
clears these temporary results and cancels work from the previous build.

When configuring a modeled Gwennen pair, the selector warns if one example cannot run on the current item. You can still record or configure the pair for a later step; a successful example does not prove every random outcome will succeed.

**Calculate action odds** enumerates supported finite outcomes, including next-affix draws, Talisman fractures, Allflame selection and supported finite Gwennen outcomes. Other goals and actions may use bounded sampling with a confidence interval. Results state which method was used.

## Compare fossil subsets

To compare fossils, select **Fossil resonator**, open **Settings → Configure fossil combination**, and choose up to four different fossils. Reopening the form retains your selection; a Tangled outcome must be supplied explicitly after it is revealed.

Then open **Simulate → Compare fossil subsets**. The comparison shows fossil artwork, success intervals, cost per trial and cost per observed success. Sort by cost or chance, select a row to inspect it, or copy the comparison as CSV. **Use selected fossils** configures the workbench without crafting the item or spending currency. **Fossil results** reopens the captured comparison; rerun it after changing inputs. This compares the supplied candidates, not every possible crafting method.

## Keep a project

Use **Keep working craft** to checkpoint the working item, undo history, targets, seed and settings, then save the build. Reopening that project resumes the checkpoint. Experiments do not spend your recorded resources; use [Journey](journey.md) to track actual holdings, spending and gear reservations.

**Keep item snapshot** stores a named snapshot in the build's **Item inventory**. Browse item cards, rename/remove snapshots, undo a removal, compare with the working item, or resume a snapshot as a separate working craft. Full simulated states survive, including fractures, imprints and pending unveils. Inventory travels with saved builds and planning bundles and has no item-count cap; the existing metadata size guard still applies. Use normal **Save** to persist changes.

Keeping a recipe marks the build unsaved. Use normal build **Save** to persist it. There is no project-count limit: keep plans for every gear slot and alternatives for each piece. Crafting metadata retains a 2 MiB total size limit and per-field validation. Projects and recipes live in AI Edition XML; other editions may discard them on re-save. AI Edition preserves unreadable or newer metadata unchanged.

On a project's **Item** tab, **Remove project** removes the guide and its saved
inventory. **Undo removal** restores the last removed guide, its order and working
draft during the current session. Linked gear goals remain listed; choose another
guide for those goals. Save the build to persist a removal or restoration.

Working-draft status is tracked per guide. Keeping one guide does not hide another
guide's unfinished work, and opening another build starts with fresh save status.
AI clients can propose `remove_crafting_project` through `propose_build`; native
review identifies the removed guide, inventory count and remaining gear links.

**Preview in build** calculates a separate candidate. Review controls application, and the existing undo flow restores the build. Simulation and planning never spend game currency.

## Compare recipes

The desktop **Simulate → Compare recipes** view compares up to three supported routes with the same captured item, final targets, seed, trial count and action budget. Saved resource quotes apply to every route. Action overrides apply to single-action routes; a saved recipe needs prices for every executed ingredient to report a cost. Results include success intervals, mean attempts and executed actions, spending when known, and failed transitions. **Cancel comparison** stops the job. Invalid action prices keep the comparison form open. Property-only goals work without a modifier-target group. These are bounded model experiments, not guaranteed game costs.

**Rules** opens a browser searchable by mechanic, with assumptions alongside implemented actions. Advanced actions still validate item-specific prerequisites when applied.

## Use AI through MCP

Enable the desktop connection and reconnect the client after updating.

For `simulate_crafting`, a structured starting state belongs in `recipe.initialState`.
`options.priceBook` supplies saved quotes; `options.prices` overrides shared
resource prices. Use `options.actionPrices` for action totals, for example
`{"alchemy":7}`. Inspection and fossil results expose `priceKey`; simulations
list `stepPriceKeys`. Use those keys rather than constructing them yourself.
The result reports how many action overrides were actually used. These
fields also work in fossil optimization, whose initial state is in
`options.initialState`.


| Tool | Purpose |
| --- | --- |
| `get_crafting_projects` | Read saved projects. |
| `inspect_crafting_item` | Read native IDs, initial state and coverage; supply an action to inspect its Allflame profile or a paged Bestiary modifier pool. |
| `apply_crafting_action` | Emulate an action; continue with the original text and returned state. |
| `simulate_crafting` | Run a background recipe with targets, routes and prices. |
| `calculate_crafting` | Enumerate finite outcomes or sample other actions in a cancellable job. |
| `optimize_crafting_fossils` | Compare combinations from up to eight candidates. |
| `cancel_crafting_simulation` | Cancel using the job request ID. |
| `propose_crafting_plan` | Propose a saved project and equipment preview for review. |

`inspect_crafting_item` reports `methodAvailability` for the supplied state, with explanations for unavailable methods. These are general prerequisites; individual options and outcomes can have further restrictions. It also keeps the full queried bench and Essence catalogues and adds `available` and `unavailableReason`. `harvestOptions` gives current reforge, augment and resistance-swap choices. Pass the returned state when inspecting the next step. An unavailable choice may still be useful later in a recipe after an earlier step changes the item.

Poll `get_proposal_status` for results. Requests allow at most 2,000 trials, 2,000 actions per trial and 20,000 budgeted actions overall. Results include seeds, versions and limitations. Simulation options accept `baseCost` and `retainSuccesses` (0-100); retained successes are the first successful trials. MCP never automatically equips an outcome or saves the build.

## External cross-check

Craft of Exile remains an optional independent check. Its [documented import links](https://beta.craftofexile.com/developers?game=poe1) accept advanced game-copy text; it provides no public crafting API. Other handoffs are labeled **base-only**. Verify the imported item and patch. External exports remain opaque data; supplied external results stay separately labeled from native calculations.

The project library separates **Item**, **Plan**, and **Sharing & tools**. The workbench stays in the planning workspace; **Back to projects** preserves the current item and undo history for this session. Currency icons dim when incompatible with the item, and the action hint explains why.

Changing targets, simulation settings or craft options marks a **Working draft**.
Use **Keep working craft**, then build **Save**, to retain those changes after a
restart. Opening a saved craft, browsing its tabs or cancelling an options dialog
does not mark it as edited. **Keep resource prices** saves its quotes directly;
other unfinished work still needs **Keep working craft**.

Base artwork is bundled from the same pinned game-data export as crafting. Missing artwork uses PoB's equipment silhouette. The workbench works offline; `python tools/update_crafting_art.py` refreshes the asset manifest when the crafting data is updated.

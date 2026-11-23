# Loot filter economy review

In PoB AI Edition, open **Loot Filter → Profile tools → Review exchange prices** on a Normal-mode profile that imports your filter. Leave League ID blank to use the current PC trade league or enter the exact poe.ninja league ID. Review the proposed stack changes, then export a separate filter.

For another filter, add standalone comments `# PoB economy: begin` and `# PoB economy: end` around the exact item-name stack hides you want to review. Existing personal filters with the original tiered-test section headings also work.

The review uses the current poe.ninja exchange snapshot. The default target is one chaos per stack. It requires the category's minimum quoted market volume and a 15% margin above the target at the old cutoff before suggesting a reduction. Unsupported rules and thin markets keep their existing cutoffs. General currency rules later in the filter still determine the label and visibility of stacks that pass these hides.

For divination cards, use an exact `Class == "Divination Cards"` and exact `BaseType ==` names in a tagged Hide block. The card feed requires a quoted volume of at least 500 chaos. If a unit clears the price margin, PoB can remove its name from the managed hide. Later rules still determine whether it appears in game.

## Daily sync on Windows

Open **Loot Filter → Profile tools → Daily price sync**. Enter the live .filter file, the fixed baseline .filter file, and the league ID. Select **Enable / update**. PoB keeps a checksum-verified baseline copy. Use **Sync now** to run the first check immediately, or let PoB check at or after 9:00 a.m. local time while the app is open.

The current daily flow supports the protected tiered-test filter profile. It checks all requested feeds for an exchange snapshot served within the past hour, parses the generated filter, and checks protected drops before publishing. It backs up a changed live file, keeps a recovery record, and pauses writes if the target was edited outside PoB. After reviewing an edit, use Enable / update to adopt it. Use Disable to stop the daily refresh. In Path of Exile, reload the filter if the game is already open.

The sync settings accept a local hour and a chaos target per stack. **Sync now** can refresh again on the same day. **Pause** keeps the setup and history. **Restore backup** verifies the previous file and pauses sync while you review it. **Last review** shows cutoff changes, skipped items, and recent runs.

For a different tagged filter, provide a JSON array of one to 500 sample drops in **Protected samples JSON**. Each sample needs at least a BaseType and Rarity. Add every property needed by the filter rules leading to its Show block. For example, a filter with an unconditional Cord Belt rule can use this sample:

```json
[{"BaseType":"Cord Belt","Rarity":"Magic"}]
```

PoB copies the samples into the sync settings when you enable it. For the original tiered-test filter, leave the field empty to use the built-in checks. The original live file and baseline must share the rule prefix ahead of the managed section.

Daily sync uses the lower of the latest liquid quote and the median of available earlier daily quotes from the last week. A new profile starts with the latest quote. Repeated checks on the same day replace that day's sample. The review shows the quote used, the latest quote, and how many observations contributed. A lower current quote takes effect immediately.

Use **Preview changes** before enabling a new setup. It fetches prices and validates the proposed filter, then opens the full text comparison without saving settings or replacing your file.

For up to 250 changed entries, the sync review shows a simulated area-level 83 drop at one item above the proposed hide cutoff. The result uses the first class in the rule and reports the matching line when available. Other classes and area levels can match different rules.

**Browse market prices** opens a read-only market browser for cards, uniques, maps, gems, and crafting bases. It shows the quote and available variant details, including map tier, gem level and quality, links, and listing counts. Daily filter changes support managed commodity stack rules and explicitly tagged card hides.

Daily sync retains still-fresh exchange responses in memory for conditional requests. It honors rate-limit delays and rechecks the age of every response before publication. The displayed age is the age of the response, not the age of underlying trades. Provider IDs distinguish same-name items, and ambiguous names or categories below their volume floor keep the baseline rule.

The desktop AI bridge exposes read-only daily sync status and up to 40 cutoff changes through `get_loot_sync_status`. Local paths, protected sample definitions, and raw transport errors stay in the desktop app.

If a sync target was edited outside PoB, **External edits** compares the live file with the last verified file. Automatic sync stops before contacting the market until the live file matches the known state again or you explicitly re-enable with reviewed edits.

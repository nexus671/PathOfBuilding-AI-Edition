# Loot filter economy review

In PoB AI Edition, open **Loot Filter → Profile tools → Review exchange prices** on a Normal-mode profile that imports your filter. Leave League ID blank to use the current PC trade league or enter the exact poe.ninja league ID. Review the proposed stack changes, then export a separate filter.

Use **Profile tools → Managed price rules** to add exact commodity or divination card hides in a Normal-mode profile. Export the profile to get the managed section automatically. To author the section by hand, add standalone comments `# PoB economy: begin` and `# PoB economy: end` around the exact item-name stack hides you want to review. Existing personal filters with the original tiered-test section headings also work.

The review uses the current poe.ninja exchange snapshot. The default target is one chaos per stack. It requires the category's minimum quoted market volume and a 15% margin above the target at the old cutoff before suggesting a reduction. Unsupported rules and thin markets keep their existing cutoffs. General currency rules later in the filter still determine the label and visibility of stacks that pass these hides.

For divination cards, use an exact `Class == "Divination Cards"` and exact `BaseType ==` names in a tagged Hide block. The card feed requires a quoted volume of at least 500 chaos. If a unit clears the price margin, PoB can remove its name from the managed hide. Later rules still determine whether it appears in game.

## Daily sync on Windows

Open **Loot Filter → Profile tools → Daily price sync**. Choose the live .filter file, fixed baseline, and PoE 1 PC trade league. The Browse buttons open a local file picker. **Use PoE selection** fills in the local filter currently selected in the Path of Exile 1 client. Select **Enable / update**. PoB keeps a checksum-verified baseline copy. Use **Sync now** to run the first check immediately, or let PoB check at or after 9:00 a.m. local time while the app is open.

The current daily flow supports the protected tiered-test filter profile. It checks all requested feeds for an exchange snapshot served within the past hour, parses the generated filter, and checks protected drops before publishing. It backs up a changed live file, keeps a recovery record, and pauses writes if the target was edited outside PoB. After reviewing an edit, use Enable / update to adopt it. Use Disable to stop the daily refresh. In Path of Exile, reload the filter if the game is already open.

The sync settings accept a local time in HH:MM, a repeat interval from one to seven days, and a chaos target per stack. **Sync now** can refresh again on the same day. **Pause** keeps the setup and history. **Restore backup** verifies the previous file and pauses sync while you review it. **Last review** shows cutoff changes, skipped items, and recent runs. The most recent failed refresh remains visible after restarting PoB until a refresh succeeds.

For a different tagged filter, provide a JSON array of one to 500 sample drops in **Protected samples JSON**. Each sample needs at least a BaseType and Rarity. Add every property needed by the filter rules leading to its Show block. For example, a filter with an unconditional Cord Belt rule can use this sample:

```json
[{"BaseType":"Cord Belt","Rarity":"Magic"}]
```

PoB copies the samples into the sync settings when you enable it. For the original tiered-test filter, leave the field empty to use the built-in checks. The live file and baseline must match on both sides of the managed section. After a personal edit outside that section, review the change and use an updated baseline.

Daily sync uses the lower of the latest liquid quote and the median of available earlier daily quotes from the last week. A new profile starts with the latest quote. Repeated checks on the same day replace that day's sample. The review shows the quote used, the latest quote, and how many observations contributed. A lower current quote takes effect immediately.

Use **Preview changes** before enabling a new setup. It fetches prices and validates the proposed filter, then opens the full text comparison without saving settings or replacing your file.

The sync review tests up to 500 combinations of affected classes and representative areas at the first stack size whose cutoff changed. It shows both the baseline and candidate outcome and the matching line, including stacks that another rule still hides.

**Browse market prices** opens a read-only market browser for cards, uniques, maps, gems, and crafting bases. It shows the quote and available variant details, including map tier, gem level and quality, links, and listing counts. Daily filter changes support managed commodity stack rules and explicitly tagged card hides.

Daily sync retains still-fresh exchange responses in memory for conditional requests. It honors rate-limit delays and rechecks the age of every response before publication. The displayed age is the age of the response, not the age of underlying trades. Provider IDs distinguish same-name items, and ambiguous names or categories below their volume floor keep the baseline rule.

The desktop AI bridge exposes read-only daily sync status and up to 40 cutoff changes through `get_loot_sync_status`. Local paths, protected sample definitions, and raw transport errors stay in the desktop app.

If a sync target was edited outside PoB, **External edits** compares the live file with the last verified file. Automatic sync stops before contacting the market until the live file matches the known state again or you explicitly re-enable with reviewed edits.

**Copy diagnostics** exports a JSON report with recent run times, verified response ages, and available quote and simulated drop details. The report excludes local file paths and protected sample definitions.

## Optional background sync on Windows

Select **Enable background sync** in **Daily price sync** to register a task for your Windows account. While you are signed in, Windows checks every five minutes for a due update, including when PoB is closed. PoB still uses your configured daily time, verified baseline, and protected samples. The task stays idle when sync is paused or disabled, and **Disable background sync** removes it.

**Enable notifications** adds a Windows notification for a new failure or when an update changes at least five managed cutoffs. Clicking it opens PoB. Windows notification settings determine when the alert appears.

For a one-time scheduled check from the Windows command line, launch your PoB executable with `--loot-filter-sync`. It uses the saved local settings and exits after the check. It returns exit code 1 on failure. It respects the daily time, pause state, and provider cooldown.

## Pickup policy

Open **Pickup policy** in daily sync and choose optional campaign and map chaos targets. These apply to exact managed Hide rules that say `AreaLevel < 68` or `AreaLevel >= 68`. Rules without an area condition still use the default target. Only tagged sections support the campaign condition.

You can also set an absolute maximum hide cutoff for an exact commodity name. For example, `{"Orb of Alteration": 7}` permits a managed rule to hide stacks of at most seven when prices justify it. A new profile needs the latest liquid quote plus three earlier liquid daily quotes before it can tighten. The highest of the recent quotes must still put the newly hidden stacks below 85% of the pickup target. Divination cards retain their visibility-only policy.

Select **Use with next update**, then **Preview changes** to check the resulting filter or **Enable / update** to save the policy. An existing matching baseline and league can reuse saved daily quotes in preview.

## Named sync profiles

Open **Profiles** in **Daily price sync** to create or switch profiles. Each profile has its own fixed baseline, protected samples, PoE 1 PC trade league, schedule, and price history. The original setup appears as **Default**. A destination belongs to one profile, including when a different Windows path spelling resolves to the same file.

PoB checks due profiles in order. Enable background sync individually on profiles that should also run while PoB is closed. They share one Windows task, which is removed when the last profile turns off background sync.

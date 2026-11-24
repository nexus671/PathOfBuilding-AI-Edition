# Loot filter economy review

In PoB AI Edition, open **Loot Filter → Profile tools → Review exchange prices** on a Normal-mode profile that imports your filter. Leave League ID blank to use the current PC trade league or enter the exact poe.ninja league ID. Review the proposed stack changes, then export a separate filter.

Use **Profile tools → Managed price rules** to add exact commodity, divination card, map-tier, or gem hides in a Normal-mode profile. Export the profile to get the managed section automatically. To author the section by hand, add standalone comments `# PoB economy: begin` and `# PoB economy: end` around the exact item-name stack hides you want to review. Existing personal filters with the original tiered-test section headings also work.

The review uses the current poe.ninja exchange snapshot. The default target is one chaos per stack. It requires the category's minimum quoted market volume and a 15% margin above the target at the old cutoff before suggesting a reduction. Unsupported rules and thin markets keep their existing cutoffs. General currency rules later in the filter still determine the label and visibility of stacks that pass these hides.

For divination cards, use an exact `Class == "Divination Cards"` and exact `BaseType ==` names in a tagged Hide block. The card feed requires a quoted volume of at least 500 chaos. If a unit clears the price margin, PoB can remove its name from the managed hide. Later rules still determine whether it appears in game.

In **Browse loot market prices**, unique results show other quoted variants that share the same base, even when your search returns one name. A supported estimate needs at least 20 observations and 20 listings. Thin quotes, conflicting price IDs, and rows without a stable price ID do not contribute to that range. PoB also flags names in its loaded item catalogue with no supported quote for the base. The market range covers supported variants in the response. The catalogue can include items that do not drop in the selected league.

In Pickup policy, set optional chaos thresholds for the normal and strong highlights on managed commodity stacks and divination cards. Choose a minimap icon and beam preset for each threshold. The defaults are a yellow circle and an orange star. PoB uses the specified value for the stack and skips ambiguous or thin quotes. PoB adds these appearances only to matching explicit Show rules, keeping the original rule order and visibility. Use Last review to see the marker on a sampled stack. The feature skips any unresolved imports.

Enable GGG trade confirmation in Pickup policy to require a liquid direct-chaos trade before increasing a managed hide cutoff. PoB uses the higher of the recent live-price samples and the completed-hour GGG trade average. If the historical trade feed or exact match is unavailable, the original cutoff remains. This option leaves price-based visibility increases available.

## Daily sync on Windows

Open **Loot Filter → Profile tools → Daily price sync**. Choose the live .filter file, fixed baseline, and PoE 1 PC trade league. Use **Choose league** to verify the provider's current PC league list. Existing profiles keep the league you saved. The Browse buttons open a local file picker. **Use PoE selection** fills in the local filter currently selected in the Path of Exile 1 client. Select **Enable / update**. PoB keeps a checksum-verified baseline copy. Use **Sync now** to run the first check immediately, or let PoB check at or after 9:00 a.m. local time while the app is open.

The current daily flow supports the protected tiered-test filter profile. It checks all requested feeds for an exchange snapshot served within the past hour, parses the generated filter, and checks protected drops before publishing. It backs up a changed live file, keeps a recovery record, and pauses writes if the target was edited outside PoB. After reviewing an edit, use Enable / update to adopt it. Use Disable to stop the daily refresh. In Path of Exile, reload the filter if the game is already open.

For the tiered-test baseline, a custom protection file adds examples to the built-in Cord Belt, six-link, fractured magic, rank A/B Fated, and hidden scroll checks.

Protected examples use bundled base dimensions and ordinary base drop levels. A unique's drop level and defence percentile are left unknown when its base does not establish them; if either could decide a protected result, the daily check stops and explains why. Base-update reviews warn when the previous result is unknown. These are representative examples, not a guarantee for every possible drop.

Price-change examples use known base properties and the chosen area level. They leave the item's level unknown, so a dependent rule produces an uncertain preview rather than assuming an item level from the area. **Last review** identifies missing properties for the before and after examples separately; other unresolved conditions are labelled without guessing.

The sync settings accept a local time in HH:MM, a repeat interval from one to seven days, and a chaos target per stack. **Sync now** can refresh again on the same day. **Pause** keeps the setup and history. **Review backups** lists up to 30 recorded versions. Open the exact file diff before confirming a restore. PoB validates the backup and the current state, keeps the replaced file as an undo point, and pauses daily sync. **Backup retention** defaults to keeping all files. An optional limit removes older recorded backups after a successful refresh only when their bytes still match the recorded checksum. The live filter and fixed baseline stay in place. **Last review** shows cutoff changes, skipped items, and recent runs. The most recent failed refresh remains visible after restarting PoB until a refresh succeeds.

To review pickup settings when the price service is unavailable, open **Offline prices** and select a maximum age of one, three, or seven days before the next successful refresh. Use **Preview last prices** to compare pending settings against that profile's most recent verified snapshot. PoB checks the snapshot and reports the age of the oldest quote. Scheduled sync still requires fresh prices.

For a different tagged filter, provide a JSON array of one to 500 sample drops in **Protected samples JSON**. Each sample needs at least a BaseType and Rarity. Add every property needed by the filter rules leading to its Show block. For example, a filter with an unconditional Cord Belt rule can use this sample:

```json
[{"BaseType":"Cord Belt","Rarity":"Magic"}]
```

PoB copies the samples into the sync settings when you enable it. For the original tiered-test filter, leave the field empty to use the built-in checks. The live file and baseline must match on both sides of the managed section. After a personal edit outside that section, review the change and use an updated baseline.

Daily sync uses the lower of the latest liquid quote and the median of available earlier daily quotes from the last week. A new profile starts with the latest quote. Repeated checks on the same day replace that day's sample. The review shows the quote used, the latest quote, and how many observations contributed. A lower current quote takes effect immediately. Once the two previous daily snapshots each have at least 20 liquid quotes for an exchange category, a refresh that finds fewer than a quarter of the lower count keeps the verified filter.

Use **Preview changes** before enabling a new setup. It fetches prices and validates the proposed filter, then opens the full text comparison without saving settings or replacing your file.

The sync review tests up to 500 combinations of affected classes and representative areas at the first stack size whose cutoff changed and at proposed highlight thresholds. It shows both the baseline and candidate outcome and the matching line, including stacks that another rule still hides.

**Browse market prices** opens a read-only market browser for all 19 documented PoE 1 exchange categories, plus uniques, maps, gems, and crafting bases. Exchange results show estimated chaos values, price IDs, and liquidity notes. Stash results show available variant details, including map tier, gem level and quality, links, and listing counts. Daily filter changes support managed commodity stacks, cards, tier-wide maps, and exact regular gem variants. [Market API reference](https://poe.ninja/docs/api)

Daily sync retains still-fresh exchange responses in memory for conditional requests. The scheduler, exchange review, market browser, and league picker share provider cooldowns across PoB windows and the Windows background worker. The shared deadline belongs to the configured price endpoint. Diagnostics show the source mode and any active wait. Daily sync rechecks the age of every response before publication. The displayed age is the age of the response, not the age of underlying trades. Provider IDs distinguish same-name items, and ambiguous names or categories below their volume floor keep the baseline rule.

The desktop AI bridge exposes read-only daily sync status and up to 40 cutoff changes through `get_loot_sync_status`. The read-only `get_loot_sync_diff` tool pages through the Default profile's last verified cutoff decisions, quote evidence, and bounded samples for the checked classes and areas. Its existing `sample` remains the first example; `samples` contains up to 20 and `samplesTruncated` indicates if more were retained. Sampling is bounded across the whole review, so absent examples are not evidence of an unchanged outcome. An uncertain sample includes known missing property names as `beforeMissing` or `afterMissing`; an absent list does not prove there was no other uncertainty. Last review and Copy diagnostics list the age of each price feed at the time of the successful sync and whether the provider confirmed an unchanged response. For changed items with an exact currency ID, Compare GGG trades shows a historical direct-chaos average from the official completed hour. For other profiles, use Copy diagnostics in that profile's daily sync dialog. Local paths, protected sample definitions, and raw transport errors stay in the desktop app.

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

## Managed maps

In **Managed price rules**, choose **Maps**, a tier from 1 to 16, and Ordinary, Blighted, or Blight-ravaged. PoB uses separate stash price feeds for those variants. The rule excludes unique, corrupted, implicit-modified, enchanted, Mirage, memory, Shaped, and Elder maps. It can be relaxed when that exact tier-wide quote clears the price margin. The maps pickup target applies when configured.

The provider often groups maps by tier. Exact named maps, Atlas boss variants, and unique maps keep their existing rules. A quote needs at least 20 sampled listings and 20 listings in the overview. Missing or conflicting tier quotes keep the baseline hide. Automatic map repricing can loosen these managed hides.

## Managed gem variants

In **Managed price rules**, select **Skill Gems** or **Support Gems**. Enter the exact name, gem level, quality and corruption state, then choose the area. The generated rule applies to regular gems and excludes transfigured and imbued gems. A matching listing-backed quote can remove the baseline hide. Later filter rules still decide how the gem appears.

A quote needs a stable price ID, at least 20 observations and at least 20 listings. Invalid or conflicting identities, a missing exact variant, and thin listings keep the baseline hide. Daily profiles with managed gem rules additionally require a fresh `SkillGem` overview. If the feed is unavailable, the profile keeps its last verified output. Other profiles continue using their existing feeds. Enable gem rules when your market source can serve the stash category reliably. [Item filter reference](https://www.pathofexile.com/item-filter/about) · [Market API reference](https://poe.ninja/docs/api)

## Named sync profiles

Open **Profiles** in **Daily price sync** to create or switch profiles. Each profile has its own fixed baseline, protected samples, PoE 1 PC trade league, schedule, and price history. The original setup appears as **Default**. A destination belongs to one profile, including when a different Windows path spelling resolves to the same file.

PoB checks due profiles in order. Enable background sync individually on profiles that should also run while PoB is closed. They share one Windows task, which is removed when the last profile turns off background sync.

## NeverSink base updates

When a kept bundled profile references an older NeverSink revision, open **Profile tools → Audit and update → Update bundled NeverSink base**. PoB retrieves the exact saved revision and compiles it and the bundled revision with the same personal rules. The review shows removed conditions, matching visibility checks for protected drops, and changes to saved examples. **View full diff** compares both compiled filters.

**Apply to draft** is available after the protected checks pass. The new bundled revision and preserved personal rules remain in the draft until you keep it. The daily sync file and its fixed baseline can be replaced separately after reviewing the new export.

## Publish a verified filter to a PoE account

In **Daily price sync**, open **Publish to account** after a successful refresh. Use the existing PoE login and item-filter permission, select an existing filter in the matching realm, and review the full diff. **Publish exact output** rechecks the local checksum and the remote filter before sending the approved text. The server validates the update.

Local and background sync do not publish account filters. An uncertain server result is shown for review before retrying.


Use **Check Windows task** in daily sync to compare the profile's background preference with Task Scheduler. The check reports missing or disabled registrations, mismatched worker actions, account or trigger changes, and a missing PoB executable. The expected task checks for due profiles every five minutes while the user is signed in. If the profile already opts in, use **Repair task** to register the expected Windows task for recoverable problems.

## Shared cache for app distribution

PoB can use an operator-managed HTTPS cache for all poe.ninja economy requests. Set `POB_MARKET_CACHE_URL` to the full public HTTPS prefix, such as `https://prices.example.test/pob-market/`, before starting PoB. The Windows task records that source when you enable or repair it, so the scheduled worker uses the same endpoint even if Task Scheduler inherits different settings. The direct source is the default when the setting is empty.

Daily sync records the source when you enable or update a profile. If the runtime's source differs, sync leaves the active filter in place. To change sources, restart with the desired setting, preview the prices, save the profile, and repair the Windows task if you use background sync. Use **Check Windows task** after upgrading an older task to see whether it needs repair.

Configure the final HTTPS URL. PoB rejects redirects for economy feeds and preserves the active filter if a scheduled refresh receives one.

The operator runs `node tools/serve_loot_market_cache.cjs` with `POB_MARKET_UPSTREAM_AGENT` set to the application's descriptive User-Agent and contact. It binds to loopback on port 9410 by default. Publish that service through the deployment's HTTPS reverse proxy by stripping the configured path prefix. Restrict the proxy to the intended audience and use `/health` from monitoring to inspect pending work, cache hits, coalesced requests and failures.

The service accepts only the app's public economy routes and active leagues. It coalesces requests, bounds the upstream queue, respects provider caching, and preserves origin age and retry timing. Throttled, stale, oversized and malformed data go through the app's existing checks before any filter is published. The operator needs to qualify the deployed host with the provider and verify fresh responses from that host before enabling distribution. [poe.ninja API guidelines](https://poe.ninja/docs/api)

Run the cache probe after configuring HTTPS and before pointing scheduled clients at the service.

```sh
node tools/check_loot_market_cache.cjs https://prices.example.test/pob-market/ Covens SkillGem,BaseType,Scarab
```

The league defaults to the current PC trade league. Omit the third argument to check only the eight core feeds. Add supported exchange or stash category names to qualify their availability. The read-only command reports cache health, source age, quote evidence and HTTP failures. A successful probe qualifies the requested transport and feed shape. Then use PoB's **Preview changes** against the intended baseline to check exact matches and protected drops before enabling sync.

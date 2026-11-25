# Loot filter economy review

<!-- cspell:ignore lupa -->

In PoB AI Edition, open **Loot Filter → Profile tools → Review exchange prices** on a Normal-mode profile that imports your filter. Leave League ID blank to use the current PC trade league or enter the exact poe.ninja league ID. Review the proposed stack changes, then export a separate filter.

Use **Profile tools → Managed price rules** to add exact commodity, divination card, map-tier, or gem hides in a Normal-mode profile. Export the profile to get the managed section automatically. To author the section by hand, add standalone comments `# PoB economy: begin` and `# PoB economy: end` around the exact item-name stack hides you want to review. Existing personal filters with the original tiered-test section headings also work.

The review uses the current poe.ninja exchange snapshot. The default target is one chaos per stack. It requires the category's minimum quoted market volume and a 15% margin above the target at the old cutoff before suggesting a reduction. Unsupported rules and thin markets keep their existing cutoffs. General currency rules later in the filter still determine the label and visibility of stacks that pass these hides.

For divination cards, use an exact `Class == "Divination Cards"` and exact `BaseType ==` names in a tagged Hide block. The card feed requires a quoted volume of at least 500 chaos. If a unit clears the price margin, PoB can remove its name from the managed hide. Later rules still determine whether it appears in game.

In **Browse loot market prices**, unique results show other quoted variants that share the same base, even when your search returns one name. A supported estimate needs at least 20 observations and 20 listings. Thin quotes, conflicting price IDs, and rows without a stable price ID do not contribute to that range. PoB also flags names in its loaded item catalogue with no supported quote for the base. The market range covers supported variants in the response. The catalogue can include items that do not drop in the selected league.

In Pickup policy, set optional chaos thresholds for the normal and strong highlights on managed commodity stacks and divination cards. Choose a minimap icon and beam preset for each threshold. The defaults are a yellow circle and an orange star. PoB uses the specified value for the stack and skips ambiguous or thin quotes. PoB adds these appearances only to matching explicit Show rules, keeping the original rule order and visibility. Use Last review to see the marker on a sampled stack. The feature skips any unresolved imports.

Enable GGG trade confirmation in Pickup policy to require a liquid direct-chaos trade before increasing a managed hide cutoff. PoB uses the higher of the recent live-price samples and the completed-hour GGG trade average. If the historical trade feed or exact match is unavailable, the original cutoff remains. This option leaves price-based visibility increases available.

In **Browse loot market prices**, choose **GGG trades** to review a recent completed exchange hour for PC, Xbox, or PlayStation. Enter a league ID or leave it blank to browse leagues with eligible trades in that realm. Results identify the realm and league and show the average chaos per item, units traded, total chaos, and UTC hour. Quotes require an exact item ID and at least five items and 100 chaos traded directly. Supported IDs include Atlas Threads and empty Chaotic Resonators. The history is read-only. Automatic filters still use their configured PC price feeds. [GGG Currency Exchange API](https://www.pathofexile.com/developer/docs/reference#currency-exchange)

## Daily sync on Windows

Price history matches the feed, provider price ID and exact item identity. Existing snapshots recorded by older builds still establish the usual feed coverage. Only snapshots with an exact identity contribute historical prices to the weekly median or to the three earlier observations required to tighten a cutoff above the fixed baseline.

Open **Loot Filter → Profile tools → Daily price sync**. Choose the live .filter file, fixed baseline, and PoE 1 PC trade league. Use **Choose league** to verify the provider's current PC league list. Existing profiles keep the league you saved. The Browse buttons open a local file picker. **Use PoE selection** fills in the local filter currently selected in the Path of Exile 1 client. Select **Enable / update**. PoB keeps a checksum-verified baseline copy. Use **Sync now** to run the first check immediately, or let PoB check at or after 9:00 a.m. local time while the app is open.

When the provider confirms that a configured league is no longer listed, **Last attempt** shows the verified current challenge league. **Choose league** lists the active PC trade leagues and marks the current challenge league. To switch an existing profile, select a league, open **Review league**, and select **Save reviewed league** after checking the diff. PoB verifies a fresh league list and the price feeds for the proposed league. A later fresh refresh from the fixed baseline writes the live filter. Paused profiles stay paused.

The current daily flow supports the protected tiered-test filter profile. It checks all requested feeds for an exchange snapshot served within the past hour, parses the generated filter, and checks protected drops before publishing. It backs up a changed live file and pauses writes if the target was edited outside PoB. If PoB stops after installing a fully validated filter, the next sync check verifies the saved candidate and backup and completes its review locally, including during a provider cooldown. Offline price previews resume after the next successful price download. After reviewing an edit, use Enable / update to adopt it. Use Disable to stop the daily refresh. In Path of Exile, reload the filter if the game is already open.

A missing, ambiguous, or thin individual quote can keep that rule's previously verified lower cutoff while other rules update. Last review shows why the lower cutoff was kept. PoB uses fresh eligible quotes for new cutoff and highlight decisions. An update to the schedule keeps this history when the filter, baseline, market source, league, and pickup settings still match. New profiles and changed pickup settings start from their fixed baseline. A profile must first record a verified lower cutoff to retain it later.

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

Daily sync uses the lower of the latest liquid quote and the median of available earlier daily quotes from the last week. A new profile starts with the latest quote. Repeated checks on the same day replace that day's sample. The review shows the quote used, the latest quote, and how many observations contributed. A lower current quote takes effect immediately. Coverage checks use the lower median of the available earlier daily counts from the last week, with at least two earlier snapshots. A refresh keeps the verified filter if an exchange or divination card category with a reference of at least 20 liquid quotes falls below one quarter of that reference. Map categories with a reference of at least four liquid quotes must keep at least half. **Last attempt**, copied diagnostics, and read-only AI status report the feed, available count, and recent median when the coverage check fails.

Use **Preview changes** before enabling a new setup. It fetches prices and validates the proposed filter, then opens the full text comparison without saving settings or replacing your file.

The sync review tests up to 500 combinations of affected classes and areas at the first stack size whose cutoff changed and at proposed highlight thresholds. For scoped drops it includes the relevant side of the area-level 67/68 boundary. It checks Normal, Magic, and Rare maps separately. Each sample shows the baseline and updated outcomes with their matching rule lines when available, including drops that stay hidden. Decisions that reach the review limit identify their incomplete coverage in the desktop review and through `samplesLimited` in the AI bridge. PoB preserves unsupported Hide rules in an explicitly managed section. The desktop review shows the reason and baseline line for the first 250 after stripping generated price highlights, and counts any additional rules it preserved.

**Browse market prices** opens a read-only market browser for all 19 documented PoE 1 exchange categories and all 29 documented stash item categories. Exchange results show estimated chaos values, price IDs, and liquidity notes. Stash results show the available variant details and listing counts. The added stash categories require a scoped search and flag thin evidence or conflicting variant IDs. Required character level describes the level needed to equip an item. Item-level valuation needs a separate data source. Daily filter changes support managed commodity stacks, cards, tier-wide maps, and exact regular gem variants. [Market API reference](https://poe.ninja/docs/api)

Daily sync retains still-fresh exchange responses in memory for conditional requests. The scheduler, exchange review, market browser, and league picker share provider cooldowns across PoB windows and the Windows background worker. The shared deadline belongs to the configured price endpoint. Diagnostics show the source mode and any active wait. Daily sync rechecks the age of every response before publication. The displayed age is the age of the response, not the age of underlying trades. Provider IDs distinguish same-name items. Matching duplicate exchange and map rows use the lower volume. Invalid or conflicting quote evidence and categories below their volume floor keep the baseline rule.

The desktop AI bridge exposes read-only daily sync status and up to 40 cutoff changes through `get_loot_sync_status`. The read-only `get_loot_sync_diff` tool pages through the Default profile's last verified cutoff decisions, quote evidence, and bounded samples for the checked classes and areas. Its existing `sample` remains the first example; `samples` contains up to 20 and `samplesTruncated` indicates if more were retained. Sampling is bounded across the whole review, so absent examples are not evidence of an unchanged outcome. An uncertain sample includes known missing property names as `beforeMissing` or `afterMissing`; an absent list does not prove there was no other uncertainty. Last review and Copy diagnostics list the age of each price feed at the time of the successful sync and whether the provider confirmed an unchanged response. For changed items with an exact currency ID, Compare GGG trades shows a historical direct-chaos average from the official completed hour. For other profiles, use Copy diagnostics in that profile's daily sync dialog. Local paths, protected sample definitions, and raw transport errors stay in the desktop app.

## Windows trade overlay preview

Open **Browse market prices → Trade overlay**. You can also run the bundled PoB executable with `--trade-overlay` without opening a build. Select the full path to the actual Path of Exile 1 executable, choose a shortcut and PC trade league, and select **Arm overlay**. PoB registers the shortcut while the selected client is in focus. Hover an item and press the shortcut to send the game's copy action once. PoB reads new clipboard text from that process for the market review.

The overlay requests an overview for supported gems, currencies, and uniques. Select a **Saved listing capture** and its exact PC trade league to open comparable asking prices for supported rolled gear automatically. PoB reads the file again for each check, requiring a timestamped PoB capture for that league. The result shows the declared capture age and flags captures over one hour old. Use **Review roll filters** to edit criteria and **Compare saved capture** to rerun the comparison. Live rolled listings inside the overlay still need an approved source.

Press Escape or leave the review window to dismiss it. Restore the overlay from the Windows taskbar to disarm it or exit. Arming remembers the executable, shortcut, league, and optional capture path. Each new session opens setup for you to arm. Use windowed or borderless-windowed PoE. Real client and multi-monitor qualification are tracked separately. [GGG developer guidelines](https://www.pathofexile.com/developer/docs) · [Overlay qualification](https://github.com/nexus671/PathOfBuilding-AI-Edition/issues/22)

If a sync target was edited outside PoB, **External edits** compares the live file with the last verified file. Automatic sync stops before contacting the market until the live file matches the known state again or you explicitly re-enable with reviewed edits.

**Copy diagnostics** exports a JSON report with recent run times, verified response ages, and available quote and simulated drop details. The report excludes local file paths and protected sample definitions.

**Last attempt** shows the feed, failure reason, and HTTP status when a price request stops a refresh. It also shows the time of the last verified refresh. The diagnostic report and read-only AI status include the same bounded feed evidence.

**Last review**, **Copy diagnostics**, and the read-only AI diff include the provider price ID for changed rules when the feed supplies an ID. The AI diff includes the protected check count and the freshness of every requested feed. For an unchanged managed rule, Last review shows the selected feed when a quote is missing or ambiguous.

## Optional background sync on Windows

Select **Enable background sync** in **Daily price sync** to register a task for your Windows account. While you are signed in, Windows checks every five minutes for a due update, including when PoB is closed. PoB still uses your configured daily time, verified baseline, and protected samples. The task stays idle when sync is paused or disabled, and **Disable background sync** removes it.

**Enable notifications** adds a Windows notification for a new failure or when an update changes at least five managed cutoffs. PoB counts separate area rules, map tiers and variants, and gem variants. Appearance-only and quote-evidence changes leave this count unchanged. Clicking the notification opens PoB. Windows notification settings determine when the alert appears.

For a one-time scheduled check from the Windows command line, launch your PoB executable with `--loot-filter-sync`. It uses the saved local settings and exits after the check. It returns exit code 1 on failure, even if Windows cannot save the failure to the sync history. The worker continues checking other due profiles and respects the daily time, pause state, and provider cooldown. For a task registered by an older version, use **Check Windows task** and **Repair task** if the action needs updating.

## Pickup policy

Open **Pickup policy** in daily sync and choose optional campaign and map chaos targets. These apply to exact managed Hide rules that say `AreaLevel < 68` or `AreaLevel >= 68`. Rules without an area condition still use the default target. Only tagged sections support the campaign condition.

Under **Per-item stack caps**, use **Add** to enter an exact managed commodity name and the largest stack PoB may hide. For example, a cap of 7 for Orb of Alteration permits a managed rule to hide stacks of up to seven when prices justify it. Use **Edit** or **Remove** on the selected cap to change it. A new profile needs the latest liquid quote plus three earlier liquid daily quotes before it can tighten. The highest of the recent quotes must still put the newly hidden stacks below 85% of the pickup target. Divination cards retain their visibility-only policy.

Select **Use with next update**, then **Preview changes** to check the resulting filter or **Enable / update** to save the policy. An existing matching baseline and league can reuse saved daily quotes in preview.

In **Last review**, select **Pickup policy** to find caps that cannot tighten the fixed baseline. The review identifies exact names without an eligible rule and caps at or below every matching baseline cutoff.

After a verified sync, use **Test observed stack** to enter a stackable item's exact name, stack size, and area level. If a rule needs the item level, enter it when known. PoB compares the fixed baseline with the verified filter, previews their loot labels side by side, and shows matched lines and configured appearance, including colors, markers, beams and sounds. The illustration is an approximation of the game. The comparison uses the entered observation and leaves both files untouched.

In **Preview changes**, **Offline price preview**, or **Review league change**, **Test observed stack** compares the current and proposed text shown in that preview. You can check the proposed visibility before saving the policy or league.

In **Test observed stack**, choose **Paste stack** after copying a supported stack with its stack size in Path of Exile. Enter the area level, then choose **Record stack** for each observation. You can also enter values by hand. **Save stacks** writes up to 250 observations to a new JSON file in the PoB user folder. A successful save starts a new batch. **Compare file** opens the saved file or another JSON array with one entry per observed stack. Repeated entries count as separate observations. Add `ItemLevel` if known and `Class` if the name alone does not identify the stackable class.

Batch results group the sample counts by item class and area level. Select a recorded stack and choose **Preview labels** for the side-by-side illustration. Results with unresolved includes or other preview assumptions are counted as unresolved, with the warning shown in the item details. When multiple rules match through `Continue`, their line numbers appear in match order.

```json
[
  {"BaseType":"Orb of Transmutation","StackSize":24,"AreaLevel":83},
  {"BaseType":"Orb of Alteration","StackSize":5,"AreaLevel":67}
]
```

The report counts stacks that become visible, become hidden, stay at the same visibility, or remain unresolved. Select an outcome to see which items contributed and the matching lines in each filter.

## Managed exchange feeds

In **Managed price rules**, enter an exact commodity name, its filter class, scope, and baseline stack cutoff. Choose **Exchange feed** for a category such as Scarabs, Fossils, or Tattoos. PoB matches the name within that feed and uses its own price history. **Default exchange feeds** keeps the usual lookup for existing rules.

Choose **From build** to select eligible identified rare equipment or an anointed Putrid Seed. To check an item directly, copy it in Path of Exile and choose **Paste item**. Enter the trade league ID, then choose **Compare listing file** with a local JSON page in the [GGG Public Stashes format](https://www.pathofexile.com/developer/docs/reference#public-stashes). Use a PC export for the selected league. The raw page does not identify its realm. PoB compares the base, item level, item state, and rolled modifier channels. It supports socketless jewellery, ordinary and Abyss jewels, rare Cluster Jewels with standard passive layouts, and ordinary weapons and armour. Cluster comparisons require the printed passive count, jewel socket count, small-passive bonus, and all rolled modifiers, including notables. Weapon and armour comparisons require the same ordered socket colours and links, quality, and supported displayed combat properties. Armour needs recorded defence values in the build item. The comparison excludes unsupported properties and special sockets, including catalysts, Intangibility, Memory Strands, Abyssal sockets, Crucible trees, and vestigial items. It counts matching listings and reports separate chaos and divine asking prices, taking the lowest ask from each distinct seller. A median needs at least three sellers. The file does not establish listing freshness or completed sales. This review is read-only.

An anointed Putrid Seed comparison requires its granted passives in the same sequence in the listing's `enchantMods` array. The result shows that sequence. It requires the exact unique name, base, item level, item state, and supported modifier channels. This comparison has been verified with fixtures based on the documented item fields. Live stash qualification is pending.

Rare quivers can be compared from copied text or the equipped off-hand slot. PoB requires exact modifier rolls and socket colors and links. It skips items with socketed contents, quality, or unsupported displayed properties. When a discontinued quiver shares a public base name, PoB requires the current natural implicit and skips ambiguous or altered cases. Two-Point and Penetrating Arrow Quivers share their natural implicit with discontinued bases and are excluded.

For a copied or equipped rare supported by listing comparison, **Review Trade search** opens an editable set of Trade filters. Enter your PC trade league first. Include or exclude individual modifiers, and adjust either bound where the Trade stat has a single numeric value. The review lists unavailable and ambiguous modifiers. **Open official Trade** sends the reviewed filters, base, item level, corruption, and applicable socket and link counts to the official site. Inspect the returned items for other differences before comparing prices.

Choose **Compare listing file** inside **Review Trade search** to apply the selected modifier filters to a local public stash page or capture. A selected modifier must be present in the same modifier channel. A single numeric roll must also meet any supplied bounds. The local comparison still checks item level, influence, corruption, equipment properties, and identifying implicits or Cluster Jewel layout. Select at least one modifier. Open **Compare listing file** from the main market browser to compare a complete exact roll instead. Both actions show distinct seller counts and require three sellers for a median in each currency.

AI clients can request the same offline review with `compare_gear_listings`, providing the build revision, exactly one item source (an equipped gear slot, an allocated passive jewel socket ID as `jewelSocketId`, or copied item text), an absolute path to a local JSON snapshot, and league ID. Omit `modifierFilters` for exact rolls. For a filtered comparison, pass a list with each selected modifier's `kind`, exact displayed `line` without its channel tag, and optional numeric `min` or `max`. Poll `get_proposal_status` for aggregate results. The tool returns asking prices from the supplied file and leaves the build as it was.

To compare several pages recorded from the same PC stream, bundle up to 32 consecutive responses in a capture file. Keep the cursor actually used to request each page and the UTC capture time. The local bundler takes those values from the recorder and does not contact GGG. Select its output with **Compare listing file**.

```powershell
python tools/build_public_stash_capture.py --league Covens --captured-at 1795545600 --page cursor-a first.json --page cursor-b second.json covens-capture.json
```

Replace the example cursors, time, league and paths with the recorded values. The first page must return `cursor-b` in this example. PoB rejects gaps, cycles, a different league, and a non-PC capture. A later public change replaces the earlier tab. A withdrawal removes the tab. The reader accepts a 16 MiB capture or a 4 MiB single page. Capture metadata is declared by the recorder. A capture covers only the recorded stream window and cannot confirm full market coverage, live availability, or sales.

<!-- cspell:ignore psapi -->
An authorized backend can use `tools/collect_public_stash_capture.py` to produce the same file directly. Start with a cursor from the approved PC stream. Configure `POB_GGG_PUBLIC_STASH_TOKEN` through the backend secret store with that backend's `service:psapi` access, and supply the registered application ID and public contact email. The desktop market browser opens the resulting file without taking the credential. [GGG authorization and service scopes](https://www.pathofexile.com/developer/docs/authorization#scopes)

```powershell
python tools/collect_public_stash_capture.py --league Covens --client-id your-app --contact ops@example.com --cursor known-cursor covens-capture.json
```

Use `--resume-from covens-capture.json` in place of `--cursor` for the next run, and choose a new output name. A successful run prints its page count, next cursor, stop reason, and any wait requested by GGG. Exit code 75 reports a provider cooldown in JSON on stderr and publishes no capture. Schedule another run only after that wait. Collection time records when the tool pulled the pages. It does not establish the age of the original listings. The API stream is delayed, and a known cursor can refer to historical changes. [GGG Public Stashes reference](https://www.pathofexile.com/developer/docs/reference#public-stashes)

Use **Check quote** in the rule editor to open a read-only lookup for the selected feed and exact item or variant. Choose the intended league before requesting prices. The lookup shows the current quote and liquidity evidence without saving the rule or publishing a filter.

Choose **Embers of the Allflame** for an exact ember. PoB uses its per-item quote and can remove the baseline hide. An exported fixed baseline carries these feed selections into daily sync. Each explicit extra category is fetched once per refresh. If a required feed is unavailable, stale, or contains malformed rows, daily sync keeps the last verified output. Missing, ambiguous, or thin item quotes keep their baseline rules. [Market API reference](https://poe.ninja/docs/api)

## Managed maps

In **Managed price rules**, choose **Maps**, a tier from 1 to 16, and Ordinary, Blighted, or Blight-ravaged. PoB uses separate stash price feeds for those variants. The rule excludes unique, corrupted, implicit-modified, enchanted, Mirage, memory, Shaped, and Elder maps. It can be relaxed when that exact tier-wide quote clears the price margin. The maps pickup target applies when configured.

The provider often groups maps by tier. Exact named maps, Atlas boss variants, and unique maps keep their existing rules. A quote needs at least 20 sampled listings and 20 listings in the overview. Missing or conflicting tier quotes keep the baseline hide. Automatic map repricing can loosen these managed hides.

## Managed gem variants

In **Managed price rules**, select **Skill Gems** or **Support Gems**. Enter the exact name, gem level, quality and corruption state, then choose the area. The generated rule applies to regular gems and excludes transfigured and imbued gems. A matching listing-backed quote can remove the baseline hide. Later filter rules still decide how the gem appears.

A quote needs a stable price ID, at least 20 observations and at least 20 listings. Invalid or conflicting identities, a missing exact variant, and thin listings keep the baseline hide. Daily profiles with managed gem rules additionally require a fresh `SkillGem` overview. If the feed is unavailable, the profile keeps its last verified output. Other profiles continue using their existing feeds. Enable gem rules when your market source can serve the stash category reliably. [Item filter reference](https://www.pathofexile.com/item-filter/about) · [Market API reference](https://poe.ninja/docs/api)

PoB checks the provider label against the gem fields. For example, `20/20c` must agree with level 20, 20% quality and explicit corruption. An omitted quality or corruption field can represent zero quality or an uncorrupted gem when the label agrees. The read-only build-item browser also compares named transfigured gems when the provider supplies matching evidence.

When comparing an Imbued gem from a build, PoB can show a read-only market estimate for the same gem and support when the feed omits level or quality. The result lists missing fields and warns about insufficient listing evidence.

For equipped crafting bases, **From build** shows item levels available in the build. **Search exact base on trade** opens official PC trade with the exact base and item level. PoB uses the original base implicit to distinguish known variants that share a trade name. Enter a league first or use the action from the price results, where PoB uses the selected or verified current league. The overview's provider level remains unverified and its prices are estimates for base variants.

## Named sync profiles

Open **Profiles** in **Daily price sync** to create or switch profiles. Each profile has its own fixed baseline, protected samples, PoE 1 PC trade league, schedule, and price history. The original setup appears as **Default**. A destination belongs to one profile, including when a different Windows path spelling resolves to the same file.

PoB checks due profiles in order. A Windows background run starts a profile only if there is time for a full refresh before the task limit. Profiles left in the queue stay due and are checked on the next trigger. Enable background sync individually on profiles that should also run while PoB is closed. They share one Windows task, which is removed when the last profile turns off background sync.

## NeverSink base updates

When a kept bundled profile references an older NeverSink revision, open **Profile tools → Audit and update → Update bundled NeverSink base**. PoB retrieves the exact saved revision and compiles it and the bundled revision with the same personal rules. The review shows removed conditions, matching visibility checks for protected drops, and changes to saved examples. **View full diff** compares both compiled filters.

**Apply to draft** is available after the protected checks pass. The new bundled revision and preserved personal rules remain in the draft until you keep it. The daily sync file and its fixed baseline can be replaced separately after reviewing the new export.

When refreshing an imported baseline or adopting external edits to the tiered test filter, PoB also protects its marked rare-equipment rules. It checks the Tier 5 Rank A/B block, fallback hide, and identified corrupted affix rules for changes. A precedence check replays the declared bases at tiers 4 and 5 and examples of lower-ranked and corrupted equipment. Their filter decisions and visible appearance must match before PoB accepts the update.

Open **Profile tools → Tier 5 rare exceptions** to see which eligible bases outside the marked Rank A/B list show in the compiled profile. Select **Inspect sample** to open the same item in Simulate. After a verified refresh, **Rare exceptions** in **Daily price sync** opens the same audit for the checksummed fixed baseline or verified local filter. Each source shows its own rule lines. The audit tests unidentified, uncorrupted, item-level 86 rares in an area at level 83 with no sockets, using examples from PoB's item catalogue.

## Publish a verified filter to a PoE account

In **Daily price sync**, open **Publish to account** after a successful refresh. Use the existing PoE login and item-filter permission, select an existing filter in the matching realm, and review the full diff. **Publish exact output** rechecks the local checksum and the remote filter before sending the approved text. The server validates the update.

Local and background sync do not publish account filters. An uncertain server result is shown for review before retrying.


Use **Check Windows task** in daily sync to compare the profile's background preference with Task Scheduler. The check reports missing or disabled registrations, mismatched worker actions, account or trigger changes, and a missing PoB executable. The expected task checks for due profiles every five minutes while the user is signed in. If the profile already opts in, use **Repair task** to register the expected Windows task for recoverable problems.

## Shared cache for app distribution

PoB can use an operator-managed HTTPS cache for all poe.ninja economy requests. Set `POB_MARKET_CACHE_URL` to the full public HTTPS prefix, such as `https://prices.example.test/pob-market/`, before starting PoB. The Windows task records that source when you enable or repair it, so the scheduled worker uses the same endpoint even if Task Scheduler inherits different settings. The direct source is the default when the setting is empty.

Daily sync records the source when you enable or update a profile. If the runtime's source differs, sync leaves the active filter in place. To change sources, restart with the desired setting, preview the prices, save the profile, and repair the Windows task if you use background sync. Use **Check Windows task** after upgrading an older task to see whether it needs repair.

Configure the final HTTPS URL. PoB rejects redirects for economy feeds and preserves the active filter if a scheduled refresh receives one.

The operator runs `node tools/serve_loot_market_cache.cjs` with `POB_MARKET_UPSTREAM_AGENT` set to the application's descriptive User-Agent and contact. It binds to loopback on port 9410 by default. Publish that service through the deployment's HTTPS reverse proxy by stripping the configured path prefix. Restrict the proxy to the intended audience and use `/health` from monitoring to inspect pending work, cache hits, coalesced requests and failures.

For a single relay process, set `POB_MARKET_COOLDOWN_FILE` to a dedicated file in a private, writable state directory retained across restarts. The relay creates the file when needed and saves the upstream retry deadline before replying to a rate limit or service outage. Keep the file with the relay instance. It contains only a deadline.

The service accepts only the app's public economy routes and active leagues. It coalesces requests, bounds the upstream queue, respects provider caching, and preserves origin age and retry timing. Throttled, stale, oversized and malformed data go through the app's existing checks before any filter is published. The operator needs to qualify the deployed host with the provider and verify fresh responses from that host before enabling distribution. [poe.ninja API guidelines](https://poe.ninja/docs/api)

Optionally set `POB_MARKET_SNAPSHOT_DIRECTORY` to a separate, private, writable directory kept across restarts. Give each relay process its own directory. Deploy the complete relay tools from the repository.

The relay atomically stores validated responses with a positive shared cache lifetime. It preserves the original HTTP freshness time and expiry on restart. An expired cache lifetime requires upstream revalidation before the response can be used again. Snapshots older than one hour, incomplete writes, and invalid records are discarded. Private, no-store, and immediate-revalidation responses stay out of the disk cache.

The cache retains up to 48 entries and 48 MiB of response bodies. It evicts the least recently used entries and drops their snapshots. The **snapshots** section of **/health** reports restored and discarded snapshots and storage errors without exposing paths or payloads. The HTTPS qualification tool fails when it observes a storage error. Fix the private directory and restart to verify recovery.

### Deploy the relay container

The Compose package runs the Node relay as an unprivileged user with a read-only root filesystem. The named state volume keeps cached snapshots and provider cooldowns across container replacement. Use Docker Engine 28 or newer for the published loopback port to stay restricted to the host. [Docker port publishing](https://docs.docker.com/engine/network/port-publishing/)

Set `POB_MARKET_UPSTREAM_AGENT` to the application name and an operator contact, then start the service from the repository root.

```sh
docker compose -f deploy/market-relay/compose.yaml up -d --build --wait
```

The default loopback port is 9410. Set `POB_MARKET_LOOPBACK_PORT` before starting Compose to change that port. Configure the HTTPS reverse proxy to strip the `/pob-market` prefix and forward it to the loopback port. For a reverse proxy running on the host, the equivalent Caddy configuration is below. Use the deployed DNS name in place of the example.

```caddyfile
prices.example.test {
    handle_path /pob-market/* {
        reverse_proxy 127.0.0.1:9410
    }
}
```

Run the HTTPS qualification command below before enabling the endpoint in PoB. Review a candidate filter against the fixed baseline and confirm its protected drops. During upgrades or rollback, use the same Compose project name to retain state. Container health checks relay storage and HTTP readiness, while the qualification command checks availability of specific market feeds.

When the configured shared cache rejects an upstream response, **Last attempt** can distinguish a stale feed from an invalid or oversized response alongside HTTP 502. Older caches can still report a generic provider error.

### Monitor the relay

Polling **/health** reads the current process without fetching prices. A top-level **ready** status means the relay can answer HTTP requests. **provider.state** reports whether the relay has yet to contact the provider (**idle**), last validated a response (**ready**), last failed a validation (**degraded**), or is waiting out a provider cooldown (**cooldown**). The receipt includes the remaining cooldown, aggregate attempts, and numeric timestamps and fixed reason codes for the last outcomes.

**cached** counts stored entries, including ones due for revalidation. **serviceable** counts entries the relay can serve immediately and **cachedBytes** measures the stored response bodies. Client rejections, refreshes refused by the queue, and refreshes stopped by cooldown have separate counters. The existing rejected count measures HTTP responses, including clients sharing a refresh. A failed validation can carry an upstream HTTP 200 when the response body is unusable. The numbers reset on process restart. The endpoint exposes aggregate diagnostics without league names, request URLs, or upstream response bodies.

Monitor repeated degraded results, cooldowns, and queue rejections during the pilot. Use the qualification command to verify each required feed.

With cooldown persistence enabled, `provider.cooldownPersistence` reports `ready` or `error`. The qualification tool fails on a persistence error. Restore the state directory and let the running relay report `ready` before restarting it. The relay honors its in-memory deadline and waits for a successful write before resuming upstream requests.

Run the cache probe after configuring HTTPS and before pointing scheduled clients at the service.

```sh
node tools/check_loot_market_cache.cjs https://prices.example.test/pob-market/ Covens SkillGem,BaseType,Scarab
```

The league defaults to the current PC trade league. Omit the third argument to check only the eight core feeds. Add supported exchange or stash category names to qualify their availability. The read-only command reports cache health, source age, quote evidence and HTTP failures. For exchange quotes, matching duplicate rows use the lowest quoted volume. Conflicting or invalid observations cannot qualify the currency reference. For stash feeds it counts each unambiguous price ID once and reports how many have at least 20 observations and 20 listings. Use PoB's **Preview changes** against the intended baseline to check exact matches and protected drops before enabling sync.

For `Map`, `BlightedMap`, and `BlightRavagedMap`, check `exactMapTiers` for the tiers backed by a liquid, unambiguous tier-wide quote. A map feed needs at least one such tier to pass. `ImbuedGem` reports `advisoryGemQuotes` for listing-backed gem and support combinations. Exact managed gem rules use the separate `SkillGem` check.

### Stage the relay rollout

1. Arrange production hosting and confirm the allowed integration with the provider. Run the loopback relay behind the deployment's TLS reverse proxy and configure its descriptive User-Agent and operator contact.
2. Run the qualification command from the intended client network. Request the eight core feeds and the optional categories the pilot profile uses. Keep the report with the source version and the time of the check.
3. Qualify the packaged Windows worker on a fresh portable extraction and a copy of the intended fixed baseline. Require each optional category that the pilot needs. The worker review reports the verified source mode, feed ages, protected check count, and filter checksum. The pilot checks that a same-day rerun keeps identical bytes.
4. Observe the pilot before pointing additional profiles at the relay. On repeated failures, stop expanding the rollout and keep each client's last verified output. Respect the provider's retry window. Resume after qualification passes from the deployed host.

```powershell
python tools/smoke_portable_windows.py <fresh-extraction-folder> --loot-filter <fixed-baseline.filter> --league Covens --market-cache https://prices.example.test/pob-market/ --require-feed SkillGem
```

Run this from the client network after installing the pilot's Python dependency with `python -m pip install lupa==2.8`. Use a baseline outside the extraction folder. For a custom filter, pass `--protected-samples <samples.json>` and set `--protected-checks` to the minimum check count expected for that pilot. The tool writes its settings, filter and reports to the extraction. Then run **Preview changes** on the intended profile, verify rollback and check the saved Windows task's source if it uses background sync.

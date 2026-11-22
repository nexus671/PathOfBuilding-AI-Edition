# Loot filter economy review

In PoB AI Edition, open **Loot Filter → Profile tools → Review exchange prices** on a Normal-mode profile that imports your filter. Leave League ID blank to use the current PC trade league or enter the exact poe.ninja league ID. Review the proposed stack changes, then export a separate filter.

For another filter, add standalone comments `# PoB economy: begin` and `# PoB economy: end` around the exact item-name stack hides you want to review. Existing personal filters with the original tiered-test section headings also work.

The review uses the current poe.ninja exchange snapshot. The default target is one chaos per stack. It requires 100 chaos of hourly volume and a 15% margin above the target at the old cutoff before suggesting a reduction. Unsupported rules and thin markets keep their existing cutoffs. General currency rules later in the filter still determine the label and visibility of stacks that pass these hides.

This handles commodity stack rules. Cards, uniques, gear valuation, and historical price smoothing are outside this release.

## Daily sync on Windows

Open **Loot Filter → Profile tools → Daily price sync**. Enter the live .filter file, the fixed baseline .filter file, and the league ID. Select **Enable / update**. PoB keeps a checksum-verified baseline copy. Use **Sync now** to run the first check immediately, or let PoB check at or after 9:00 a.m. local time while the app is open.

The current daily flow supports the protected tiered-test filter profile. It checks all requested feeds for an exchange snapshot served within the past hour, parses the generated filter, and checks protected drops before publishing. It backs up a changed live file, keeps a recovery record, and pauses writes if the target was edited outside PoB. After reviewing an edit, use Enable / update to adopt it. Use Disable to stop the daily refresh. In Path of Exile, reload the filter if the game is already open.

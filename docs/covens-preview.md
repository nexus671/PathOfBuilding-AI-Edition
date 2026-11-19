# Covens of Umbra trees

The fork bundles upstream PR #10437's **3.30 Standard and Ruthless passive trees**, plus GGG's **3.30.0c Atlas** and the earlier Atlas preview. **New builds default to 3.30**, and new Atlas plans on those builds use 3.30.0c. Existing builds and saved plans keep their recorded versions, including our earlier passive preview.

## Passive tree

New builds open on **3.30**. To convert an existing build, choose it in **Tree > Version** and review the native conversion dialog. Keep a separate tree spec when you want to compare versions. **3.30 (ruthless)** and the earlier **3.30 preview** remain selectable. The imported upstream parser handles the new distance wording and strips GGG tooltip tags from downloaded mastery descriptions.

The tree warning and AI build analysis identify builds still using the earlier preview. Items, gems and new league mechanics still use the current calculation engine; adding the tree does not establish full 3.30 calculation support. Review unsupported modifiers before relying on a result.

## Wickerman

Paste Viscera item text into Items, or use character import with OAuth to bring in equipped Wickerman items. The four Wickerman slots can also be used in AI build proposals and Journey acquisition plans. Names and slot types are provisional; the catalogue does not invent modifier values. Enter or import the item's actual modifiers and review unsupported lines. Account-name import does not currently expose Wickerman data.

## Atlas

New 3.30 Atlas plans use **3.30.0c** by default. Choose **3.30.0-preview** when you want to review the earlier snapshot. The base point limit is **150**, with granted points accounted for separately. Search, routing, strategy stages, native saving, bundles and MCP proposals preserve the selected version.

GGG's Standard and Covens Atlas exports have identical graph data within each mode at the bundled revisions. The separate Ruthless graph is bundled and defaults for 3.30 Ruthless characters; its node modifiers differ from Standard. The generator verifies the matching league graphs and shared artwork. Standard and Ruthless Standard snapshots of **3.29.3**, 3.29.1 and 3.27.0 are also available; their historical league variants are not included.

## Sources

- [Passive tree preview, commit 550fb34](https://github.com/grindinggear/skilltree-export/commit/550fb34ae7fca9ec4d760a2ac845bb2ba1032ec3)
- [Atlas 3.30.0c, commit 24bd611](https://github.com/grindinggear/atlastree-export/commit/24bd611b33fb727c0d1264185599fdd973d02d2d)
- [Atlas preview 2, commit d225501](https://github.com/grindinggear/atlastree-export/commit/d225501d7a3e52c991309116473908c284075e89)
- [Stable Atlas 3.29.3, commit dcb2a00](https://github.com/grindinggear/atlastree-export/commit/dcb2a006b68740f3ecbd317775c262fc6ed7b8af)

`python tools/update_passive_preview.py` regenerates the passive preview using the existing ascendancy-position preprocessor. `python tools/update_atlas_data.py --version 3.30.0-preview` regenerates the Atlas preview. Both use immutable source commits and bundle artwork for offline use. Provenance and asset SHA-256 hashes are stored beside the generated data.

After changing bundled artwork, run `python tools/update_headless_image_sizes.py` to refresh image dimensions used by headless rendering. The UI suite uses real dimensions and sprite UVs for passive-tree screenshots, including textured connectors and repeated backgrounds.

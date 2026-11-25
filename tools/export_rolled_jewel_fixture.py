"""Extract a historical rolled-jewel fixture from a local PC Public Stashes capture."""

import argparse
import json
from pathlib import Path
import re

from build_public_stash_capture import CAPTURE_LIMIT, assemble_capture, encode_response, publish_capture
from collect_public_stash_capture import read_capture


FIXTURE_EPOCH = 1577836800
FIXTURE_LEAGUE = "Fixture"
BASES = {"Small Cluster Jewel", "Medium Cluster Jewel", "Large Cluster Jewel", "Mycelium Core"}
RARITIES = {"Normal", "Magic", "Rare", "Unique"}
ID = re.compile(r"[0-9a-fA-F]{64}")
PRICE = re.compile(r"[ \t\r\n\v\f]*~(price|b/o)[ \t\r\n\v\f]+([0-9]+\.?[0-9]*)[ \t\r\n\v\f]+(chaos|divine)[ \t\r\n\v\f]*")
MOD_FIELDS = ("implicitMods", "explicitMods", "craftedMods", "fracturedMods", "enchantMods")
MOD_FLAGS = {"fractured", "crafted", "mutated", "desecrated", "vestigial", "rareonly"}
INFLUENCES = {"shaper", "elder", "warlord", "hunter", "crusader", "redeemer", "searing", "tangled"}
STATE_FIELDS = (
    "identified", "corrupted", "fractured", "synthesised", "split", "abyssJewel",
    "shaper", "elder", "warlord", "hunter", "crusader", "redeemer", "searing", "tangled",
    "duplicated", "doubleCorrupted", "memoryItem", "mutated", "veiled", "lockedToCharacter",
    "lockedToAccount", "enshrouded", "unmodifiable", "vestigial", "delve", "foreseeing",
    "unmodifiableExceptChaos", "replica", "isRelic",
)
PRESENCE_FIELDS = ("realm", "scourged", "crucible", "incubatedItem", "builtInSupport", "monsterLevel", "foilVariation")
ARRAY_FIELDS = (
    "socketedItems", "scourgeMods", "crucibleMods", "veiledMods", "grantedSkills",
    "sockets", "notableProperties", "additionalProperties", "utilityMods", "ultimatumMods", "mutatedMods",
)


def alias(aliases, value, template):
    if value not in aliases:
        aliases[value] = template.format(len(aliases) + 1)
    return aliases[value]


def safe_note(value):
    if value is None or value == "":
        return value
    match = PRICE.fullmatch(value) if isinstance(value, str) and len(value.encode("utf-8")) <= 80 else None
    return "~{} {} {}".format(*match.groups()) if match else "Unpriced"


def state(value):
    # Lua treats all values except false and nil as true, even zero and empty strings.
    return value if value is None or type(value) is bool else 1


def flags(value, fields):
    if isinstance(value, list):
        return {"unsupported": True} if value else {}
    if not isinstance(value, dict):
        return value if value is None or value is False else 1
    known = {key: state(flag) for key, flag in value.items() if key in fields and flag is not None}
    if any(key not in fields and flag is not None for key, flag in value.items()):
        known["unsupported"] = True
    return known


def modifiers(value):
    if not isinstance(value, list):
        if isinstance(value, dict) and all(entry is None for entry in value.values()):
            return []
        return None if value is None else True
    out = []
    for mod in value:
        if isinstance(mod, str):
            out.append(mod)
        elif isinstance(mod, dict):
            projected = {
                key: state(mod[key]) for key in ("disabled", "custom", "variant") if key in mod
            }
            if isinstance(mod.get("description"), str):
                projected["description"] = mod["description"]
            if "flags" in mod:
                projected["flags"] = flags(mod["flags"], MOD_FLAGS)
            out.append(projected)
        else:
            out.append(True)
    return out


def array_shape(value):
    if value is None:
        return None
    if isinstance(value, (list, dict)):
        return [True] if value else []
    return True


def jewel_properties(value):
    if not isinstance(value, list) or len(value) != 1 or not isinstance(value[0], dict):
        return array_shape(value)
    entry = value[0]
    values = entry.get("values")
    # These are the only property name and display tuple the native matcher recognizes.
    return [{
        "name": "Limited to" if entry.get("name") == "Limited to" else "Other",
        "displayMode": entry["displayMode"] if type(entry.get("displayMode")) in (int, float) else None,
        "values": [["1", 0]] if (
            isinstance(values, list) and len(values) == 1 and isinstance(values[0], list)
            and len(values[0]) == 2 and values[0][0] == "1"
            and type(values[0][1]) in (int, float) and values[0][1] == 0
        ) else array_shape(values),
    }]


def project_item(item, item_ids, league):
    base = item.get("baseType")
    if not isinstance(base, str) or base not in BASES:
        return
    out = {"baseType": base}
    item_id = item.get("id")
    if isinstance(item_id, str) and ID.fullmatch(item_id):
        out["id"] = alias(item_ids, item_id.lower(), "{:064x}")
    if item.get("league") is not None:
        out["league"] = FIXTURE_LEAGUE if item["league"] == league else "Other"
    for key in ("ilvl", "frameType", "stackSize"):
        if item.get(key) is not None:
            value = item[key]
            out[key] = value if type(value) in (int, float) or value is False else True
    frame_id = item.get("frameTypeId")
    if isinstance(frame_id, str) and re.fullmatch(r"[A-Za-z0-9_]{1,48}", frame_id):
        out["frameTypeId"] = frame_id
    rarity = item.get("rarity")
    if isinstance(rarity, str) and rarity in RARITIES:
        out["rarity"] = rarity
    if item.get("name") == "Putrid Seed":
        out["name"] = "Putrid Seed"
    if item.get("typeLine") is not None:
        out["typeLine"] = "Mycelium Core" if item["typeLine"] == "Mycelium Core" else "Other"
    out.update((key, state(item[key])) for key in STATE_FIELDS if key in item)
    out.update((key, True) for key in PRESENCE_FIELDS if item.get(key) is not None)
    out.update((key, array_shape(item[key])) for key in ARRAY_FIELDS if key in item)
    out.update((key, modifiers(item[key])) for key in MOD_FIELDS if key in item)
    if "influences" in item:
        out["influences"] = flags(item["influences"], INFLUENCES)
    if "properties" in item:
        out["properties"] = jewel_properties(item["properties"])
    if "note" in item:
        out["note"] = safe_note(item["note"])
    return out


def export_fixture(capture):
    league = capture["league"]
    stash_ids, item_ids, sellers, cursors = {}, {}, {}, {}
    captured_pages = capture["pages"]
    pages = []
    jewel_count = 0
    for entry in captured_pages:
        original = entry["response"]
        rows = []
        request = alias(cursors, entry["requestCursor"], "fixture-{}")
        next_cursor = alias(cursors, original["next_change_id"], "fixture-{}")
        for stash in original["stashes"]:
            row = {"id": alias(stash_ids, stash["id"].lower(), "{:064x}"), "public": stash["public"]}
            if stash["public"] and stash.get("league") == league:
                row["league"] = FIXTURE_LEAGUE
                seller = stash.get("accountName")
                if isinstance(seller, str) and len(seller.encode("utf-8")) <= 128 and seller.strip(" \t\r\n\v\f"):
                    # Use the same ASCII case mapping as Lua string.lower.
                    key = seller.encode("utf-8").lower()
                    row["accountName"] = alias(sellers, key, "Seller {}")
                row["stash"] = safe_note(stash.get("stash"))
                row["items"] = []
                for item in stash["items"]:
                    projected = project_item(item, item_ids, league)
                    if projected:
                        row["items"].append(projected)
                        jewel_count += 1
            rows.append(row)
        pages.append((request, encode_response({"next_change_id": next_cursor, "stashes": rows})))
    if not jewel_count:
        raise ValueError("The capture contains no Cluster Jewel or Mycelium Core rows")
    fixture = json.loads(assemble_capture(FIXTURE_LEAGUE, FIXTURE_EPOCH, pages, len(pages)))
    fixture["fixture"] = "rolled-jewels-v1"
    body = encode_response(fixture)
    # The last assembly checks the limit before adding the fixture marker.
    if len(body) > CAPTURE_LIMIT:
        raise ValueError("The fixture exceeds 16 MiB")
    return body, jewel_count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", required=True, help="Exact league of the private PC capture")
    parser.add_argument("capture", type=Path)
    parser.add_argument("output", type=Path, help="A new JSON file")
    args = parser.parse_args()
    try:
        capture = read_capture(args.capture, args.league)
        body, count = export_fixture(capture)
        publish_capture(args.output, body)
    except (OSError, RecursionError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(f"Wrote {count} rolled-jewel rows across {len(capture['pages'])} pages")


if __name__ == "__main__":
    main()

"""Build a pinned Genesis graph from the 3.30.0.4 client data export."""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "c97553d1fc14a134dd6813e672d2b45fddf5b42d"
BASE = f"https://raw.githubusercontent.com/repoe-fork/repoe-fork.github.io/{COMMIT}/data/"
TREE = "passive_skill_trees/BrequelTree.json"
TRANSLATIONS = "stat_translations.json"
HASHES = {
    TREE: "9a622145daa25586c7db36a82276be37ee609ed7e3c8d6c650f4079afd4473ab",
    TRANSLATIONS: "8cc0c8301aafe9507452fc4f34fad97f405a156b139458fc3654688d41784946",
}
DESTINATION = ROOT / "src/Data/Genesis/3.30.0d.json"


def same_generated_content(actual, expected):
    return actual.replace(b"\r\n", b"\n") == expected


def read_source(name, directory):
    if directory:
        raw = (directory / Path(name).name).read_bytes()
    else:
        with urlopen(BASE + name, timeout=60) as response:
            raw = response.read()
    if hashlib.sha256(raw).hexdigest() != HASHES[name]:
        raise ValueError(f"Unexpected source hash for {name}")
    return json.loads(raw)


def translate(stat, value, index):
    entries = index.get(stat, [])
    matches = []
    for entry in entries:
        if entry["ids"] != [stat]:
            continue
        for rule in entry.get("English") or []:
            if len(rule["condition"]) != 1:
                continue
            condition = rule["condition"][0]
            if condition.get("negated") is not None:
                raise ValueError(f"Unsupported translation condition: {stat}")
            if (condition["min"] is None or value >= condition["min"]) and (condition["max"] is None or value <= condition["max"]):
                matches.append(rule)
    if len(matches) != 1:
        raise ValueError(f"Expected one translation for {stat}, got {len(matches)}")
    rule = matches[0]
    number = value
    for handler in rule["index_handlers"][0]:
        if handler == "negate":
            number = -number
        else:
            raise ValueError(f"Unsupported translation handler {handler}: {stat}")
    fmt = rule["format"][0]
    if fmt == "ignore":
        rendered = ""
    elif fmt == "#":
        rendered = str(number)
    elif fmt == "+#":
        rendered = f"{number:+d}"
    else:
        raise ValueError(f"Unsupported translation format {fmt}: {stat}")
    return rule["string"].replace("{0}", rendered)


def build(tree, translations):
    index = {}
    for entry in translations:
        for stat in entry["ids"]:
            index.setdefault(stat, []).append(entry)
    nodes = {}
    for group in tree["groups"]:
        for placement in group["passives"]:
            node_id = str(placement["hash"])
            if node_id in nodes:
                raise ValueError(f"Duplicate placement: {node_id}")
            node = tree["passives"][node_id]
            stats = node["stats"]
            nodes[node_id] = {
                "id": placement["hash"], "internalId": node["id"], "name": node["name"],
                "stats": [translate(stat, value, index) for stat, value in stats.items()],
                "rawStats": stats, "icon": node.get("icon"),
                "notable": node["is_notable"], "choice": node["is_multiple_choice"],
                "choiceOption": node["is_multiple_choice_option"],
                "groupX": group["x"], "groupY": group["y"],
                "orbit": placement["radius"], "orbitIndex": placement["position_clockwise"],
                "links": sorted(placement["connections"]),
            }
    if set(nodes) != set(tree["passives"]):
        raise ValueError("Passive placements do not match the source catalogue")
    graph = {int(node_id): set(node["links"]) for node_id, node in nodes.items()}
    for node_id, links in list(graph.items()):
        for target in links:
            if target not in graph or target == node_id:
                raise ValueError(f"Invalid edge {node_id} -> {target}")
            graph[target].add(node_id)
    roots = tree["roots"]
    if len(roots) != 4 or len(set(roots)) != 4:
        raise ValueError("Expected four distinct Genesis roots")
    visited = set()
    for root in roots:
        pending = [root]
        while pending:
            current = pending.pop()
            if current in visited:
                continue
            visited.add(current)
            nodes[str(current)]["root"] = root
            pending.extend(graph[current] - visited)
    if len(visited) != len(nodes) or len({nodes[str(root)]["root"] for root in roots}) != 4:
        raise ValueError("Genesis roots do not form four separate connected trees")
    for node_id, links in graph.items():
        nodes[str(node_id)]["links"] = sorted(links)
    return {"version": "3.30.0d", "sourceCommit": COMMIT,
            "treeSource": BASE + TREE, "treeSha256": HASHES[TREE],
            "translationsSource": BASE + TRANSLATIONS, "translationsSha256": HASHES[TRANSLATIONS],
            "title": tree["title"], "roots": roots, "nodes": nodes,
            "layoutNote": "Group coordinates, orbit and orbit index are retained from the export; rendering geometry and live-game behavior need verification."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="Directory containing the two pinned JSON files")
    parser.add_argument("--check", action="store_true", help="Compare the generated result without writing")
    args = parser.parse_args()
    result = build(read_source(TREE, args.source_dir), read_source(TRANSLATIONS, args.source_dir))
    raw = (json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    if args.check:
        if not same_generated_content(DESTINATION.read_bytes(), raw):
            raise SystemExit("Genesis data differs from the pinned sources")
        print(f"Genesis data verified: {len(result['nodes'])} nodes, {len(result['roots'])} roots")
    else:
        DESTINATION.parent.mkdir(parents=True, exist_ok=True)
        DESTINATION.write_bytes(raw)
        print(f"Wrote {DESTINATION}: {len(result['nodes'])} nodes")


if __name__ == "__main__":
    main()

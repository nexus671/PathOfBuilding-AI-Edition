"""Compare a GGG Atlas tag and its generated graphs with this checkout."""
import argparse
import hashlib
import json
import math
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    ("3.30.0-preview", "data.json", "sha256"),
    ("3.30.0-preview", "league.json", "leagueSha256"),
    ("3.30.0-preview-ruthless", "ruthless.json", "sha256"),
    ("3.30.0-preview-ruthless", "ruthless-league.json", "leagueSha256"),
)

ANGLES = [0, 30, 45, 60, 90, 120, 135, 150, 180, 210, 225, 240, 270, 300, 315, 330]


def graph_errors(graph, source):
    """Check generated node contents and layout against an official export."""
    errors = []
    nodes = source["nodes"]
    expected = {key for key, node in nodes.items() if key != "root" and not node.get("isMastery")}
    decorations = {key for key, node in nodes.items() if key != "root" and node.get("isMastery")}
    actual_decorations = {str(entry["id"]): entry for entry in graph["decorations"]}
    if set(graph["nodes"]) != expected:
        errors.append("allocatable node IDs differ")
    if len(actual_decorations) != len(graph["decorations"]) or set(actual_decorations) != decorations:
        errors.append("decorative node IDs differ")
    if graph["start"] != int(nodes["root"]["out"][0]):
        errors.append("start node differs")
    if graph["maxPoints"] != source["points"]["totalPoints"]:
        errors.append("point budget differs")
    if graph["bounds"] != [source[key] for key in ("min_x", "min_y", "max_x", "max_y")]:
        errors.append("tree bounds differ")
    for key in sorted(expected | decorations, key=int):
        node = nodes[key]
        entry = graph["nodes"].get(key) if key in expected else actual_decorations.get(key)
        if entry is None:
            continue
        kind = ("keystone" if node.get("isKeystone") else "notable" if node.get("isNotable")
                else "gateway" if node.get("isWormhole") else "small")
        links = sorted({int(other) for other in node["out"] + node["in"]
                        if other != "root" and not nodes[other].get("isMastery")})
        group = source["groups"][str(node["group"])]
        count = source["constants"]["skillsPerOrbit"][node["orbit"]]
        angle = math.radians(ANGLES[node["orbitIndex"]] if count == 16 else 360 * node["orbitIndex"] / count)
        radius = source["constants"]["orbitRadii"][node["orbit"]]
        fields = {
            "id": int(key), "name": node["name"] or "Atlas start", "stats": node["stats"],
            "x": round(group["x"] + math.sin(angle) * radius, 2),
            "y": round(group["y"] - math.cos(angle) * radius, 2),
            "links": links, "kind": kind, "grantedPoints": node.get("grantedPassivePoints", 0),
            "icon": node.get("icon"),
        }
        if node.get("isMultipleChoiceVariant"):
            fields["variantEffects"] = node["variantEffects"]
        elif "variantEffects" in entry:
            errors.append(f"node {key}: unexpected variant effects")
        for field, value in fields.items():
            if entry.get(field) != value:
                errors.append(f"node {key}: {field} differs")
    groups = [{"x": group["x"], "y": group["y"], "background": group["background"]["image"]}
              for group in source["groups"].values() if group.get("background")]
    if graph["groups"] != groups:
        errors.append("group backgrounds differ")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="3.30.0", help="GGG Atlas export tag or commit")
    parser.add_argument("--version", default="3.30.0-preview", choices=("3.30.0-preview", "3.30.0c"), help="Bundled Standard graph identifier")
    args = parser.parse_args()
    ref = quote(args.ref, safe="")
    failed = False
    exports = {}
    sources = tuple((args.version + ("-ruthless" if "ruthless" in version else ""), filename, field)
                    for version, filename, field in SOURCES)
    for version, filename, field in sources:
        graph = json.loads((ROOT / "src" / "Data" / "Atlas" / (version + ".json")).read_text(encoding="utf-8"))
        url = f"https://raw.githubusercontent.com/grindinggear/atlastree-export/{ref}/{filename}"
        with urlopen(url, timeout=30) as response:
            raw = response.read()
        digest = hashlib.sha256(raw).hexdigest()
        exports[filename] = json.loads(raw)
        matches = digest == graph[field]
        failed |= not matches
        print(f"{filename}: {'matches' if matches else 'DIFFERS'} {version} ({digest})")
    if failed:
        raise SystemExit("Atlas export differs; inspect and regenerate the affected graphs before updating plans.")
    for version, main_file, league_file in ((args.version, "data.json", "league.json"),
                                            (args.version + "-ruthless", "ruthless.json", "ruthless-league.json")):
        source, league = exports[main_file], exports[league_file]
        if {key: value for key, value in source.items() if key != "tree"} != {
                key: value for key, value in league.items() if key != "tree"}:
            raise SystemExit("League and non-league exports differ")
        graph = json.loads((ROOT / "src/Data/Atlas" / (version + ".json")).read_text(encoding="utf-8"))
        errors = graph_errors(graph, source)
        if errors:
            raise SystemExit(f"{version}: {len(errors)} graph differences: " + "; ".join(errors[:10]))
        print(f"{version}: verified {len(graph['nodes'])} generated nodes and {len(graph['decorations'])} decorations")
    print("Source files and generated graphs match. The live game's tree was not checked.")


if __name__ == "__main__":
    main()

"""Generate the crafting bench catalogue from the reviewed 3.30 client export."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BENCH_HASH = "d664372c28784a65f9c10c1b8d36608d084ac698a6caaafbaf4be40be8b6f76a"
MODS_HASH = "a6814fdd00755eca4208b2d5bae7877795e5c91a2d0935daa6748b49f26ec0ce"


def build(bench_raw, mods_raw):
    if hashlib.sha256(bench_raw).hexdigest() != BENCH_HASH or hashlib.sha256(mods_raw).hexdigest() != MODS_HASH:
        raise ValueError("Client export does not match the reviewed 3.30.0.1.4 data")
    rows, mods = json.loads(bench_raw), json.loads(mods_raw)
    if len(rows) != 782:
        raise ValueError("Unexpected number of bench entries")
    result_mods = {}
    for row in rows:
        ident = row["actions"].get("add_explicit_mod")
        if ident:
            mod = mods[ident]
            if not isinstance(mod["text"], str) or not mod["text"]:
                raise ValueError(f"Missing modifier text: {ident}")
            result_mods[ident] = {key: mod[key] for key in ("text", "required_level", "generation_type")}
    return {"schemaVersion": 1, "clientVersion": "3.30.0.1.4", "benchSha256": BENCH_HASH,
            "modsSha256": MODS_HASH, "bench": rows, "benchMods": result_mods}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Directory containing the reviewed client JSON exports")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = ROOT / "src/Data/Crafting/3.30-bench.json"
    data = build((args.directory / "crafting_bench_options.json").read_bytes(), (args.directory / "mods.json").read_bytes())
    encoded = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"
    if args.check:
        if output.read_text(encoding="utf-8") != encoded:
            raise ValueError("Bench catalogue differs from the reviewed source")
    else:
        output.write_text(encoded, encoding="utf-8", newline="\n")
    print("3.30 bench catalogue verified" if args.check else "3.30 bench catalogue generated")


if __name__ == "__main__":
    main()

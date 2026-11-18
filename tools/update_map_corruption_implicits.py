"""Extract ordinary-map corruption implicits from the pinned 3.30 client export."""
import argparse, hashlib, json
from pathlib import Path

SOURCE_SHA256 = "06f5c7c3fa55dc566efffd16d7a6d49ce95987e67c4571c3ca77fbd8312ccb10"
DEST = Path(__file__).resolve().parents[1] / "src/Data/Crafting/MapCorruption330.json"
# The client extraction does not include these generic stat descriptions.
FALLBACK = {
    "MapCorruptionItemQuantity": "+(10-20)% Item Quantity (legacy)",
    "MapCorruptionItemRarity": "+(10-20)% Item Rarity",
    "MapCorruptionPackSize": "+(5-10)% Pack Size",
    "MapCorruptionModEffect": "(10-20)% increased Explicit Modifier magnitudes",
}

def main():
    parser=argparse.ArgumentParser();parser.add_argument("source",type=Path);parser.add_argument("--check",action="store_true");args=parser.parse_args()
    raw=args.source.read_bytes();assert hashlib.sha256(raw).hexdigest()==SOURCE_SHA256,"Unexpected source hash"
    source=json.loads(raw);entries={}
    for key,mod in source.items():
        if not key.startswith("MapCorruption") or mod.get("domain")!="area" or mod.get("generation_type")!="corrupted": continue
        weights=mod.get("spawn_weights",[]);default=next((row["weight"] for row in weights if row["tag"]=="default"),0)
        if default<=0 and key!="MapCorruptionItemQuantity": continue
        assert len(mod["stats"])==1
        text=mod.get("text") or FALLBACK.get(key);assert text,key
        entries[key]={"text":text,"requiredLevel":mod["required_level"],"spawnWeights":weights,"stat":mod["stats"][0],"legacy":default<=0}
    assert len(entries)==9
    output=json.dumps({"patch":"3.30.0.2","sourceSha256":SOURCE_SHA256,"entries":entries},indent=2,sort_keys=True)+"\n"
    if args.check: assert DEST.read_text(encoding="utf-8")==output,"Map corruption data differs"
    else: DEST.write_text(output,encoding="utf-8",newline="\n")
    print("Verified",len(entries),"map corruption implicit records")
if __name__=="__main__": main()

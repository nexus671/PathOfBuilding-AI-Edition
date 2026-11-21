"""Extract ordinary-map corruption implicits from the pinned 3.30 client export."""
import argparse, hashlib, json
from pathlib import Path

SOURCE_SHA256 = "06f5c7c3fa55dc566efffd16d7a6d49ce95987e67c4571c3ca77fbd8312ccb10"
NEWER_SHA256 = "8549a332c5de55ba5b3a7208adf2fca321ccce3ba50698200a78e867cba1f4e4"
DEST = Path(__file__).resolve().parents[1] / "src/Data/Crafting/MapCorruption330.json"
# The client extraction does not include these generic stat descriptions.
FALLBACK = {
    "MapCorruptionItemQuantity": "+(10-20)% Item Quantity (legacy)",
    "MapCorruptionItemRarity": "+(10-20)% Item Rarity",
    "MapCorruptionPackSize": "+(5-10)% Pack Size",
    "MapCorruptionModEffect": "(10-20)% increased Explicit Modifier magnitudes",
}

def main():
    parser=argparse.ArgumentParser();parser.add_argument("source",type=Path);parser.add_argument("--check",action="store_true");parser.add_argument("--compare-newer",type=Path);args=parser.parse_args()
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
    if args.compare_newer:
        newer_raw=args.compare_newer.read_bytes();assert hashlib.sha256(newer_raw).hexdigest()==NEWER_SHA256,"Unexpected 3.30.0.4 source hash"
        newer=json.loads(newer_raw)
        active={key for key,mod in newer.items() if key.startswith("MapCorruption") and mod.get("domain")=="area" and mod.get("generation_type")=="corrupted" and any(row["weight"]>0 for row in mod.get("spawn_weights",[]))}
        assert active=={key for key,entry in entries.items() if not entry["legacy"]},"Current corruption implicit IDs differ"
        for key,entry in entries.items():
            mod=newer[key];assert mod["stats"]==[entry["stat"]] and mod["spawn_weights"]==entry["spawnWeights"] and mod["required_level"]==entry["requiredLevel"],key
            assert not mod.get("text") or mod["text"]==entry["text"],key
        print("Verified corruption implicit records match the 3.30.0.4 export")
    print("Verified",len(entries),"map corruption implicit records")
if __name__=="__main__": main()

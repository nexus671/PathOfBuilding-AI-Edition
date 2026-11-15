"""Extract the Gwennen reference from a saved 3.30 datamine HTML page.

This is a discovery aid, not an authoritative implementation of server rules.
Pass the saved page as the only argument; its hash is retained for review.
"""
import hashlib
import html
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
raw = Path(sys.argv[1]).read_bytes()
text = raw.decode("utf-8")
articles = re.findall(r'<article class="finding search-record".*?</article>', text)
entries = []
for article in articles:
    if "GwennenCraft_" not in article:
        continue
    def field(pattern):
        match = re.search(pattern, article)
        return html.unescape(match.group(1)) if match else None
    title = field(r'<h4 class="record-id">(.*?)</h4>')
    number = field(r'<code>(\d+)</code>')
    function = field(r'<span class="metadata-label">Function:</span>\s*(.*?)</p>')
    arguments = field(r'<span class="metadata-label">Arguments:</span>\s*(.*?)</p>')
    family = field(r'<span class="metadata-label">DealFamily:</span>\s*(\d+)</p>')
    assert title and number and family and "<" not in title
    entries.append({"id": int(number), "description": title, "function": function,
                    "arguments": arguments, "family": int(family)})
assert [row["id"] for row in entries] == list(range(1000, 1045)), "Unexpected source rows"
result = {"source": "https://poe-datamine.phelnaxgaming.workers.dev/",
          "sourceSha256": hashlib.sha256(raw).hexdigest(), "reportedPatch": "3.30",
          "offers": entries}
destination = root / "src" / "Data" / "Crafting" / "GwennenReference.json"
destination.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
print(f"Wrote {len(entries)} reference outcomes to {destination}")

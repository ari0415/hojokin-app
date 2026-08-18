#!/usr/bin/env python3
"""Fetch J-Net21 support.xml RSS, merge new local-government subsidy items into
data/local_gov.json, merge with data/jgrants_national.json, and rebuild index.html
from app_template.html. Run from the repository root."""
import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RSS_URL = "https://j-net21.smrj.go.jp/snavi/support/support.xml"
NS = {
    "dc": "http://purl.org/dc/elements/1.1/",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
}


def fetch_rss_items():
    req = urllib.request.Request(RSS_URL, headers={"User-Agent": "hojokin-compass-bot/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
    root = ET.fromstring(raw)
    items = []
    for it in root.iter("item"):
        title = (it.findtext("title") or "").strip()
        link = (it.findtext("link") or "").strip()
        desc = (it.findtext("description") or "").strip()
        desc = re.sub(r"\s+", " ", desc)
        title = re.sub(r"\s+", " ", title)
        pub = it.findtext("dc:date", namespaces=NS) or ""
        cov_label_el = it.find("dc:coverage/rdf:label", NS)
        cov_label = cov_label_el.text if cov_label_el is not None else None
        org = None
        m = re.match(r"^【([^】]+)】", title)
        if m:
            org = m.group(1)
        if not link or not title:
            continue
        items.append({
            "id": link,
            "t": title,
            "o": org,
            "a": [cov_label] if cov_label else ["全国"],
            "e": 0,
            "m": None,
            "s": "unknown",
            "d": "unknown",
            "src": "local",
            "u": link,
            "pub": pub,
            "desc": desc,
        })
    return items


def main():
    local_path = ROOT / "data" / "local_gov.json"
    national_path = ROOT / "data" / "jgrants_national.json"
    template_path = ROOT / "app_template.html"
    out_path = ROOT / "index.html"
    dataset_path = ROOT / "dataset.json"

    existing = json.loads(local_path.read_text(encoding="utf-8")) if local_path.exists() else []
    existing_by_id = {rec["id"]: rec for rec in existing}

    fetched = fetch_rss_items()
    new_count = 0
    for rec in fetched:
        if rec["id"] not in existing_by_id:
            existing_by_id[rec["id"]] = rec
            new_count += 1

    merged_local = list(existing_by_id.values())
    local_path.write_text(
        json.dumps(merged_local, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    national = json.loads(national_path.read_text(encoding="utf-8"))
    combined = national + merged_local
    dataset_path.write_text(
        json.dumps(combined, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    template = template_path.read_text(encoding="utf-8")
    combined_json = json.dumps(combined, ensure_ascii=False, separators=(",", ":"))
    final_html = template.replace("/*__DATA__*/", combined_json)
    out_path.write_text(final_html, encoding="utf-8")

    print(f"RSS items fetched: {len(fetched)}")
    print(f"New local-gov items added: {new_count}")
    print(f"Total local-gov items accumulated: {len(merged_local)}")
    print(f"Total combined dataset size: {len(combined)}")
    print(f"index.html size: {out_path.stat().st_size} bytes")


if __name__ == "__main__":
    main()

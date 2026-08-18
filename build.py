#!/usr/bin/env python3
"""Scrape J-Net21's 支援情報ヘッドライン subsidy search results (paginated, newest
first), merge new local-government subsidy items into data/local_gov.json, merge
with data/jgrants_national.json, and rebuild index.html from app_template.html.
Run from the repository root.

Pages are sorted newest-first, so on a normal run we stop as soon as we hit a
page containing no new ids (everything from there on was already collected on
a previous run). A fresh/empty local_gov.json instead walks all pages."""
import html
import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASE = "https://j-net21.smrj.go.jp/snavi2/results.php"
LIST_BASE = "https://j-net21.smrj.go.jp/snavi"
MAX_PAGES_SAFETY = 120

ARTICLE_RE = re.compile(r'<article class="pickup-item">([\s\S]*?)</article>')
FIELD_RES = {
    "id": re.compile(r'data-id="([0-9]+)"'),
    "title": re.compile(r'data-title="([^"]*)"'),
    "url": re.compile(r'data-url="([^"]*)"'),
    "category": re.compile(r'data-category="([^"]*)"'),
    "region": re.compile(r'data-region="([^"]*)"'),
}
ORG_RE = re.compile(r"実施機関：</dt>\s*<dd>([^<]*)</dd>")
PERIOD_RE = re.compile(r"募集期間：</dt>\s*<dd>([^<]*)</dd>")
TOTAL_RE = re.compile(r'search-count__total["\s\S]*?<span class="num">([0-9,]+)</span>')
DATE_RE = re.compile(r"(\d{4})年(\d{1,2})月(\d{1,2})日")
ORG_BRACKET_RE = re.compile(r"^【([^】]+)】")


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "hojokin-compass-bot/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read()
    return raw.decode("utf-8")


def parse_jdate(s):
    m = DATE_RE.search(s)
    if not m:
        return None
    y, mo, d = (int(g) for g in m.groups())
    return f"{y:04d}-{mo:02d}-{d:02d}"


def parse_period(period):
    if not period:
        return "unknown", "unknown"
    parts = re.split(r"[~〜～]", period)
    s = parse_jdate(parts[0]) if len(parts) >= 1 else None
    d = parse_jdate(parts[1]) if len(parts) >= 2 else None
    return (s or "unknown"), (d or "unknown")


def parse_page(page_html):
    items = []
    for m in ARTICLE_RE.finditer(page_html):
        block = m.group(1)

        def find(name):
            fm = FIELD_RES[name].search(block)
            return html.unescape(fm.group(1)) if fm else None

        rec_id = find("id")
        title = find("title")
        rel_url = FIELD_RES["url"].search(block)
        if not rec_id or not title or not rel_url:
            continue
        url = LIST_BASE + rel_url.group(1)
        category = find("category")
        region = find("region")
        org_m = ORG_RE.search(block)
        org = html.unescape(org_m.group(1).strip()) if org_m else None
        if not org:
            bm = ORG_BRACKET_RE.match(title)
            org = bm.group(1) if bm else None
        period_m = PERIOD_RE.search(block)
        period = html.unescape(period_m.group(1).strip()) if period_m else None
        s, d = parse_period(period)

        cat_arr = [c.strip() for c in category.split(",") if c.strip()] if category else []
        area_arr = [r.strip() for r in re.split("[,、]", region) if r.strip()] if region else ["全国"]

        items.append({
            "id": url,
            "t": title,
            "o": org,
            "a": area_arr,
            "e": 0,
            "m": None,
            "s": s,
            "d": d,
            "src": "local",
            "u": url,
            "c": cat_arr,
        })
    return items


def scrape_new(existing_ids):
    """Walk pages newest-first. Stop once a page yields zero unseen ids
    (bootstrap case: existing_ids is empty, so this walks everything)."""
    collected = []
    page = 1
    while page <= MAX_PAGES_SAFETY:
        url = (f"{BASE}?category=2&page={page}&sort=publish_date_default"
               f"&period=1&displaysort=DESC&displaycount=30&navitype=is-number")
        page_html = fetch(url)
        items = parse_page(page_html)
        if not items:
            break
        new_on_page = [it for it in items if it["id"] not in existing_ids]
        collected.extend(new_on_page)
        if existing_ids and len(new_on_page) == 0:
            break
        page += 1
    return collected


def main():
    local_path = ROOT / "data" / "local_gov.json"
    national_path = ROOT / "data" / "jgrants_national.json"
    template_path = ROOT / "app_template.html"
    out_path = ROOT / "index.html"
    dataset_path = ROOT / "dataset.json"

    existing = json.loads(local_path.read_text(encoding="utf-8")) if local_path.exists() else []
    existing_by_id = {rec["id"]: rec for rec in existing}

    new_items = scrape_new(set(existing_by_id.keys()))
    for rec in new_items:
        existing_by_id[rec["id"]] = rec

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

    print(f"New local-gov items added: {len(new_items)}")
    print(f"Total local-gov items accumulated: {len(merged_local)}")
    print(f"Total combined dataset size: {len(combined)}")
    print(f"index.html size: {out_path.stat().st_size} bytes")


if __name__ == "__main__":
    main()

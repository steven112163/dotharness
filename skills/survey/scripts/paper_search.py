#!/usr/bin/env python3
"""Fetch paper metadata from arXiv, Semantic Scholar, and OpenReview.

Standard-library only (urllib, xml.etree). Emits a normalized JSON list so the
survey skill cites real retrieved records instead of model recall. Two modes:

    discover  --query "<terms>"   search a source by keyword
    curated   --ids <id,...>      fetch specific papers by arXiv id or DOI

Each record: source, id, title, authors, year, venue, abstract, tldr,
citation_count, influential_citation_count, pdf_url, url. Missing fields are
null so the caller can tell "absent" from "empty".

Semantic Scholar works anonymously; set S2_API_KEY for higher rate limits.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

USER_AGENT = "dotharness-survey/1.0 (https://github.com/; research use)"
ARXIV_API = "http://export.arxiv.org/api/query"
S2_API = "https://api.semanticscholar.org/graph/v1"
OPENREVIEW_API = "https://api2.openreview.net/notes"
CROSSREF_API = "https://api.crossref.org/works"
S2_FIELDS = (
    "title,abstract,year,venue,authors,externalIds,openAccessPdf,url,tldr,"
    "citationCount,influentialCitationCount"
)
ARXIV_NS = {
    "atom": "http://www.w3.org/2005/Atom",
    "arxiv": "http://arxiv.org/schemas/atom",
}


def _get(url, headers=None, timeout=30):
    req = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, **(headers or {})}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _post_json(url, payload, headers=None, timeout=30):
    data = json.dumps(payload).encode()
    hdrs = {
        "User-Agent": USER_AGENT,
        "Content-Type": "application/json",
        **(headers or {}),
    }
    req = urllib.request.Request(url, data=data, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _record(**kw):
    base = dict.fromkeys(
        (
            "source",
            "id",
            "title",
            "authors",
            "year",
            "venue",
            "abstract",
            "tldr",
            "citation_count",
            "influential_citation_count",
            "pdf_url",
            "url",
        )
    )
    base.update(kw)
    return base


# --- arXiv -----------------------------------------------------------------
def _arxiv_entry(entry):
    def text(path):
        node = entry.find(path, ARXIV_NS)
        return node.text.strip() if node is not None and node.text else None

    arxiv_id = (text("atom:id") or "").rsplit("/", 1)[-1] or None
    pdf = None
    for link in entry.findall("atom:link", ARXIV_NS):
        if link.get("title") == "pdf":
            pdf = link.get("href")
    authors = [
        a.text.strip()
        for a in entry.findall("atom:author/atom:name", ARXIV_NS)
        if a.text
    ]
    published = text("atom:published")
    return _record(
        source="arxiv",
        id=arxiv_id,
        title=text("atom:title"),
        authors=authors,
        year=int(published[:4]) if published else None,
        abstract=text("atom:summary"),
        venue=text("arxiv:journal_ref"),
        pdf_url=pdf,
        url=text("atom:id"),
    )


def arxiv_search(query, limit):
    params = {
        "search_query": query,
        "start": 0,
        "max_results": limit,
        "sortBy": "relevance",
        "sortOrder": "descending",
    }
    raw = _get(f"{ARXIV_API}?{urllib.parse.urlencode(params)}")
    root = ET.fromstring(raw)
    return [_arxiv_entry(e) for e in root.findall("atom:entry", ARXIV_NS)]


def arxiv_by_ids(ids, limit):
    params = {"id_list": ",".join(ids), "max_results": max(limit, len(ids))}
    raw = _get(f"{ARXIV_API}?{urllib.parse.urlencode(params)}")
    root = ET.fromstring(raw)
    return [_arxiv_entry(e) for e in root.findall("atom:entry", ARXIV_NS)]


# --- Semantic Scholar ------------------------------------------------------
def _s2_headers():
    key = os.environ.get("S2_API_KEY")
    return {"x-api-key": key} if key else {}


def _s2_record(p):
    ext = p.get("externalIds") or {}
    pdf = (p.get("openAccessPdf") or {}).get("url")
    tldr = (p.get("tldr") or {}).get("text")
    ident = ext.get("DOI") or (
        f"arXiv:{ext['ArXiv']}" if ext.get("ArXiv") else p.get("paperId")
    )
    return _record(
        source="semanticscholar",
        id=ident,
        title=p.get("title"),
        authors=[a.get("name") for a in (p.get("authors") or [])],
        year=p.get("year"),
        venue=p.get("venue") or None,
        abstract=p.get("abstract"),
        tldr=tldr,
        citation_count=p.get("citationCount"),
        influential_citation_count=p.get("influentialCitationCount"),
        pdf_url=pdf,
        url=p.get("url"),
    )


def s2_search(query, limit, year=None):
    params = {"query": query, "limit": min(limit, 100), "fields": S2_FIELDS}
    if year:
        params["year"] = year
    raw = _get(
        f"{S2_API}/paper/search?{urllib.parse.urlencode(params)}", headers=_s2_headers()
    )
    return [_s2_record(p) for p in (json.loads(raw).get("data") or [])]


def s2_by_ids(ids):
    url = f"{S2_API}/paper/batch?{urllib.parse.urlencode({'fields': S2_FIELDS})}"
    raw = _post_json(url, {"ids": ids}, headers=_s2_headers())
    return [_s2_record(p) for p in json.loads(raw) if p]


# --- OpenReview ------------------------------------------------------------
def _or_value(content, field):
    item = (content or {}).get(field)
    if isinstance(item, dict):
        return item.get("value")
    return item


def openreview_venue(venue_id, limit):
    invitation = f"{venue_id}/-/Submission"
    params = {"invitation": invitation, "limit": min(limit, 1000), "offset": 0}
    raw = _get(f"{OPENREVIEW_API}?{urllib.parse.urlencode(params)}")
    notes = json.loads(raw).get("notes") or []
    out = []
    for n in notes:
        c = n.get("content") or {}
        authors = _or_value(c, "authors") or []
        out.append(
            _record(
                source="openreview",
                id=n.get("id"),
                title=_or_value(c, "title"),
                authors=authors if isinstance(authors, list) else [authors],
                abstract=_or_value(c, "abstract"),
                venue=_or_value(c, "venue") or venue_id,
                pdf_url=f"https://openreview.net/pdf?id={n.get('id')}",
                url=f"https://openreview.net/forum?id={n.get('id')}",
            )
        )
    return out


# --- Crossref --------------------------------------------------------------
def _crossref_params():
    mailto = os.environ.get("CROSSREF_MAILTO")
    return {"mailto": mailto} if mailto else {}


def _crossref_record(item):
    title = item.get("title") or [None]
    venue = item.get("container-title") or [None]
    authors = [
        " ".join(p for p in (a.get("given"), a.get("family")) if p)
        for a in (item.get("author") or [])
    ]
    abstract = item.get("abstract")
    if abstract:
        abstract = re.sub(r"<[^>]+>", "", abstract).strip()
    year = None
    parts = (item.get("issued") or {}).get("date-parts") or [[None]]
    if parts and parts[0]:
        year = parts[0][0]
    pdf = None
    for link in item.get("link") or []:
        if link.get("content-type") == "application/pdf":
            pdf = link.get("URL")
            break
    return _record(
        source="crossref",
        id=item.get("DOI"),
        title=title[0],
        authors=authors,
        year=year,
        venue=venue[0],
        abstract=abstract,
        citation_count=item.get("is-referenced-by-count"),
        pdf_url=pdf,
        url=item.get("URL"),
    )


def crossref_search(query, limit):
    params = {"query": query, "rows": min(limit, 100), **_crossref_params()}
    raw = _get(f"{CROSSREF_API}?{urllib.parse.urlencode(params)}")
    items = (json.loads(raw).get("message") or {}).get("items") or []
    return [_crossref_record(i) for i in items]


def crossref_by_ids(ids):
    suffix = urllib.parse.urlencode(_crossref_params())
    out = []
    for doi in ids:
        url = f"{CROSSREF_API}/{urllib.parse.quote(doi)}"
        if suffix:
            url = f"{url}?{suffix}"
        try:
            raw = _get(url)
        except urllib.error.HTTPError as e:
            print(f"crossref: {doi} not found (HTTP {e.code})", file=sys.stderr)
            continue
        item = json.loads(raw).get("message")
        if item:
            out.append(_crossref_record(item))
        time.sleep(0.2)
    return out


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = ap.add_subparsers(dest="mode", required=True)

    d = sub.add_parser("discover", help="search a source by keyword")
    d.add_argument("--query", help="required for arxiv/s2/crossref")
    d.add_argument(
        "--source", default="arxiv", choices=["arxiv", "s2", "openreview", "crossref"]
    )
    d.add_argument("--limit", type=int, default=20)
    d.add_argument("--year", help="S2 only, e.g. 2020- or 2018-2023")
    d.add_argument("--venue", help="OpenReview venue id, e.g. ICLR.cc/2025/Conference")

    c = sub.add_parser("curated", help="fetch specific papers by id")
    c.add_argument("--ids", required=True, help="comma-separated arXiv ids or DOIs")
    c.add_argument("--source", default="s2", choices=["arxiv", "s2", "crossref"])
    c.add_argument("--limit", type=int, default=50)

    args = ap.parse_args()
    try:
        if args.mode == "discover":
            if args.source == "openreview":
                if not args.venue:
                    ap.error("--venue is required for --source openreview")
                records = openreview_venue(args.venue, args.limit)
            else:
                if not args.query:
                    ap.error("--query is required for --source arxiv/s2/crossref")
                if args.source == "arxiv":
                    records = arxiv_search(args.query, args.limit)
                elif args.source == "crossref":
                    records = crossref_search(args.query, args.limit)
                else:
                    records = s2_search(args.query, args.limit, args.year)
        else:
            ids = [i.strip() for i in args.ids.split(",") if i.strip()]
            if args.source == "arxiv":
                records = arxiv_by_ids(ids, args.limit)
            elif args.source == "crossref":
                records = crossref_by_ids(ids)
            else:
                records = s2_by_ids(ids)
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} from {args.source}: {e.reason}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"network error reaching {args.source}: {e.reason}", file=sys.stderr)
        sys.exit(1)

    json.dump(
        {"count": len(records), "records": records},
        sys.stdout,
        indent=2,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")
    time.sleep(0.1)


if __name__ == "__main__":
    main()

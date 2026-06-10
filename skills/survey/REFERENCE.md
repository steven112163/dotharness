# Source API reference

Raw endpoints behind `scripts/paper_search.py`. Use the script first; reach for
these when you need a query shape the script does not cover (citation graph
traversal, reviews, custom filters). All facts verified against official docs;
URLs at the bottom.

## arXiv (Atom API)

- **Endpoint:** `http://export.arxiv.org/api/query` (HTTPS also works).
- **Search:** `search_query` with field prefixes `ti:`, `abs:`, `au:`, `all:`, `cat:`. Boolean `AND`, `OR`, `ANDNOT`. Phrases use URL-encoded quotes (`%22...%22`). Fetch a known id with `id_list=2205.14135`.
- **Paging/sort:** `start`, `max_results` (<=2000, prefer <=1000); `sortBy` = `relevance|lastUpdatedDate|submittedDate`, `sortOrder` = `ascending|descending`.
- **Auth/limits:** none; anonymous. Insert roughly a 3-second delay between successive calls (official guidance).
- **Fields returned (Atom XML):** `title`, `summary` (abstract), `author/name`, `published`, `updated`, `link[title=pdf]`, `arxiv:journal_ref`, `arxiv:doi`, `arxiv:primary_category`. No citation counts.
- **Example:**
  ```bash
  curl 'http://export.arxiv.org/api/query?search_query=abs:%22flash+attention%22+AND+cat:cs.LG&max_results=10&sortBy=submittedDate&sortOrder=descending'
  ```

## Semantic Scholar (Graph API v1)

- **Base:** `https://api.semanticscholar.org/graph/v1`.
- **Relevance search:** `GET /paper/search?query=...&limit=<=100&offset=&fields=...` (ranked, ~1000 result cap).
- **Bulk search:** `GET /paper/search/bulk` (up to 1000/request, cursor via `token`; no inline citation/reference data).
- **Batch details:** `POST /paper/batch?fields=...` with body `{"ids": ["arXiv:2205.14135", "10.1145/3531120", "<paperId>"]}`. Order preserved; nulls for not-found.
- **Filters:** `year=2020-` or `year=2018-2023`, `venue`, `fields` (comma-separated, no spaces).
- **Auth/limits:** anonymous works but the shared pool is aggressively throttled (HTTP 429 is common). A free key (emailed on request) sent as `x-api-key` raises limits to ~1 RPS on search/batch, ~10 RPS elsewhere. The script reads `S2_API_KEY` from the environment. Keys are pruned after ~60 days idle.
- **Useful fields:** `title`, `abstract`, `tldr` (AI summary), `year`, `venue`, `authors`, `externalIds` (DOI, ArXiv), `openAccessPdf`, `url`, `citationCount`, `influentialCitationCount`, `references`, `citations`. Springer abstracts are withheld in the public API.
- **Example:**
  ```bash
  curl -H "x-api-key: $S2_API_KEY" \
    'https://api.semanticscholar.org/graph/v1/paper/search?query=flash+attention&limit=5&fields=title,tldr,citationCount,openAccessPdf,year'
  ```

## Crossref

- **Base:** `https://api.crossref.org/works`.
- **Search:** `GET /works?query=...&rows=<=1000` (default 20). Field-scoped variants exist: `query.bibliographic`, `query.author`, `query.title`.
- **By DOI:** `GET /works/{doi}` — one DOI per call. Covers any registered DOI, including IEEE (`10.1109/...`) and ACM (`10.1145/...`).
- **Auth/limits:** free, no key. Use the "polite pool" by adding `mailto=you@example.com` (a real address) for better rate limits; the script reads `CROSSREF_MAILTO`. Anonymous (public pool) works but is best-effort.
- **Fields returned (`message.items[]`):** `title` (array), `author` (`given`/`family`), `issued.date-parts` (year), `container-title` (venue, array), `abstract` (JATS XML when deposited — many publishers omit it; the script strips tags), `DOI`, `URL`, `is-referenced-by-count` (citation count), `link` (PDF when an open full-text link is registered). No TLDR.
- **Coverage note:** Crossref gives reliable bibliographic metadata and citation counts for paywalled IEEE/ACM papers by DOI, but rarely the abstract or PDF. Pair with arXiv (for a preprint PDF) or Semantic Scholar (for abstract + TLDR) when you need more than the citation.
- **Example:**
  ```bash
  curl 'https://api.crossref.org/works/10.1109/5.726791?mailto=you@example.com'
  curl 'https://api.crossref.org/works?query=composable+kernel+gpu&rows=5'
  ```

## OpenReview (API v2)

- **Base:** `https://api2.openreview.net` (v2 is current; legacy `api.openreview.net` only serves older venues).
- **Submissions for a venue:** `GET /notes?invitation={venueId}/-/Submission&limit=<=1000&offset=`. Example venue id: `ICLR.cc/2025/Conference`. Confirm the submission name from the venue group's `content.submission_name.value` if the default does not match.
- **Reviews:** add `details=replies` to the submission query, then filter each reply by invitation suffix — `Official_Review`, `Meta_Review`, `Decision`, `Rebuttal`. Reviews are the reviewers' critiques, not the authors' claims; weight them accordingly.
- **Status:** filter by `content.venueid` to separate accepted / withdrawn / rejected.
- **Field access (v2):** note content is nested as `content.<field>.value` (e.g. `content.title.value`). The script unwraps this.
- **Auth:** anonymous reads public notes only; many venues make reviews public after decisions. Restricted notes need `Authorization: Bearer <token>` from `POST /login`.
- **Example:**
  ```bash
  curl 'https://api2.openreview.net/notes?invitation=ICLR.cc/2025/Conference/-/Submission&details=replies&limit=50'
  ```

## Sources

- arXiv API user manual — https://info.arxiv.org/help/api/user-manual.html
- Semantic Scholar API docs — https://api.semanticscholar.org/api-docs/
- Semantic Scholar tutorial — https://www.semanticscholar.org/product/api/tutorial
- Crossref REST API docs — https://api.crossref.org/swagger-ui/index.html
- Crossref etiquette / polite pool — https://github.com/CrossRef/rest-api-doc#etiquette
- OpenReview, retrieving notes/reviews — https://docs.openreview.net/how-to-guides/data-retrieval-and-modification/how-to-get-all-notes-for-submissions-reviews-rebuttals-etc
- OpenReview API v2 definition — https://docs.openreview.net/reference/api-v2/openapi-definition

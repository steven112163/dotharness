---
name: survey
argument-hint: "[discover|curated] <topic | paper ids>"
description: Use when surveying academic literature — producing a literature review, related-work synthesis, or comparison of papers on a topic. Triggers include "survey the literature on X", "review papers about Y", "compare these papers", "what's the state of the art in Z". Discovers papers from arXiv/Semantic Scholar/Crossref/OpenReview or works from a supplied set, then synthesizes a grounded full report.
---

# Survey

## Overview

Produce a literature survey grounded in papers actually retrieved, never in model
recall. The skill runs a four-stage pipeline — search, screen, extract,
synthesize — and emits a full report: summary, audit trail, thematic synthesis,
comparison table, per-paper notes, and gaps. Every citation carries a verifiable
identifier (arXiv id or DOI) returned by a source.

The methodology follows Kitchenham's systematic-review phases for *conduct* and
PRISMA's flow counts for the *audit trail*. The non-negotiable rule is citation
discipline: LLMs fabricate references at high rates (GPT-4-class models fabricate
roughly 18-20% of citations and get errors in another ~25-45% of the real ones),
so this skill cites only what the fetch step returned.

## Modes

Select with the first argument; auto-detect if omitted.

- **discover** — given a topic or question, search the sources, screen for
  relevance, then synthesize. Use when the input is a subject ("survey
  long-context attention methods").
- **curated** — given a specific set of papers (arXiv ids, DOIs, or titles),
  fetch their metadata, then extract and synthesize from just those. Use when the
  input is a list the requester already trusts.

Both modes share the extract and synthesize stages; they differ only in how the
paper set is assembled.

## The fetch helper

`scripts/paper_search.py` (stdlib only) is the grounding layer. Always fetch
through it — do not write citations from memory.

```bash
# discover
python3 scripts/paper_search.py discover --source arxiv --query 'all:"flash attention"' --limit 25
python3 scripts/paper_search.py discover --source s2 --query 'long context attention' --year 2022- --limit 50
python3 scripts/paper_search.py discover --source crossref --query 'composable kernel gpu' --limit 50
python3 scripts/paper_search.py discover --source openreview --venue 'ICLR.cc/2025/Conference' --limit 200

# curated
python3 scripts/paper_search.py curated --source s2 --ids 'arXiv:2205.14135,10.1145/3531120'
python3 scripts/paper_search.py curated --source crossref --ids '10.1109/5.726791,10.1145/1327452.1327492'
python3 scripts/paper_search.py curated --source arxiv --ids '2205.14135,2307.08691'
```

Output is JSON: `{count, records[]}` where each record has `source, id, title,
authors, year, venue, abstract, tldr, citation_count, influential_citation_count,
pdf_url, url`. Semantic Scholar throttles the anonymous pool hard (HTTP 429); set
`S2_API_KEY` for reliable runs, or fall back to arXiv/Crossref. See `REFERENCE.md`
for raw endpoints when the script does not cover a query shape (citation-graph
traversal, fetching reviews).

For deeper reading than the abstract, fetch `pdf_url` with WebFetch and quote the
relevant passage.

## Workflow

### 1. Search (discover mode)

Decompose the topic into sub-questions, then query at least two sources to reduce
single-source bias. Combine keyword variants. Retain the raw result set — do not
silently drop records.

Pick sources by what the topic needs:

- **arXiv** — preprints, full PDFs, cutting-edge ML/systems work. Default for recent CS.
- **Semantic Scholar** — abstracts, TLDRs, citation and influential-citation counts. Best for ranking by impact and finding seminal work. Throttled anonymously; set `S2_API_KEY`.
- **Crossref** — bibliographic metadata and citation counts for published venues by DOI, including paywalled IEEE (`10.1109/...`) and ACM (`10.1145/...`). It rarely returns abstracts or PDFs, so pair a Crossref hit with arXiv (preprint PDF) or S2 (abstract) when you need to read past the citation.
- **OpenReview** — submissions plus reviewer critiques for hosted venues (ICLR, NeurIPS). Use when peer-review signal matters.

For curated mode, fetch the supplied ids directly and skip to extraction.

### 2. Screen

Apply explicit inclusion and exclusion criteria derived from the topic (scope,
recency, relevance, peer-review status). Record how many records entered, how many
were removed, and why. This is the PRISMA audit trail and it goes in the report.

### 3. Extract

For each included paper, record into a synthesis matrix (themes as rows, papers as
columns): problem, method, datasets, metrics, headline results, stated
limitations. Read the abstract at minimum; fetch the PDF for any claim you intend
to attribute precisely. A claim must be *entailed* by the cited text, not merely
on the same topic.

### 4. Synthesize

Organize by theme, not by paper — walk across each matrix row, not down each
column. "Paper 1 says…, paper 2 says…" is the failure mode to avoid. Chronological
or methodological organization is acceptable when the literature calls for it
(rapid temporal development, or sharply distinct approaches). Empty matrix cells
are signal: they mark gaps that feed the future-work section.

## Output: full report

Produce these sections in order.

1. **Summary** — 3-5 sentences: scope, how many papers, the main finding.
2. **Method and audit trail** — sources queried, inclusion/exclusion criteria, and
   the counts: found → after dedup → screened out (with reasons) → included.
3. **Thematic synthesis** — the body, grouped by theme, every claim cited inline
   as `(Author, Year, arXiv:id-or-DOI)`. Note agreements, contradictions, and open
   debates across papers.
4. **Comparison table** — one row per paper, columns: Reference (Year), Category,
   Method, Dataset(s), Metrics, Key results, Limitations. Show empty cells rather
   than hiding them; inconsistent reporting across papers is itself a finding.
5. **Gaps and future directions** — what the literature does not yet cover, drawn
   from empty cells and stated limitations.
6. **References** — full list, each with its verifiable identifier and link.

## Citation safeguards

These are mandatory and apply in every mode.

- **Cite only retrieved papers.** If the fetch step did not return it, do not cite
  it. Never reconstruct a reference from memory.
- **Every reference needs a verifiable id** — an arXiv id or DOI present in a
  source record. No bare titles.
- **Entailment, not topicality.** Attribute a claim only when the abstract or a
  fetched passage actually supports it. Quote the span when precision matters.
- **Label the unverifiable.** A claim you believe but cannot ground in a retrieved
  source is marked "unverified," never presented as cited fact.
- **Report retrieval failures.** If a source was throttled or a paper could not be
  fetched, say so in the audit trail rather than papering over the gap.

## Common mistakes

- **Summarizing instead of synthesizing.** Organizing the body paper-by-paper
  defeats the purpose. Group by idea.
- **Trusting parametric recall for citations.** The whole skill exists because that
  fails. Fetch everything.
- **Hiding empty comparison cells.** They are the most useful part — they show gaps.
- **Skipping the audit trail.** Without counts and criteria, the survey is not
  reproducible.
- **One source only.** Single-source surveys inherit that source's coverage bias.

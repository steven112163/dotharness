# [short title]

Date: [YYYY-MM-DD]

Source: [where this plan came from — research findings, grill-me session, council debate, an
issue/ticket, etc. Link or name the sessions/skills involved.]

## Problem

[What's broken, missing, or risky today. Cite exact files/lines where relevant. This is the
"why" — the plan below is the "what/how".]

## Design decisions

[Each significant choice made before implementation, and the reasoning — especially anything
resolved via grill-me/council debate where an alternative was seriously considered and rejected.
Bullet form; one bullet per decision. Note explicit tradeoffs and known limitations accepted
rather than fixed (state why they're acceptable for now).]

## Sequencing

[If the work spans multiple branches/PRs, list them in dependency order and say why the order
matters (what artifact shape one branch produces that the next depends on).]

## Branch/phase breakdown

[One subsection per branch or phase. One item per planned commit/PR. Cite the file(s) each item
touches. Flag open questions explicitly as "open question, not yet confirmed" rather than
asserting an unverified design as settled — resolve these before implementation starts, not
during it.]

## Explicitly out of scope

[What this plan deliberately does not do, and why — so a later reader doesn't re-litigate a
decision that was already made on purpose.]

## Related files

- Implementation notes: `notes/[same-date-slug]-implementation.md` (created when implementation starts)
- Test notes: `notes/[same-date-slug]-test.md` (created when tests are written)

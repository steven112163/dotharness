# Test notes: [short title]

Plan: `plans/[same-date-slug].md`
Implementation notes: `notes/[same-date-slug]-implementation.md`
Date started: [YYYY-MM-DD]

Log entries as tests are written, not retroactively. Capture what was actually verified, not
just what the plan said should be tested — the two often diverge once real edge cases surface.

## [YYYY-MM-DD] — [what's being tested]

- What test(s) were added, with file:line references.
- What each test actually verifies (be specific — "tests the rejection logic" is too vague;
  "asserts a second `run_profile` call targeting a busy server returns `rejected` without
  spawning a subprocess" is useful).
- Any edge case found while writing tests that the plan didn't call out — note it and whether it
  was fixed in the implementation or logged as a follow-up.
- Verification method for any fix claimed as "done": what was reverted/re-applied to confirm the
  test actually catches the regression it's meant to catch (per this repo's own testing
  discipline — a test that passes whether or not the fix exists is not verification).

## Coverage gaps

[What's explicitly not covered and why (out of scope, no test infrastructure for it yet,
deferred) — so a gap reads as a decision, not an oversight.]

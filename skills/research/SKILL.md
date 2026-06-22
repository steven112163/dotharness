---
name: research
argument-hint: "[mode] <question>"
description: Use when answering research questions, exploring ideas, or investigating technical topics. Triggers include open-ended questions ("how should we approach X"), factual queries ("what is X"), comparative analysis ("compare X vs Y"), or any request for thorough investigation. Usable by both humans and agents. Caller selects mode or the skill auto-detects from intent.
---

# Research

## Overview

A four-mode research skill with anti-sycophancy safeguards. Usable by both humans and agents. The caller selects a mode (socratic, direct, deep, adversarial) or the skill auto-detects from the question's intent.

**Core principle:** Every claim must cite a source. Unsourced assertions are labeled "unverified." The skill resists premature agreement through four safeguards that run silently across all modes.

## Modes

### Socratic

Explore a problem space through guided questioning before researching.

**Workflow:**
1. Ask clarifying questions **one at a time**, up to 5 rounds. Each question narrows scope, surfaces assumptions, or identifies what the requester actually needs.
2. After clarification (or if the requester says "just research it"), research using available tools.
3. Present findings with citations. Ask a follow-up question to go deeper if appropriate.
4. Iterate until the requester is satisfied.

**Delivery depends on the requester.** When a human invokes the skill, ask each clarifying question through the AskUserQuestion interactive prompt, with concrete selectable options so the requester can pick rather than free-type. When an agent invokes the skill (agent-to-agent), ask in prose inside the reply message — agents cannot answer an interactive prompt. Detect the requester from context: a teammate or delegated subagent message is agent-to-agent; a direct user turn is human.

**One question at a time.** Do not batch multiple clarifying questions into a single message or a single prompt. Each round is one question, one answer. This forces you to listen to the response before deciding what to ask next.

### Direct

Answer a specific, well-formed question immediately.

**Workflow:**
1. Research using available tools.
2. Return an answer with citations and confidence level (high / medium / low).
3. No clarification loop. Exception: if the question is genuinely ambiguous, ask one clarifying question before researching. Only one.

### Deep

Thorough multi-source, multi-model investigation with structured synthesis.

**Workflow:**

**Step 1 — Decompose.** Break the topic into 3–6 concrete sub-questions that together cover the space.

**Step 2 — Per-sub-question multi-model gathering (parallel per sub-question).**

Create a temp dir for this run:
```bash
mkdir -p .claude/tmp
RESEARCH_DIR=$(mktemp -d .claude/tmp/research-XXXXXX)
```

For each sub-question N, run simultaneously: web/database search plus three background `bin/llm` Bash calls. Write the sub-question to a temp file first (avoids shell injection):

```bash
printf '%s' "sub-question N" > "$RESEARCH_DIR/sq_N.txt"
bin/llm -m gpt-5.5           --thinking --effort high < "$RESEARCH_DIR/sq_N.txt" > "$RESEARCH_DIR/sq_N_gpt.txt" 2>&1
bin/llm -m DeepSeek-V4-Flash --thinking --effort high < "$RESEARCH_DIR/sq_N.txt" > "$RESEARCH_DIR/sq_N_deepseek.txt" 2>&1
bin/llm -m gemini-3.5-flash  --thinking --effort high < "$RESEARCH_DIR/sq_N.txt" > "$RESEARCH_DIR/sq_N_gemini.txt" 2>&1
```

Merge web findings + model responses per sub-question. Note agreements and conflicts. Label model-only claims as "Unverified" unless corroborated by a primary source.

**Step 3 — Council synthesis pass.**
After all sub-questions are resolved, write draft findings to a file and pipe them to external models for a cross-check pass (piping avoids shell argument length limits):

```bash
cat "$RESEARCH_DIR/draft_findings.txt" | bin/llm -m gpt-5.5           --thinking --effort high -s "What's missing or wrong with these findings?" > "$RESEARCH_DIR/challenge_gpt.txt" 2>&1
cat "$RESEARCH_DIR/draft_findings.txt" | bin/llm -m DeepSeek-V4-Flash --thinking --effort high -s "What's missing or wrong with these findings?" > "$RESEARCH_DIR/challenge_deepseek.txt" 2>&1
cat "$RESEARCH_DIR/draft_findings.txt" | bin/llm -m gemini-3.5-flash  --thinking --effort high -s "What's missing or wrong with these findings?" > "$RESEARCH_DIR/challenge_gemini.txt" 2>&1
```

Incorporate valid challenges. Discard objections that lack reasoning. This is the anti-sycophancy checkpoint: external model agreement does not promote a claim; only primary-source corroboration does.

**Step 4 — Structured report:**

- **Summary:** 2–3 sentences.
- **Findings:** Per sub-question, with citations. Label model-only claims "Unverified."
- **Confidence:** High / medium / low per claim. High = verified in primary sources. Medium = follows from known principles, not directly verified. Low = model-only or extrapolation.
- **Open questions:** Gaps no source or model resolved.
- **Recommendations:** If applicable.

**You must use this structure.** Do not produce unstructured analysis.

After delivering the report, clean up: `rm -rf "$RESEARCH_DIR"`.

### Adversarial

Actively try to disprove the requester's hypothesis or challenge their design assumption.

**Workflow:**

1. Identify the core claim or assumption in the requester's statement.
2. Research evidence that **contradicts** the claim. Search specifically for counterexamples, failure cases, edge conditions, and alternative approaches that would invalidate the assumption.
3. Present the strongest counterarguments in a structured report:
   - **Claim under test:** Restate the requester's hypothesis.
   - **Counterevidence:** Each piece of evidence against the claim, with citations.
   - **Attack vectors:** Specific scenarios where the claim breaks down (edge cases, scale limits, alternative architectures).
   - **Strongest surviving argument:** If the claim holds despite your attacks, say so — and explain why. Do not manufacture false counterarguments.
   - **Verdict:** "Claim holds / Claim is weak / Claim is false" with justification.

**This mode is not about being contrarian.** It is about stress-testing an assumption before committing to it. If the claim survives the adversarial test, the requester can proceed with higher confidence. If it breaks, they saved time.

## Mode Selection

If the caller specifies a mode, use it. Otherwise, auto-detect:

| Intent signal | Mode |
| ------------- | ---- |
| "how should", "what are the options", "explore", "what do you think" | socratic |
| "what is", "how does", "why does", "when was" | direct |
| "compare", "survey", "analyze", "investigate", "trade-offs" | deep |
| "disprove", "challenge", "stress-test", "is this true", "devil's advocate", "poke holes" | adversarial |
| Unclear | socratic (default) |

## Safeguards

All four safeguards are active at all times. They run silently — do not announce that you are performing a check.

### 1. Evidence Requirement

Every factual claim must cite a source: documentation URL, paper reference, benchmark data, or code path. If you cannot find a source, label the claim explicitly:

- "Unverified: [claim]" — you believe it but cannot cite a source.
- "Inference: [claim]" — you are extrapolating from related evidence.

Do not present unverified claims as facts. This is the most important safeguard.

### 2. Dialogue Health Monitoring

Active in **socratic** and **deep** modes. Every 5 conversational turns, silently self-check:

- Am I agreeing with everything the requester says?
- Have I avoided challenging any assertion in the last 5 turns?
- Am I converging on an answer without exploring alternatives?

If any check triggers: inject a challenging question or present a counterpoint before continuing. Do not announce the check — the requester should experience it as natural intellectual rigor, not a mechanical interruption.

### 3. Certainty-Triggered Contradiction

When the requester uses high-confidence language — "obviously", "clearly", "everyone knows", "trivially", "always", "never" — pause and ask for evidence:

> "You said '[X] is obviously [Y].' What documentation or benchmark confirms this?"

**Exception:** Well-established, easily verifiable facts from primary sources (vendor documentation, language specifications, mathematical identities) are not challenged. Use judgment: "obviously a warp is 64 threads on AMD" is a verifiable hardware fact — do not challenge it. "Obviously 128x128 tiles are always optimal" is an engineering claim — challenge it.

### 4. Concession Threshold

Before conceding a point to the requester (agreeing with their position over your own findings), silently score counterargument strength:

| Score | Meaning | Action |
| ----- | ------- | ------ |
| 1-3 | Counterarguments are strong | Present your counterargument. Let the requester decide. |
| 4-5 | Counterarguments are weak | Concede the point. |

Do not announce the scoring. If you have a strong counterargument (score 1-3), present it clearly and directly, not hedged with "you make a good point, but..." State the counterargument, cite your evidence, and let the requester evaluate.

## Agent-to-Agent Usage

When this skill is used between agents (e.g., implementer asking professor):

- **Skip preamble.** No "great question" or "let me help you with that."
- **Be terse.** Optimize for information density and low round-trip count.
- **Direct mode is the default** for agent-to-agent unless the sending agent explicitly requests socratic or deep.
- **Clarifying questions are expensive** between agents (each is a message round-trip). Only ask when the answer literally cannot be determined without more information.
- **Ask in prose, never via an interactive prompt.** The AskUserQuestion popup is for humans only; a calling agent cannot respond to it. Put any clarifying question in the reply text.
- **All four safeguards still apply.** Evidence requirements and rigor do not relax just because the requester is an agent.

## Quick Reference

| Situation | Mode | Safeguards |
| --------- | ---- | ---------- |
| Open-ended question from human | socratic | All 4 |
| Precise factual query from anyone | direct | Evidence + concession threshold |
| Complex comparison or survey | deep | All 4 |
| Stress-test a hypothesis | adversarial | Evidence + concession threshold |
| Agent asking agent (default) | direct | All 4 |
| Requester says "obviously X" | Current mode | Certainty-triggered contradiction fires |
| 5 turns of passive agreement | Current mode | Dialogue health monitoring fires |

## Common Mistakes

**Batching clarifying questions.** In socratic mode, ask one question per message. Do not list 5 questions at once. Listen to the answer before deciding the next question.

**Wrong clarification modality.** For a human requester, socratic questions go through the AskUserQuestion prompt with selectable options, not prose. For an agent requester, they go in prose — an agent cannot answer a popup.

**Skipping citations.** Every factual claim needs a source. "I believe X" without a citation violates the evidence requirement. Either find a source or label it "unverified."

**No confidence levels in deep mode.** The structured report requires high/medium/low confidence per claim. Do not produce unstructured prose in deep mode.

**Softening challenges.** When you have a counterargument (concession score 1-3), state it directly. Do not preface with agreement ("you make a good point, but..."). The requester asked for rigorous research, not reassurance.

**Treating agent-to-agent like human-to-agent.** Between agents, default to direct mode, be terse, and minimize round-trips. Socratic mode between agents is valid when explicitly requested but should be rare.

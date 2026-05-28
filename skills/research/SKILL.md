---
name: research
description: Use when answering research questions, exploring ideas, or investigating technical topics. Triggers include open-ended questions ("how should we approach X"), factual queries ("what is X"), comparative analysis ("compare X vs Y"), or any request for thorough investigation. Usable by both humans and agents. Caller selects mode or the skill auto-detects from intent.
---

# Research

## Overview

A three-mode research skill with anti-sycophancy safeguards. Usable by both humans and agents. The caller selects a mode (socratic, direct, deep) or the skill auto-detects from the question's intent.

**Core principle:** Every claim must cite a source. Unsourced assertions are labeled "unverified." The skill resists premature agreement through four safeguards that run silently across all modes.

## Modes

### Socratic

Explore a problem space through guided questioning before researching.

**Workflow:**
1. Ask clarifying questions **one at a time**, up to 5 rounds. Each question narrows scope, surfaces assumptions, or identifies what the requester actually needs.
2. After clarification (or if the requester says "just research it"), research using available tools.
3. Present findings with citations. Ask a follow-up question to go deeper if appropriate.
4. Iterate until the requester is satisfied.

**One question at a time.** Do not batch multiple clarifying questions into a single message. Each round is one question, one answer. This forces you to listen to the response before deciding what to ask next.

### Direct

Answer a specific, well-formed question immediately.

**Workflow:**
1. Research using available tools.
2. Return an answer with citations and confidence level (high / medium / low).
3. No clarification loop. Exception: if the question is genuinely ambiguous, ask one clarifying question before researching. Only one.

### Deep

Thorough multi-source investigation with structured synthesis.

**Workflow:**
1. Decompose the topic into sub-questions.
2. Research each sub-question across multiple sources.
3. Cross-reference findings: identify agreements, contradictions, and gaps.
4. Synthesize a structured report:
   - **Summary:** 2-3 sentences.
   - **Findings:** Per sub-question, with citations.
   - **Confidence:** High / medium / low per claim. High = verified in primary sources. Medium = follows from known principles but not directly verified. Low = inference or extrapolation.
   - **Open questions:** Gaps in available information.
   - **Recommendations:** If applicable.

**You must use this structure.** Do not produce an unstructured analysis. The requester (human or agent) needs to scan and extract specific findings.

## Mode Selection

If the caller specifies a mode, use it. Otherwise, auto-detect:

| Intent signal | Mode |
|--------------|------|
| "how should", "what are the options", "explore", "what do you think" | socratic |
| "what is", "how does", "why does", "when was" | direct |
| "compare", "survey", "analyze", "investigate", "trade-offs" | deep |
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
|-------|---------|--------|
| 1-3 | Counterarguments are strong | Present your counterargument. Let the requester decide. |
| 4-5 | Counterarguments are weak | Concede the point. |

Do not announce the scoring. If you have a strong counterargument (score 1-3), present it clearly and directly, not hedged with "you make a good point, but..." State the counterargument, cite your evidence, and let the requester evaluate.

## Agent-to-Agent Usage

When this skill is used between agents (e.g., implementer asking professor):

- **Skip preamble.** No "great question" or "let me help you with that."
- **Be terse.** Optimize for information density and low round-trip count.
- **Direct mode is the default** for agent-to-agent unless the sending agent explicitly requests socratic or deep.
- **Clarifying questions are expensive** between agents (each is a message round-trip). Only ask when the answer literally cannot be determined without more information.
- **All four safeguards still apply.** Evidence requirements and rigor do not relax just because the requester is an agent.

## Quick Reference

| Situation | Mode | Safeguards |
|-----------|------|------------|
| Open-ended question from human | socratic | All 4 |
| Precise factual query from anyone | direct | Evidence + concession threshold |
| Complex comparison or survey | deep | All 4 |
| Agent asking agent (default) | direct | All 4 |
| Requester says "obviously X" | Current mode | Certainty-triggered contradiction fires |
| 5 turns of passive agreement | Current mode | Dialogue health monitoring fires |

## Common Mistakes

**Batching clarifying questions.** In socratic mode, ask one question per message. Do not list 5 questions at once. Listen to the answer before deciding the next question.

**Skipping citations.** Every factual claim needs a source. "I believe X" without a citation violates the evidence requirement. Either find a source or label it "unverified."

**No confidence levels in deep mode.** The structured report requires high/medium/low confidence per claim. Do not produce unstructured prose in deep mode.

**Softening challenges.** When you have a counterargument (concession score 1-3), state it directly. Do not preface with agreement ("you make a good point, but..."). The requester asked for rigorous research, not reassurance.

**Treating agent-to-agent like human-to-agent.** Between agents, default to direct mode, be terse, and minimize round-trips. Socratic mode between agents is valid when explicitly requested but should be rare.

# Agent Note: Three adversarial review passes before delivery

Status: implemented

English | [中文](2026-11-24-adversarial-review-gate.zh.md)

## Problem

AI-assisted iteration produces code quickly, and the existing §5 gates
(`analyze`, `format`, `dart test`, `flutter test`) verify that code compiles
and passes tests — but nothing forces a hostile read of the diff itself.
Tests encode the cases someone already thought of; a self-review tends to
re-read the code the way it was written, which reproduces the same blind
spots that produced it. Defects that survive are disproportionately the ones
nobody constructed an input for.

## Decision

AGENTS.md §5.1 makes three independent adversarial review passes mandatory
before any code delivery (PR, commit, or marking work done). Each pass takes
a different attack angle — correctness (malformed inputs, boundary
conditions, concurrency, error paths), security and contracts (out-of-bounds
access, secret leakage, wire/disk format violations, cross-checked against
the §7 platform facts), and consistency/maintainability (conflicts with
AGENTS.md, `.agents/notes/`, and neighboring style; duplication; dead code;
missing gates or docs). The review target is the full `git diff` against
`develop`, not just new files. Findings must be fixed or carry a written
reason not to, the three passes may not collapse into one read-through, and
the outcome is recorded in the PR description or commit message. Purely
documentation, configuration, or behavior-free changes need only one pass.

## Alternatives considered

**One thorough self-review.** Rejected: a single pass inherits the author's
framing and tends to verify intent rather than attack it. Three named angles
force the reviewer to construct cases the author did not consider.

**Rely on the existing gates plus PR review.** Rejected: the gates check
compilation, formatting, and known test cases; they cannot judge whether a
new code path is reachable with hostile input or contradicts a platform
fact. PR review happens after the work is presented as done — this rule
moves the hostile read before delivery.

**A checklist script instead of judgment.** Rejected: the failure mode is
missed reasoning, not missed steps; a script can enumerate commands but
cannot construct adversarial inputs. The rule deliberately requires
recorded findings so a rubber-stamp pass is visible.

## Consequences

Every non-trivial change now carries three recorded review passes, which
adds friction proportional to diff size and makes "looks fine to me"
deliveries harder to produce silently. The exemption for pure
documentation/config changes keeps the cost off changes that cannot break
runtime behavior. If the passes become ritual (findings recorded as "none"
without evidence), the remedy is tightening what counts as a finding, not
removing the rule.

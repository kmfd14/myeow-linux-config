# ADRs, RFCs, and when to just ship

Standards: [Nygard ADR](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions), [AWS ADR guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/architectural-decision-records/adr-process.html), staff-level design docs / RFCs for cross-cutting change.

## Pick the artifact

| Situation | Artifact |
| --- | --- |
| Two-way door | Ship. PR description is the record. |
| One-way door, one decision (store, auth vendor, API shape) | **ADR** (one page). Use [assets/adr-template.md](../assets/adr-template.md). |
| Cross-module design with sequence, data model, rollout | **RFC-lite / design doc** (the plan contract in SKILL.md). Still extract one ADR for the core decision. |
| Incident | Timeline + fix. ADR only if the fix changes architecture. |

## ADR rules

- **Immutable once accepted.** Reverse by writing a new ADR that supersedes the old one. History is the value.
- **Imperative decision.** “We will use Postgres as the notifications store.” Not “we should consider.”
- **Context includes alternatives.** An ADR without rejected options is a press release.
- **Consequences include the pain.** Ops load, lock-in, scaling ceiling, what we postponed.
- Status: `Proposed` → `Accepted` (user/team agrees) → `Superseded by ADR-NNN` / `Deprecated`.

## RFC-lite sections (if the plan is the RFC)

Match the skill output contract. Staff-level extras only when they change the decision:

- Non-goals
- Public contracts (API, events, schema)
- Rollout, rollback, monitoring
- Open questions with owners

Do not write a 20-page design doc for a table and an endpoint.

## Review culture

- Ask, don’t tell: “What happens when the IdP cert expires?” beats “add monitoring.”
- Blocking vs later: only one-way-door gaps block.
- If reviewers disagree, record the dissent in the ADR consequences — do not silently pick the loudest title.

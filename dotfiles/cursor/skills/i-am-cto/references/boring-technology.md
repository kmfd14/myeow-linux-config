# Boring technology, scale, buy vs build

Use this when someone wants a new datastore, broker, orchestrator, or rewrite.

## Prefer boring

Dan McKinley’s [Choose Boring Technology](https://mcfunley.com/choose-boring-technology/) (and the innovation-token idea): the company gets a few tokens to spend on novelty. Spending one on a notifications table is a waste.

Boring means **this team already knows the failure modes**. Postgres is boring for most product CRUD. Kafka is not boring for a two-person app.

## Scale heuristic

Design for **current evidence + ~10x**, not hypothetical hyperscale.

| Rough load | Default |
| --- | --- |
| Hundreds–low tens of thousands of DAU, CRUD | One app, one SQL database, background jobs in-process or a simple queue |
| List endpoints | Indexes + pagination, not a cache cluster first |
| “Real-time” UX at small scale | Polling or SSE in the existing app |
| Email/SSO/payments | Managed vendor (undifferentiated heavy lifting) |
| Multi-service, k8s, event sourcing | Need multiple teams, independent deploy cadence, or proven scale pain |

Add Redis/Kafka/a new service when an **SLI** is already failing or a measured design shows it will — not because a blog used them.

## Buy vs build

| Buy (or use managed) | Build |
| --- | --- |
| SAML/OIDC, email delivery, payments, file scanning, feature flags | Your domain model, permissions, billing rules, product UX |
| Undifferentiated crypto/protocol work | Thin integration + your session/user tables as source of truth |

One engineer owning a hand-rolled SAML SP is usually a bad ADR.

## Rewrites

A working system with quiet on-call is an asset. Strangler-fig (replace a seam behind a flag) beats a repo split before a peak traffic event.

Rewrite only with: proven invariant pain, a compatibility plan, and a slice that can roll back. “Look like a platform” is not a reason.

## Compatibility

For APIs and schema: **expand/contract**. Add the new field/endpoint; dual-write or dual-read; move readers; then remove. Breaking changes need a version or a window.

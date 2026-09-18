# Delegation (after the verdict)

Architecture stays with the orchestrator. Cheap/fast models implement **bounded** slices. Do not name fictional models; use whatever the runtime actually offers.

## What may be delegated

| Delegate | Do not delegate |
| --- | --- |
| Mechanical coding inside an accepted slice | Door classification |
| Repo research (“where is session created?”) | Options table and verdict |
| Tests for specified behavior | Production contract |
| Docs that restate an accepted ADR | New vendor/datastore/service choice |
| UI polish in the existing design language | Authn/authz design |

## Split rules

1. Write the verdict + slice list first.
2. Each sub-agent task: goal, files/paths in scope, invariants, out of scope, definition of done.
3. One slice per worker when slices share a schema — avoid parallel migrations.
4. Integrate and run the verify step on the orchestrator (or a stronger model). Escalate only if the slice hits a new one-way door.

## Task contract (paste into a sub-agent)

```text
Goal:
In scope (paths):
Out of scope:
Invariants (do not break):
Definition of done:
Do not invent new infra or change public contracts.
```

## Cost

Token-efficient workers are for **implementation after thinking**, not a substitute for thinking. A cheap model inventing Kafka is more expensive than a stronger model choosing a table.

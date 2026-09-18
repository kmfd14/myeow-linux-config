# Quality attributes (score the job, not the stack)

Use this when filling the options table. Do not score every row every time. Pick 4–7 attributes that can kill the job, plus **operability** and **reversibility** always.

Industry maps: [ISO/IEC 25010](https://iso25000.com/index.php/en/iso-25000-standards/iso-25010) product quality, [AWS Well-Architected](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html) pillars, [DORA four keys](https://dora.dev/guides/dora-metrics-four-keys/) for delivery health.

## Attribute set

| Attribute | Question | Cheap signal |
| --- | --- | --- |
| **Functional fit** | Does it complete the job and non-goals? | User path exists end-to-end |
| **Reversibility** | Hours vs weeks to undo? Data leftover? | Feature flag, droppable table, dual-write |
| **Operability** | Can this team run it at 3am with current tools? | One deployable vs many; runbook exists |
| **Security** | Authn/authz, trust boundaries, secrets, abuse | Threat model for new surface |
| **Reliability** | Failure modes, blast radius, rollback | Idempotency, timeouts, retries with jitter |
| **Performance efficiency** | Latency/throughput at *stated* scale + ~10x | Query plans, N+1, payload size |
| **Cost** | Build days + vendor $ + on-call load | New class of infra is a cost |
| **Maintainability** | Matches this repo; bus factor | New language/framework is a cost |
| **Compatibility** | Breaks API/schema/clients? | Expand/contract migrations |
| **Usability** | Steps to the job; empty/error; a11y | Count clicks; keyboard; contrast |
| **Compliance / privacy** | PII, retention, residency, audit | Data inventory for new stores |
| **Delivery health** | Helps or hurts DORA (lead time, fail rate, restore) | Big-bang rewrite hurts all four |

Well-Architected check (only for cloud/infra decisions): operational excellence, security, reliability, performance efficiency, cost optimization, sustainability. Same idea — pillars are questions, not a mandate to adopt AWS services.

## How to score

Use **High / Med / Low** fit for *this* context, not absolute goodness.

- A Kafka pipeline can score High reliability at 100k events/s and **Low** operability for a two-person team at 2k DAU.
- “High scale” without a number is not a score. Use the evidence pack (DAU, QPS, row counts, p95).
- If two options tie on fit, pick the more reversible one.

## DORA — do not weaponize

Use the four keys as a **system** health lens: deployment frequency, lead time for changes, change failure rate, time to restore. Do not set them as individual targets for a one-off feature. Prefer options that keep changes small and restorably fast.

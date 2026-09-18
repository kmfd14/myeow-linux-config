# Threat model (STRIDE-lite)

Use this for one-way doors that touch **auth, public HTTP, tenancy, PII, payments, or file upload**. Do not paste a generic OWASP list.

Method: data-flow + [STRIDE](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) on each trust boundary. Security floor: [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/) L1 for internet-facing apps.

## 1. Draw the flow (text is enough)

Name: actors, processes, stores, external systems, trust boundaries.

```text
Browser --TLS--> App --SQL--> Postgres
                App --HTTPS--> Email/IdP/Payments vendor
```

Mark what is secret (session, API keys, tokens) and what is PII.

## 2. STRIDE each boundary

| Threat | Question | Default control |
| --- | --- | --- |
| **S**poofing | Who is this caller? | Verified session/token; no secrets in query strings or logs |
| **T**ampering | Can they change the payload or cookie? | Integrity (signed cookies/JWT iss+aud, parameterized SQL) |
| **R**epudiation | Can we prove who did what? | Audit log on authz and data export |
| **I**nformation disclosure | What leaks if this row/endpoint is public? | Allowlisted fields; tenant checks on every read |
| **D**enial of service | What is unbounded? | Pagination, rate limit, max body, timeouts |
| **E**levation of privilege | Can member become admin / tenant A read tenant B? | Explicit authz on resource+tenant, not just “logged in” |

## 3. Minimum for a new public surface

Ship with the surface, not “next quarter”:

- Authn on every non-public route; authz on every resource (IDOR check)
- Secrets in env/secret manager; never in git or client bundles
- Parameterized queries / safe ORM; output encoding for HTML
- Rate limits on auth and list endpoints
- Pagination and field allowlists on list APIs
- CSRF plan for cookie sessions; `HttpOnly; Secure; SameSite` cookies
- File uploads: type/size allowlist, stored outside web root

## 4. What not to do

- “Add helmet and call it done”
- JWT in query string or localStorage as the only store without an XSS story
- `SELECT *` dumps of a contacts/users table to a partner
- Skipping tenant predicates because the ID looks unguessable

If the change is local UI with no new trust boundary, write `Threat model: N/A — no new boundary` and move on.

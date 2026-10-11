# Official requirements and milestone traceability

Source of truth: the supplied Cognizant FinTech Payment Fraud Detection PDF.
Implementation sequence: the user's pasted five-milestone instructions; the
build guide supplies examples, not proof of implementation. On 11 October 2026
the user narrowed current work to the initial part, deferring Docker/DB/MailHog.

Statuses below describe implementation scope. PASS must be supported by the
actual milestone evidence, not by file existence. Future-stage items are PENDING.

| Official functional requirement | Intended implementation files | Current scope / required evidence |
|---|---|---|
| F1 HTTP POST, RAML, APIkit, schema validation | `src/main/mule/payment-events-api.xml`, `resources/api/*` | M1: HTTP suite validates 202/400 and real routing; see milestone report |
| F2 Amount, geography, velocity, merchant, usual hours in DW; editable thresholds without redeploy | `resources/modules/RiskRules.dwl`, `config-dev.yaml`, future runtime rule source | Initial DW module exists; rule tests run in Mule. Live velocity, DB hours and hot configuration are PENDING M2 |
| F3 Score and LOW/MEDIUM/HIGH configurable bands | `RiskRules.dwl`, `global-config.xml` | M1: scoring/band unit tests; boundaries 29/30/59/60/100 |
| F4 Per-card velocity counter and configurable TTL | future velocity subflow, Object Store | PENDING M2; initial count is explicitly 1, not a live counter |
| F5 HIGH priority queue, LOW/MEDIUM standard | `payment-events-api.xml`, `global-config.xml` | M1 queue selection; real HIGH consume test. No HIGH fallback. Strict scheduling precedence unproven |
| F6 Async consumers, DB enrichment, APPROVE/REVIEW/BLOCK | future scoring consumer, `RiskRules.dwl` | PENDING M2; only pure decision function is unit tested |
| F7 Every scored event + individual triggered rules in MySQL | `resources/sql/schema.sql`, future persistence flow | PENDING M3; schema prepared, no persistence implemented |
| F8 Immediate email for HIGH or BLOCK, masked card, amount, merchant, rules, score | future alerting flow/templates | PENDING M3; agreed alert latency must be recorded and measured |
| F9 Per-card throttle, single aggregate lists all transactions | future alerting and throttle Object Store | PENDING M3; recovery and expired-window flush required |
| F10 No PAN in logs, DB, email; retain last four | `Masking.dwl`, API schema, `log4j2.xml`, future consumers | M1: schema and recursive PAN guard; log/API evidence required. DB/email PENDING |
| F11 Global errors, transient DB/SMTP retries, original masked payload + reason in DLQ | `global-config.xml`, future consumer/DLQ flows | Intake error handling and publish retries M1; DB/SMTP/DLQ PENDING M3/M4 |
| F12 Correlation end-to-end, DLQ depth and HIGH spike alerts | intake envelope/logs, future monitors | Correlation intake-to-queue M1; consumers/alerts/monitors PENDING |
| F13 MUnit rule isolation, band boundaries, throttle, DB/SMTP mocks | `src/test/munit/*` | Rule and intake suites M1; throttle and external dependency mocks PENDING M4 |

| Official negative scenario | Verification / status |
|---|---|
| N1 Malformed, missing required fields, negative amount, unsupported currency | M1 HTTP suite; also add table-driven missing-field variants |
| N2 Duplicate ID, no double scoring/rows/email | M1 real Object Store returns 409; DB/email dedup PENDING |
| N3 Queue unavailable, configurable retries, no false acceptance | M1 injected VM timeout: 503, four attempts, reservation absent afterward |
| N4 Priority misrouting explicitly asserted/logged | M1 selected HIGH queue tested; consumer assertion PENDING M2 |
| N5 Scoring failure routes REVIEW, never APPROVE | DW finalize fail-safe unit test; consumer behavior PENDING |
| N6 Missing customer defaults and records incomplete enrichment | PENDING M2 |
| N7 DB timeout retries and unacknowledged/redelivered message | PENDING M4; transactional VM handling needs validation |
| N8 SMTP retries then durable pending status | PENDING M3/M4 |
| N9 Burst mail throttle, aggregate includes every transaction | PENDING M3/M4 |
| N10 No PAN or restricted data in logs/responses/emails | M1 rejection tests; log search and deferred DB/email inspection |
| N11 Unexpected error, consistent code/correlation, no internals | M1 global safe 500 handler; add forced-error integration verification |
| N12 Additional negatives | PAN in other string fields/unknown fields tested M1; concurrent duplicates, ambiguous publish, restart, DLQ failure, email/status race PENDING M4 |

| Official acceptance criterion | Current status / planned evidence |
|---|---|
| A1 Valid event accepted, scored, queued; score/band/correlation response | Initial HTTP/VM suite; status in milestone report |
| A2 Amount + geography gives HIGH and priority routing | Sample score 82, three hit codes, real HIGH queue test |
| A3 Every event persisted with one child row per rule | PENDING M3; SQL queries, LOW event with zero hits, redelivery tests |
| A4 HIGH mail within agreed time lists all rules | PENDING M3; SMTP receipt and latency evidence |
| A5 Repeated events give aggregate rather than mail flooding | PENDING M3; burst and aggregate membership evidence |
| A6 No unmasked PAN anywhere | Partial M1 API/queue/logs; DB/email PENDING |
| A7 DB stopped then recovered, messages redelivered | PENDING M4; outage and recovery evidence |
| A8 Isolated rules and boundaries, mocked dependencies | Partial M1 rules; final consumer/throttle/DB/SMTP tests PENDING |
| A9 Anypoint runtime deployed, autodiscovery and policies | PENDING M5; no deployment attempted |

| Official technical standard | Scope / evidence needed |
|---|---|
| T1 High-level design | Initial architecture documented in README; final HLD PENDING M5 |
| T2 API-led architecture | RAML intake/process/system flow layers in intended design; full integration PENDING |
| T3 Global error handling | `global-config.xml`; validate all branches in M4 |
| T4 RAML + APIkit | Intake contract/router and HTTP suite M1 |
| T5 MUnit 100% component coverage or valid reasons | Actual M1 report only; full quality gate M4 |
| T6 Autodiscovery | PENDING M5, requires API Manager ID and account |
| T7 External properties, secure properties, DWL | Config/module files; AES/CBC key supplied externally, encrypted local YAML ignored |
| T8 Appropriate logging | Structured correlation/routing/error messages; no raw payload logging |
| T9 Performance/security policies | PENDING M5 |
| T10 Private/subflows | Dedupe, config, scoring and publication subflows M1 |
| T11 Core processors where needed | Choice, transform, until-successful used in intake |
| T12 Domain app for Studio | PENDING; retain separate local/domain vs CloudHub packaging |
| T13 Basic logging, monitoring, alerts | Logging M1; operational alerts PENDING M3 |
| T14 Git and team workflow | Local repo M1; remote/team clone/PR/conflict practice PENDING M5 |
| T15 Batch/cache/Object Store where required | Dedupe store M1; velocity/throttle PENDING. No unnecessary batch component |
| T16 Standard component names | Named configs/subflows/processors; final review M4 |

Hackathon guidelines: five-calendar-day deadline starts when requirements are
communicated (date not supplied); runnable source and MUnit on every team laptop
must be demonstrated; cloud runtime is preferred but local fallback scores lower.
The guide's optional-deployment wording does not mark official A9 satisfied.

## Corrections and reliability risks identified in the build guide

- YAML `${...}`/`p(...)` externalization is not hot reload. F2's no-redeployment
  threshold requirement needs a runtime source and behavior test in M2.
- More consumers on HIGH do not establish strict global ordering across queues.
- HIGH-to-standard fallback weakens official priority routing. Initial intake
  returns 503 when the selected queue cannot confirm publication.
- A failed publish may have an ambiguous outcome; dedupe alone cannot eliminate
  duplicate queue deliveries. Consumer persistence must use event-ID uniqueness.
- `on-error-continue` after failed requeue/DLQ publish can discard a message.
  Masked error logs are not durable DB/DLQ delivery evidence. Do not copy that
  later guide pattern without a transactional/durable recovery design.
- Per-key Object Store operations are atomic; a retrieve/modify/store sequence
  is not atomic as a group. Live velocity and throttle need serialization or
  locking, including consumers, schedulers, reconcilers and runtime replicas.
- Throttle TTL must not expire unsent aggregate membership. Status/reconcile
  races can cause duplicate alerts; SMTP acceptance is not recipient delivery.
- VM persistent queues are unavailable on CloudHub 2.0 and Runtime Fabric.
  Deployment target must support the chosen mandatory VM architecture.

References: [VM connector](https://docs.mulesoft.com/vm-connector/latest/),
[Object Store atomic operations](https://docs.mulesoft.com/object-store-connector/latest/object-store-connector-reference),
[Configuration properties](https://docs.mulesoft.com/mule-runtime/latest/configuring-properties).

# Milestone 2 - scoring and asynchronous priority processing

Implemented and validated locally on 11 October 2026 (Asia/Calcutta), on branch
`feature/milestone-2`, starting from Milestone 1 commit `802dd7a`.
Live Docker/MySQL/MailHog execution remains deferred as previously requested.

## Files and implemented behavior

| New/changed files | Result |
|---|---|
| `velocity.xml`, `modules/Velocity.dwl`, intake flow | Per-card Object Store history, explicit epoch seconds, rolling-window filtering and distinct event IDs. Intake's single-concurrency source serializes the whole read/modify/write sequence |
| `modules/RiskConfig.dwl`, global config, `examples/risk-policy.json`, file connector dependency | Validated external JSON policy reread per intake; thresholds/weights/categories/bands can change without redeployment. Overridden keys are removed before merging to prevent duplicate-key validation ambiguity |
| `modules/RiskRules.dwl` | All five mandatory rules plus watchlist, capped score, bands, overnight usual-hour ranges and scoring-failure REVIEW. System failure rule hits are deduplicated |
| `scoring-consumer.xml`, `modules/CustomerProfile.dwl` | HIGH/standard listeners (8/4 consumers), MySQL profile lookup, safe profile normalization, incomplete-enrichment REVIEW, APPROVE/REVIEW/BLOCK and explicit HIGH misroute recovery |
| `global-config.xml`, `config-dev.yaml`, `mule-artifact.json` | MySQL connector, decision queue, configurable consumer activation, TTL sweep and registered new flows |
| `src/test/munit/milestone-2-test-suite.xml` and existing suites | 20 new tests, original 29 retained; explicit DB mock target variables and queue cleanup prevent test interference |
| Evidence scripts, README, requirements checklist | Milestone-specific evidence output preserves the historical Milestone 1 reports and documents setup/limits |

The consumer publishes a finalized envelope to the persistent
`payments-decisions-q` for Milestone 3. It includes the original event and intake
scoring, validated policy snapshot, database profile, final score/band/decision,
rule hits, correlation ID, enrichment flag and alert-required flag. Any intake
HIGH, final HIGH or BLOCK keeps `alertRequired=true` for later alert handling.
This is an actual queue handoff, not a placeholder persistence flow.

Consumer input and next VM publication share a local VM transaction. The MySQL
read explicitly runs outside it. Exceptions propagate through the consumer error
handler, rolling back consumption. Publish retries are bounded at one initial
attempt plus three retries. DB lookup also uses three retries; after exhaustion,
the input transaction rolls back. HIGH on standard is logged and rerouted to HIGH
before profile lookup. Poison-message classification/DLQ handling is still M4.

## Actual validation

`./scripts/maven.ps1 test` finished with **BUILD SUCCESS at 16:11:39 IST**.
**49 tests passed, zero failures, zero errors, zero skipped** on Mule EE 4.12.0,
Studio Java 17.0.12 and MUnit 3.7.3. Every original Milestone 1 test name appears
in the successful result. The earlier failures were fixed and rerun; they are
not counted as passing evidence.

| Requirement/check | Actual result |
|---|---|
| Prior intake contracts | PASS: original 202/400/409/503 cases; sample score 82 HIGH; real HIGH and standard queue publication; duplicate key retained and only one publication; response correlation header also asserted |
| Five mandatory rules, positive and negative | PASS: isolated amount/geo/velocity/merchant/hour tests, watchlist positive/negative and overnight hours |
| Aggregation/capping/bands | PASS: score capped at 100; 29/30/31 and 59/60/61 boundaries plus 100 |
| Live velocity state | PASS: real Object Store, card isolation, same-event retry does not increment, expired timestamps removed |
| Object Store physical TTL | PASS: configured 2-second TTL and 1-second sweep in tests, polling verifies key disappearance. Normal development values remain 300/5 seconds |
| Threshold edits without redeployment | PASS: two real HTTP requests in the same running app; file edit changes amount score from 0 to 35 |
| Invalid live policy | PASS: invalid band ordering returns HTTP 503, zero VM publications. Categories are normalized case-insensitively |
| Async HIGH consumer | PASS: actual VM listener with mocked MySQL consumes an event and publishes score 82 / REVIEW with original identifiers |
| Async standard consumer | PASS: actual VM listener with mocked MySQL publishes APPROVE and preserves standard source queue/correlation |
| MySQL profile mapping / decisions | PASS WITH MOCKS: APPROVE at LOW, REVIEW at MEDIUM, WATCHLIST sample 92 / BLOCK; SQL connector itself is mocked |
| Missing/invalid profile | PASS WITH MOCKS: default profile, `enrichmentIncomplete=true`, REVIEW; no silent approval |
| Scoring failure | PASS: malformed timestamp inside scoring returns a fail-safe intake score, then finalizes as REVIEW; exactly one SYS_SCORING_FAILURE hit |
| Priority misroute | PASS: HIGH on standard causes one HIGH publish and zero DB lookups, using mocked publish to inspect routing |
| DB outage rollback | PASS WITH MOCKED DB: four failed selects; the real VM consume is rolled back and the event is consumed again from the queue |
| Milestone 1 queued-envelope compatibility | PASS: envelope without a policy snapshot loads configuration and finalizes successfully |
| XML/schema/flow consistency | PASS: 11 XML files, sample and 11 invalid schema cases, flow/config references |
| Package | PASS: `package -DskipMunitTests`, BUILD SUCCESS at 16:09:09 IST, application JAR produced. Application source did not change after packaging; three additional tests subsequently passed |

Evidence is under `verification/milestone-2`: `munit-results.json`,
`milestone-2-test.log`, `milestone-2-package.log`, `static-checks.json` and
`coverage/summary.html`. The export checks that original regression tests are
present and that logs contain neither local keys/passwords nor the tested PAN.

Coverage is **90.14%: 64 of 71 processors**, across four Mule configuration
resources. Seven remaining processors are identified in the JSON report:

- `global-config.xml`: routing-error logger/body (92/93), unexpected-error logger/body (140/141).
- `payment-events-api.xml`: dedupe-release-failure logger (82).
- `velocity.xml`: Object Store failure-to-503 translation (19).
- `scoring-consumer.xml`: unsafe queue-envelope rejection (33).

These need further negative injections in M4; they are testable, so no claim is
made that 100% coverage is impossible. Pure DataWeave functions are tested but
are not separate processors in this coverage measurement.

## Run and verify without breaking the existing intake

The normal default remains `consumer.initialState=stopped`, and `risk.policyFile`
is empty. Existing Studio import, Java 17, key and POST instructions continue to
work without MySQL/SMTP. Velocity now tracks actual distinct card events.

To use a live policy, copy `examples/risk-policy.json` to an external writable
path and set `-M-Drisk.policyFile=<absolute path>` in the Mule VM arguments. Edit
that file atomically, then submit a new event ID. A malformed file returns 503;
no invalid rules are silently applied. An accepted event keeps its policy
snapshot, protecting it from later rule changes. Velocity TTL/window and other
connector YAML settings remain startup properties.

After live MySQL setup is authorized and `customer_risk_profile` is available,
add `-M-Dconsumer.initialState=started`. The listeners then consume HIGH/standard
queues and park decisions for the next milestone. Do not drain that queue or
clear runtime data to fix an error. No SMTP service is needed for M2.

CLI regression: `./scripts/maven.ps1 test`. Package:
`./scripts/maven.ps1 package -DskipMunitTests`. Evidence export:
`python scripts/export-test-evidence.py --milestone 2`. Static checks:
`python scripts/verify-static.py --output-dir verification/milestone-2`.
The tests use their own rule file and override consumer state/TTL inside MUnit;
they do not enable consumers in the normal app configuration.

## Pending, blocked and next milestone

Live MySQL connectivity, actual SQL execution, Studio GUI activation and a real
database stop/recovery test are **NOT VERIFIED**. Database responses were mocked.
No Docker, DB or MailHog service was started. This remains the M2 environment
validation limitation, rather than a fabricated completed dependency check.

Single-instance intake serialization is proven by design/tests; multi-worker
Object Store coordination and load latency are not established. Two queues with
8/4 consumers do not imply strict ordering across all workers. VM restart/crash
durability and deployment-target support require later testing. Publish timeouts
can have ambiguous outcomes; M3 must persist idempotently by event ID. Duplicate
queue deliveries remain possible after TTL or rollback. No no-message-loss or
exactly-once guarantee is claimed from retries or one rollback test.

Persistent decisions wait for M3, which will implement parent/child database
transactions, idempotent redelivery and alert outbox/throttling. SMTP/email, DLQ,
monitoring, API Manager and deployment have not been implemented in M2. Poison
events currently roll back repeatedly; M4 must classify them and route them to a
durable DLQ without swallowing publish failures. The existing branch and M1
commit are preserved; unrelated Studio metadata files were not modified.

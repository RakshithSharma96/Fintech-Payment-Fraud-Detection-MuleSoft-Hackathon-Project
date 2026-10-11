# Initial foundation and intake - milestone report

Date: 11 October 2026, Asia/Calcutta. Current scope follows the user's instruction
to finish the initial part and handle Docker, DB and MailHog later.

## Implemented files and behavior

| Files created | Purpose |
|---|---|
| `pom.xml`, `mule-artifact.json`, `.project`, `.classpath` | Mule 4.12.0 EE / Java 17 Studio application; HTTP, APIkit, VM 2.0.2, Object Store, Secure Properties, MySQL, Email and MUnit dependencies |
| `src/main/mule/global-config.xml` | HTTP/APIkit, separate persistent VM queues, Object Stores, risk configuration and safe global HTTP errors |
| `src/main/mule/payment-events-api.xml` | Intake validation, PAN guard, dedupe ownership, scoring, priority routing, bounded publication retries and acceptance response |
| `src/main/resources/api/payment-events-api.raml`, `api/schemas/payment-event.json` | API contract and strict request shape, supported currencies/channels, positive amount, masked card pattern, no unknown fields |
| `src/main/resources/modules/RiskRules.dwl` | Configurable rules, capped aggregation, LOW/MEDIUM/HIGH bands and pure decision/fail-safe functions |
| `src/main/resources/modules/Masking.dwl`, `ErrorResponse.dwl` | Masking, recursive PAN detection, consistent safe responses |
| `config-dev.yaml`, `log4j2.xml` | External development configuration and structured logs with redaction |
| `src/test/munit/fraud-rules-test-suite.xml`, `intake-http-test-suite.xml`, `src/test/resources/payment-event.json` | Real Mule rule tests and real HTTP/APIkit/Object Store/VM tests |
| `examples/payment-event.json` | Official sample for a manual POST |
| `scripts/maven.ps1`, `setup-local.ps1`, `verify-static.py`, `export-test-evidence.py`, `requirements-dev.txt` | Java 17/Maven selection, ignored local secrets, static checks, non-secret evidence export |
| `compose.yaml`, `src/main/resources/sql/schema.sql` | Prepared only for deferred database/mail setup; not executed |
| `.gitignore`, `README.md`, `docs/requirements.md`, `verification/*` | Secret exclusions, run instructions, full official checklist and actual evidence |

Ignored local files were also created: `.env`, `.local/secure.key` and encrypted
`src/main/resources/secure-dev.yaml`. Their contents are not in source control.
Secure Properties uses AES/CBC and an externally supplied key. No DB connection
or email connection is initialized in this milestone.

The initial intake scores the official sample as 82 (35 amount + 30 geography +
17 merchant category), selects `payments-high-q`, and returns 202 only after
VM publication completes. A LOW sample scores 0 and reaches `payments-std-q`.
Duplicate reservations use atomic Object Store `failIfPresent`; HTTP 409 does not
release a previously accepted event's reservation. Failure before publication
releases only the current request's reservation. HIGH publication failure returns
503 rather than falling back to standard.

## Validation actually performed

`./scripts/maven.ps1 test` completed with BUILD SUCCESS at
14:01:22 IST on 11 October 2026, using Mule EE 4.12.0, Java 17.0.12 and MUnit 3.7.3.
All **29 tests passed, 0 failures, 0 errors, 0 skipped**. The tests execute the
actual Mule application in the embedded runtime; the HTTP source is enabled.
Successful queue tests use real VM publication and consumption. The failure test
injects a VM timeout and verifies four calls (one attempt plus three retries).

| Initial requirement / validation | Result and evidence |
|---|---|
| RAML/APIkit startup and contract validation | PASS in embedded Mule; schema loaded and HTTP listener invoked |
| Official sample accepted with score/band/status | PASS: HTTP 202, 82, HIGH, body correlation ID; HIGH queue envelope checked |
| LOW event reaches standard queue | PASS: HTTP 202, score 0, LOW from consumed standard envelope |
| Malformed JSON, missing identifiers/amount/currency/card token/merchant/channel | PASS: HTTP 400 in individual tests |
| Negative amount and unsupported currency | PASS: HTTP 400 |
| Repeated event ID | PASS: real Object Store returns HTTP 409; later DB/email deduplication is deferred |
| Correlation propagation | PASS: response body and real VM envelope carry `intake-test-corr`; same ID in application logs. Header is configured, but a dedicated header assertion is not included |
| No false success on publish failure | PASS: HTTP 503, four publish attempts, Object Store reservation absent afterward |
| Full PAN in masked field, customer free text or unknown field | PASS: HTTP 400; safe error body does not echo the tested digits |
| Rule isolation, boundaries, sample 82, pure fail-safe, masking | PASS: 12 rule-level tests in Mule |
| Static XML, schema and flow references | PASS: 8 XML files, official sample, 11 invalid schema cases, no missing flow/config references |
| Secret exclusions | PASS: Git ignores `.env`, `.local`, encrypted local YAML and `target` |
| Full application package | PASS: `package -DskipMunitTests`, BUILD SUCCESS at 14:02:21 IST; `target/payment-fraud-detection-1.0.0-mule-application.jar` created |
| Studio GUI Run As > Mule Application | NOT VERIFIED; exact manual steps are in README |
| MySQL schema execution, Docker/MailHog startup | DEFERRED by user; not represented as passing |

Evidence: `verification/munit-results.json`, `milestone-1-test.log`,
`milestone-1-package.log`, `static-checks.json`, and `verification/coverage/summary.html`.
The exported final build log was checked for the local key/passwords and the
raw PAN used in negative tests; none were found. Earlier failed diagnostic runs
remain only in ignored `.local` and are not presented as final evidence.

## Coverage and limits

The actual coverage report is **82.50%: 33 of 40 processors, across 8 flows in
2 resources**. It is not a 100% coverage claim. The seven uncovered components:

- `global-config.xml`, lines 81/82: non-validation API routing error logger/body.
- `global-config.xml`, lines 129/130: generic unexpected-error logger/body.
- `payment-events-api.xml`, line 83: logger for failure to release a reservation.
- `payment-events-api.xml`, lines 115/116: intake scoring-error logger/transform.

These branches need targeted failure injection in the later quality milestone.
They can be tested; no claim is made that 100% is impossible. The pure DataWeave
finalization fail-safe is tested, but that is not coverage of the intake error
handler. The tests share one MUnit config and one fixture hook because eager
initialization with multiple MunitModule configs failed in this environment.
Maven runs MUnit with `-Dmunit.disable.lazy.initialization=true` to initialize
the VM queue manager correctly.

Remaining limits: live velocity tracking and DB profile enrichment are not wired;
the initial context uses velocity count 1 and configured default hours. TTL is
configured to 24 hours but actual expiry has not been exercised. Restart/crash
durability, ambiguous publish outcomes, concurrent requests and eventual DB/DLQ
delivery have not been proven. Threshold hot reload, domain execution, DB/email,
alerts, monitors, external policies and deployment remain pending. Component
tests do not establish latency under load or recipient email delivery.

## Run and verify

Use the README's Studio import/runtime/key steps, then POST
`examples/payment-event.json` to `http://localhost:8081/api/payments/events`.
On a fresh event ID expect 202/82/HIGH; repeat expects 409. Change the event ID,
then test malformed/missing/negative values for 400. Inspect correlation/routing
logs under `.local/logs`. The queue consumers are intentionally absent, so events
wait in VM queues. Do not delete `.mule` to resolve duplicates without preserving
the queue/store evidence.

CLI: `./scripts/maven.ps1 test` reruns the 29 tests without Docker/DB/SMTP.
`./scripts/maven.ps1 package -DskipMunitTests` packages after the successful test
run. On another laptop set `FRAUD_JAVA_HOME` and `FRAUD_MAVEN_CMD`, and generate
local encrypted properties with the official Secure Properties Tool.

Git repository initialized on `main`. No commit identity was invented: the
environment has an email configured but no `user.name`. Configure your own
name before creating the initial commit; remote/PR/team history belongs to M5.

## Next milestone

Add live per-card velocity with safe concurrency and TTL tests, runtime-editable
rule configuration, HIGH/standard consumers, MySQL customer enrichment and final
decisions. Then add persistence, email/throttle recovery and the reliability/DLQ
quality gate incrementally. Docker, DB and MailHog execution remains deferred.

# Payment Fraud Detection - Mule intake and asynchronous scoring

Milestones 1 and 2 implement intake, live velocity tracking and asynchronous
scoring with customer enrichment and final decisions. Docker, live MySQL testing,
MailHog, persistence, email and deployment remain deferred. Consumers default to
stopped so the existing intake runs independently. When enabled, they hand final
decisions to a persistent queue for the later persistence milestone.

The project uses Mule 4.12.0 Enterprise and Java 17, matching the installed
Anypoint Studio runtime. It uses HTTP, RAML/APIkit, DataWeave, Object Store,
VM queues, Secure Properties and MUnit. MySQL and Email dependencies are present
for later milestones. A MySQL profile connection is configured with deployment
failure disabled; the stopped consumers do not execute queries during intake.

## Run in Anypoint Studio

1. File > Import > Anypoint Studio > Anypoint Studio project from File System.
   Select this project folder. If the importer requires an archive, use
   File > Import > General > Existing Projects into Workspace with this folder.
2. Select Mule Server 4.12.0 EE and the bundled Java 17 JDK. Maven > Update Project.
   Do not generate APIkit flows: they already exist in `src/main/mule`.
3. Local encrypted properties and the local key have already been generated on
   this machine. On a fresh clone, run `./scripts/setup-local.ps1 -SecureToolJar
   <absolute-path-to-official-secure-properties-tool.jar>` from PowerShell 7.
   The tool creates ignored secrets; it does not start Docker or connect to DB/SMTP.
4. Run > Run Configurations > Mule Application > Arguments > VM arguments:
   add `-M-Dsecure.key=<contents of .local/secure.key>`. Never commit or share the key.
   No Anypoint account or Docker is needed for intake.
5. Run As > Mule Application. Wait for `DEPLOYED` before sending requests.

```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:8081/api/payments/events `
  -ContentType application/json -Headers @{'X-Correlation-ID'='demo-corr-1'} `
  -Body (Get-Content ./examples/payment-event.json -Raw)
```

Expected on a fresh event ID: HTTP 202, score 82, HIGH,
`QUEUED_FOR_REVIEW`, and the same correlation ID in the body/header.
Repeat the event: HTTP 409. Change the event ID for another accepted request.
Malformed JSON, missing required fields, negative/zero amounts, unsupported
currencies and PAN-like data produce HTTP 400 without echoing values.

The endpoint uses `/api` as its listener base path; the RAML resource is
`POST /payments/events`. HIGH events use `payments-high-q`; other bands use
`payments-std-q`. A failure to confirm publication returns HTTP 503 after
bounded retries and releases the request's own deduplication reservation.
There is no fallback from HIGH to standard because official priority routing
is required. A publish timeout can have an ambiguous outcome; later persistence
must be idempotent by event ID.

## Build and test

```powershell
./scripts/maven.ps1 clean test
./scripts/maven.ps1 package -DskipMunitTests
```

The helper selects the detected bundled JDK and local Maven. On another machine
set `FRAUD_JAVA_HOME` to a Java 17 JDK and `FRAUD_MAVEN_CMD` to `mvn.cmd`.
For direct Maven use, set `JAVA_HOME` to Java 17 and `FRAUD_SECURE_KEY` to the
local key first. Do not use Java 26 on PATH. MUnit receives the key through an
environment variable, not a hardcoded Maven value.

The HTTP suite starts the real listener, checks APIkit validation, consumes the
actual HIGH VM queue, checks duplicate handling and injects a publish failure.
The scoring suites exercise all rules, boundaries, live velocity and expiry,
MySQL enrichment with mocks, final decisions and VM transaction rollback.
They also run an actual asynchronous HIGH listener with MySQL mocked. All
original Milestone 1 tests remain in the regression run.
Coverage is written under `target/site/munit`; the milestone report records the
actual results. Studio's GUI run must be verified separately.

Optional static checks (these do not execute Mule): install
`python -m pip install -r requirements-dev.txt`, then run
`python scripts/verify-static.py`. This checks XML, schema cases, flow references
and artifact config files; the application itself contains no Python backend.

## Milestone 2 configuration

The default run arguments remain compatible with Milestone 1. Intake serializes
the complete per-card Object Store read/modify/write sequence using one HTTP
source (`maxConcurrency="1"`). Velocity counts distinct event IDs received in
the configured window, using explicit epoch seconds. A retry of a failed publish
does not count the same ID again within that window. Valid attempts whose queue
publication fails remain counted once, conservatively reflecting suspicious
activity. Consumer redelivery does not increment velocity again.

To change rule thresholds without redeployment, copy `examples/risk-policy.json`
to a writable external path and supply `-M-Drisk.policyFile=<absolute JSON path>`
in the Studio Mule run arguments (quote paths with spaces). The file is read for
each intake. Changes to amount/velocity limits, weights, categories, default
hours and band/decision boundaries apply to the next request. Invalid or missing
configured files produce 503 and no publication; they never silently use an old
policy. Replace the file atomically during updates. With the default empty path,
the existing YAML properties remain the source of rule settings.

Each queued event includes its validated risk-config snapshot. The consumer uses
that snapshot so a later rule-file change cannot rewrite the decision policy for
an already accepted event. Legacy Milestone 1 queue envelopes without a snapshot
load the currently configured rules. Store TTL/window and queue/concurrency
properties are startup settings; changing those requires restarting the app.

After the deferred MySQL setup, enable consumers with
`-M-Dconsumer.initialState=started`. HIGH uses 8 consumers, standard uses 4.
They query `customer_risk_profile`, rescore with database usual hours/watchlist,
then decide APPROVE, REVIEW or BLOCK. Missing/invalid profiles use safe defaults,
record `enrichmentIncomplete` and force REVIEW. An intake or final scoring error
also forces REVIEW. HIGH events found on standard are logged and transactionally
rerouted to HIGH before any profile query.

Final envelopes go to `payments-decisions-q`; they retain event/correlation IDs,
input scoring, profile, rule hits, decision and `alertRequired`. SQL lookup is
outside the local VM transaction. Consume and next VM publication share that
transaction, so an error propagates and rolls back consumption. No persistence
or email delivery is claimed at this stage; do not drain the decisions queue
until the Milestone 3 persistence consumer exists.

MUnit uses a separate live-rule test file in `.local`, a 2-second velocity TTL,
a 1-second expiry sweep and test-only started flow state. Source activation is
controlled by each test; these settings do not change normal Studio defaults.
Mocked database operations explicitly supply their target variable values.

See `docs/milestone-2.md` and `verification/milestone-2` for current evidence.

## Current limits and next work

- MySQL connector/query wiring is implemented and tested with mocks; a live
  MySQL run and Studio GUI consumer activation remain unverified.
- Intake runs with `maxConcurrency="1"` while reservation/publish behavior is
  established. It is not a demonstrated production latency/throughput configuration.
- Dedupe keys persist with a 24-hour TTL; this does not provide permanent
  idempotency. Deleting `.mule` loses local store/queue evidence.
- Separate queues do not establish strict scheduling precedence. VM persistence,
  restart behavior and eventual DB/DLQ delivery still need reliability testing.
- Live rule-file reads support threshold changes; other YAML properties remain
  startup settings. Multi-instance locking and crash/restart tests are pending.
- Domain-based Studio execution is a later technical-standard deliverable.
- HTTP traffic/debug logging must remain disabled. Validation errors contain
  static messages only; application logs never include raw payment payloads.
- Docker Compose and SQL are preparation only. Do not run them until the deferred
  database/mail setup step. Passwords live in ignored `.env` and encrypted YAML.

See `docs/requirements.md` for requirement mapping and
`docs/milestone-1.md` for the historical Milestone 1 evidence. Milestone 3 will
add idempotent database persistence and alerting; Milestone 4 will finish poison
message/DLQ handling and crash/restart reliability verification.

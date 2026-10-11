# Payment Fraud Detection - initial Mule application

Milestone 1 implements the synchronous intake path. Docker, MySQL execution,
MailHog, asynchronous consumers, persistence, alerting and deployment are deferred
at the user's request. Accepted events remain in the configured VM queues until
consumers are added. This initial application is for local development only.

The project uses Mule 4.12.0 Enterprise and Java 17, matching the installed
Anypoint Studio runtime. It uses HTTP, RAML/APIkit, DataWeave, Object Store,
VM queues, Secure Properties and MUnit. MySQL and Email dependencies are present
for later milestones; their connections are deliberately not initialized yet.

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
The scoring suite exercises DataWeave rules and boundaries. It does not prove
live velocity tracking, customer enrichment or final consumer decisions.
Coverage is written under `target/site/munit`; the milestone report records the
actual results. Studio's GUI run must be verified separately.

Optional static checks (these do not execute Mule): install
`python -m pip install -r requirements-dev.txt`, then run
`python scripts/verify-static.py`. This checks XML, schema cases, flow references
and artifact config files; the application itself contains no Python backend.

## Current limits and next work

- Live per-card velocity tracking and customer profile enrichment belong to
  Milestone 2. Initial scoring uses count 1 and default usual hours.
- Intake runs with `maxConcurrency="1"` while reservation/publish behavior is
  established. It is not a demonstrated production latency/throughput configuration.
- Dedupe keys persist with a 24-hour TTL; this does not provide permanent
  idempotency. Deleting `.mule` loses local store/queue evidence.
- Separate queues do not establish strict scheduling precedence. VM persistence,
  restart behavior and eventual DB/DLQ delivery still need reliability testing.
- YAML properties are loaded at startup; externalization alone does not prove
  threshold changes without redeployment. Runtime rule configuration is pending.
- Domain-based Studio execution is a later technical-standard deliverable.
- HTTP traffic/debug logging must remain disabled. Validation errors contain
  static messages only; application logs never include raw payment payloads.
- Docker Compose and SQL are preparation only. Do not run them until the deferred
  database/mail setup step. Passwords live in ignored `.env` and encrypted YAML.

See `docs/requirements.md` for requirement mapping and
`docs/milestone-1.md` for validation evidence and remaining work.

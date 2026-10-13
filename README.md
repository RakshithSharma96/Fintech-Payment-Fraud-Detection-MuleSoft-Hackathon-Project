# Payment Fraud Detection System

A MuleSoft-based payment fraud detection application that ingests payment events, evaluates transaction risk, and processes suspicious transactions through asynchronous workflows, MySQL persistence, and email alerts.

## Overview

The Payment Fraud Detection System is built using **Mule 4, RAML, DataWeave, MySQL, and MUnit**. It provides an API for receiving payment events and a processing pipeline for identifying potentially fraudulent transactions.

The application combines request validation, duplicate-event detection, configurable risk rules, asynchronous processing, database persistence, and alert delivery. This separation allows the intake API to acknowledge valid events without waiting for all downstream processing to finish.

## Key Features

- **REST API:** Accepts payment events through an HTTP endpoint defined using RAML.
- **Input validation:** Rejects malformed requests, missing required fields, invalid transaction amounts, unsupported currencies, and other invalid input.
- **Duplicate detection:** Identifies previously received event IDs and rejects duplicate submissions.
- **Risk evaluation:** Applies configurable rules and scoring logic to identify transactions requiring further review.
- **Asynchronous processing:** Uses Mule VM queues to separate request intake from downstream scoring and processing.
- **MySQL persistence:** Stores payment-fraud event records and supports database-backed processing.
- **Email notifications:** Uses the Mule Email Connector to send alerts for qualifying high-risk transactions and fraud decisions.
- **Secure configuration:** Supports Mule Secure Configuration Properties and externalized configuration.
- **Automated testing:** Includes MUnit test suites for fraud rules, API intake, processing, persistence, alerting, and error scenarios.

## Technology Stack

| Component | Technology |
|---|---|
| Integration platform | Mule Runtime 4.12.x |
| API definition | RAML / APIkit |
| Transformation | DataWeave 2.0 |
| Language and runtime | Java 17 |
| Build system | Maven |
| Database | MySQL |
| Database integration | Mule Database Connector |
| Asynchronous messaging | Mule VM Connector |
| Duplicate detection and state | Mule Object Store |
| Email notifications | Mule Email Connector |
| Testing | MUnit 3.7.3 |
| Development environment | Anypoint Studio |

## Architecture

The application follows an event-driven integration approach.

```text
Payment Event
     |
     v
HTTP API / APIkit
     |
     v
Request Validation
     |
     v
Duplicate Event Detection
     |
     v
Event Intake and Queueing
     |
     v
Asynchronous Risk Processing
     |
     v
Risk Evaluation and Decision
     |
     +--------------------+
     |                    |
     v                    v
MySQL Persistence    Alert Processing
                          |
                          v
                    Email Notification
```

The diagram represents the logical processing pipeline. Actual execution, retries, and alert delivery depend on the configured flows and runtime state.

### Processing Workflow

1. **Receive:** The API accepts a payment event over HTTP.
2. **Validate:** Required fields, data types, and business constraints are checked.
3. **Deduplicate:** The system checks the event ID to prevent duplicate processing.
4. **Queue:** Valid events are passed into the asynchronous processing workflow.
5. **Evaluate:** Configured risk rules and scoring logic determine the transaction's risk classification.
6. **Persist:** The application records relevant event and processing information in MySQL.
7. **Alert:** Qualifying high-risk transactions or fraud decisions are routed through the alerting workflow.

An HTTP acceptance response indicates that the event was accepted for processing; it does not by itself guarantee that database persistence or email delivery has completed.

## API Reference

### Submit a Payment Event

| Property | Value |
|---|---|
| Method | `POST` |
| Local endpoint | `http://localhost:8081/api/payments/events` |
| Content type | `application/json` |
| Successful intake response | `202 Accepted` |

### Sample Request

```json
{
  "eventId": "PAY-EVT-2026-884512",
  "eventTimestamp": "2026-09-11T14:22:07+05:30",
  "transaction": {
    "transactionId": "TXN-99120455",
    "amount": 248500.00,
    "currency": "INR",
    "channel": "ONLINE",
    "entryMode": "CARD_NOT_PRESENT"
  },
  "card": {
    "cardToken": "TKN-example-4d9a77",
    "maskedCardNumber": "XXXXXXXXXXXX4417",
    "cardType": "CREDIT",
    "issuingCountry": "IN"
  },
  "customer": {
    "customerId": "CUST-77219",
    "name": "Example Customer",
    "email": "customer@example.com",
    "riskProfile": "STANDARD"
  },
  "merchant": {
    "merchantId": "MER-5581",
    "merchantName": "Example Online Store",
    "merchantCategory": "ELECTRONICS",
    "merchantCountry": "SG"
  },
  "device": {
    "ipAddress": "203.0.113.77",
    "deviceId": "DEV-example",
    "geoCountry": "SG"
  }
}
```

Use the RAML definition in the project as the source of truth for the complete request schema and permitted values. The example is intended for development and uses illustrative data.

### Response Behaviour

| Scenario | Expected behaviour |
|---|---|
| Valid payment event | Accepted for processing |
| Duplicate event ID | Rejected with `409 Conflict` |
| Invalid request or malformed JSON | Rejected with `400 Bad Request` |

The exact response body and error format are defined by the API implementation.

## Project Structure

```text
payment-fraud-detection/
├── src/
│   ├── main/
│   │   ├── mule/
│   │   │   ├── global-config.xml
│   │   │   ├── payment-events-api.xml
│   │   │   ├── velocity.xml
│   │   │   ├── scoring-consumer.xml
│   │   │   ├── persistence.xml
│   │   │   └── alerting.xml
│   │   └── resources/
│   │       ├── config-dev.yaml
│   │       ├── modules/
│   │       └── sql/
│   └── test/
│       └── munit/
├── scripts/
│   ├── setup-local.ps1
│   ├── maven.ps1
│   ├── verify-static.py
│   └── test-milestone-3.ps1
├── mule-artifact.json
├── pom.xml
└── README.md
```

The tree shows the principal application files; additional test, SQL, and validation utilities may be present in the repository.

## Local Setup

### Prerequisites

Install and configure the following before running the application:

- Anypoint Studio with a compatible Mule 4 runtime.
- Java 17.
- MySQL Server.
- MailHog or another SMTP server for local email testing.
- Access to the Maven dependencies and MuleSoft repositories required by the project.

### 1. Prepare the Project

Clone or open the repository in Anypoint Studio and import it as an existing Mule project.

Open a PowerShell terminal in the project root.

### 2. Configure the Environment

Review `src/main/resources/config-dev.yaml` and the global Mule configuration.

Configure the database connection, SMTP host and port, and other environment-specific values for your local environment. Use `scripts/setup-local.ps1` where applicable for the project's local setup process.

Initialize the database using the SQL scripts in `src/main/resources/sql/`, following the appropriate schema and migration requirements for your existing database.

Start MySQL and the local SMTP service before testing flows that depend on them.

**Do not commit database passwords, SMTP credentials, encryption keys, or other secrets to Git.** Keep sensitive values in local configuration or secure property mechanisms.

### 3. Run the Application

In Anypoint Studio:

1. Import and open the project.
2. Verify that the Maven dependencies resolve successfully.
3. Start the required local services.
4. Run the project as a Mule application.
5. Send a payment event to the configured local API endpoint.

The default endpoint documented for local testing is:

```text
http://localhost:8081/api/payments/events
```

Confirm the port and base path against the active runtime configuration.

### 4. Test the API

Example PowerShell request:

```powershell
$body = @{
    eventId = "PAY-TEST-001"
    eventTimestamp = "2026-09-11T14:22:07+05:30"
    transaction = @{
        transactionId = "TXN-TEST-001"
        amount = 248500.00
        currency = "INR"
        channel = "ONLINE"
        entryMode = "CARD_NOT_PRESENT"
    }
    card = @{
        cardToken = "TKN-TEST-001"
        maskedCardNumber = "XXXXXXXXXXXX4417"
        cardType = "CREDIT"
        issuingCountry = "IN"
    }
    customer = @{
        customerId = "CUST-TEST-001"
        name = "Test Customer"
        email = "customer@example.com"
        riskProfile = "STANDARD"
    }
    merchant = @{
        merchantId = "MER-TEST-001"
        merchantName = "Example Online Store"
        merchantCategory = "ELECTRONICS"
        merchantCountry = "SG"
    }
    device = @{
        ipAddress = "203.0.113.77"
        deviceId = "DEV-TEST-001"
        geoCountry = "SG"
    }
} | ConvertTo-Json -Depth 6

Invoke-RestMethod `
    -Uri "http://localhost:8081/api/payments/events" `
    -Method Post `
    -ContentType "application/json" `
    -Body $body
```

Use unique event IDs for independent tests. Risk outcomes depend on the configured rules, and successful intake does not guarantee a high-risk classification.

## Automated Testing

The project contains MUnit test suites covering the intake API, fraud rules, queue processing, persistence, alerts, and validation/error paths.

Run the tests through the configured Maven setup. For example, from PowerShell:

```powershell
.\scripts\maven.ps1 clean test
```

Review the script and its accepted arguments if your local Maven wrapper uses a different invocation.

A successful test run should report `BUILD SUCCESS` with no failed or errored tests. Test coverage reports are generated by the configured MUnit coverage process.

## Security Considerations

- Keep sensitive configuration outside version control.
- Use secure properties or environment-specific variables for credentials.
- Preserve card masking and avoid logging full card numbers or unnecessary customer data.
- Validate inbound data before processing.
- Apply appropriate database privileges to the application account.
- Configure production authentication, authorization, TLS, and operational monitoring before exposing the API publicly.

## Current Status

The project includes the local Mule application, asynchronous processing, fraud scoring, MySQL persistence, email alerting, and MUnit test suites.

Local functional and automated testing has been performed. CloudHub deployment and its external service connections remain a separate configuration and verification step.



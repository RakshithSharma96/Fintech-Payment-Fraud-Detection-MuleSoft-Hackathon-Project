CREATE DATABASE IF NOT EXISTS frauddb CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
USE frauddb;

CREATE TABLE IF NOT EXISTS fraud_events (
  event_id VARCHAR(30) PRIMARY KEY,
  transaction_id VARCHAR(30) NOT NULL,
  event_timestamp TIMESTAMP NOT NULL,
  customer_id VARCHAR(20) NOT NULL,
  card_token VARCHAR(40) NOT NULL,
  masked_card VARCHAR(20) NOT NULL,
  amount DECIMAL(14,2) NOT NULL,
  currency CHAR(3) NOT NULL,
  merchant_id VARCHAR(20),
  merchant_country CHAR(2),
  geo_country CHAR(2),
  risk_score INT NOT NULL,
  risk_band VARCHAR(10) NOT NULL,
  decision VARCHAR(10) NOT NULL,
  alert_status VARCHAR(20),
  correlation_id VARCHAR(50) NOT NULL,
  enrichment_incomplete BOOLEAN NOT NULL DEFAULT FALSE,
  policy_snapshot JSON,
  decision_envelope JSON,
  decision_hash CHAR(64),
  alert_required BOOLEAN NOT NULL DEFAULT FALSE,
  timestamp_fallback BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_fe_alert_status (alert_status, created_at),
  INDEX idx_fe_band_created (risk_band, created_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS fraud_rule_hits (
  hit_seq INT AUTO_INCREMENT PRIMARY KEY,
  event_id VARCHAR(30) NOT NULL,
  rule_code VARCHAR(30) NOT NULL,
  rule_name VARCHAR(120) NOT NULL,
  rule_weight INT NOT NULL,
  UNIQUE KEY uq_event_rule (event_id, rule_code),
  CONSTRAINT fk_hits_event FOREIGN KEY (event_id) REFERENCES fraud_events (event_id)
) ENGINE=InnoDB;

-- Reference data used by the scoring consumer (profile enrichment)
CREATE TABLE IF NOT EXISTS customer_risk_profile (
  customer_id VARCHAR(20) PRIMARY KEY,
  risk_profile VARCHAR(20) NOT NULL DEFAULT 'STANDARD',
  usual_hour_start INT DEFAULT 6,
  usual_hour_end INT DEFAULT 23
) ENGINE=InnoDB;

-- Dead-letter store: the "recorded reason" the brief demands for events that could not be processed
CREATE TABLE IF NOT EXISTS dead_letter_events (
  dlq_id INT AUTO_INCREMENT PRIMARY KEY,
  event_id VARCHAR(30),
  correlation_id VARCHAR(50),
  source_queue VARCHAR(60),
  reason VARCHAR(1000) NOT NULL,
  transient_retries INT DEFAULT 0,
  original_payload TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
  failed_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;


INSERT IGNORE INTO customer_risk_profile VALUES
 ('CUST-77219','STANDARD',6,23),
 ('CUST-10001','TRUSTED',5,23),
 ('CUST-10002','WATCHLIST',8,20);

-- Create/grant the native Windows application user separately; no credentials
-- or account-changing statements belong in this schema.

CREATE TABLE IF NOT EXISTS alert_card_windows (
  card_token VARCHAR(40) PRIMARY KEY,
  window_id CHAR(36),
  window_end DATETIME(6),
  masked_card VARCHAR(20) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS fraud_persistence_claims (
  event_id VARCHAR(30) PRIMARY KEY,
  CONSTRAINT fk_persistence_claim_event FOREIGN KEY (event_id) REFERENCES fraud_events(event_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS alert_outbox (
  alert_id VARCHAR(80) PRIMARY KEY,
  kind VARCHAR(12) NOT NULL,
  card_token VARCHAR(40) NOT NULL,
  masked_card VARCHAR(20) NOT NULL,
  status VARCHAR(12) NOT NULL DEFAULT 'PENDING',
  lease_token CHAR(36),
  last_delivery_token CHAR(36),
  lease_until DATETIME(6),
  attempts INT NOT NULL DEFAULT 0,
  failure_code VARCHAR(60),
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  sent_at DATETIME(6),
  INDEX idx_outbox_dispatch (status, lease_until, created_at)
) ENGINE=InnoDB;

-- Every affected event belongs to exactly one immediate/aggregate notification.
-- OPEN aggregates are not dispatched until the window closes.
CREATE TABLE IF NOT EXISTS alert_outbox_members (
  event_id VARCHAR(30) PRIMARY KEY,
  alert_id VARCHAR(80) NOT NULL,
  CONSTRAINT fk_alert_member_event FOREIGN KEY (event_id) REFERENCES fraud_events(event_id),
  CONSTRAINT fk_alert_member_batch FOREIGN KEY (alert_id) REFERENCES alert_outbox(alert_id)
) ENGINE=InnoDB;

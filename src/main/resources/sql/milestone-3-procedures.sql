-- MySQL 8.0+ / InnoDB. Each procedure owns one DB transaction. Mule calls with
-- NOT_SUPPORTED while its independent local VM consume transaction remains open.
-- DB commit precedes VM ack: redelivery is safe through event-ID uniqueness.
USE frauddb;
DELIMITER $$
DROP PROCEDURE IF EXISTS persist_payment_decision$$
CREATE PROCEDURE persist_payment_decision(IN p JSON, IN window_seconds INT, OUT outcome VARCHAR(12))
SQL SECURITY DEFINER
main: BEGIN
  DECLARE event_key VARCHAR(30);
  DECLARE token VARCHAR(40);
  DECLARE existing_hash CHAR(64);
  DECLARE inserted INT;
  DECLARE current_window CHAR(36);
  DECLARE expires DATETIME(6);
  DECLARE batch VARCHAR(80);
  DECLARE suppressed INT DEFAULT 0;
  DECLARE clock_now DATETIME(6);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET event_key=JSON_UNQUOTE(JSON_EXTRACT(p,'$.eventId'));
  SET token=JSON_UNQUOTE(JSON_EXTRACT(p,'$.cardToken'));
  SET clock_now=UTC_TIMESTAMP(6);
  SET time_zone='+00:00';
  IF window_seconds < 1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='INVALID_ALERT_WINDOW'; END IF;
  START TRANSACTION;
  INSERT INTO fraud_events(event_id,transaction_id,event_timestamp,customer_id,card_token,masked_card,
    amount,currency,merchant_id,merchant_country,geo_country,risk_score,risk_band,decision,
    alert_status,correlation_id,enrichment_incomplete,policy_snapshot,decision_envelope,
    decision_hash,alert_required,timestamp_fallback)
  VALUES(event_key,JSON_UNQUOTE(JSON_EXTRACT(p,'$.transactionId')),JSON_UNQUOTE(JSON_EXTRACT(p,'$.eventTimestamp')),
    JSON_UNQUOTE(JSON_EXTRACT(p,'$.customerId')),token,JSON_UNQUOTE(JSON_EXTRACT(p,'$.maskedCard')),
    JSON_EXTRACT(p,'$.amount'),JSON_UNQUOTE(JSON_EXTRACT(p,'$.currency')),
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(p,'$.merchantId')),'null'),NULLIF(JSON_UNQUOTE(JSON_EXTRACT(p,'$.merchantCountry')),'null'),
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(p,'$.geoCountry')),'null'),JSON_EXTRACT(p,'$.riskScore'),
    JSON_UNQUOTE(JSON_EXTRACT(p,'$.riskBand')),JSON_UNQUOTE(JSON_EXTRACT(p,'$.decision')),
    'NOT_REQUIRED',JSON_UNQUOTE(JSON_EXTRACT(p,'$.correlationId')),
    JSON_UNQUOTE(JSON_EXTRACT(p,'$.enrichmentIncomplete'))='true',JSON_EXTRACT(p,'$.policySnapshot'),JSON_EXTRACT(p,'$.envelope'),
    JSON_UNQUOTE(JSON_EXTRACT(p,'$.decisionHash')),JSON_UNQUOTE(JSON_EXTRACT(p,'$.alertRequired'))='true',
    JSON_UNQUOTE(JSON_EXTRACT(p,'$.timestampFallback'))='true')
  ON DUPLICATE KEY UPDATE event_id=event_key;
  SET inserted=ROW_COUNT();
  -- ROW_COUNT for no-op updates can be 1 with CLIENT_FOUND_ROWS. Do not rely on
  -- that driver setting: membership/child creation is gated by a fresh hash row
  -- claim below and a serialized event lock.
  SELECT decision_hash INTO existing_hash FROM fraud_events WHERE event_id=event_key FOR UPDATE;
  IF existing_hash IS NULL OR existing_hash <> JSON_UNQUOTE(JSON_EXTRACT(p,'$.decisionHash')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='EVENT_ID_CONFLICT_OR_LEGACY_ROW';
  END IF;
  -- Claim is unique per event and participates in the same transaction.
  INSERT IGNORE INTO fraud_persistence_claims(event_id) VALUES(event_key);
  SET inserted=ROW_COUNT();
  IF inserted=0 THEN
    SET outcome='DUPLICATE'; COMMIT; LEAVE main;
  END IF;
  INSERT INTO fraud_rule_hits(event_id,rule_code,rule_name,rule_weight)
  SELECT event_key,h.code,h.name,h.weight FROM JSON_TABLE(p,'$.ruleHits[*]' COLUMNS(
    code VARCHAR(30) PATH '$.ruleCode',name VARCHAR(120) PATH '$.ruleName',weight INT PATH '$.ruleWeight')) h;
  IF JSON_UNQUOTE(JSON_EXTRACT(p,'$.alertRequired'))='true' THEN
    INSERT INTO alert_card_windows(card_token,masked_card) VALUES(token,JSON_UNQUOTE(JSON_EXTRACT(p,'$.maskedCard')))
      ON DUPLICATE KEY UPDATE card_token=token;
    SELECT window_id,window_end INTO current_window,expires FROM alert_card_windows WHERE card_token=token FOR UPDATE;
    IF current_window IS NOT NULL THEN
      SELECT COUNT(*) INTO suppressed FROM alert_outbox_members WHERE alert_id=CONCAT('A:',current_window);
    END IF;
    IF expires IS NOT NULL AND expires > clock_now THEN
      SET batch=CONCAT('A:',current_window);
      INSERT IGNORE INTO alert_outbox(alert_id,kind,card_token,masked_card,status)
        VALUES(batch,'AGGREGATE',token,JSON_UNQUOTE(JSON_EXTRACT(p,'$.maskedCard')),'OPEN');
      UPDATE fraud_events SET alert_status='SUPPRESSED' WHERE event_id=event_key;
    ELSEIF suppressed > 0 THEN
      -- Match guide: an arrival after an expired window joins its unsent aggregate.
      SET batch=CONCAT('A:',current_window);
      UPDATE alert_outbox SET status='PENDING' WHERE alert_id=batch AND status='OPEN';
      UPDATE fraud_events e JOIN alert_outbox_members m ON e.event_id=m.event_id
        SET e.alert_status='PENDING' WHERE m.alert_id=batch AND e.alert_status='SUPPRESSED';
      UPDATE alert_card_windows SET window_id=NULL,window_end=NULL WHERE card_token=token;
      UPDATE fraud_events SET alert_status='PENDING' WHERE event_id=event_key;
    ELSE
      SET batch=CONCAT('I:',event_key);
      INSERT INTO alert_outbox(alert_id,kind,card_token,masked_card,status)
        VALUES(batch,'IMMEDIATE',token,JSON_UNQUOTE(JSON_EXTRACT(p,'$.maskedCard')),'PENDING');
      UPDATE alert_card_windows SET window_id=UUID(),window_end=TIMESTAMPADD(SECOND,window_seconds,clock_now),
        masked_card=JSON_UNQUOTE(JSON_EXTRACT(p,'$.maskedCard')) WHERE card_token=token;
      UPDATE fraud_events SET alert_status='PENDING' WHERE event_id=event_key;
    END IF;
    INSERT INTO alert_outbox_members(event_id,alert_id) VALUES(event_key,batch);
  END IF;
  SET outcome='INSERTED';
  COMMIT;
END$$

DROP PROCEDURE IF EXISTS flush_alert_window$$
CREATE PROCEDURE flush_alert_window(IN token VARCHAR(40))
SQL SECURITY DEFINER
BEGIN
  DECLARE current_window CHAR(36);
  DECLARE expires DATETIME(6);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET time_zone='+00:00';
  START TRANSACTION;
  SELECT window_id,window_end INTO current_window,expires FROM alert_card_windows WHERE card_token=token FOR UPDATE;
  IF expires IS NOT NULL AND expires <= UTC_TIMESTAMP(6) THEN
    UPDATE alert_outbox SET status='PENDING' WHERE alert_id=CONCAT('A:',current_window) AND status='OPEN';
    UPDATE fraud_events e JOIN alert_outbox_members m ON e.event_id=m.event_id
      SET e.alert_status='PENDING' WHERE m.alert_id=CONCAT('A:',current_window) AND e.alert_status='SUPPRESSED';
    UPDATE alert_card_windows SET window_id=NULL,window_end=NULL WHERE card_token=token;
  END IF;
  COMMIT;
END$$

DROP PROCEDURE IF EXISTS claim_alert_batch$$
CREATE PROCEDURE claim_alert_batch(IN owner_key CHAR(36),IN lease_seconds INT,OUT claimed VARCHAR(80))
SQL SECURITY DEFINER
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET claimed=NULL;
  SET time_zone='+00:00';
  START TRANSACTION;
  -- Retry of an ambiguously committed claim returns the same owned batch.
  SELECT alert_id INTO claimed FROM alert_outbox WHERE status='SENDING' AND lease_token=owner_key LIMIT 1 FOR UPDATE;
  IF claimed IS NOT NULL THEN
    UPDATE alert_outbox SET lease_until=TIMESTAMPADD(SECOND,lease_seconds,UTC_TIMESTAMP(6)) WHERE alert_id=claimed;
  ELSE
    SELECT alert_id INTO claimed FROM alert_outbox
      WHERE status='PENDING' OR (status='SENDING' AND lease_until < UTC_TIMESTAMP(6))
      ORDER BY created_at,alert_id LIMIT 1 FOR UPDATE SKIP LOCKED;
    IF claimed IS NOT NULL THEN
      UPDATE alert_outbox SET status='SENDING',lease_token=owner_key,
        lease_until=TIMESTAMPADD(SECOND,lease_seconds,UTC_TIMESTAMP(6)),attempts=attempts+1,
        failure_code=NULL WHERE alert_id=claimed;
    END IF;
  END IF;
  COMMIT;
END$$

DROP PROCEDURE IF EXISTS complete_alert_batch$$
CREATE PROCEDURE complete_alert_batch(IN batch VARCHAR(80),IN owner_key CHAR(36),IN delivered BOOLEAN)
SQL SECURITY DEFINER
main: BEGIN
  DECLARE kind_value VARCHAR(12);
  DECLARE state_value VARCHAR(12);
  DECLARE last_owner CHAR(36);
  DECLARE changed INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET time_zone='+00:00';
  START TRANSACTION;
  SELECT kind,status,last_delivery_token INTO kind_value,state_value,last_owner FROM alert_outbox WHERE alert_id=batch FOR UPDATE;
  IF last_owner=owner_key AND ((delivered AND state_value='SENT') OR (NOT delivered AND state_value='PENDING')) THEN
    COMMIT; LEAVE main;
  END IF;
  UPDATE alert_outbox SET status=IF(delivered,'SENT','PENDING'),
    sent_at=IF(delivered,UTC_TIMESTAMP(6),sent_at),lease_token=NULL,lease_until=NULL,
    last_delivery_token=owner_key,
    failure_code=IF(delivered,NULL,'SMTP_OR_STATUS_FAILURE')
    WHERE alert_id=batch AND status='SENDING' AND lease_token=owner_key;
  SET changed=ROW_COUNT();
  IF changed=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='ALERT_LEASE_LOST'; END IF;
  IF delivered THEN
    UPDATE fraud_events e JOIN alert_outbox_members m ON e.event_id=m.event_id
      SET e.alert_status=IF(kind_value='AGGREGATE','AGGREGATED_SENT','SENT') WHERE m.alert_id=batch;
  ELSE
    UPDATE fraud_events e JOIN alert_outbox_members m ON e.event_id=m.event_id
      SET e.alert_status='PENDING' WHERE m.alert_id=batch;
  END IF;
  COMMIT;
END$$
DELIMITER ;

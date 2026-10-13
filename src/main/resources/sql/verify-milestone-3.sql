-- NOT YET EXECUTED. Native MySQL integration assertions.
-- ONLY an isolated empty frauddb, a fresh autocommit session, Studio stopped.
-- Ordinary test SQL/assertion failures are handled and cleaned, then reported FAIL.
-- Connection loss, server termination or script/DDL compilation errors can prevent
-- cleanup: inspect reserved m3_* objects/test IDs before retrying. Never use production.
-- This is procedure-only verification; its synthetic envelope is not for SMTP.
USE frauddb;
DELIMITER $$
DROP PROCEDURE IF EXISTS m3_assert$$
CREATE PROCEDURE m3_assert(IN ok BOOLEAN,IN reason VARCHAR(120))
BEGIN IF ok IS NULL OR NOT ok THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=reason; END IF; END$$
DROP PROCEDURE IF EXISTS m3_cleanup_test_records$$
CREATE PROCEDURE m3_cleanup_test_records()
BEGIN
  DECLARE test_batch VARCHAR(80);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  WHILE EXISTS (SELECT 1 FROM alert_outbox_members WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL')) DO
    SELECT MIN(alert_id) INTO test_batch FROM alert_outbox_members WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL');
    DELETE FROM alert_outbox_members WHERE alert_id=test_batch AND event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL');
    DELETE FROM alert_outbox WHERE alert_id=test_batch
      AND NOT EXISTS (SELECT 1 FROM alert_outbox_members WHERE alert_id=test_batch);
  END WHILE;
  DELETE FROM alert_outbox WHERE alert_id IN ('I:M3-SQL-1','I:M3-SQL-2','I:M3-SQL-3','I:M3-SQL-4',
    'I:M3-SQL-5','I:M3-SQL-6','I:M3-SQL-LOW','I:M3-SQL-FAIL')
    AND NOT EXISTS (SELECT 1 FROM alert_outbox_members m WHERE m.alert_id=alert_outbox.alert_id);
  DELETE FROM alert_card_windows WHERE card_token='M3-SQL-CARD';
  DELETE FROM fraud_rule_hits WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL');
  DELETE FROM fraud_persistence_claims WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL');
  DELETE FROM fraud_events WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL');
  COMMIT;
END$$
DROP PROCEDURE IF EXISTS m3_verify$$
CREATE PROCEDURE m3_verify()
BEGIN
  DECLARE p JSON;
  DECLARE result VARCHAR(12);
  DECLARE batch VARCHAR(80);
  DECLARE again VARCHAR(80);
  DECLARE owner1 CHAR(36);
  DECLARE owner2 CHAR(36);
  DECLARE conflicted BOOLEAN DEFAULT FALSE;
  DECLARE failed BOOLEAN DEFAULT FALSE;
  DECLARE test_started BOOLEAN DEFAULT FALSE;
  DECLARE error_state CHAR(5);
  DECLARE error_number INT;
  DECLARE error_message TEXT;
  DECLARE aggregate_batch VARCHAR(80);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 error_state=RETURNED_SQLSTATE,error_number=MYSQL_ERRNO,error_message=MESSAGE_TEXT;
    ROLLBACK;
    SET @m3_verify_status='FAIL',@m3_verify_error_state=error_state,
      @m3_verify_error_number=error_number,@m3_verify_error_message=error_message;
    SET @m3_inject_membership=FALSE;
    IF test_started THEN
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET @m3_verify_cleanup_failed=TRUE;
        CALL m3_cleanup_test_records();
      END;
    END IF;
    -- Do not RESIGNAL here: return FAIL so the script can DROP all test helpers/triggers.
  END;
  CALL m3_assert(@@autocommit=1,'Use a fresh autocommit session with Studio stopped');
  CALL m3_assert((SELECT COUNT(*)=0 FROM fraud_events),'Isolated database must have no fraud_events');
  CALL m3_assert((SELECT COUNT(*)=0 FROM fraud_rule_hits),'Isolated database must have no fraud_rule_hits');
  CALL m3_assert((SELECT COUNT(*)=0 FROM fraud_persistence_claims),'Isolated database must have no persistence claims');
  CALL m3_assert((SELECT COUNT(*)=0 FROM alert_card_windows),'Isolated database must have no card windows');
  CALL m3_assert((SELECT COUNT(*)=0 FROM alert_outbox),'Isolated database must have no outbox batches');
  CALL m3_assert((SELECT COUNT(*)=0 FROM alert_outbox_members),'Isolated database must have no outbox members');
  SET test_started=TRUE;
  SET p=JSON_OBJECT('eventId','M3-SQL-1','transactionId','M3-TX-1',
    'eventTimestamp','2026-09-11 09:00:00','customerId','M3-CUST',
    'cardToken','M3-SQL-CARD','maskedCard','************4417','amount',150000,
    'currency','INR','merchantId','M3-MERCHANT','merchantCountry','US','geoCountry','IN',
    'riskScore',82,'riskBand','HIGH','decision','REVIEW','correlationId','m3-sql-corr',
    'enrichmentIncomplete',FALSE,'policySnapshot',JSON_OBJECT('test',TRUE),
    'envelope',JSON_OBJECT('nativeAssertion',TRUE),
    'decisionHash',REPEAT('a',64),'alertRequired',TRUE,'timestampFallback',FALSE,
    'ruleHits',JSON_ARRAY(JSON_OBJECT('ruleCode','R01','ruleName','Amount','ruleWeight',35),
      JSON_OBJECT('ruleCode','R02','ruleName','Geo','ruleWeight',30)));
  -- JSON booleans must be real JSON true/false, not SQL numeric 1/0.
  SET p=JSON_SET(p,'$.alertRequired',CAST('true' AS JSON),
    '$.enrichmentIncomplete',CAST('false' AS JSON),'$.timestampFallback',CAST('false' AS JSON));
  CALL persist_payment_decision(p,300,result);
  CALL m3_assert(result='INSERTED','First persistence outcome');
  CALL persist_payment_decision(p,300,result);
  CALL m3_assert(result='DUPLICATE','Replay outcome');
  CALL m3_assert((SELECT COUNT(*)=1 FROM fraud_events),'One parent after replay');
  CALL m3_assert((SELECT COUNT(*)=2 FROM fraud_rule_hits),'Two unique children after replay');
  CALL m3_assert((SELECT COUNT(*)=1 FROM alert_outbox_members),'One alert membership after replay');
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 error_state=RETURNED_SQLSTATE,error_number=MYSQL_ERRNO,error_message=MESSAGE_TEXT;
      IF error_state<>'45000' OR error_number<>1644 OR error_message<>'EVENT_ID_CONFLICT_OR_LEGACY_ROW' THEN RESIGNAL; END IF;
      SET conflicted=TRUE;
    END;
    CALL persist_payment_decision(JSON_SET(p,'$.decisionHash',REPEAT('b',64)),300,result);
  END;
  CALL m3_assert(conflicted,'Changed hash must conflict');
  CALL m3_assert((SELECT risk_score=82 FROM fraud_events WHERE event_id='M3-SQL-1'),'Conflict preserves parent');
  SET p=JSON_SET(p,'$.eventId','M3-SQL-2','$.decisionHash',REPEAT('c',64));
  CALL persist_payment_decision(p,300,result);
  SET p=JSON_SET(p,'$.eventId','M3-SQL-3','$.decisionHash',REPEAT('d',64));
  CALL persist_payment_decision(p,300,result);
  CALL m3_assert((SELECT COUNT(*)=2 FROM alert_outbox),'Immediate plus aggregate');
  CALL m3_assert((SELECT COUNT(*)=2 FROM fraud_events WHERE alert_status='SUPPRESSED'),'Two suppressed members');
  UPDATE alert_card_windows SET window_end=UTC_TIMESTAMP(6)-INTERVAL 1 SECOND WHERE card_token='M3-SQL-CARD';
  SET p=JSON_SET(p,'$.eventId','M3-SQL-4','$.decisionHash',REPEAT('4',64));
  CALL persist_payment_decision(p,300,result);
  SELECT alert_id INTO aggregate_batch FROM alert_outbox_members WHERE event_id='M3-SQL-2';
  CALL m3_assert((SELECT status='PENDING' FROM alert_outbox WHERE alert_id=aggregate_batch),'Arrival seals aggregate');
  CALL m3_assert((SELECT COUNT(*)=3 FROM fraud_events e JOIN alert_outbox_members m ON m.event_id=e.event_id
    WHERE m.alert_id=aggregate_batch AND e.alert_status='PENDING'),'All expired-arrival members pending');
  -- A separate new window proves the scheduler flush path too.
  SET p=JSON_SET(p,'$.eventId','M3-SQL-5','$.decisionHash',REPEAT('5',64));
  CALL persist_payment_decision(p,300,result);
  SET p=JSON_SET(p,'$.eventId','M3-SQL-6','$.decisionHash',REPEAT('6',64));
  CALL persist_payment_decision(p,300,result);
  UPDATE alert_card_windows SET window_end=UTC_TIMESTAMP(6)-INTERVAL 1 SECOND WHERE card_token='M3-SQL-CARD';
  CALL flush_alert_window('M3-SQL-CARD');
  CALL m3_assert((SELECT COUNT(*)=4 FROM alert_outbox WHERE status='PENDING'),'Both immediate and aggregate windows pending');
  CALL m3_assert((SELECT COUNT(*)=0 FROM fraud_events e JOIN alert_outbox_members m ON m.event_id=e.event_id
    JOIN alert_outbox o ON o.alert_id=m.alert_id WHERE o.status='PENDING' AND e.alert_status<>'PENDING'),'Parent/outbox pending states agree');
  -- Set a deterministic test ordering even on clocks with coarse resolution.
  UPDATE alert_outbox o JOIN alert_outbox_members m ON m.alert_id=o.alert_id
    SET o.created_at=TIMESTAMPADD(MICROSECOND,CASE m.event_id
      WHEN 'M3-SQL-1' THEN 1 WHEN 'M3-SQL-2' THEN 2 WHEN 'M3-SQL-5' THEN 3 ELSE 4 END,'2026-09-11 09:00:00')
    WHERE m.event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-5','M3-SQL-6');
  SET owner1=UUID(); SET owner2=UUID();
  CALL claim_alert_batch(owner1,180,batch);
  CALL m3_assert(batch='I:M3-SQL-1','Oldest immediate batch claimed first');
  CALL claim_alert_batch(owner1,180,again);
  CALL m3_assert(batch=again,'Ambiguous claim retry returns same batch');
  CALL m3_assert((SELECT attempts=1 FROM alert_outbox WHERE alert_id=batch),'Claim retry does not increment attempts');
  UPDATE alert_outbox SET lease_until=UTC_TIMESTAMP(6)-INTERVAL 1 SECOND WHERE alert_id=batch;
  CALL claim_alert_batch(owner2,180,again);
  CALL m3_assert(batch=again,'Expired lease recovers batch');
  CALL complete_alert_batch(batch,owner2,FALSE);
  CALL complete_alert_batch(batch,owner2,FALSE);
  CALL m3_assert((SELECT status='PENDING' FROM alert_outbox WHERE alert_id=batch),'Failed SMTP releases pending, retry safe');
  CALL claim_alert_batch(owner1,180,batch);
  CALL complete_alert_batch(batch,owner1,TRUE);
  CALL complete_alert_batch(batch,owner1,TRUE);
  CALL m3_assert((SELECT status='SENT' FROM alert_outbox WHERE alert_id=batch),'Successful completion retry safe');
  CALL claim_alert_batch(owner2,180,batch);
  CALL m3_assert(batch=aggregate_batch,'Second oldest batch is the first aggregate');
  -- Force stale audit statuses to ensure failed delivery repairs every member.
  UPDATE fraud_events e JOIN alert_outbox_members m ON e.event_id=m.event_id SET e.alert_status='SUPPRESSED' WHERE m.alert_id=batch;
  CALL complete_alert_batch(batch,owner2,FALSE);
  CALL complete_alert_batch(batch,owner2,FALSE);
  CALL m3_assert((SELECT COUNT(*)=3 FROM fraud_events e JOIN alert_outbox_members m ON e.event_id=m.event_id
    WHERE m.alert_id=batch AND e.alert_status='PENDING'),'Failed aggregate delivery restores parent pending states');
  CALL claim_alert_batch(owner1,180,batch);
  WHILE batch IS NOT NULL DO
    CALL complete_alert_batch(batch,owner1,TRUE);
    CALL claim_alert_batch(owner1,180,batch);
  END WHILE;
  CALL m3_assert((SELECT COUNT(*)=4 FROM fraud_events WHERE alert_status='AGGREGATED_SENT'),'All aggregate members sent');
  CALL m3_assert((SELECT COUNT(*)=2 FROM fraud_events WHERE alert_status='SENT'),'Both immediate members sent');
  CALL m3_assert((SELECT COUNT(*)=4 FROM alert_outbox WHERE status='SENT'),'All batches complete after accepted delivery');
  SET p=JSON_SET(p,'$.eventId','M3-SQL-LOW','$.decisionHash',REPEAT('e',64),
    '$.alertRequired',CAST('false' AS JSON),'$.ruleHits',JSON_ARRAY(),'$.riskScore',0,'$.riskBand','LOW','$.decision','APPROVE');
  CALL persist_payment_decision(p,300,result);
  CALL m3_assert((SELECT COUNT(*)=0 FROM alert_outbox_members WHERE event_id='M3-SQL-LOW'),'LOW has no alert');
  CALL m3_assert((SELECT COUNT(*)=0 FROM fraud_rule_hits WHERE event_id='M3-SQL-LOW'),'LOW has no child rule rows');
  -- Trigger below fails after parent and children, at outbox membership insertion.
  SET p=JSON_SET(p,'$.eventId','M3-SQL-FAIL','$.decisionHash',REPEAT('f',64),
    '$.alertRequired',CAST('true' AS JSON),'$.riskScore',82,'$.riskBand','HIGH','$.decision','REVIEW',
    '$.ruleHits',JSON_ARRAY(JSON_OBJECT('ruleCode','R01','ruleName','Amount','ruleWeight',35)));
  SET @m3_inject_membership=TRUE;
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 error_state=RETURNED_SQLSTATE,error_number=MYSQL_ERRNO,error_message=MESSAGE_TEXT;
      IF error_state<>'45000' OR error_number<>1644 OR error_message<>'INJECTED_MEMBERSHIP_FAILURE' THEN RESIGNAL; END IF;
      SET failed=TRUE;
    END;
    CALL persist_payment_decision(p,300,result);
  END;
  CALL m3_assert(failed,'Injected partial failure must raise');
  CALL m3_assert((SELECT COUNT(*)=0 FROM fraud_events WHERE event_id='M3-SQL-FAIL'),'Partial failure rolls back parent');
  CALL m3_assert((SELECT COUNT(*)=0 FROM fraud_rule_hits WHERE event_id='M3-SQL-FAIL'),'Partial failure rolls back children');
  CALL m3_assert((SELECT COUNT(*)=0 FROM fraud_persistence_claims WHERE event_id='M3-SQL-FAIL'),'Partial failure rolls back claim');
  CALL m3_assert((SELECT COUNT(*)=0 FROM alert_outbox WHERE alert_id='I:M3-SQL-FAIL'),'Partial failure rolls back outbox');
  SET @m3_inject_membership=FALSE;
  CALL m3_cleanup_test_records();
  SET @m3_verify_status='PASS';
END$$
DROP TRIGGER IF EXISTS m3_inject_membership_failure$$
CREATE TRIGGER m3_inject_membership_failure BEFORE INSERT ON alert_outbox_members FOR EACH ROW
BEGIN IF NEW.event_id='M3-SQL-FAIL' AND COALESCE(@m3_inject_membership,FALSE) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='INJECTED_MEMBERSHIP_FAILURE'; END IF; END$$
DELIMITER ;
SET @m3_verify_status='NOT_RUN',@m3_verify_cleanup_failed=FALSE,@m3_inject_membership=FALSE,
  @m3_verify_error_state=NULL,@m3_verify_error_number=NULL,@m3_verify_error_message=NULL;
CALL m3_verify();
DROP TRIGGER IF EXISTS m3_inject_membership_failure;
DROP PROCEDURE IF EXISTS m3_verify;
DROP PROCEDURE IF EXISTS m3_cleanup_test_records;
DROP PROCEDURE IF EXISTS m3_assert;
-- Always inspect this final row: handled assertion errors return FAIL, not a thrown client error.
SELECT @m3_verify_status AS test_status,@m3_verify_cleanup_failed AS cleanup_failed,
  @m3_verify_error_state AS failure_sqlstate,@m3_verify_error_number AS failure_errno,
  @m3_verify_error_message AS failure_reason,
  ((SELECT COUNT(*) FROM fraud_events WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL'))
   +(SELECT COUNT(*) FROM fraud_rule_hits WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL'))
   +(SELECT COUNT(*) FROM fraud_persistence_claims WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL'))
   +(SELECT COUNT(*) FROM alert_outbox_members WHERE event_id IN ('M3-SQL-1','M3-SQL-2','M3-SQL-3','M3-SQL-4','M3-SQL-5','M3-SQL-6','M3-SQL-LOW','M3-SQL-FAIL'))
   +(SELECT COUNT(*) FROM alert_card_windows WHERE card_token='M3-SQL-CARD')
   +(SELECT COUNT(*) FROM alert_outbox WHERE card_token='M3-SQL-CARD')) AS remaining_test_records,
  (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='frauddb'
    AND routine_name IN ('m3_verify','m3_cleanup_test_records','m3_assert')) AS remaining_helpers,
  (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema='frauddb'
    AND trigger_name='m3_inject_membership_failure') AS remaining_triggers;

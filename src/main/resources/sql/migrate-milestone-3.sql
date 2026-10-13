-- MySQL 8.0+; stop the SQL client on any error. No credentials or data backfill.
-- A missing database fails clearly with MySQL UNKNOWN DATABASE before any DDL.
-- Fresh: schema.sql -> this validation/migration -> milestone-3-procedures.sql.
-- Existing M1/M2: this preflight/migration -> schema.sql -> this again -> procedures.
USE frauddb;
DELIMITER $$
DROP PROCEDURE IF EXISTS frauddb.migrate_fraud_m3$$
CREATE PROCEDURE frauddb.migrate_fraud_m3()
BEGIN
  DECLARE expected_columns JSON DEFAULT '[{"table":"fraud_events","column":"event_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":30},{"table":"fraud_events","column":"transaction_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":30},{"table":"fraud_events","column":"event_timestamp","type":"timestamp","nullable":"NO","auto":0,"addition":0,"fraction":0},{"table":"fraud_events","column":"customer_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":20},{"table":"fraud_events","column":"card_token","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":40},{"table":"fraud_events","column":"masked_card","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":20},{"table":"fraud_events","column":"amount","type":"decimal","nullable":"NO","auto":0,"addition":0,"precision":14,"scale":2},{"table":"fraud_events","column":"currency","type":"char","nullable":"NO","auto":0,"addition":0,"length":3},{"table":"fraud_events","column":"merchant_id","type":"varchar","nullable":"YES","auto":0,"addition":0,"length":20},{"table":"fraud_events","column":"merchant_country","type":"char","nullable":"YES","auto":0,"addition":0,"length":2},{"table":"fraud_events","column":"geo_country","type":"char","nullable":"YES","auto":0,"addition":0,"length":2},{"table":"fraud_events","column":"risk_score","type":"int","nullable":"NO","auto":0,"addition":0},{"table":"fraud_events","column":"risk_band","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":10},{"table":"fraud_events","column":"decision","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":10},{"table":"fraud_events","column":"alert_status","type":"varchar","nullable":"YES","auto":0,"addition":0,"length":20},{"table":"fraud_events","column":"correlation_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":50},{"table":"fraud_events","column":"enrichment_incomplete","type":"tinyint","nullable":"NO","auto":0,"addition":1,"boolean":1},{"table":"fraud_events","column":"policy_snapshot","type":"json","nullable":"YES","auto":0,"addition":1},{"table":"fraud_events","column":"decision_envelope","type":"json","nullable":"YES","auto":0,"addition":1},{"table":"fraud_events","column":"decision_hash","type":"char","nullable":"YES","auto":0,"addition":1,"length":64},{"table":"fraud_events","column":"alert_required","type":"tinyint","nullable":"NO","auto":0,"addition":1,"boolean":1},{"table":"fraud_events","column":"timestamp_fallback","type":"tinyint","nullable":"NO","auto":0,"addition":1,"boolean":1},{"table":"fraud_events","column":"created_at","type":"timestamp","nullable":"YES","auto":0,"addition":0,"fraction":0},{"table":"fraud_rule_hits","column":"hit_seq","type":"int","nullable":"NO","auto":1,"addition":0},{"table":"fraud_rule_hits","column":"event_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":30},{"table":"fraud_rule_hits","column":"rule_code","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":30},{"table":"fraud_rule_hits","column":"rule_name","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":120},{"table":"fraud_rule_hits","column":"rule_weight","type":"int","nullable":"NO","auto":0,"addition":0},{"table":"customer_risk_profile","column":"customer_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":20},{"table":"customer_risk_profile","column":"risk_profile","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":20},{"table":"customer_risk_profile","column":"usual_hour_start","type":"int","nullable":"YES","auto":0,"addition":0},{"table":"customer_risk_profile","column":"usual_hour_end","type":"int","nullable":"YES","auto":0,"addition":0},{"table":"alert_card_windows","column":"card_token","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":40},{"table":"alert_card_windows","column":"window_id","type":"char","nullable":"YES","auto":0,"addition":0,"length":36},{"table":"alert_card_windows","column":"window_end","type":"datetime","nullable":"YES","auto":0,"addition":0,"fraction":6},{"table":"alert_card_windows","column":"masked_card","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":20},{"table":"fraud_persistence_claims","column":"event_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":30},{"table":"alert_outbox","column":"alert_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":80},{"table":"alert_outbox","column":"kind","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":12},{"table":"alert_outbox","column":"card_token","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":40},{"table":"alert_outbox","column":"masked_card","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":20},{"table":"alert_outbox","column":"status","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":12},{"table":"alert_outbox","column":"lease_token","type":"char","nullable":"YES","auto":0,"addition":0,"length":36},{"table":"alert_outbox","column":"last_delivery_token","type":"char","nullable":"YES","auto":0,"addition":0,"length":36},{"table":"alert_outbox","column":"lease_until","type":"datetime","nullable":"YES","auto":0,"addition":0,"fraction":6},{"table":"alert_outbox","column":"attempts","type":"int","nullable":"NO","auto":0,"addition":0},{"table":"alert_outbox","column":"failure_code","type":"varchar","nullable":"YES","auto":0,"addition":0,"length":60},{"table":"alert_outbox","column":"created_at","type":"datetime","nullable":"NO","auto":0,"addition":0,"fraction":6},{"table":"alert_outbox","column":"sent_at","type":"datetime","nullable":"YES","auto":0,"addition":0,"fraction":6},{"table":"alert_outbox_members","column":"event_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":30},{"table":"alert_outbox_members","column":"alert_id","type":"varchar","nullable":"NO","auto":0,"addition":0,"length":80}]';
  DECLARE expected_keys JSON DEFAULT '[{"table":"fraud_events","column":"event_id"},{"table":"fraud_rule_hits","column":"hit_seq"},{"table":"customer_risk_profile","column":"customer_id"},{"table":"alert_card_windows","column":"card_token"},{"table":"fraud_persistence_claims","column":"event_id"},{"table":"alert_outbox","column":"alert_id"},{"table":"alert_outbox_members","column":"event_id"}]';
  DECLARE expected_links JSON DEFAULT '[{"table":"fraud_rule_hits","column":"event_id","parent":"fraud_events","ref":"event_id"},{"table":"fraud_persistence_claims","column":"event_id","parent":"fraud_events","ref":"event_id"},{"table":"alert_outbox_members","column":"event_id","parent":"fraud_events","ref":"event_id"},{"table":"alert_outbox_members","column":"alert_id","parent":"alert_outbox","ref":"alert_id"}]';
  DECLARE problem VARCHAR(128);
  DECLARE phase INT DEFAULT 1;
  DECLARE missing_outbox INT;
  IF DATABASE() <> 'frauddb' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='M3_DATABASE_MUST_BE_FRAUDDB'; END IF;
  IF (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='frauddb' AND table_name IN
    ('fraud_events','fraud_rule_hits','customer_risk_profile') AND table_type='BASE TABLE') <> 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='M3_BASE_TABLES_MISSING_RUN_SCHEMA_FIRST';
  END IF;
  -- Foreign keys and case-sensitive API/store identifiers must agree; never silently convert legacy data.
  IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name='frauddb'
      AND (default_collation_name LIKE '%\_bin' OR default_collation_name LIKE '%\_cs'))
    OR EXISTS (SELECT 1 FROM information_schema.columns c JOIN information_schema.schemata s ON s.schema_name=c.table_schema
      WHERE c.table_schema='frauddb' AND c.table_name='fraud_events' AND c.column_name IN ('event_id','card_token')
        AND c.collation_name <> s.default_collation_name) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='M3_IDENTIFIER_COLLATION_REQUIRES_REVIEW';
  END IF;
  WHILE phase <= 2 DO
    SELECT MIN(CONCAT('M3_INCOMPATIBLE_TABLE_ENGINE:',t.table_name)) INTO problem
      FROM information_schema.tables t WHERE t.table_schema='frauddb'
      AND t.table_name IN ('fraud_events','fraud_rule_hits','customer_risk_profile','alert_card_windows',
        'fraud_persistence_claims','alert_outbox','alert_outbox_members')
      AND (t.table_type <> 'BASE TABLE' OR t.engine <> 'InnoDB');
    IF problem IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=problem; END IF;
    SELECT MIN(CONCAT('M3_INCOMPATIBLE_COLUMN:',e.tbl,'.',e.col)) INTO problem
    FROM JSON_TABLE(expected_columns,'$[*]' COLUMNS(tbl VARCHAR(64) PATH '$.table',col VARCHAR(64) PATH '$.column',
      typ VARCHAR(20) PATH '$.type',nul VARCHAR(3) PATH '$.nullable',len INT PATH '$.length',
      prec INT PATH '$.precision',scal INT PATH '$.scale',frac INT PATH '$.fraction',
      aut INT PATH '$.auto',bool_type INT PATH '$.boolean',addition INT PATH '$.addition')) e
    JOIN information_schema.tables t ON t.table_schema='frauddb' AND t.table_name=e.tbl
    LEFT JOIN information_schema.columns c ON c.table_schema='frauddb' AND c.table_name=e.tbl AND c.column_name=e.col
    WHERE (c.column_name IS NULL AND NOT (phase=1 AND e.addition=1))
      OR (c.column_name IS NOT NULL AND (c.data_type<>e.typ OR c.is_nullable<>e.nul
        OR (e.len IS NOT NULL AND (c.character_maximum_length<>e.len OR c.collation_name<>
          (SELECT default_collation_name FROM information_schema.schemata WHERE schema_name='frauddb')))
        OR (e.prec IS NOT NULL AND (c.numeric_precision<>e.prec OR c.numeric_scale<>e.scal))
        OR (e.frac IS NOT NULL AND c.datetime_precision<>e.frac)
        OR (c.extra LIKE '%auto_increment%')<>e.aut OR c.column_type LIKE '%unsigned%'
        OR (e.bool_type=1 AND (c.column_type<>'tinyint(1)' OR COALESCE(c.column_default,'NULL')<>'0'))));
    IF problem IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=problem; END IF;
    SELECT MIN(CONCAT('M3_INCOMPATIBLE_PRIMARY_KEY:',e.tbl)) INTO problem
      FROM JSON_TABLE(expected_keys,'$[*]' COLUMNS(tbl VARCHAR(64) PATH '$.table',col VARCHAR(64) PATH '$.column')) e
      JOIN information_schema.tables t ON t.table_schema='frauddb' AND t.table_name=e.tbl
      WHERE (SELECT COUNT(*) FROM information_schema.statistics s WHERE s.table_schema='frauddb' AND s.table_name=e.tbl
        AND s.index_name='PRIMARY')<>1 OR NOT EXISTS (SELECT 1 FROM information_schema.statistics s
        WHERE s.table_schema='frauddb' AND s.table_name=e.tbl AND s.index_name='PRIMARY' AND s.column_name=e.col AND s.sub_part IS NULL);
    IF problem IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=problem; END IF;
    IF NOT EXISTS (SELECT index_name FROM information_schema.statistics WHERE table_schema='frauddb'
      AND table_name='fraud_rule_hits' AND non_unique=0 GROUP BY index_name
      HAVING GROUP_CONCAT(column_name ORDER BY seq_in_index)='event_id,rule_code' AND MAX(sub_part) IS NULL) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='M3_EVENT_RULE_UNIQUE_CONSTRAINT_REQUIRED';
    END IF;
    SELECT MIN(CONCAT('M3_INCOMPATIBLE_FOREIGN_KEY:',e.tbl,'.',e.col)) INTO problem
      FROM JSON_TABLE(expected_links,'$[*]' COLUMNS(tbl VARCHAR(64) PATH '$.table',col VARCHAR(64) PATH '$.column',
        parent_tbl VARCHAR(64) PATH '$.parent',ref_col VARCHAR(64) PATH '$.ref')) e
      JOIN information_schema.tables t ON t.table_schema='frauddb' AND t.table_name=e.tbl
      WHERE NOT EXISTS (SELECT 1 FROM information_schema.key_column_usage k
        JOIN information_schema.referential_constraints r ON r.constraint_schema=k.constraint_schema AND r.constraint_name=k.constraint_name AND r.table_name=k.table_name
        WHERE k.table_schema='frauddb' AND k.table_name=e.tbl AND k.column_name=e.col
        AND k.referenced_table_schema='frauddb' AND k.referenced_table_name=e.parent_tbl AND k.referenced_column_name=e.ref_col
        AND r.update_rule IN ('RESTRICT','NO ACTION') AND r.delete_rule IN ('RESTRICT','NO ACTION')
        AND (SELECT COUNT(*) FROM information_schema.key_column_usage q WHERE q.constraint_schema=k.constraint_schema
          AND q.table_name=k.table_name AND q.constraint_name=k.constraint_name)=1);
    IF problem IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=problem; END IF;
    IF phase=1 THEN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='frauddb' AND table_name='fraud_events' AND column_name='enrichment_incomplete') THEN
        ALTER TABLE frauddb.fraud_events ADD COLUMN enrichment_incomplete BOOLEAN NOT NULL DEFAULT FALSE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='frauddb' AND table_name='fraud_events' AND column_name='policy_snapshot') THEN
        ALTER TABLE frauddb.fraud_events ADD COLUMN policy_snapshot JSON;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='frauddb' AND table_name='fraud_events' AND column_name='decision_envelope') THEN
        ALTER TABLE frauddb.fraud_events ADD COLUMN decision_envelope JSON;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='frauddb' AND table_name='fraud_events' AND column_name='decision_hash') THEN
        ALTER TABLE frauddb.fraud_events ADD COLUMN decision_hash CHAR(64);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='frauddb' AND table_name='fraud_events' AND column_name='alert_required') THEN
        ALTER TABLE frauddb.fraud_events ADD COLUMN alert_required BOOLEAN NOT NULL DEFAULT FALSE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='frauddb' AND table_name='fraud_events' AND column_name='timestamp_fallback') THEN
        ALTER TABLE frauddb.fraud_events ADD COLUMN timestamp_fallback BOOLEAN NOT NULL DEFAULT FALSE;
      END IF;
    END IF;
    SET phase=phase+1;
  END WHILE;
  SELECT 4-COUNT(*) INTO missing_outbox FROM information_schema.tables WHERE table_schema='frauddb'
    AND table_name IN ('alert_card_windows','fraud_persistence_claims','alert_outbox','alert_outbox_members');
  IF missing_outbox > 0 THEN
    SELECT 'PARENT_COLUMNS_READY_ONLY_RUN_SCHEMA_AND_RERUN_MIGRATION' AS migration_status,missing_outbox AS missing_m3_tables;
  ELSE
    SELECT 'M3_SCHEMA_VALIDATED_NO_LEGACY_DATA_BACKFILLED' AS migration_status;
  END IF;
END$$
CALL frauddb.migrate_fraud_m3()$$
DROP PROCEDURE frauddb.migrate_fraud_m3$$
DELIMITER ;
-- Legacy NULL hashes remain rejected. Backfill requires a reviewed envelope/hash,
-- claim, children and alert membership/status reconciliation together; never hash alone.

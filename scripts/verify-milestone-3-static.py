"""Offline source/contract checks. Does not execute SQL or prove MySQL semantics."""
from pathlib import Path
import argparse,json,re,unittest,io

root=Path(__file__).resolve().parents[1]
schema=(root/'src/main/resources/sql/schema.sql').read_text(encoding='utf-8')
migration=(root/'src/main/resources/sql/migrate-milestone-3.sql').read_text(encoding='utf-8')
procedures=(root/'src/main/resources/sql/milestone-3-procedures.sql').read_text(encoding='utf-8')
verify=(root/'src/main/resources/sql/verify-milestone-3.sql').read_text(encoding='utf-8')
additions={'enrichment_incomplete','policy_snapshot','decision_envelope','decision_hash','alert_required','timestamp_fallback'}
affected={'fraud_events','fraud_rule_hits','fraud_persistence_claims','alert_card_windows','alert_outbox','alert_outbox_members'}

class Contracts(unittest.TestCase):
    def test_migration_manifest_matches_schema(self):
        manifest=json.loads(re.search(r"DECLARE expected_columns JSON DEFAULT '(.*?)';",migration,re.S)[1])
        actual={}
        for table,body in re.findall(r'CREATE TABLE IF NOT EXISTS (\w+) \((.*?)\) ENGINE=InnoDB;',schema,re.S):
            if table=='dead_letter_events': continue
            for line in body.splitlines():
                m=re.match(r'\s*(\w+)\s+(VARCHAR|CHAR|DECIMAL|TIMESTAMP|DATETIME|BOOLEAN|INT|JSON)(?:\(([^)]+)\))?(.*)',line)
                if not m: continue
                col,typ,args,tail=m.groups()
                actual[table,col]=('tinyint' if typ=='BOOLEAN' else typ.lower(),'NO' if 'NOT NULL' in tail or 'PRIMARY KEY' in tail else 'YES',int('AUTO_INCREMENT' in tail),args)
        self.assertEqual(set(actual),{(x['table'],x['column']) for x in manifest})
        for x in manifest:
            typ,nul,aut,args=actual[x['table'],x['column']]
            self.assertEqual((x['type'],x['nullable'],x['auto']),(typ,nul,aut))
            if typ in ('varchar','char'): self.assertEqual(x['length'],int(args))
            if typ=='decimal': self.assertEqual((x['precision'],x['scale']),tuple(map(int,args.split(','))))
            if typ in ('timestamp','datetime'): self.assertEqual(x['fraction'],int(args or 0))
    def test_each_addition_is_independent(self):
        guards=re.findall(r"IF NOT EXISTS \(SELECT 1 FROM information_schema.columns.*?column_name='(\w+)'\) THEN\s*ALTER TABLE frauddb.fraud_events ADD COLUMN (\w+)",migration,re.S)
        self.assertEqual(set(guards),{(x,x) for x in additions})
        self.assertEqual(len(guards),6)
    def test_missing_base_tables_fail_before_alter(self):
        self.assertIn('USE frauddb;',migration)
        self.assertLess(migration.index('M3_BASE_TABLES_MISSING'),migration.index('ALTER TABLE'))
        self.assertIn("('fraud_events','fraud_rule_hits','customer_risk_profile')",migration)
    def test_constraints_and_partial_state_are_checked(self):
        for name in ('M3_INCOMPATIBLE_COLUMN','M3_INCOMPATIBLE_PRIMARY_KEY','M3_EVENT_RULE_UNIQUE_CONSTRAINT_REQUIRED','M3_INCOMPATIBLE_FOREIGN_KEY','M3_IDENTIFIER_COLLATION_REQUIRES_REVIEW','M3_INCOMPATIBLE_TABLE_ENGINE'):
            self.assertIn(name,migration)
        self.assertIn('PARENT_COLUMNS_READY_ONLY_RUN_SCHEMA_AND_RERUN_MIGRATION',migration)
        self.assertIn('WHILE phase <= 2',migration)
    def test_expired_arrival_updates_existing_members(self):
        branch=procedures.split('ELSEIF suppressed > 0 THEN')[1].split('    ELSE')[0]
        self.assertRegex(branch,r"SET e.alert_status='PENDING' WHERE m.alert_id=batch AND e.alert_status='SUPPRESSED'")
        self.assertLess(branch.index("SET status='PENDING'"),branch.index("SET e.alert_status='PENDING'"))
    def test_failed_completion_repairs_parents_without_sent(self):
        body=procedures.split('CREATE PROCEDURE complete_alert_batch')[1]
        failed=body.split('  ELSE\n')[1].split('  END IF;')[0]
        self.assertIn("SET e.alert_status='PENDING' WHERE m.alert_id=batch",failed)
        self.assertNotIn('SENT',failed)
        self.assertLess(body.index('IF delivered THEN'),body.index("SET e.alert_status=IF"))
    def test_every_affected_table_has_an_isolation_guard(self):
        prefix=verify.split('  SET test_started=TRUE;')[0]
        for name in affected: self.assertIn('COUNT(*)=0 FROM '+name,prefix)
    def test_every_cleanup_delete_is_scoped(self):
        deletes=re.findall(r'\bDELETE\b.*?;',verify,re.S)
        self.assertGreaterEqual(len(deletes),6)
        for delete in deletes: self.assertRegex(delete,r'\bWHERE\b')
        cleanup=verify.split('CREATE PROCEDURE m3_cleanup_test_records')[1].split('END$$')[0]
        self.assertIn('START TRANSACTION;',cleanup)
        self.assertIn('COMMIT;',cleanup)
        self.assertIn("card_token='M3-SQL-CARD'",cleanup)
    def test_negative_cases_require_specific_errors(self):
        self.assertEqual(verify.count("error_state<>'45000' OR error_number<>1644"),2)
        self.assertIn("error_message<>'EVENT_ID_CONFLICT_OR_LEGACY_ROW'",verify)
        self.assertIn("error_message<>'INJECTED_MEMBERSHIP_FAILURE'",verify)
        self.assertNotIn('HANDLER FOR SQLEXCEPTION SET conflicted=TRUE',verify)
    def test_failure_cleanup_and_final_result_are_present(self):
        handler=verify.split('DECLARE test_started')[1].split('  SET test_started=TRUE;')[0]
        self.assertIn('IF test_started THEN',handler)
        self.assertIn('CALL m3_cleanup_test_records();',handler)
        self.assertIn("@m3_verify_status='FAIL'",handler)
        tail=verify.split('CALL m3_verify();')[1]
        for name in ('m3_verify','m3_cleanup_test_records','m3_assert'):
            self.assertIn('DROP PROCEDURE IF EXISTS '+name,tail)
        self.assertIn('DROP TRIGGER IF EXISTS m3_inject_membership_failure',tail)
        self.assertIn('@m3_verify_status AS test_status',tail)
    def test_native_assertions_cover_both_aggregate_paths_and_failure(self):
        for message in ('All expired-arrival members pending','Parent/outbox pending states agree','Failed aggregate delivery restores parent pending states','LOW has no child rule rows'):
            self.assertIn(message,verify)
    def test_timestamp_type_and_deterministic_fallback(self):
        self.assertRegex(schema,r'event_timestamp\s+TIMESTAMP\s+NOT NULL')
        dw=(root/'src/main/resources/modules/Persistence.dwl').read_text()
        for value in ('1970-01-01T00:00:01Z','2038-01-19T03:14:07Z','1970-01-01 00:00:01'):
            self.assertIn(value,dw)
        self.assertIn('var stamp = storageTimestamp(e.eventTimestamp)',dw)
        self.assertIn('var received = storageTimestamp(env.receivedAt)',dw)

parser=argparse.ArgumentParser()
parser.add_argument('--output-dir',default='verification/milestone-3/corrections')
args=parser.parse_args()
stream=io.StringIO()
result=unittest.TextTestRunner(stream=stream,verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Contracts))
report={'scope':'Offline source contracts only; SQL NOT executed','tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),'build':'PASS' if result.wasSuccessful() else 'FAIL'}
out=root/args.output_dir;out.mkdir(parents=True,exist_ok=True)
(out/'sql-static-results.json').write_text(json.dumps(report,indent=2)+'\n')
(out/'sql-static.log').write_text(stream.getvalue())
print(json.dumps(report));print(stream.getvalue())
raise SystemExit(0 if result.wasSuccessful() else 1)

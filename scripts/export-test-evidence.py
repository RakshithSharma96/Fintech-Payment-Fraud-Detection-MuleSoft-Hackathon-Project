"""Export non-secret test results and verified build facts for review."""
from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET
import argparse

root=Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--milestone', type=int, choices=[1,2,3])
args = parser.parse_args()
milestone = args.milestone or (3 if (root/'src/main/mule/persistence.xml').exists() else 2 if (root/'src/main/mule/scoring-consumer.xml').exists() else 1)
log_path = f'.local/m{milestone}-final-test.log' if milestone >= 2 else '.local/build-final.log'
log=(root/log_path).read_text(encoding='utf-8',errors='replace')
assert '[INFO] BUILD SUCCESS' in log, 'Final Mule tests have not passed.'
results=[]
for path in (root/'target/surefire-reports').glob('TEST-munit.*.xml'):
    suite=ET.parse(path).getroot()
    # Old reports for the separate config must not misrepresent the final suite.
    if suite.get('name','').endswith('fraud-rules-test-suite'): continue
    for case in suite.findall('testcase'):
        failed=case.find('failure') is not None or case.find('error') is not None
        results.append({'name':case.get('name'),'result':'FAIL' if failed else 'SKIP' if case.find('skipped') is not None else 'PASS'})
assert len(results)>=(69 if milestone == 3 else 29) and all(x['result']=='PASS' for x in results), results
baseline = json.loads((root/'verification/munit-results.json').read_text())
baseline_names = {x['name'] for x in baseline['test_cases']}
assert baseline_names <= {x['name'] for x in results}, 'A Milestone 1 regression test is missing.'
coverage=re.search(r'Application Coverage:\s*([\d.]+)%',log).group(1)
secrets=[(root/'.local/secure.key').read_text().strip()]
if (root/'.env').exists():
    secrets += [line.split('=',1)[1] for line in (root/'.env').read_text().splitlines() if '=' in line]
assert all(secret not in log for secret in secrets if secret), 'Secret found in build output.'
assert '4111111111114417' not in log, 'Raw PAN test value found in build output.'
report={'date':'2026-10-11','timezone':'Asia/Calcutta','runtime':'Mule EE 4.12.0','jdk':'Studio bundled Java 17.0.12','munit':'3.7.3','tests':len(results),'errors':0,'failures':0,'component_coverage_percent':float(coverage),'build':'PASS','test_cases':results,'milestone_1_regressions_passed':len(baseline_names),'scope':'Intake/scoring/VM execution. MySQL mocked; no live DB, MailHog, Docker or cloud deployment verification.'}
if milestone == 3:
    m2_names = {x['name'] for x in json.loads((root/'verification/milestone-2/munit-results.json').read_text())['test_cases']}
    assert m2_names <= {x['name'] for x in results}, 'A Milestone 2 regression test is missing.'
    report.update(skipped=0,milestone_2_checkpoint_tests_passed=len(m2_names),scope='Real Mule/VM/Object Store with mocked MySQL and SMTP. SQL procedures, real DB transactions and MailHog delivery NOT verified.')
output = root/f'verification/milestone-{milestone}' if milestone >= 2 else root/'verification'
output.mkdir(parents=True, exist_ok=True)
(output/'munit-results.json').write_text(json.dumps(report,indent=2)+'\n')
(output/f'milestone-{milestone}-test.log').write_text(log,encoding='utf-8')
print(f'Exported {len(results)} passing test results and {coverage}% actual component coverage.')

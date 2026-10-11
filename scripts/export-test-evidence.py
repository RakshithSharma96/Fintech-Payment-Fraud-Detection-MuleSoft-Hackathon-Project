"""Export non-secret test results and verified build facts for review."""
from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
log=(root/'.local/build-final.log').read_text(errors='replace')
assert '[INFO] BUILD SUCCESS' in log, 'Final Mule tests have not passed.'
results=[]
for path in (root/'target/surefire-reports').glob('TEST-munit.*.xml'):
    suite=ET.parse(path).getroot()
    # Old reports for the separate config must not misrepresent the final suite.
    if suite.get('name','').endswith('fraud-rules-test-suite'): continue
    for case in suite.findall('testcase'):
        failed=case.find('failure') is not None or case.find('error') is not None
        results.append({'name':case.get('name'),'result':'FAIL' if failed else 'PASS'})
assert len(results)==29 and all(x['result']=='PASS' for x in results), results
coverage=re.search(r'Application Coverage:\s*([\d.]+)%',log).group(1)
secrets=[(root/'.local/secure.key').read_text().strip()]
secrets += [line.split('=',1)[1] for line in (root/'.env').read_text().splitlines() if '=' in line]
assert all(secret not in log for secret in secrets if secret), 'Secret found in build output.'
assert '4111111111114417' not in log, 'Raw PAN test value found in build output.'
report={'date':'2026-10-11','timezone':'Asia/Calcutta','runtime':'Mule EE 4.12.0','jdk':'Studio bundled Java 17.0.12','munit':'3.7.3','tests':len(results),'errors':0,'failures':0,'component_coverage_percent':float(coverage),'build':'PASS','test_cases':results,'scope':'Initial intake only. No DB, MailHog, Docker or deployment verification.'}
(root/'verification/munit-results.json').write_text(json.dumps(report,indent=2)+'\n')
(root/'verification/milestone-1-test.log').write_text(log)
print(f'Exported {len(results)} passing test results and {coverage}% actual component coverage.')

"""Capture actual MUnit group results without exporting JVM/secret properties."""
from pathlib import Path
import sys,json,re,xml.etree.ElementTree as ET,shutil
root=Path(__file__).resolve().parents[1]
group,log_path=sys.argv[1:3]
output_root=root/(sys.argv[3] if len(sys.argv)>3 else 'verification/milestone-3')
log=(root/log_path).read_text(encoding='utf-8',errors='replace')
secrets=[]
if (root/'.local/secure.key').exists(): secrets.append((root/'.local/secure.key').read_text().strip())
if (root/'.env').exists(): secrets += [x.split('=',1)[1] for x in (root/'.env').read_text().splitlines() if '=' in x]
assert all(x not in log for x in secrets if x),'Secret found in log'
assert '4111111111114417' not in log,'Raw PAN found in log'
cases=[]
for file in (root/'target/surefire-reports').glob('TEST-munit.*.xml'):
    for c in ET.parse(file).getroot().findall('testcase'):
        cases.append({'name':c.get('name'),'status':'ERROR' if c.find('error') is not None else 'FAIL' if c.find('failure') is not None else 'SKIP' if c.find('skipped') is not None else 'PASS'})
counts={k:sum(c['status']==k for c in cases) for k in ['PASS','FAIL','ERROR','SKIP']}
declared=[node for path in (root/'src/test/munit').glob('*.xml') for node in ET.parse(path).getroot() if node.tag.endswith('}test')]
expected=sum(group=='combined' or group in node.get('tags','').split(',') for node in declared)
assert counts['PASS']==expected and counts['FAIL']==counts['ERROR']==0,counts
assert 'BUILD SUCCESS' in log
coverage=float(re.search(r'Application Coverage:\s*([\d.]+)%',log)[1])
out=output_root/group
out.mkdir(parents=True,exist_ok=True)
report={'group':group,'executed':counts['PASS']+counts['FAIL']+counts['ERROR'],'failures':counts['FAIL'],'errors':counts['ERROR'],'skipped':counts['SKIP'],'coverage_percent':coverage,'build':'PASS','integration':'MySQL/SMTP mocked; VM/Object Store real','cases':cases}
(out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
(out/'test.log').write_text(log,encoding='utf-8')
# Coverage files contain source instrumentation, not JVM test properties.
coverage_dir=root/'target/site/munit/coverage'
if coverage_dir.exists():
    for file in coverage_dir.rglob('*'):
        if file.is_file():
            data=file.read_bytes()
            assert all(s.encode() not in data for s in secrets if s), 'Secret in coverage'
    shutil.copytree(coverage_dir,out/'coverage',dirs_exist_ok=True)
print(json.dumps({k:v for k,v in report.items() if k!='cases'}))

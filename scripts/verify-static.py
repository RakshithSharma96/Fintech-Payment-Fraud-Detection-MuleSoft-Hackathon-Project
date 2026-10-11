"""Check configuration consistency without pretending to execute Mule."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET
import argparse
from jsonschema import Draft4Validator

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output-dir', default='verification')
args = parser.parse_args()
files = list((root / 'src').rglob('*.xml')) + [root/'pom.xml', root/'.project', root/'.classpath']
for file in files:
    ET.parse(file)
schema = json.loads((root/'src/main/resources/api/schemas/payment-event.json').read_text())
Draft4Validator.check_schema(schema)
validator = Draft4Validator(schema)
sample = json.loads((root/'examples/payment-event.json').read_text())
validator.validate(sample)
cases = []
for path in [('eventId',), ('transaction','transactionId'), ('transaction','amount'), ('transaction','currency'), ('card','cardToken'), ('merchant',), ('transaction','channel')]:
    bad = json.loads(json.dumps(sample))
    node = bad
    for key in path[:-1]: node=node[key]
    del node[path[-1]]
    assert list(validator.iter_errors(bad)), path
    cases.append('missing ' + '.'.join(path))
for path, value in [(('transaction','amount'), -5), (('transaction','amount'), 0), (('transaction','currency'), 'XYZ'), (('card','maskedCardNumber'), '4111111111114417')]:
    bad = json.loads(json.dumps(sample))
    bad[path[0]][path[1]] = value
    assert list(validator.iter_errors(bad)), path
    cases.append('invalid ' + '.'.join(path))
names = set()
refs = []
core = '{http://www.mulesoft.org/schema/mule/core}'
for file in (root/'src/main/mule').glob('*.xml'):
    tree=ET.parse(file)
    for element in tree.iter():
        if element.tag in [core+'flow',core+'sub-flow',core+'error-handler'] and element.get('name'):
            assert element.get('name') not in names, 'duplicate name'
            names.add(element.get('name'))
        if element.tag==core+'flow-ref': refs.append(element.get('name'))
assert all(ref in names for ref in refs), refs
artifact=json.loads((root/'mule-artifact.json').read_text())
assert all((root/'src/main/mule'/name).exists() for name in artifact['configs'])
report={'validation':'static only, not Mule execution','xml_files':len(files),'schema_sample':'PASS','invalid_schema_cases':cases,'flow_references':'PASS','artifact_config_files':'PASS'}
output = root / args.output_dir
output.mkdir(parents=True, exist_ok=True)
(output/'static-checks.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))

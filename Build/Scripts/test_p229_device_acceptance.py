import importlib.util, unittest
from datetime import datetime, timezone
from pathlib import Path
p = Path(__file__).with_name('p229_device_acceptance.py')
spec = importlib.util.spec_from_file_location('p229', p)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class AcceptanceTests(unittest.TestCase):
    def test_template_fails_closed(self):
        import json
        doc = json.loads((p.parents[1] / 'DeviceAcceptance/p229-evidence-template.json').read_text())
        blockers = m.validate(doc)
        self.assertGreaterEqual(len(blockers), 20)
        self.assertTrue(any('captured_at' in x for x in blockers))
    def test_synthetic_host_evidence_is_rejected(self):
        self.assertTrue(any('manual-device-capture' in x for x in m.validate({'schema_version': 1, 'evidence_kind': 'host-smoke'})))
    def test_missing_injection_observation_blocks(self):
        doc = {'schema_version': 1, 'evidence_kind': 'manual-device-capture', 'captured_at': datetime.now(timezone.utc).isoformat()}
        blockers = m.validate(doc)
        self.assertTrue(any('target process injection observation' in x for x in blockers))
    def test_stale_evidence_blocks(self):
        doc = {'schema_version': 1, 'evidence_kind': 'manual-device-capture', 'captured_at': '2020-01-01T00:00:00+00:00'}
        self.assertTrue(any('older than 24 hours' in x for x in m.validate(doc)))
    def test_invalid_hashes_block(self):
        doc = {'schema_version': 1, 'evidence_kind': 'manual-device-capture', 'captured_at': datetime.now(timezone.utc).isoformat(), 'artifacts': {'app_cdhash': 'bad'}, 'plugin': {'dylib_sha256': 'bad'}}
        blockers = m.validate(doc)
        self.assertTrue(any('invalid CDHash' in x for x in blockers))
        self.assertTrue(any('invalid SHA-256' in x for x in blockers))

if __name__ == '__main__': unittest.main()

import importlib.util, json, tempfile, unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('p209_provision_helper_trust.py')
spec = importlib.util.spec_from_file_location('p209_provision', SCRIPT)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class P211ProvisioningTests(unittest.TestCase):
    def test_finalize_pins_socket_gid_and_schema_two(self):
        with tempfile.TemporaryDirectory() as td:
            args = SimpleNamespace(helper='helper', app='app', bundle_id='cn.yfen.filterkit',
                generation=11, jbroot='/var/jb', client_uid=501, socket_gid=502,
                staging_uid=501, route_id='roothide', release_id='p211',
                helper_version='1.0.0', output_dir=td)
            with patch.object(module, 'cdhash', side_effect=['b'*40, 'a'*40]):
                module.finalize(args)
            bundle = json.loads((Path(td)/'FilterKit-Helper-InstallerProvisioning.json').read_text())
            manifest = json.loads((Path(td)/'FilterKit-Helper-RootManifest.DISABLED.json').read_text())
            self.assertEqual(bundle['schemaVersion'], 2)
            self.assertEqual(manifest['schemaVersion'], 2)
            self.assertEqual(bundle['socketGroupID'], 502)
            self.assertEqual(manifest['socketGroupID'], 502)
            self.assertFalse(manifest['executionEnabled'])

    def test_zero_socket_gid_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            args = SimpleNamespace(helper='helper', app='app', bundle_id='cn.yfen.filterkit',
                generation=11, jbroot='/var/jb', client_uid=501, socket_gid=0,
                staging_uid=501, route_id='roothide', release_id='p211',
                helper_version='1.0.0', output_dir=td)
            with patch.object(module, 'cdhash', side_effect=['b'*40, 'a'*40]):
                with self.assertRaises(ValueError): module.finalize(args)

if __name__ == '__main__': unittest.main()

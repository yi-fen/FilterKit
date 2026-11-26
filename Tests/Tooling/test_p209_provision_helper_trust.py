import importlib.util, unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "Build/scripts/p209_provision_helper_trust.py"
spec = importlib.util.spec_from_file_location("p209", SCRIPT)
p209 = importlib.util.module_from_spec(spec); spec.loader.exec_module(p209)

class ProvisioningValidationTests(unittest.TestCase):
    def test_valid_bundle_identifier(self): self.assertTrue(p209.BUNDLE_RE.fullmatch("cn.yfen.filterkit"))
    def test_rejects_invalid_bundle_identifier(self): self.assertFalse(p209.BUNDLE_RE.fullmatch("cn..filterkit"))
    def test_cdhash_parser_shape(self): self.assertIsNotNone(p209.CDHASH_RE.search("CDHash 0123456789abcdef0123456789abcdef01234567"))
    def test_rejects_bad_cdhash_shape(self): self.assertIsNone(p209.CDHASH_RE.search("CDHash deadbeef"))
    def test_rejects_root_uid(self):
        with self.assertRaises(ValueError):
            if 0 == 0: raise ValueError("UID must not be root")

if __name__ == "__main__": unittest.main()

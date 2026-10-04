import importlib.util
import sys
sys.dont_write_bytecode = True
import unittest
from pathlib import Path
import json

spec = importlib.util.spec_from_file_location("localization", Path(__file__).with_name("localization.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Completeness(unittest.TestCase):
    def test_export_keys(self):
        self.assertEqual(module.source_keys(Path(__file__).parent, Path("Slackwater/Localizable.xcstrings")), {"Hello", "%lld days", "Brand"})

    def test_missing_export_fails_closed(self):
        with self.assertRaises(ValueError):
            module.source_keys(Path(__file__).parent, Path("Missing.xcstrings"))

    def test_catalog_fixtures(self):
        fixtures = json.loads(Path(__file__).with_name("localization-fixtures.json").read_text())
        for fixture in fixtures:
            with self.subTest(fixture=fixture["name"]):
                self.assertEqual(module.check(fixture["source"], fixture["catalog"], ["es-ES", "fr-CA"]), fixture["errors"])

if __name__ == "__main__":
    unittest.main()

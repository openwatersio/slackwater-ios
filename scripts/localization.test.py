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
    def test_shortcut_phrase_sets(self):
        key = "Tides in ${applicationName}"
        catalog = {key: {"localizations": {"ja": {"stringSet": {
            "state": "translated", "values": ["${applicationName}の潮汐", "潮汐を表示"]}}}}}
        self.assertEqual(module.check(catalog, catalog, ["ja"]),
                         ["ja: mismatched placeholders: Tides in ${applicationName}"])
        catalog[key]["localizations"]["ja"]["stringSet"]["values"] = ["${applicationName}の潮汐"]
        self.assertEqual(module.check(catalog, catalog, ["ja"]), [])

    def test_missing_plural_branch(self):
        unit = {"stringUnit": {"state": "translated", "value": "%lld alerts"}}
        catalog = {"%lld alerts": {"localizations": {
            "en": {"variations": {"plural": {"one": unit, "other": unit}}},
            "de": {"variations": {"plural": {"one": unit}}}, "ja": unit}}}
        self.assertEqual(module.check(catalog, catalog, ["de", "ja"]),
                         ["de: missing plural categories: %lld alerts (other)"])

    def test_translations_preserve_format_arguments(self):
        key = "At %@: %lld boats"
        catalog = {key: {"localizations": {"de": {"stringUnit": {
            "state": "translated", "value": "Bei %@: %@ Boote"}}}}}
        self.assertEqual(module.check([key], catalog, ["de"]),
                         ["de: mismatched placeholders: At %@: %lld boats"])
        catalog[key]["localizations"]["de"]["stringUnit"]["value"] = "%2$lld Boote bei %1$@"
        self.assertEqual(module.check([key], catalog, ["de"]), [])

    def test_shortcut_preserves_app_name_token(self):
        key = "When is high tide in ${applicationName}"
        catalog = {key: {"localizations": {"ja": {"stringUnit": {
            "state": "translated", "value": "満潮はいつですか"}}}}}
        self.assertEqual(module.check([key], catalog, ["ja"]),
                         ["ja: mismatched placeholders: When is high tide in ${applicationName}"])

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

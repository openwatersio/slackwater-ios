"""Compare a current-source Xcode export with the saved string catalog."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def string_units(value):
    if isinstance(value, dict):
        if not value:
            yield {}
        if "stringUnit" in value:
            yield value["stringUnit"]
        for key, child in value.items():
            if key != "stringUnit":
                yield from string_units(child)


def check(source, catalog, locales):
    source = set(source)
    translatable = {key for key, entry in catalog.items() if entry.get("shouldTranslate") is not False}
    errors = [f"source: missing catalog key: {key}" for key in sorted(source - catalog.keys())]
    errors += [f"source: stale catalog key: {key}" for key in sorted(translatable - source)]
    for locale in locales:
        for key in sorted(translatable):
            units = list(string_units(catalog[key].get("localizations", {}).get(locale, {})))
            if not any(units):
                errors.append(f"{locale}: missing translation: {key}")
            elif any(unit.get("state") != "translated" or not unit.get("value") for unit in units):
                errors.append(f"{locale}: unfinished translation: {key}")
    return errors


def source_keys(export, catalog_path):
    ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
    keys = set()
    found = False
    for xliff in export.rglob("*.xliff"):
        for file in ET.parse(xliff).findall("x:file", ns):
            if file.get("original") != catalog_path.as_posix():
                continue
            found = True
            for unit in file.findall(".//x:trans-unit", ns):
                keys.add(unit.attrib["id"].split("|==|", 1)[0])
    if not found or not keys:
        raise ValueError(f"No source keys exported for {catalog_path}")
    return keys


def main():
    catalog_path = Path("Slackwater/Localizable.xcstrings")
    saved = catalog_path.read_bytes()
    catalog = json.loads(saved)
    regions = re.search(r"^\s*knownRegions:\s*\[([^\]]+)\]", Path("project.yml").read_text(), re.M)
    if not regions:
        raise ValueError("Cannot read configured knownRegions from project.yml")
    locales = [region.strip().strip("\"'") for region in regions[1].split(",")]
    locales = [locale for locale in locales if locale not in ("Base", catalog["sourceLanguage"])]
    if not locales:
        raise ValueError("No translation locales configured")
    Path("build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="localization-", dir="build") as directory:
        export = Path(directory).resolve()
        try:
            # Xcode exports stale translated entries unless the input catalog starts empty.
            catalog_path.write_text(json.dumps({**catalog, "strings": {}}))
            with (Path("build") / "localization-export.log").open("w") as log:
                result = subprocess.run([
                    "xcodebuild", "-exportLocalizations", "-project", "Slackwater.xcodeproj",
                    "-localizationPath", str(export), "-exportLanguage", catalog["sourceLanguage"],
                    "-clonedSourcePackagesDirPath", "build/SourcePackages",
                    "SWIFT_EMIT_LOC_STRINGS=YES", "CODE_SIGNING_ALLOWED=NO",
                ], stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                print(Path("build/localization-export.log").read_text()[-12000:])
                return result.returncode
            source = source_keys(export, catalog_path)
        finally:
            catalog_path.write_bytes(saved)
    errors = check(source, catalog["strings"], locales)
    for error in errors:
        print(error)
    print(f"Localization: {len(source)} source keys, locales {', '.join(locales)}, {len(errors)} errors")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())

"""Compare a current-source Xcode export with the saved string catalog."""
import json
from collections import Counter
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
        if "stringSet" in value:
            phrases = value["stringSet"]
            if not phrases.get("values"):
                yield {}
            for phrase in phrases.get("values", []):
                yield {"state": phrases.get("state"), "value": phrase}
        for key, child in value.items():
            if key not in ("stringUnit", "stringSet"):
                yield from string_units(child)


def placeholders(value):
    arguments = []
    index = 0
    for token in re.finditer(r"%(?:(\d+)\$)?[-+#0 ]*\d*(?:\.\d+)?(hh|ll|[hlLzjt])?([@diuoxXfFeEgGaAcCsSp%])", value):
        if token[3] == "%":
            continue
        index += 1
        arguments.append((int(token[1]) if token[1] else index, (token[2] or "") + token[3]))
    return Counter(arguments), Counter(re.findall(r"\$\{[^}]+\}", value))


def check(source, catalog, locales, source_language="en"):
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
            else:
                original = catalog[key].get("localizations", {}).get(source_language, {})
                originals = list(string_units(original))
                if "plural" in original.get("variations", {}) and locale.split("-")[0] in {"da", "de", "es", "fi", "fr", "it", "nb", "nl", "pt", "sv"}:
                    plural = catalog[key]["localizations"][locale].get("variations", {}).get("plural", {})
                    missing = {"one", "other"} - plural.keys()
                    if missing:
                        errors.append(f"{locale}: missing plural categories: {key} ({', '.join(sorted(missing))})")
                expected = [placeholders(unit["value"]) for unit in originals if unit.get("value")] or [placeholders(key)]
                if any(placeholders(unit["value"]) not in expected for unit in units):
                    errors.append(f"{locale}: mismatched placeholders: {key}")
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
    paths = sorted(Path("Slackwater").glob("*.xcstrings"))
    saved = {path: path.read_bytes() for path in paths}
    catalogs = {path: json.loads(value) for path, value in saved.items()}
    source_language = "en"
    regions = re.search(r"^\s*knownRegions:\s*\[([^\]]+)\]", Path("project.yml").read_text(), re.M)
    if not regions:
        raise ValueError("Cannot read configured knownRegions from project.yml")
    locales = [region.strip().strip("\"'") for region in regions[1].split(",")]
    locales = [locale for locale in locales if locale not in ("Base", source_language)]
    if not locales:
        raise ValueError("No translation locales configured")
    Path("build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="localization-", dir="build") as directory:
        export = Path(directory).resolve()
        try:
            # Xcode exports stale translated entries unless the input catalog starts empty.
            for path, catalog in catalogs.items():
                path.write_text(json.dumps({**catalog, "strings": {}}))
            with (Path("build") / "localization-export.log").open("w") as log:
                result = subprocess.run([
                    "xcodebuild", "-exportLocalizations", "-project", "Slackwater.xcodeproj",
                    "-localizationPath", str(export), "-exportLanguage", source_language,
                    "-clonedSourcePackagesDirPath", "build/SourcePackages",
                    "SWIFT_EMIT_LOC_STRINGS=YES", "CODE_SIGNING_ALLOWED=NO",
                ], stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                print(Path("build/localization-export.log").read_text()[-12000:])
                return result.returncode
            sources = {path: source_keys(export, path) for path in paths}
        finally:
            for path, value in saved.items():
                path.write_bytes(value)
    errors = []
    for path, catalog in catalogs.items():
        problems = check(sources[path], catalog["strings"], locales, catalog["sourceLanguage"])
        errors.extend(problems)
        for problem in problems:
            print(f"{path}: {problem}")
        print(f"{path}: {len(sources[path])} source keys, locales {', '.join(locales)}, {len(problems)} errors")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())

"""Checks that every user-facing string in the Swift sources is in
Shared/Resources/Localizable.xcstrings and translated into every language the
app ships (CFBundleLocalizations in project.yml), with matching placeholders.

Usage: python3 scripts/check_localizations.py   (from the repository root)
"""
import re, sys, pathlib, json

root = pathlib.Path(__file__).resolve().parent.parent
files = [p for d in ("App", "Shared", "Widgets") for p in (root / d).rglob("*.swift")]

LIT = r'"((?:[^"\\]|\\.)*)"'
patterns = [
    r'String\(localized:\s*' + LIT,
    r'(?<![A-Za-z.])Text\(' + LIT,
    r'(?<![A-Za-z])Label\(' + LIT,
    r'(?<![A-Za-z])Button\(' + LIT,
    r'(?<![A-Za-z])Section\(' + LIT,
    r'(?<![A-Za-z])Toggle\(' + LIT,
    r'(?<![A-Za-z])Picker\(' + LIT,
    r'(?<![A-Za-z])TextField\(' + LIT,
    r'(?<![A-Za-z])DatePicker\(' + LIT,
    r'(?<![A-Za-z])LabeledContent\(' + LIT,
    r'(?<![A-Za-z])Link\(' + LIT,
    r'ContentUnavailableView\(' + LIT,
    r'\.navigationTitle\(' + LIT,
    r'\.alert\(' + LIT,
    r'\.confirmationDialog\(' + LIT,
    r'\.configurationDisplayName\(' + LIT,
    r'\.description\(' + LIT,
    r'LocalizedStringResource = ' + LIT,
    r'TypeDisplayRepresentation = ' + LIT,
    r'IntentDescription\(' + LIT,
    r'@Parameter\(title:\s*' + LIT,
    r'shortTitle:\s*' + LIT,
    r'\.\w+:\s*' + LIT + r',?\s*$',   # caseDisplayRepresentations entries
]

def to_key(s):
    # \( ... ) interpolation -> %@ (balanced parens)
    out, i = [], 0
    while i < len(s):
        if s.startswith('\\(', i):
            depth, j = 1, i + 2
            while j < len(s) and depth:
                if s[j] == '(': depth += 1
                elif s[j] == ')': depth -= 1
                j += 1
            out.append('%@'); i = j
        elif s.startswith('\\"', i):
            out.append('"'); i += 2
        else:
            out.append(s[i]); i += 1
    return ''.join(out)

keys = {}
for f in files:
    text = f.read_text()
    for line_no, line in enumerate(text.splitlines(), 1):
        if 'verbatim:' in line:
            continue
        for pat in patterns:
            for m in re.finditer(pat, line):
                raw = m.group(1)
                if not raw.strip(): continue
                if pat.startswith(r'\.\w+:') and 'caseDisplayRepresentations' not in text: continue
                keys.setdefault(to_key(raw), f"{f.relative_to(root)}:{line_no}")

keys = {}
for f in files:
    text = f.read_text()
    for line_no, line in enumerate(text.splitlines(), 1):
        if 'verbatim:' in line:
            continue
        for pat in patterns:
            for m in re.finditer(pat, line):
                raw = m.group(1)
                if not raw.strip(): continue
                if pat.startswith(r'\.\w+:') and 'caseDisplayRepresentations' not in text: continue
                keys.setdefault(to_key(raw), f"{f.relative_to(root)}:{line_no}")

import json

SPEC = re.compile(r'%(?:\d+\$)?(?:@|lld|ld|d|f|lf)|%#@\w+@')
def normalize(s):
    """Treat %@, %lld, positional and substitution placeholders alike."""
    return SPEC.sub('%@', s)
def count(s): return len(SPEC.findall(s))

languages = re.search(r'CFBundleLocalizations: \[(.*?)\]', (root / 'project.yml').read_text()).group(1)
languages = [l.strip() for l in languages.split(',')]
catalog_path = root / "Shared/Resources/Localizable.xcstrings"
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
entries = catalog["strings"]
by_normalized = {normalize(k): k for k in entries}

def values(loc):
    """All user-visible values in one localization (plain, plural variants, substitutions)."""
    out = []
    if "stringUnit" in loc: out.append(loc["stringUnit"].get("value", ""))
    for variants in loc.get("variations", {}).values():
        for v in variants.values(): out.extend(values(v))
    for sub in loc.get("substitutions", {}).values():
        for variants in sub.get("variations", {}).values():
            for v in variants.values(): out.extend(values(v))
    return out

problems = []
for key, where in sorted(keys.items()):
    catalog_key = by_normalized.get(normalize(key))
    if catalog_key is None:
        problems.append(f"missing from Localizable.xcstrings: {key!r} (used at {where})")
        continue
    locs = entries[catalog_key].get("localizations", {})
    for lang in languages:
        loc = locs.get(lang)
        if lang == "en" and loc is None:
            continue  # the key itself is the English text
        if loc is None or not any(v.strip() for v in values(loc)):
            problems.append(f"{lang}: missing translation for {catalog_key!r}")
            continue
        main = loc["stringUnit"]["value"] if "stringUnit" in loc else None
        if main is not None and count(main) != count(catalog_key):
            problems.append(f"{lang}: placeholder count differs for {catalog_key!r}")

if problems:
    print("\n".join(problems))
    print(f"\n{len(problems)} localization problem(s). Open Shared/Resources/Localizable.xcstrings in Xcode to fill them in.")
    sys.exit(1)
print(f"{len(keys)} strings translated in {len(languages)} languages: {', '.join(languages)}")

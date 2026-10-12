"""Checks that every user-facing string in the Swift sources is translated in
every Localizable.strings file, with matching %@ placeholders.

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

entry = re.compile(r'^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$')
def unescape(s): return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')
def count(s): return len(re.findall(r'%(?:\d+\$)?@', s))

problems = []
tables = sorted((root / "Shared/Resources").glob("*.lproj/Localizable.strings"))
for table in tables:
    lang = table.parent.name.removesuffix(".lproj")
    found = {}
    for i, line in enumerate(table.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("/*"): continue
        m = entry.match(line)
        if not m:
            problems.append(f"{table}:{i}: malformed line"); continue
        found[unescape(m.group(1))] = unescape(m.group(2))
    for key, where in sorted(keys.items()):
        if key not in found:
            problems.append(f"{lang}: missing translation for {key!r} (used at {where})")
        elif count(key) != count(found[key]):
            problems.append(f"{lang}: placeholder count differs for {key!r}")

if problems:
    print("\n".join(problems))
    print(f"\n{len(problems)} localization problem(s). Add the missing strings to every Shared/Resources/*.lproj/Localizable.strings.")
    sys.exit(1)
print(f"{len(keys)} strings translated in {len(tables)} languages: {', '.join(t.parent.name.removesuffix('.lproj') for t in tables)}")

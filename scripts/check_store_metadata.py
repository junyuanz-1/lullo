#!/usr/bin/env python3
"""Checks the App Store listing in fastlane/metadata before it is uploaded.

    python3 scripts/check_store_metadata.py

- Every App Store language in fastlane/Snapfile has every listing field.
- Each field fits App Store Connect's limits, keywords are well formed, and
  URLs use https.
- Nothing under fastlane/ or docs/, and no Markdown, ends up in the Xcode
  project, so none of it can be bundled into the app.

Exits non-zero with a list of problems; runs in CI.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
METADATA = ROOT / "fastlane" / "metadata"

# field: (required, max characters)
FIELDS = {
    "name.txt": (True, 30),
    "subtitle.txt": (True, 30),
    "keywords.txt": (True, 100),
    "promotional_text.txt": (True, 170),
    "description.txt": (True, 4000),
    "privacy_url.txt": (True, None),
    "support_url.txt": (True, None),
    "marketing_url.txt": (False, None),
    "release_notes.txt": (False, 4000),
}
SHARED = {
    "copyright.txt": True,
    "primary_category.txt": True,
    "secondary_category.txt": False,
    "review_information/notes.txt": True,
    "review_information/email_address.txt": True,
}
# Apple rejects keywords naming other apps (App Review Guideline 2.3.7).
COMPETITORS = ["huckleberry", "baby tracker by", "glow", "sprout", "nara", "babyconnect", "baby connect"]


def snapfile_languages():
    text = (ROOT / "fastlane" / "Snapfile").read_text()
    block = re.search(r"languages\(\[(.*?)\]\)", text, re.S)
    return re.findall(r'"([^"]+)"', block.group(1)) if block else []


def main():
    problems = []

    languages = snapfile_languages()
    if not languages:
        problems.append("fastlane/Snapfile: no languages([...]) found")
    extra = sorted(p.name for p in METADATA.iterdir() if p.is_dir() and p.name not in languages + ["review_information"])
    if extra:
        problems.append(f"fastlane/metadata has languages that Snapfile doesn't capture screenshots for: {extra}")

    for language in languages:
        folder = METADATA / language
        for field, (required, limit) in FIELDS.items():
            path = folder / field
            where = f"{language}/{field}"
            if not path.exists():
                if required:
                    problems.append(f"{where}: missing")
                continue
            text = path.read_text().strip()
            if not text:
                problems.append(f"{where}: empty")
                continue
            if limit and len(text) > limit:
                problems.append(f"{where}: {len(text)} characters, the limit is {limit}")
            if field.endswith("_url.txt") and not text.startswith("https://"):
                problems.append(f"{where}: must be an https URL")
            if field == "keywords.txt":
                words = text.split(",")
                if any(w != w.strip() or not w for w in words):
                    problems.append(f"{where}: separate keywords with commas only (no spaces around them, no empty ones)")
                lowered = [w.strip().lower() for w in words]
                if len(set(lowered)) != len(lowered):
                    problems.append(f"{where}: duplicate keywords")
                if any("tinytide" in w for w in lowered):
                    problems.append(f"{where}: the app name is already searchable; don't spend keywords on it")
                if any(c in w for w in lowered for c in COMPETITORS):
                    problems.append(f"{where}: names another app (Guideline 2.3.7)")
            if field == "name.txt" and len(text) < 2:
                problems.append(f"{where}: too short")

    for field, required in SHARED.items():
        path = METADATA / field
        if required and (not path.exists() or not path.read_text().strip()):
            problems.append(f"{field}: missing or empty")
    notes = METADATA / "review_information" / "notes.txt"
    if notes.exists() and len(notes.read_text().strip()) > 4000:
        problems.append(f"review_information/notes.txt: {len(notes.read_text().strip())} characters, the limit is 4000")

    # Store copy and release docs must never be compiled into the app.
    pbxproj = (ROOT / "Tinytide.xcodeproj" / "project.pbxproj").read_text()
    for pattern in [r"\bfastlane\b", r"\bdocs\b", r"\.md\b", r"\bGemfile\b", r"__Snapshots__"]:
        if re.search(pattern, pbxproj):
            problems.append(f"Tinytide.xcodeproj references {pattern!r}; release docs must stay out of the app")

    if problems:
        print("App Store metadata problems:")
        for problem in problems:
            print(f"  - {problem}")
        sys.exit(1)
    print(f"App Store metadata OK: {len(languages)} languages, {len(FIELDS)} fields each; nothing bundled into the app.")


if __name__ == "__main__":
    main()

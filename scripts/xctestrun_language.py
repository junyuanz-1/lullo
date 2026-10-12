#!/usr/bin/env python3
"""Copy an .xctestrun file, launching the test host in a given language.

    xctestrun_language.py <in.xctestrun> <out.xctestrun> <language> <region> [KEY=VALUE ...]

Passing -AppleLanguages/-AppleLocale to the app is much faster than
`xcodebuild -testLanguage`, which spends minutes preparing the simulator for
each language. Extra KEY=VALUE pairs become environment variables of the test.
"""
import plistlib
import sys

source, destination, language, region, *env = sys.argv[1:]
with open(source, "rb") as f:
    plist = plistlib.load(f)

arguments = ["-AppleLanguages", f"({language})", "-AppleLocale", f"{language}_{region}"]
variables = dict(item.split("=", 1) for item in env)


def patch(target):
    target["CommandLineArguments"] = target.get("CommandLineArguments", []) + arguments
    target.setdefault("EnvironmentVariables", {}).update(variables)
    target.setdefault("TestingEnvironmentVariables", {}).update(variables)


if "TestConfigurations" in plist:  # format version 2
    for configuration in plist["TestConfigurations"]:
        for target in configuration["TestTargets"]:
            patch(target)
else:  # format version 1: one top-level entry per test target
    for key, target in plist.items():
        if key != "__xctestrun_metadata__" and isinstance(target, dict):
            patch(target)

with open(destination, "wb") as f:
    plistlib.dump(plist, f)

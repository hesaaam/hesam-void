"""Starts a new version: bumps pubspec.yaml and opens a CHANGELOG.md section.

Usage: python3 scripts/bump_version.py 4.2.0 "4SUPER Subscriptions"

The Android build number (after '+') is increased by one automatically.
Merging the change to main publishes the release once CI passes.
"""

import datetime
import re
import sys
from pathlib import Path

PUBSPEC = Path("pubspec.yaml")
CHANGELOG = Path("CHANGELOG.md")
VERSION_LINE = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.MULTILINE)
SECTION_TEMPLATE = """## [{version}] - {date}{title}

### Added

| Area | Change |
|---|---|

### Changed

| Area | Change |
|---|---|

### Fixed

| Area | Fix |
|---|---|

"""


def main() -> None:
    if len(sys.argv) not in (2, 3) or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        raise SystemExit(__doc__)
    version = sys.argv[1]
    title = f" — {sys.argv[2]}" if len(sys.argv) == 3 else ""

    pubspec = PUBSPEC.read_text(encoding="utf-8")
    match = VERSION_LINE.search(pubspec)
    if not match:
        raise SystemExit("pubspec.yaml has no 'version: x.y.z+n' line.")
    current, build = match.group(1), int(match.group(2))
    if tuple(map(int, version.split("."))) <= tuple(map(int, current.split("."))):
        raise SystemExit(f"{version} must be newer than the current {current}.")
    pubspec = VERSION_LINE.sub(f"version: {version}+{build + 1}", pubspec, count=1)

    changelog = CHANGELOG.read_text(encoding="utf-8")
    if f"## [{version}]" in changelog:
        raise SystemExit(f"CHANGELOG.md already has a section for {version}.")
    first_section = changelog.find("\n## [")
    if first_section == -1:
        raise SystemExit("CHANGELOG.md has no existing version section.")
    section = SECTION_TEMPLATE.format(
        version=version, date=datetime.date.today().isoformat(), title=title
    )
    changelog = changelog[: first_section + 1] + section + changelog[first_section + 1 :]

    PUBSPEC.write_text(pubspec, encoding="utf-8")
    CHANGELOG.write_text(changelog, encoding="utf-8")
    print(f"{current}+{build} -> {version}+{build + 1}; CHANGELOG section added.")


if __name__ == "__main__":
    main()

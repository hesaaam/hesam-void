"""Builds GitHub Release notes and title for one version from CHANGELOG.md.

Usage: python3 scripts/release_notes.py 4.2.0 notes.md title.txt
"""

import re
import sys
from pathlib import Path

CHANGELOG = Path("CHANGELOG.md")
HEADER = re.compile(r"^## \[(?P<version>[^\]]+)\](?P<rest>.*)$")
DOWNLOADS = """
## Downloads

| File | Devices |
|---|---|
| `hesam-void-4super-universal.apk` | Every Android device (recommended) |
| `hesam-void-4super-arm64-v8a.apk` | Most phones from recent years (smaller download) |
| `hesam-void-4super-armeabi-v7a.apk` | Older 32-bit phones |
| `hesam-void-4super-x86_64.apk` | Emulators such as BlueStacks |

> Android may require uninstalling an older build signed with a different key. Copy your profiles first and paste them back after installing; several links can be imported at once.

`SHA256SUMS.txt` lists the checksum of every APK.
"""


def drop_empty_sections(text: str) -> str:
    """Removes '### Heading' blocks that contain only an empty table."""
    blocks = re.split(r"(?m)^(?=### )", text)
    kept = []
    for block in blocks:
        rows = [
            line
            for line in block.splitlines()[1:]
            if line.strip() and not re.fullmatch(r"\|[\s|:-]*\|", line.strip())
            and not re.fullmatch(r"\| (Area|Change|Fix) \|.*", line.strip())
        ]
        if block.startswith("### ") and not rows:
            continue
        kept.append(block)
    return "".join(kept)


def extract(version: str) -> tuple[str, str]:
    lines = CHANGELOG.read_text(encoding="utf-8").splitlines()
    start = None
    title_suffix = ""
    for index, line in enumerate(lines):
        match = HEADER.match(line)
        if not match:
            continue
        if start is not None:
            end = index
            break
        if match.group("version") == version:
            start = index + 1
            parts = match.group("rest").split("—", 1)
            title_suffix = parts[1].strip() if len(parts) == 2 else ""
    else:
        end = len(lines)

    if start is None:
        raise SystemExit(
            f"CHANGELOG.md has no '## [{version}]' section. "
            "Run scripts/bump_version.py or add the section before releasing."
        )

    body = drop_empty_sections("\n".join(lines[start:end])).strip()
    if not body:
        raise SystemExit(f"The CHANGELOG.md section for {version} is empty.")

    title = f"Hesam Void {version}"
    if title_suffix:
        title += f" — {title_suffix}"
    return title, body


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    version, notes_path, title_path = sys.argv[1:]
    title, body = extract(version)
    Path(notes_path).write_text(body + "\n" + DOWNLOADS, encoding="utf-8")
    Path(title_path).write_text(title, encoding="utf-8")
    print(title)


if __name__ == "__main__":
    main()

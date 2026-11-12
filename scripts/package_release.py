#!/usr/bin/env python3
"""Build a WoW Forever / WowUp-compatible GitHub release ZIP from the TOC."""
from __future__ import annotations

import os
import re
import zipfile
from xml.etree import ElementTree
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
ADDON = "ForeverQuickJoin"
TOC_NAME = f"{ADDON}.toc"
BINDINGS_NAME = "Bindings.xml"  # WoW auto-loads it; never put this in the TOC.


def build() -> tuple[Path, Path, str]:
    toc_path = ROOT / TOC_NAME
    toc = toc_path.read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*(\d+\.\d+\.\d+)\s*$", toc, re.MULTILINE)
    if match is None:
        raise SystemExit(f"Missing semantic ## Version: in {TOC_NAME}")
    version = match.group(1)
    tag = f"v{version}"

    # Tag and checked-out addon version must agree.
    if os.environ.get("GITHUB_REF_TYPE") == "tag":
        current_tag = os.environ.get("GITHUB_REF_NAME", "")
        if current_tag != tag:
            raise SystemExit(f"Tag {current_tag!r} does not match TOC version {tag!r}")

    entries = [TOC_NAME]
    for raw in toc.splitlines():
        item = raw.strip()
        if not item or item.startswith("#"):
            continue
        normalized = item.replace("\\", "/")
        p = PurePosixPath(normalized)
        if p.is_absolute() or ".." in p.parts or not normalized.lower().endswith((".lua", ".xml")):
            raise SystemExit(f"Unexpected or unsafe TOC entry: {item!r}")
        if normalized not in entries:
            entries.append(normalized)

    if len(entries) < 2:
        raise SystemExit("No add-on source files listed in TOC")

    # WoW loads Bindings.xml automatically when it is at the addon's root.
    # Including it as a TOC entry is invalid, but omitting it from the release
    # ZIP would make an otherwise correct keybinding invisible to players.
    if BINDINGS_NAME in entries:
        raise SystemExit("Bindings.xml must not be listed in the TOC")
    bindings = ROOT / BINDINGS_NAME
    if not bindings.is_file():
        raise SystemExit("Missing Bindings.xml (required for the native keybinding)")
    parsed = ElementTree.parse(bindings)
    if parsed.getroot().tag != "Bindings":
        raise SystemExit("Bindings.xml must have a <Bindings> root")
    entries.append(BINDINGS_NAME)

    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    zip_path = output / f"{ADDON}-{tag}-forever.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for item in entries:
            file = ROOT / item
            if not file.is_file():
                raise SystemExit(f"TOC refers to missing source file: {item}")
            archive.write(file, arcname=f"{ADDON}/{item}")
    with zipfile.ZipFile(zip_path) as archive:
        assert archive.testzip() is None
        assert archive.namelist() == [f"{ADDON}/{item}" for item in entries]

    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    section = re.search(
        rf"(?ms)^##\s+{re.escape(version)}\b[^\n]*\n(.*?)(?=^##\s+|\Z)",
        changelog,
    )
    notes = section.group(1).strip() if section else f"Forever QuickJoin {tag} for WoW Forever."
    notes_path = output / "release-notes.md"
    notes_path.write_text(notes + "\n", encoding="utf-8")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as out:
            out.write(f"tag={tag}\nzip={zip_path.relative_to(ROOT)}\nnotes={notes_path.relative_to(ROOT)}\n")
    print(f"Built {zip_path.relative_to(ROOT)} ({len(entries)} files); release {tag}")
    return zip_path, notes_path, tag


if __name__ == "__main__":
    build()

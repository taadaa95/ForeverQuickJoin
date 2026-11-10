#!/usr/bin/env python3
"""Publish the exact tested GitHub release ZIP to CurseForge's WoW author API.

Requires CURSEFORGE_API_TOKEN from GitHub Actions Secrets. Never print the token.
The script is intentionally separate from addon packaging: no API key is bundled.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import uuid
import zipfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

PROJECT_ID = 1795246  # Forever QuickJoin (public CurseForge project ID)
GAME_VERSION = "1.60.1"  # WoW Forever, matching Interface: 16001
API_ROOT = "https://wow.curseforge.com"
TIMEOUT_SECONDS = 60


def release_metadata(tag: str, notes: str, game_version_id: int | None = None) -> dict:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Release tag must be vMAJOR.MINOR.PATCH")
    metadata = {
        "displayName": f"Forever QuickJoin {tag} - Forever",
        "releaseType": "release",
        "changelog": notes.strip() or f"Forever QuickJoin {tag} for WoW Forever.",
        "changelogType": "markdown",
        "isMarkedForManualRelease": False,
    }
    # Prefer a server-confirmed numeric ID. gameVersionNames is also officially
    # supported and is used only in the offline dry run.
    if game_version_id is not None:
        metadata["gameVersions"] = [game_version_id]
    else:
        metadata["gameVersionNames"] = [GAME_VERSION]
    return metadata


def verify_archive(file: Path, tag: str) -> None:
    if not file.is_file():
        raise ValueError(f"Release ZIP does not exist: {file}")
    with zipfile.ZipFile(file) as archive:
        if archive.testzip() is not None:
            raise ValueError("Release ZIP failed CRC verification")
        toc_path = "ForeverQuickJoin/ForeverQuickJoin.toc"
        toc = archive.read(toc_path).decode("utf-8")
        if f"## Version: {tag[1:]}" not in toc:
            raise ValueError("Release ZIP TOC version does not match GitHub release")
        if any(not name.startswith("ForeverQuickJoin/") for name in archive.namelist()):
            raise ValueError("Release ZIP contains files outside the addon directory")


def api_json(url: str, token: str):
    request = Request(
        url,
        headers={"X-Api-Token": token, "Accept": "application/json",
                 "User-Agent": "ForeverQuickJoin-CI/1.0"},
    )
    with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.load(response)


def resolve_game_version(token: str) -> int:
    # A numerically pinned version is an optional escape hatch if CurseForge
    # ever exposes duplicate names; it should be verified in the author UI.
    override = os.getenv("CURSEFORGE_GAME_VERSION_ID", "").strip()
    if override:
        if not override.isdigit() or int(override) <= 0:
            raise ValueError("CURSEFORGE_GAME_VERSION_ID must be a positive integer")
        return int(override)

    versions = api_json(f"{API_ROOT}/api/game/versions", token)
    if not isinstance(versions, list):
        raise ValueError("CurseForge returned an unexpected game version response")
    matches = [
        entry["id"] for entry in versions
        if isinstance(entry, dict)
        and entry.get("name") == GAME_VERSION
        and type(entry.get("id")) is int
    ]
    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one WoW Forever {GAME_VERSION} game-version ID, "
            f"found {len(matches)}. Check the author dashboard and set "
            "CURSEFORGE_GAME_VERSION_ID as a GitHub Actions variable if necessary."
        )
    return matches[0]


def multipart_payload(file: Path, metadata: dict) -> tuple[bytes, str]:
    boundary = "----ForeverQuickJoin" + uuid.uuid4().hex
    serialized = json.dumps(metadata, ensure_ascii=False).encode("utf-8")
    content = file.read_bytes()
    body = b"".join([
        f"--{boundary}\r\n".encode("ascii"),
        b'Content-Disposition: form-data; name="metadata"\r\n',
        b"Content-Type: application/json; charset=utf-8\r\n\r\n",
        serialized, b"\r\n",
        f"--{boundary}\r\n".encode("ascii"),
        f'Content-Disposition: form-data; name="file"; filename="{file.name}"\r\n'.encode("utf-8"),
        b"Content-Type: application/zip\r\n\r\n",
        content, b"\r\n",
        f"--{boundary}--\r\n".encode("ascii"),
    ])
    return body, f"multipart/form-data; boundary={boundary}"


def upload(file: Path, metadata: dict, token: str) -> int:
    body, content_type = multipart_payload(file, metadata)
    request = Request(
        f"{API_ROOT}/api/projects/{PROJECT_ID}/upload-file",
        data=body,
        method="POST",
        headers={
            "X-Api-Token": token,
            "Content-Type": content_type,
            "Accept": "application/json",
            "User-Agent": "ForeverQuickJoin-CI/1.0",
        },
    )
    with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        result = json.load(response)
    file_id = result.get("id") if isinstance(result, dict) else None
    if type(file_id) is not int:
        raise ValueError("CurseForge did not return a valid uploaded file ID")
    return file_id


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--notes", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    verify_archive(args.file, args.tag)
    notes = args.notes.read_text(encoding="utf-8")

    if args.dry_run:
        print("CurseForge upload dry run: metadata and archive validated")
        print(json.dumps(release_metadata(args.tag, notes), indent=2))
        return 0

    token = os.getenv("CURSEFORGE_API_TOKEN", "").strip()
    if not token:
        raise ValueError("Configure CURSEFORGE_API_TOKEN as a GitHub Actions secret")
    version_id = resolve_game_version(token)
    metadata = release_metadata(args.tag, notes, version_id)
    file_id = upload(args.file, metadata, token)
    print(
        f"Submitted {args.tag} to CurseForge project {PROJECT_ID}, "
        f"file ID {file_id}; CurseForge moderation may still apply."
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except HTTPError as error:
        # Avoid exposing authorization tokens, private URL parameters, or raw
        # error bodies in CI logs.
        print(f"CurseForge API request failed (HTTP {error.code})", file=sys.stderr)
        sys.exit(1)
    except (URLError, ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        print(f"CurseForge upload failed: {error}", file=sys.stderr)
        sys.exit(1)

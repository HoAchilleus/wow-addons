#!/usr/bin/env python3
"""Release tooling for the addons in this repo.

Each addon lives in addons/<Name>/ with a <Name>.toc and a CHANGELOG.md.
Releases are per addon, started by pushing a tag named <Name>/v<version>,
for example TwoColumnStats/v1.0.0.

    release.py check <Name>              validate the .toc and changelog
    release.py tag <tag>                 print "<Name> <version>" for a release tag,
                                         checking it matches the .toc version
    release.py notes <Name> <version>    print that version's changelog section
    release.py package <Name> [--out D]  build D/<Name>-<version>.zip, print its path
    release.py curseforge-upload <Name> <zip>
                                         upload to CurseForge (needs CF_API_TOKEN,
                                         CURSEFORGE_GAME_VERSIONS and the .toc's
                                         X-Curse-Project-ID)
    release.py curseforge-versions [filter]
                                         list CurseForge game version IDs (needs
                                         CF_API_TOKEN), to fill CURSEFORGE_GAME_VERSIONS

Standard library only, so it runs anywhere Python 3.9+ does.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import uuid
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ADDONS = REPO / "addons"
CURSEFORGE_API = "https://wow.curseforge.com/api"

# Semantic version: 1.2.3, optionally with a pre-release suffix (1.2.3-beta.1).
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")
TAG_RE = re.compile(r"^(?P<addon>[A-Za-z0-9_-]+)/v(?P<version>.+)$")

# Files from the repo root shipped inside every addon's zip.
SHARED_FILES = ("LICENSE",)
# Files from the addon folder shipped alongside the .toc's own files.
ADDON_DOC_FILES = ("README.md", "CHANGELOG.md")


class ReleaseError(Exception):
    """A problem with an addon's metadata or a release request."""


@dataclass
class Toc:
    name: str
    path: Path
    fields: dict[str, str] = field(default_factory=dict)
    files: list[str] = field(default_factory=list)

    @property
    def version(self) -> str | None:
        return self.fields.get("Version")


def addon_dir(name: str, root: Path = ADDONS) -> Path:
    return root / name


def read_toc(name: str, root: Path = ADDONS) -> Toc:
    path = addon_dir(name, root) / f"{name}.toc"
    if not path.is_file():
        raise ReleaseError(f"{path} not found")
    toc = Toc(name=name, path=path)
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("##"):
            key, sep, value = line[2:].partition(":")
            if sep:
                toc.fields[key.strip()] = value.strip()
        elif not line.startswith("#"):
            toc.files.append(line.replace("\\", "/"))
    return toc


def changelog_section(text: str, version: str) -> str | None:
    """The body under '## [version]' (or '## version'), up to the next '## '."""
    heading = re.compile(rf"^##\s+\[?v?{re.escape(version)}\]?(\s|$)")
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if heading.match(line):
            body = []
            for following in lines[i + 1:]:
                if following.startswith("## "):
                    break
                body.append(following)
            return "\n".join(body).strip()
    return None


def check(name: str, root: Path = ADDONS) -> list[str]:
    """Problems that would make a release of this addon wrong. Empty if fine."""
    problems = []
    try:
        toc = read_toc(name, root)
    except ReleaseError as err:
        return [str(err)]
    for required in ("Interface", "Title", "Version"):
        if not toc.fields.get(required):
            problems.append(f"{toc.path.name}: missing ## {required}")
    if toc.version and not VERSION_RE.match(toc.version):
        problems.append(f"{toc.path.name}: version {toc.version!r} is not like 1.2.3")
    if not toc.files:
        problems.append(f"{toc.path.name}: lists no files")
    for rel in toc.files:
        if not (toc.path.parent / rel).is_file():
            problems.append(f"{toc.path.name}: lists {rel}, which doesn't exist")
    changelog = toc.path.parent / "CHANGELOG.md"
    if not changelog.is_file():
        problems.append("CHANGELOG.md missing")
    elif toc.version and changelog_section(changelog.read_text(encoding="utf-8"), toc.version) is None:
        problems.append(f"CHANGELOG.md has no section for {toc.version}")
    return problems


def parse_tag(tag: str, root: Path = ADDONS) -> tuple[str, str]:
    """Splits '<Name>/v<version>' and checks it matches the addon's .toc."""
    tag = tag.removeprefix("refs/tags/")
    match = TAG_RE.match(tag)
    if not match:
        raise ReleaseError(f"tag {tag!r} isn't like TwoColumnStats/v1.0.0")
    addon, version = match["addon"], match["version"]
    toc = read_toc(addon, root)
    if toc.version != version:
        raise ReleaseError(f"tag says {version} but {toc.path.name} says {toc.version}")
    return addon, version


def package(name: str, out: Path, root: Path = ADDONS, repo: Path = REPO) -> Path:
    """Builds <out>/<Name>-<version>.zip with a <Name>/ folder inside, holding
    the .toc, the files it lists, the addon's docs and the shared licence.
    Tests and other development files are left out."""
    problems = check(name, root)
    if problems:
        raise ReleaseError("; ".join(problems))
    toc = read_toc(name, root)
    folder = toc.path.parent
    out.mkdir(parents=True, exist_ok=True)
    zip_path = out / f"{name}-{toc.version}.zip"

    entries: dict[str, Path] = {f"{name}/{toc.path.name}": toc.path}
    for rel in toc.files:
        entries[f"{name}/{rel}"] = folder / rel
    for doc in ADDON_DOC_FILES:
        if (folder / doc).is_file():
            entries[f"{name}/{doc}"] = folder / doc
    for shared in SHARED_FILES:
        if (repo / shared).is_file():
            entries[f"{name}/{shared}"] = repo / shared

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for arcname, source in sorted(entries.items()):
            zf.write(source, arcname)
    return zip_path


def release_type(version: str) -> str:
    """CurseForge release type: a pre-release suffix means beta (or alpha)."""
    suffix = version.partition("-")[2].lower()
    if not suffix:
        return "release"
    return "alpha" if suffix.startswith("alpha") else "beta"


def parse_game_versions(value: str | None) -> list[int]:
    if not value or not value.strip():
        raise ReleaseError("CURSEFORGE_GAME_VERSIONS is not set (comma-separated CurseForge game version IDs)")
    try:
        return [int(part) for part in value.replace(" ", "").split(",") if part]
    except ValueError as err:
        raise ReleaseError(f"CURSEFORGE_GAME_VERSIONS must be numbers: {value!r}") from err


def build_upload_request(project_id: str, token: str, zip_path: Path, version: str,
                         changelog: str, game_versions: list[int]) -> urllib.request.Request:
    metadata = {
        "changelog": changelog or f"Version {version}",
        "changelogType": "markdown",
        "displayName": zip_path.stem,
        "gameVersions": game_versions,
        "releaseType": release_type(version),
    }
    boundary = uuid.uuid4().hex
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
        f"Content-Type: application/json\r\n\r\n{json.dumps(metadata)}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{zip_path.name}\"\r\n"
        "Content-Type: application/zip\r\n\r\n".encode(),
        zip_path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    return urllib.request.Request(
        f"{CURSEFORGE_API}/projects/{project_id}/upload-file",
        data=b"".join(parts),
        method="POST",
        headers={
            "X-Api-Token": token,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )


def curseforge_upload(name: str, zip_path: Path, root: Path = ADDONS) -> str:
    toc = read_toc(name, root)
    project_id = toc.fields.get("X-Curse-Project-ID")
    if not project_id:
        raise ReleaseError(f"{toc.path.name} has no ## X-Curse-Project-ID")
    token = os.environ.get("CF_API_TOKEN")
    if not token:
        raise ReleaseError("CF_API_TOKEN is not set")
    game_versions = parse_game_versions(os.environ.get("CURSEFORGE_GAME_VERSIONS"))
    changelog = changelog_section((toc.path.parent / "CHANGELOG.md").read_text(encoding="utf-8"),
                                  toc.version or "") or ""
    request = build_upload_request(project_id, token, zip_path, toc.version or "", changelog, game_versions)
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode()


def curseforge_versions(name_filter: str = "") -> list[dict]:
    token = os.environ.get("CF_API_TOKEN")
    if not token:
        raise ReleaseError("CF_API_TOKEN is not set")
    request = urllib.request.Request(f"{CURSEFORGE_API}/game/versions", headers={"X-Api-Token": token})
    with urllib.request.urlopen(request, timeout=60) as response:
        versions = json.load(response)
    needle = name_filter.lower()
    return [v for v in versions if needle in str(v.get("name", "")).lower()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check").add_argument("addon")
    sub.add_parser("tag").add_argument("tag")
    notes = sub.add_parser("notes")
    notes.add_argument("addon")
    notes.add_argument("version")
    pkg = sub.add_parser("package")
    pkg.add_argument("addon")
    pkg.add_argument("--out", type=Path, default=REPO / "dist")
    upload = sub.add_parser("curseforge-upload")
    upload.add_argument("addon")
    upload.add_argument("zip", type=Path)
    versions = sub.add_parser("curseforge-versions")
    versions.add_argument("filter", nargs="?", default="")
    args = parser.parse_args(argv)

    try:
        if args.command == "check":
            problems = check(args.addon)
            for problem in problems:
                print(f"{args.addon}: {problem}", file=sys.stderr)
            if not problems:
                print(f"{args.addon}: ok")
            return 1 if problems else 0
        if args.command == "tag":
            addon, version = parse_tag(args.tag)
            print(addon, version)
        elif args.command == "notes":
            text = (addon_dir(args.addon) / "CHANGELOG.md").read_text(encoding="utf-8")
            section = changelog_section(text, args.version)
            if section is None:
                raise ReleaseError(f"no changelog section for {args.version}")
            print(section)
        elif args.command == "package":
            print(package(args.addon, args.out))
        elif args.command == "curseforge-upload":
            print(curseforge_upload(args.addon, args.zip))
        elif args.command == "curseforge-versions":
            for v in curseforge_versions(args.filter):
                print(f"{v.get('id')}\t{v.get('name')}")
    except ReleaseError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

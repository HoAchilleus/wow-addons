import sys
import zipfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import release  # noqa: E402

CHANGELOG = """# Changelog

## [Unreleased]

## [1.2.0] - 2026-11-20
### Added
- Two columns.

## [1.1.0] - 2026-11-01
- Older.
"""


@pytest.fixture
def repo(tmp_path):
    """A throwaway repo with one addon, Demo, at version 1.2.0."""
    addons = tmp_path / "addons"
    demo = addons / "Demo"
    (demo / "spec").mkdir(parents=True)
    (demo / "Demo.toc").write_text(
        "## Interface: 16001\n## Title: Demo\n## Version: 1.2.0\n## X-Curse-Project-ID: 42\n\n"
        "# comment\nCore.lua\nsub\\Extra.lua\n",
        encoding="utf-8",
    )
    (demo / "Core.lua").write_text("-- core\n")
    (demo / "sub").mkdir()
    (demo / "sub" / "Extra.lua").write_text("-- extra\n")
    (demo / "spec" / "core_spec.lua").write_text("-- test\n")
    (demo / "README.md").write_text("# Demo\n")
    (demo / "CHANGELOG.md").write_text(CHANGELOG, encoding="utf-8")
    (tmp_path / "LICENSE").write_text("MIT\n")
    return tmp_path


def test_read_toc(repo):
    toc = release.read_toc("Demo", repo / "addons")
    assert toc.version == "1.2.0"
    assert toc.fields["X-Curse-Project-ID"] == "42"
    assert toc.files == ["Core.lua", "sub/Extra.lua"]


def test_check_passes(repo):
    assert release.check("Demo", repo / "addons") == []


def test_check_reports_problems(repo):
    toc = repo / "addons" / "Demo" / "Demo.toc"
    toc.write_text("## Title: Demo\n## Version: one\nMissing.lua\n")
    problems = release.check("Demo", repo / "addons")
    assert any("Interface" in p for p in problems)
    assert any("not like 1.2.3" in p for p in problems)
    assert any("Missing.lua" in p for p in problems)


def test_check_requires_changelog_entry(repo):
    toc = repo / "addons" / "Demo" / "Demo.toc"
    toc.write_text(toc.read_text().replace("1.2.0", "1.3.0"))
    assert release.check("Demo", repo / "addons") == ["CHANGELOG.md has no section for 1.3.0"]


def test_check_unknown_addon(repo):
    assert "not found" in release.check("Nope", repo / "addons")[0]


@pytest.mark.parametrize("version,expected", [("1.2.0", "- Two columns."), ("1.1.0", "- Older.")])
def test_changelog_section(version, expected):
    assert release.changelog_section(CHANGELOG, version).endswith(expected)


def test_changelog_section_missing():
    assert release.changelog_section(CHANGELOG, "9.9.9") is None
    assert release.changelog_section(CHANGELOG, "1.2") is None


def test_parse_tag(repo):
    assert release.parse_tag("refs/tags/Demo/v1.2.0", repo / "addons") == ("Demo", "1.2.0")


@pytest.mark.parametrize("tag", ["v1.2.0", "Demo-1.2.0", "Demo/1.2.0"])
def test_parse_tag_rejects_bad_names(repo, tag):
    with pytest.raises(release.ReleaseError):
        release.parse_tag(tag, repo / "addons")


def test_parse_tag_rejects_version_mismatch(repo):
    with pytest.raises(release.ReleaseError, match="toc says 1.2.0"):
        release.parse_tag("Demo/v1.2.1", repo / "addons")


def test_package_contents(repo, tmp_path):
    zip_path = release.package("Demo", tmp_path / "dist", repo / "addons", repo)
    assert zip_path.name == "Demo-1.2.0.zip"
    with zipfile.ZipFile(zip_path) as zf:
        names = sorted(zf.namelist())
    assert names == [
        "Demo/CHANGELOG.md", "Demo/Core.lua", "Demo/Demo.toc", "Demo/LICENSE",
        "Demo/README.md", "Demo/sub/Extra.lua",
    ]


def test_package_refuses_broken_addon(repo, tmp_path):
    (repo / "addons" / "Demo" / "Core.lua").unlink()
    with pytest.raises(release.ReleaseError, match="Core.lua"):
        release.package("Demo", tmp_path / "dist", repo / "addons", repo)


@pytest.mark.parametrize("version,expected", [
    ("1.0.0", "release"), ("1.0.0-beta.1", "beta"), ("1.0.0-rc.1", "beta"), ("1.0.0-alpha", "alpha"),
])
def test_release_type(version, expected):
    assert release.release_type(version) == expected


def test_parse_game_versions():
    assert release.parse_game_versions("123, 456") == [123, 456]
    with pytest.raises(release.ReleaseError):
        release.parse_game_versions("")
    with pytest.raises(release.ReleaseError):
        release.parse_game_versions("forever")


def test_build_upload_request(repo, tmp_path):
    zip_path = release.package("Demo", tmp_path / "dist", repo / "addons", repo)
    request = release.build_upload_request("42", "secret", zip_path, "1.2.0", "notes", [123])
    assert request.full_url == "https://wow.curseforge.com/api/projects/42/upload-file"
    assert request.get_method() == "POST"
    assert request.get_header("X-api-token") == "secret"
    body = request.data
    assert b'"gameVersions": [123]' in body
    assert b'"releaseType": "release"' in body
    assert b'filename="Demo-1.2.0.zip"' in body
    assert zip_path.read_bytes() in body


@pytest.mark.parametrize("raw", ["abc-123", "  abc-123\n", '"abc-123"', "'abc-123'"])
def test_curseforge_token_is_cleaned(monkeypatch, raw):
    monkeypatch.setenv("CF_API_TOKEN", raw)
    assert release.curseforge_token() == "abc-123"


def test_curseforge_http_error_becomes_release_error(monkeypatch):
    import io
    import urllib.error

    def fail(request, timeout):
        body = b'{"errorMessage":"API token is malformed. Token provided: abc-123."}'
        raise urllib.error.HTTPError(request.full_url, 400, "Bad Request", {}, io.BytesIO(body))

    monkeypatch.setenv("CF_API_TOKEN", "abc-123")
    monkeypatch.setattr(release.urllib.request, "urlopen", fail)
    with pytest.raises(release.ReleaseError, match="HTTP 400 Bad Request - check CF_API_TOKEN") as info:
        release.curseforge_versions()
    assert str(info.value).endswith("Token provided: ***.\"}")
    assert "abc-123" not in str(info.value)


def test_upload_needs_token(repo, tmp_path, monkeypatch):
    monkeypatch.delenv("CF_API_TOKEN", raising=False)
    zip_path = release.package("Demo", tmp_path / "dist", repo / "addons", repo)
    with pytest.raises(release.ReleaseError, match="CF_API_TOKEN"):
        release.curseforge_upload("Demo", zip_path, repo / "addons")

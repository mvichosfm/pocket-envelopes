"""Compose GitHub release notes for a tag from CHANGELOG.md.

Used by .github/workflows/installer.yml; stdlib only. Prints Markdown to stdout.

    python3 .github/release-notes.py <tag> <installer-file-name> <sha256> <previous-tag> <owner/repo>

The body is the CHANGELOG section whose "## " heading names the version
(e.g. "## 2026-09-08 — v0.6.0, …" for tag v0.6.0), preceded by the download
block and followed by a compare link. Falls back to a pointer at CHANGELOG.md
when no section matches, so a release is never published with empty notes.
"""
import re
import sys


def changelog_section(text: str, version: str) -> str:
    sections = re.split(r"(?m)^## ", text)[1:]
    for sec in sections:
        heading, _, rest = sec.partition("\n")
        if re.search(rf"\bv{re.escape(version)}\b", heading):
            return rest.strip()
    return ""


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")   # the notes carry non-ASCII (dashes, arrows); never depend on the console code page
    tag, name, sha, prev, repo = (sys.argv[1:6] + [""] * 5)[:5]
    version = tag.lstrip("v")
    with open("CHANGELOG.md", encoding="utf-8") as fh:
        body = changelog_section(fh.read(), version)
    if not body:
        body = "See `CHANGELOG.md` for what changed in this version."
    parts = [
        f"**Download:** `{name}` (below). SHA-256:\n\n```\n{sha}\n```\n",
        "Installing over an earlier version stops the running server, replaces the app and "
        "keeps your budget where it is. Windows SmartScreen will warn about an unrecognised "
        "publisher because the installer is not code-signed; check the hash above, or build "
        "it yourself from the `installer` folder with `installer\\build.ps1`.\n",
        "## What's new\n\n" + body + "\n",
    ]
    if prev and prev != tag and repo:
        parts.append(f"**Full Changelog**: https://github.com/{repo}/compare/{prev}...{tag}")
    print("\n".join(parts))


if __name__ == "__main__":
    main()

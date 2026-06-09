#!/usr/bin/env python3
"""Preprocess notes for Confluence publishing via mark.

No third-party dependencies — stdlib only.

Reads .publish.yaml for config. Scans notes_dir for *.md files where
frontmatter has publish: true, and writes mark-ready copies to .processed/
with Space/Title comments and a source-of-truth disclaimer injected.

Usage:
    python3 preprocess.py --root /path/to/hoard
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

FM_RE = re.compile(r"^---\n(.+?)\n---\n", re.DOTALL)


def parse_yaml_shallow(text):
    """Parse one-level-nested key: value YAML (no anchors, no lists, no multiline)."""
    result = {}
    section = None
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        key, _, val = line.lstrip().partition(":")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if indent == 0:
            if val == "":
                section = key
                result[section] = {}
            else:
                result[key] = _coerce(val)
                section = None
        else:
            if section is not None:
                result[section][key] = _coerce(val)
    return result


def _coerce(v):
    if v.lower() == "true":
        return True
    if v.lower() == "false":
        return False
    return v


def parse_frontmatter(text):
    m = FM_RE.match(text)
    if not m:
        return {}, text
    fm = parse_yaml_shallow(m.group(1))
    return fm, text[m.end():]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="Hoard root directory")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    config_path = root / ".publish.yaml"
    out_dir = root / ".processed"

    if not config_path.exists():
        print(f"error: {config_path} not found", file=sys.stderr)
        sys.exit(1)

    raw = parse_yaml_shallow(config_path.read_text())
    cfg = raw.get("confluence", {})
    space = cfg.get("space")
    if not space:
        print("error: confluence.space is required in .publish.yaml", file=sys.stderr)
        sys.exit(1)
    source_base = cfg.get("source_url_base", "").rstrip("/")
    notes_dir = root / cfg.get("notes_dir", "notes")
    if not notes_dir.is_dir():
        print(f"error: notes_dir '{notes_dir}' does not exist", file=sys.stderr)
        sys.exit(1)

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir()

    published = 0
    for md_file in sorted(notes_dir.rglob("*.md")):
        text = md_file.read_text()
        fm, body = parse_frontmatter(text)
        if fm.get("publish") is not True:
            continue

        title = fm.get("title", md_file.stem.replace("-", " ").title())
        rel_path = md_file.relative_to(root)
        source_url = f"{source_base}/{rel_path}" if source_base else None

        mark_header = f"<!-- Space: {space} -->\n<!-- Title: {title} -->\n\n"
        if source_url:
            disclaimer = (
                '<ac:structured-macro ac:name="tip" ac:schema-version="1">\n'
                '  <ac:parameter ac:name="title">Auto-published mirror</ac:parameter>\n'
                '  <ac:rich-text-body><p>'
                f'🔒 Edit <a href="{source_url}"><code>{rel_path}</code></a> on GitLab — '
                "changes made here will be overwritten on the next push."
                "</p></ac:rich-text-body>\n"
                "</ac:structured-macro>\n\n"
            )
        else:
            disclaimer = ""

        out_file = out_dir / md_file.name
        out_file.write_text(mark_header + disclaimer + body)
        print(f"  {rel_path} → .processed/{md_file.name}  ({title!r})")
        published += 1

    print(f"\n{published} note(s) staged for Confluence.")


if __name__ == "__main__":
    main()

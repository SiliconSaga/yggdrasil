#!/usr/bin/env python3
"""SADD section assembler for ADSE project hoards.

Reads .project.yaml for section order and mandatory list.
Scans all .md files (excluding working/) for sadd_section: frontmatter.
Validates mandatory sections are present (exit 1 if not).
Generates a doc-control header from .project.yaml metadata.
Writes the assembled document to .build/assembled.md (or --output path).

Usage:
    python3 assemble.py <hoard_root> [--output <path>]
"""
import argparse
import re
import sys
from datetime import date
from pathlib import Path

FM_RE = re.compile(r"^---\n(.+?)\n---\n", re.DOTALL)
INLINE_LIST_RE = re.compile(r"\[([^\]]*)\]")


def _parse_inline_list(val):
    m = INLINE_LIST_RE.match(val.strip())
    if not m:
        return [val.strip()] if val.strip() else []
    return [item.strip().strip('"').strip("'") for item in m.group(1).split(",") if item.strip()]


def parse_project_yaml(path):
    result = {
        "mandatory": [], "sections": [], "title": "", "template": "sadd",
        "authors": [], "approvers": [], "plc_template": "",
    }
    in_authors = False
    in_approvers = False
    current_person = {}

    for line in Path(path).read_text().splitlines():
        raw = line
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        if stripped.startswith("- id:"):
            result["sections"].append(stripped[len("- id:"):].strip())
            in_authors = in_approvers = False
            continue
        if stripped.startswith("- name:") and indent > 0:
            if current_person:
                if in_authors:
                    result["authors"].append(current_person)
                elif in_approvers:
                    result["approvers"].append(current_person)
            current_person = {"name": stripped[len("- name:"):].strip().strip('"')}
            continue
        if stripped.startswith("email:") and indent > 0 and current_person:
            current_person["email"] = stripped[len("email:"):].strip().strip('"')
            continue
        if stripped.startswith("role:") and indent > 0 and current_person:
            current_person["role"] = stripped[len("role:"):].strip().strip('"')
            continue
        if ":" in stripped and indent == 0:
            if current_person:
                if in_authors:
                    result["authors"].append(current_person)
                elif in_approvers:
                    result["approvers"].append(current_person)
                current_person = {}
            key, _, val = stripped.partition(":")
            key = key.strip(); val = val.strip()
            in_authors = key == "authors"
            in_approvers = key == "approvers"
            if key == "mandatory":
                result["mandatory"] = _parse_inline_list(val)
            elif key in ("template", "title", "plc_template"):
                result[key] = val.strip('"').strip("'")

    if current_person:
        if in_authors:
            result["authors"].append(current_person)
        elif in_approvers:
            result["approvers"].append(current_person)
    return result


def parse_frontmatter(text):
    m = FM_RE.match(text)
    if not m:
        return {}, text
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line and not line.startswith(" "):
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip().strip('"').strip("'")
    return fm, text[m.end():]


def scan_sections(hoard_root):
    root = Path(hoard_root)
    found = {}
    for md in sorted(root.rglob("*.md")):
        if "working" in md.parts:
            continue
        try:
            text = md.read_text()
        except Exception:
            continue
        fm, body = parse_frontmatter(text)
        section = fm.get("sadd_section", "").strip()
        if section:
            found.setdefault(section, []).append((md, fm, body))
    return found


def make_doc_control(config):
    title = config.get("title", "Untitled")
    authors = ", ".join(a.get("name", "") for a in config.get("authors", []))
    plc = config.get("plc_template", "")
    today = date.today().isoformat()

    lines = [
        f"# {title}",
        "## Software Architecture and Design Document",
        "",
        "| Item | Value |",
        "|---|---|",
        f"| Title | {title} |",
        f"| Author(s) | {authors or '—'} |",
        f"| Revision | {today} |",
        "| State | Draft |",
    ]
    if plc:
        lines.append(f"| PLC Template | {plc} |")

    approvers = config.get("approvers", [])
    if approvers:
        lines += ["", "### Approvers", "", "| Name | Role | Date |", "|---|---|---|"]
        for a in approvers:
            lines.append(f"| {a.get('name', '')} | {a.get('role', '')} | |")

    lines += ["", "---", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("hoard_root")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    hoard_root = Path(args.hoard_root).resolve()
    project_yaml = hoard_root / ".project.yaml"
    if not project_yaml.exists():
        print(f"error: {project_yaml} not found", file=sys.stderr)
        sys.exit(2)

    config = parse_project_yaml(project_yaml)
    found = scan_sections(hoard_root)
    mandatory = set(config["mandatory"])
    sections = config["sections"]

    missing = [s for s in mandatory if s not in found]
    if missing:
        print(f"ERROR: mandatory section(s) missing: {', '.join(missing)}", file=sys.stderr)
        print("Run 'ws project <name> status' for details.", file=sys.stderr)
        sys.exit(1)

    parts = [make_doc_control(config)]
    for sec_id in sections:
        entries = found.get(sec_id)
        if not entries:
            continue
        for _path, _fm, body in entries:
            parts.append(body.strip())
            parts.append("")

    assembled = "\n".join(parts).rstrip() + "\n"

    if args.output:
        out_path = Path(args.output)
    else:
        build_dir = hoard_root / ".build"
        build_dir.mkdir(exist_ok=True)
        out_path = build_dir / "assembled.md"

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(assembled)
    print(f"assembled {len(sections)} sections → {out_path}")


if __name__ == "__main__":
    main()

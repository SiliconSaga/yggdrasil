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
        "authors": [], "approvers": [], "revisions": [], "plc_template": "",
    }
    in_authors = False
    in_approvers = False
    in_revisions = False
    in_mandatory = False
    in_sections = False
    current_person = {}
    current_revision = {}

    def _flush_person():
        if current_person:
            if in_authors:
                result["authors"].append(current_person.copy())
            elif in_approvers:
                result["approvers"].append(current_person.copy())
        current_person.clear()

    def _flush_revision():
        if current_revision:
            result["revisions"].append(current_revision.copy())
        current_revision.clear()

    for line in Path(path).read_text().splitlines():
        raw = line
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        if stripped.startswith("- id:") and in_sections:  # legacy "- id: foo" form
            result["sections"].append(stripped[len("- id:"):].strip())
            continue
        if indent > 0 and stripped.startswith("- ") and in_sections \
                and not stripped.startswith("- id:"):
            result["sections"].append(stripped[2:].strip().strip('"').strip("'"))
            continue
        if indent > 0 and stripped.startswith("- ") and in_mandatory \
                and not stripped.startswith("- name:") and not stripped.startswith("- version:"):
            result["mandatory"].append(stripped[2:].strip().strip('"').strip("'"))
            continue
        if stripped.startswith("- name:") and indent > 0 and (in_authors or in_approvers):
            _flush_person()
            current_person["name"] = stripped[len("- name:"):].strip().strip('"')
            continue
        if stripped.startswith("- version:") and indent > 0 and in_revisions:
            _flush_revision()
            current_revision["version"] = stripped[len("- version:"):].strip().strip('"')
            continue
        if stripped.startswith("email:") and indent > 0 and current_person:
            current_person["email"] = stripped[len("email:"):].strip().strip('"')
            continue
        if stripped.startswith("role:") and indent > 0 and current_person:
            current_person["role"] = stripped[len("role:"):].strip().strip('"')
            continue
        if stripped.startswith("date:") and indent > 0 and current_revision:
            current_revision["date"] = stripped[len("date:"):].strip().strip('"')
            continue
        if stripped.startswith("author:") and indent > 0 and current_revision:
            current_revision["author"] = stripped[len("author:"):].strip().strip('"')
            continue
        if stripped.startswith("description:") and indent > 0 and current_revision:
            current_revision["description"] = stripped[len("description:"):].strip().strip('"')
            continue
        if ":" in stripped and indent == 0:
            _flush_person()
            _flush_revision()
            key, _, val = stripped.partition(":")
            key = key.strip(); val = val.strip()
            in_authors = key == "authors"
            in_approvers = key == "approvers"
            in_revisions = key == "revisions"
            in_sections = key == "sections"
            in_mandatory = False
            if key == "mandatory":
                if val:
                    result["mandatory"] = _parse_inline_list(val)
                else:
                    in_mandatory = True
            elif key in ("template", "title", "plc_template"):
                result[key] = val.strip('"').strip("'")

    _flush_person()
    _flush_revision()
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
    revisions = config.get("revisions", [])
    approvers = config.get("approvers", [])

    # Placeholders for empty fields (pre-defined to avoid backslash-in-f-string
    # restriction in Python < 3.12)
    ph_author   = r"*\<your name\>*"
    ph_rev_auth = r"*\<your name\>*"
    ph_rev_desc = r"*\<describe this revision\>*"
    ph_app_name = r"*\<approver name\>*"
    ph_app_role = r"*\<role\>*"

    lines = [
        f"# {title}",
        "## Software Architecture and Design Document",
        "",
        "---",
        "",
        "## Doc Control",
        "",
        "### Document Information",
        "",
        "| Field | Value |",
        "|---|---|",
        f"| Title | {title} |",
        f"| Author(s) | {authors if authors else ph_author} |",
    ]
    if plc:
        lines.append(f"| PLC Template | {plc} |")

    # Revision History table
    lines += [
        "",
        "### Revision History",
        "",
        "<!-- Add entries to `revisions:` in .project.yaml to extend this table -->",
        "",
        "| Version | Date | Author | Description |",
        "|---|---|---|---|",
    ]
    if revisions:
        for r in revisions:
            lines.append(
                f"| {r.get('version', '')} | {r.get('date', '')}"
                f" | {r.get('author', '')} | {r.get('description', '')} |"
            )
    else:
        lines.append(f"| 0.1 | YYYY-MM-DD | {ph_rev_auth} | {ph_rev_desc} |")

    # Approvals table
    lines += [
        "",
        "### Approvals",
        "",
        "<!-- Add entries to `approvers:` in .project.yaml to extend this table -->",
        "",
        "| Name | Role | Date | Signature |",
        "|---|---|---|---|",
    ]
    if approvers:
        for a in approvers:
            lines.append(f"| {a.get('name', '')} | {a.get('role', '')} | | |")
    else:
        lines.append(f"| {ph_app_name} | {ph_app_role} | | |")

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

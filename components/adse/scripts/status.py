#!/usr/bin/env python3
"""Section coverage scanner for ADSE project hoards.

Usage:
    python3 status.py <hoard_root>

Exit 0 if all mandatory sections are present.
Exit 1 if any mandatory section is missing (also prints report).
"""
import re
import sys
from pathlib import Path

FM_RE = re.compile(r"^---\n(.+?)\n---\n", re.DOTALL)
INLINE_LIST_RE = re.compile(r"\[([^\]]*)\]")


def _parse_inline_list(val):
    m = INLINE_LIST_RE.match(val.strip())
    if not m:
        return [val.strip()] if val.strip() else []
    return [item.strip().strip('"').strip("'") for item in m.group(1).split(",") if item.strip()]


def parse_project_yaml(path):
    """Parse .project.yaml with stdlib. Returns dict with mandatory (list) and sections (list of str ids)."""
    result = {"mandatory": [], "sections": [], "title": "", "template": "sadd"}
    in_mandatory = False
    for line in Path(path).read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        # Indented block list items
        if indent > 0 and stripped.startswith("- "):
            if stripped.startswith("- id:"):
                result["sections"].append(stripped[len("- id:"):].strip())
            elif in_mandatory:
                result["mandatory"].append(stripped[2:].strip().strip('"').strip("'"))
            continue
        # Root-level key: value
        if ":" in stripped and indent == 0:
            key, _, val = stripped.partition(":")
            key = key.strip()
            val = val.strip()
            in_mandatory = False
            if key == "mandatory":
                if val:
                    result["mandatory"] = _parse_inline_list(val)
                else:
                    in_mandatory = True
            elif key in ("template", "title"):
                result[key] = val.strip('"').strip("'")
    return result


def parse_frontmatter(text):
    m = FM_RE.match(text)
    if not m:
        return {}
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line and not line.startswith(" "):
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip().strip('"').strip("'")
    return fm


def scan_sections(hoard_root):
    """Return dict mapping section_id → list of file paths that tag it."""
    root = Path(hoard_root)
    found = {}
    for md in root.rglob("*.md"):
        if "working" in md.parts:
            continue
        try:
            text = md.read_text()
        except Exception:
            continue
        fm = parse_frontmatter(text)
        section = fm.get("sadd_section", "").strip()
        if section:
            found.setdefault(section, []).append(md.relative_to(root))
    return found


def main():
    if len(sys.argv) < 2:
        print("Usage: status.py <hoard_root>", file=sys.stderr)
        sys.exit(2)

    hoard_root = Path(sys.argv[1]).resolve()
    project_yaml = hoard_root / ".project.yaml"

    if not project_yaml.exists():
        print(f"error: {project_yaml} not found", file=sys.stderr)
        sys.exit(2)

    config = parse_project_yaml(project_yaml)
    found = scan_sections(hoard_root)
    mandatory = set(config["mandatory"])
    sections = config["sections"]

    missing_mandatory = []
    print(f"Section coverage — {config['title'] or hoard_root.name}\n")
    for sec_id in sections:
        files = found.get(sec_id, [])
        is_mandatory = sec_id in mandatory
        tag = "[mandatory]" if is_mandatory else "[optional]"
        sep = " * " if is_mandatory else "   "
        if files:
            print(f"  ✓ present{sep}{tag:12s}{sec_id}")
            for f in files:
                print(f"               → {f}")
        else:
            status_word = "MISSING" if is_mandatory else "missing"
            print(f"  ✗ {status_word:7s}{sep}{tag:12s}{sec_id}")
            if is_mandatory:
                missing_mandatory.append(sec_id)

    extra = set(found.keys()) - set(sections)
    for sec_id in sorted(extra):
        tag = "[unlisted]"
        print(f"  ? extra     {tag:12s}{sec_id}")

    print()
    if missing_mandatory:
        print(f"ERROR: {len(missing_mandatory)} mandatory section(s) missing: {', '.join(missing_mandatory)}")
        sys.exit(1)
    else:
        print(f"All mandatory sections present ({len(sections) - len(missing_mandatory)} of {len(sections)} total tagged).")
        sys.exit(0)


if __name__ == "__main__":
    main()

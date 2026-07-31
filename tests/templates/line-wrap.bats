#!/usr/bin/env bats

# Guard: prose in agent-facing markdown must not be hard-wrapped. Templates
# and skills are the demonstration layer — an agent drafting a commit or CR
# body copies the shape it sees, so a wrapped file quietly reteaches the
# wrapped habit no matter what AGENTS.md says (demonstration beats
# instruction). One line per paragraph and per bullet; renderers wrap.
#
# Exempt, matching the AGENTS.md rule: YAML frontmatter, fenced code blocks
# (including fences indented inside list items), tables, headings, HTML
# comments, and list STRUCTURE (one line per item) — a bullet's own text is
# still a single line.
#
# Detection: two consecutive non-empty lines where the first is prose (a
# list item counts as prose for the NEXT line) and the second is not a
# structural marker means a wrapped paragraph. POSIX awk only (workspace
# convention; see scripts/ws-orient.sh for the precedent).
#
# Coverage grows in rings: templates/*.md and docs/gdd/*.md are fully
# clean and locked; .agent/skills/ locks the clean files while the
# GRANDFATHERED list carries the legacy-wrapped ones (per the doc-writing
# convention, existing wrapped prose stays wrapped until deliberately
# reflowed). Shrink the list as files get cleaned — never add to it.

_wrap_detect() {
    awk '
        FNR == 1 { fm = 0; fence = ""; prev = 0 }
        FNR == 1 && $0 == "---" { fm = 1; next }
        fm { if ($0 == "---") fm = 0; next }
        /^[[:space:]]*(```|~~~)/ {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            marker = substr(line, 1, 3)
            if (fence == "") {
                fence = marker
            } else if (fence == marker) {
                fence = ""
            }
            prev = 0
            next
        }
        fence != "" { next }
        /^[[:space:]]*$/ { prev = 0; next }
        /^[[:space:]]*[-*][[:space:]]/ || /^[[:space:]]*[0-9]+\.[[:space:]]/ { prev = 1; next }
        /^#/ || /^>/ || /^\|/ || /^<!--/ { prev = 0; next }
        {
            if (prev) { printf "%s:%d: wrapped prose: %s\n", FILENAME, FNR, $0; bad = 1 }
            prev = 1
        }
        END { exit bad }
    ' "$@"
}

# Legacy-wrapped skills awaiting deliberate reflow. Shrink-only.
GRANDFATHERED="gdd gdd-bdd gdd-bdd-pytest gdd-branch-workflow gdd-doc-writing gdd-flow gdd-github-issues gdd-housekeeping gdd-mcp gdd-mentoring gdd-permissions gdd-quick gdd-review-triage gdd-scribe gdd-workflow-audit gdd-zen"

@test "top-level templates contain no hard-wrapped prose" {
    local repo_root
    repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    run _wrap_detect "$repo_root"/templates/*.md
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output"
        return 1
    fi
}

@test "docs/gdd pages contain no hard-wrapped prose" {
    local repo_root
    repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    run _wrap_detect "$repo_root"/docs/gdd/*.md
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output"
        return 1
    fi
}

@test "non-grandfathered skills contain no hard-wrapped prose" {
    local repo_root skill_file skill_name checked=0
    repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    for skill_file in "$repo_root"/.agent/skills/*/SKILL.md; do
        skill_name="$(basename "$(dirname "$skill_file")")"
        case " $GRANDFATHERED " in
            *" $skill_name "*) continue ;;
        esac
        checked=$((checked + 1))
        run _wrap_detect "$skill_file"
        if [ "$status" -ne 0 ]; then
            printf '%s\n' "$output"
            return 1
        fi
    done
    [ "$checked" -gt 0 ]
}

@test "grandfather list only names skills that still exist" {
    # A renamed or deleted skill must not linger as a phantom exemption a
    # future file could silently inherit.
    local repo_root name
    repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    for name in $GRANDFATHERED; do
        [ -f "$repo_root/.agent/skills/$name/SKILL.md" ] || {
            echo "grandfathered skill missing: $name"
            return 1
        }
    done
}

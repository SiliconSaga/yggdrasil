#!/usr/bin/env bats

# Guard: top-level templates must not hard-wrap prose. Templates are the
# demonstration layer — an agent drafting a commit or CR body copies the
# shape it sees, so a wrapped template quietly reteaches the wrapped habit
# no matter what AGENTS.md says (demonstration beats instruction). One
# line per paragraph and per bullet; renderers handle the wrapping.
#
# Exempt, matching the AGENTS.md rule: YAML frontmatter, fenced code
# blocks, tables, headings, HTML comments, and list STRUCTURE (one line
# per item) — a bullet's own text is still a single line.
#
# Detection: two consecutive non-empty lines where the first is prose and
# the second is not a structural marker means a wrapped paragraph — in a
# one-line-per-paragraph file every prose line is followed by a blank
# line or structure. POSIX awk only (workspace convention; see
# scripts/ws-orient.sh for the precedent).

@test "top-level templates contain no hard-wrapped prose" {
    local repo_root
    repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    run awk '
        FNR == 1 { fm = 0; fence = 0; prev = 0 }
        FNR == 1 && $0 == "---" { fm = 1; next }
        fm { if ($0 == "---") fm = 0; next }
        /^```/ { fence = 1 - fence; prev = 0; next }
        fence { next }
        /^[[:space:]]*$/ { prev = 0; next }
        /^[[:space:]]*[-*][[:space:]]/ || /^[[:space:]]*[0-9]+\.[[:space:]]/ { prev = 1; next }
        /^#/ || /^>/ || /^\|/ || /^<!--/ { prev = 0; next }
        {
            if (prev) { printf "%s:%d: wrapped prose: %s\n", FILENAME, FNR, $0; bad = 1 }
            prev = 1
        }
        END { exit bad }
    ' "$repo_root"/templates/*.md
    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output"
        return 1
    fi
}

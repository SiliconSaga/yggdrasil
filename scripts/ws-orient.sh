#!/usr/bin/env bash
# ws-orient.sh — deterministic "what can I do here?" menu.
# ws:use-when starting a session, recovering from compaction, or switching tasks
#
# `ws orient` is the L1 layer of the progressive-disclosure buffet:
#
#   L0  slim AGENTS.md + reflex contract       — always-loaded reminder
#   L1  ws orient                              — this command
#   L2  ws <cmd> --help                        — per-subcommand depth
#
# The goal is one deterministic place an agent (or a human) can run
# to see: the workspace toolset + the active realm + per-component
# adapter wiring (with the resolved command surfaced) + the skill
# index.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Honor a pre-set ROOT_DIR (matches scripts/ws + ws-commit.sh) so the
# bats smoke suite can point ws-orient at an isolated $WORK without
# the script clobbering the test's exported override.
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

orient_help() {
    cat <<'HELP'
Usage: ws orient [--check]

Deterministic "what can I do here?" menu — workspace toolset, active
realm, per-component adapters (with resolved commands), and the
skill index. Run after compaction, on a fresh dispatch, or when
switching tasks. Pairs with the per-command `ws orient` footer
nudge that fires after every subcommand.

Read-only. Renders the same output either way; --check adds an exit
code so drift can be caught on a schedule rather than by whoever
happens to read the output:

  --check   Exit non-zero if anything orient renders is broken.
            Today that means an adapter ai_context pointer that no
            longer resolves or escapes its component, or an adapter
            file that no longer parses.
HELP
    exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
    orient_help
fi

# Rot counter for --check. Incremented from _emit_one_adapter, which runs in
# this shell (its ai_context loop reads from a process substitution, not a
# pipeline), so the count survives to the gate at the bottom of the script.
ORIENT_CHECK=0
ORIENT_CONTEXT_ROT=0
for _arg in "$@"; do
    case "$_arg" in
        --check) ORIENT_CHECK=1 ;;
        --help|-h) orient_help ;;
        *)
            echo "ws orient: unknown option '$_arg'" >&2
            echo "  Usage: ws orient [--check]" >&2
            exit 1
            ;;
    esac
done

# Explicit yq presence check matching ws-list / ws-test / ws-lint —
# under `set -euo pipefail` a missing yq would otherwise surface as
# a cryptic 127 from inside `_emit_one_adapter` rather than as a
# helpful diagnostic at startup. Deliberately AFTER the --help
# short-circuit so a fresh-machine user can still discover `ws orient`
# before installing every prerequisite.
if ! type -P yq &>/dev/null || ! type -P jq &>/dev/null; then
    # Fresh machine: ws orient can't read the ecosystem config without yq.
    # Rather than a bare error, flow straight into preflight (which runs
    # WITHOUT yq) so the user gets the full per-OS install hints in one
    # pass, then say what to do next. Exit nonzero — orientation didn't run.
    echo "ws orient needs yq + jq to read the ecosystem config, but they aren't on PATH yet."
    echo "Might be a fresh machine — running 'ws preflight' to show what's missing:"
    echo ""
    bash "$SCRIPT_DIR/ws-preflight.sh" --soft
    echo ""
    echo "Once the required tools are installed (and a fresh shell opened, per the note above), re-run 'ws orient'."
    exit 1
fi

# Subcommand survey — built dynamically by scanning each handler for
# its `# ws:use-when …` docstring. Two awk passes: parse_dispatch
# maps subcommand-name → handler (a script file or a function inside
# scripts/ws); find_use_when locates the marker inside that handler.
# Marker shape:
#   # ws:use-when <text>             — single subcommand-per-handler (bare)
#   # ws:use-when:<name> <text>      — one handler, many subcommands (keyed)
# The keyed form uses a colon-separated subcommand name so the parser
# never confuses a bare-text marker whose first word happens to look
# like a kebab identifier with a keyed marker for some other subcommand.
# A handler without any marker shows as "(no `ws:use-when` marker)"
# so the gap is visible at orient time rather than discoverable only
# via grep — keeps the inventory honest as new subcommands land.
emit_subcommand_survey() {
    printf '\n%s\n' "Subcommands (name — use when …):"
    local name handler kind ref use_when
    while IFS=$'\t' read -r name handler; do
        [[ -z "$name" ]] && continue
        kind="${handler%%:*}"
        ref="${handler#*:}"
        use_when=""
        case "$kind" in
            bash)
                use_when="$(_orient_find_use_when_script "$SCRIPT_DIR/$ref" "$name")"
                ;;
            func)
                use_when="$(_orient_find_use_when_func "$SCRIPT_DIR/ws" "$ref" "$name")"
                ;;
        esac
        if [[ -n "$use_when" ]]; then
            printf '  %-18s — %s\n' "$name" "$use_when"
        else
            printf '  %-18s — (no `ws:use-when` marker — add one to %s)\n' "$name" "$ref"
        fi
    done < <(_orient_parse_dispatch "$SCRIPT_DIR/ws")
}

# Parse the `case "$COMMAND" in … esac` block in scripts/ws.
# Output: tab-separated <name>\t<kind>:<ref>
#   kind=bash  → ref is a script filename (e.g. ws-list.sh)
#   kind=func  → ref is a function name (e.g. ws_push)
# Alias-group labels (help|--help|-h) and the catchall `*)` are
# skipped — those aren't user-facing subcommand names.
# Portability note: every awk script in this file sticks to POSIX-awk
# constructs (regex match, sub, substr, RSTART/RLENGTH). The gawk-only
# 3-arg array-capture form of match (where the third arg is a named
# array that receives capture groups) is deliberately avoided so
# orient stays functional under mawk and BSD awk — `ws orient` is now
# a MUST-run on session start (per AGENTS.md), so any portability gap
# here is a session-blocker on macOS / Linux distros that ship mawk
# as the default awk. See scripts/ws-review.sh for the same precedent.
_orient_parse_dispatch() {
    local ws_file="$1"
    [[ -f "$ws_file" ]] || return 0
    awk '
        BEGIN { in_case = 0; pending = "" }
        /^case .*COMMAND.* in/ { in_case = 1; next }
        /^esac/ { exit }
        !in_case { next }
        # Match a bare label: `    name)` — leading whitespace,
        # lowercase-and-hyphen name, closing paren, no alias group.
        /^[[:space:]]+[a-z][a-z0-9-]*\)[[:space:]]*$/ {
            name = $0
            sub(/^[[:space:]]+/, "", name)
            sub(/\).*$/, "", name)
            pending = name
            next
        }
        # Body line after a label: extract the handler shape.
        # POSIX match() sets RSTART/RLENGTH for the whole match; we
        # then peel the captured token off with substr() + sub().
        pending != "" {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (match(line, /bash "\$SCRIPT_DIR\/ws-[a-z0-9-]+\.sh"/)) {
                m = substr(line, RSTART, RLENGTH)
                sub(/^bash "\$SCRIPT_DIR\//, "", m)
                sub(/".*$/, "", m)
                printf "%s\tbash:%s\n", pending, m
            } else if (match(line, /^ws_[a-z_]+/)) {
                m = substr(line, RSTART, RLENGTH)
                printf "%s\tfunc:%s\n", pending, m
            }
            pending = ""
        }
    ' "$ws_file"
}

# Scan the first 60 lines of a script file for a `# ws:use-when`
# marker. Looks for the name-keyed form first (so a shared script
# can declare different "use when" text per dispatched subcommand —
# e.g. ws-mcp-setup.sh handles both `mcp-setup` and `mcp-status`),
# then falls back to the bare form.
_orient_find_use_when_script() {
    local file="$1" name="$2"
    [[ -f "$file" ]] || return 0
    awk -v target="$name" '
        { line_count++ }
        line_count > 60 { exit }
        # Keyed form: `# ws:use-when:<name> <text>`. Only fires for
        # an exact name match; non-matching keyed markers are skipped
        # so a shared script can declare distinct text per subcommand.
        # The bare-form rule below requires whitespace right after
        # `ws:use-when`, so the colon in this pattern naturally
        # disambiguates the two shapes — no extra guard needed.
        /^#[[:space:]]*ws:use-when:[a-z][a-z0-9-]*[[:space:]]+/ {
            line = $0
            sub(/^#[[:space:]]*ws:use-when:/, "", line)
            keyname = line
            sub(/[[:space:]].*$/, "", keyname)
            text = line
            sub(/^[a-z][a-z0-9-]*[[:space:]]+/, "", text)
            if (keyname == target) { print text; exit }
            next
        }
        # Bare form: `# ws:use-when <text>`. Applies to whatever the
        # caller asked about.
        /^#[[:space:]]*ws:use-when[[:space:]]+/ {
            text = $0
            sub(/^#[[:space:]]*ws:use-when[[:space:]]+/, "", text)
            print text
            exit
        }
    ' "$file"
}

# Scan a function body inside scripts/ws for a `# ws:use-when` marker.
# Function definition shape: `<name>() {` at the start of a line.
# Function close: `}` at column 0. Anything in between is the body.
_orient_find_use_when_func() {
    local ws_file="$1" func_name="$2" sub_name="$3"
    [[ -f "$ws_file" ]] || return 0
    awk -v fn="$func_name" -v target="$sub_name" '
        in_func == 0 && $0 ~ "^" fn "[[:space:]]*\\(\\)[[:space:]]*\\{" { in_func = 1; next }
        in_func == 0 { next }
        in_func && /^}/ { exit }
        in_func {
            # See _orient_find_use_when_script for marker shape notes.
            # In-function markers carry leading whitespace from the
            # function body indent, so the regexes here allow it.
            if ($0 ~ /^[[:space:]]*#[[:space:]]*ws:use-when:[a-z][a-z0-9-]*[[:space:]]+/) {
                line = $0
                sub(/^[[:space:]]*#[[:space:]]*ws:use-when:/, "", line)
                keyname = line
                sub(/[[:space:]].*$/, "", keyname)
                text = line
                sub(/^[a-z][a-z0-9-]*[[:space:]]+/, "", text)
                if (keyname == target) { print text; exit }
                next
            }
            if ($0 ~ /^[[:space:]]*#[[:space:]]*ws:use-when[[:space:]]+/) {
                text = $0
                sub(/^[[:space:]]*#[[:space:]]*ws:use-when[[:space:]]+/, "", text)
                print text
                exit
            }
        }
    ' "$ws_file"
}

# Resolve the active realm once for the whole orient run, classifying
# the result so each emit_* function consumes a stable state rather
# than re-invoking ws_detect_realm (which exits 1 on multi-realm —
# without this catch, the rest of orient never renders).
#
# Status values: ok | none | ambiguous | error
#   ok        — exactly one realm-* directory or selector picked one
#   none      — no realms present (and no selector pointing at one)
#   ambiguous — multiple realm-* dirs and no selector to disambiguate
#   error     — any OTHER detection failure (YAML parse, file I/O, …)
#
# `ambiguous` and `error` are split deliberately: ws_detect_realm
# exits 1 on both multi-realm AND on a malformed ecosystem.local.yaml.
# Conflating them would point the user at the wrong fix path. The
# split keys off the canonical "Multiple non-template realms" stderr
# message from ws_detect_realm; anything else is classified as a
# generic error and the actual stderr first line surfaces to the user.
_ORIENT_REALM=""
_ORIENT_REALM_STATUS="none"
_ORIENT_REALM_ERROR=""
_ORIENT_REALM_TRUST=""
_resolve_orient_realm() {
    local rc=0 stderr_file
    stderr_file="$(mktemp 2>/dev/null || echo "/tmp/orient.stderr.$$")"
    _ORIENT_REALM="$(ws_detect_realm 2>"$stderr_file")" || rc=$?
    local first_err=""
    if [[ -f "$stderr_file" ]]; then
        first_err="$(head -n1 "$stderr_file" 2>/dev/null || true)"
        rm -f "$stderr_file"
    fi
    if [[ $rc -ne 0 ]]; then
        _ORIENT_REALM=""
        if [[ "$first_err" == *"Multiple non-template realms"* ]]; then
            _ORIENT_REALM_STATUS="ambiguous"
        else
            _ORIENT_REALM_STATUS="error"
            _ORIENT_REALM_ERROR="$first_err"
        fi
        return
    fi
    if [[ -n "$_ORIENT_REALM" ]]; then
        _ORIENT_REALM_STATUS="ok"
    else
        _ORIENT_REALM_STATUS="none"
    fi
}

# Per-component adapter enumeration with the resolved command
# surfaced. The "runs:" form is the adapter-trust mitigation from
# the design (§ Adapter trust): when `ws test` runs, the actual
# command the wrapper dispatches must be auditable from `ws orient`
# output. Otherwise the wrapper hides the executable-config surface.
#
# Discovery: iterate $COMPONENTS_DIR/*/ that look cloned (any .git
# entry — handles both real .git dirs and worktree-pointer .git
# files). For each, look up the realm-side adapter at
# realms/<active>/adapters/<comp>.yaml and surface what's wired.
emit_component_adapters() {
    printf '\nComponents (cloned) — adapter wiring:\n'

    local cloned=0 emitted=0 comp_dir comp adapter_file
    if [[ -d "$COMPONENTS_DIR" ]]; then
        for comp_dir in "$COMPONENTS_DIR"/*/; do
            [[ -d "$comp_dir" ]] || continue
            [[ -e "$comp_dir/.git" ]] || continue
            cloned=1
            comp="$(basename "$comp_dir")"
            # Skip components that have no adapter file at all — the
            # "no test/lint adapter" rows for every unwired clone
            # were noise that diluted the wired-adapter signal. The
            # two remaining unwired states (YAML parse failure,
            # adapter present but no commands wired) are real
            # diagnostics and still render via _emit_one_adapter.
            adapter_file=""
            if [[ -n "$_ORIENT_REALM" ]]; then
                adapter_file="$REALMS_DIR/$_ORIENT_REALM/adapters/$comp.yaml"
            fi
            [[ -f "$adapter_file" ]] || continue
            _emit_one_adapter "$comp" "$_ORIENT_REALM"
            emitted=1
        done
    fi
    if [[ $cloned -eq 0 ]]; then
        echo "  (no components cloned)"
    elif [[ $emitted -eq 0 ]]; then
        echo "  (no cloned component has an adapter wired)"
    fi
}

# Surface the workspace-root self-test. yggdrasil itself is treated as a
# "component" by ws-test.sh, whose suite is the vendored-bats files under
# tests/ (excluding tests/vendor/). It has no realm adapter, so it never
# shows up in emit_component_adapters — surface it here so `ws test
# yggdrasil` is discoverable from orient, the lowest-effort entry point.
emit_workspace_selftest() {
    [[ -n "$(LC_ALL=C find "$ROOT_DIR/tests" -path "$ROOT_DIR/tests/vendor" -prune -o -type f -name '*.bats' -print -quit 2>/dev/null)" ]] || return 0
    printf '\nWorkspace root — self-test:\n'
    printf '  yggdrasil\n'
    printf '    ws test yggdrasil [runs: bats tests/**/*.bats]\n'
}

# Render one component's adapter wiring. Walks the three plan-named
# verbs explicitly (test/lint/build) so a typo in the YAML doesn't
# silently swallow a missing slot — the diagnostic message stays
# loud either way.
#
# Caller (emit_component_adapters) is responsible for skipping
# components with no adapter file at all; by the time we get here,
# adapter_file is guaranteed to exist on disk.
_ws_orient_display_text() {
    # A \r\n pair collapses to \n first: Windows yq emits CRLF where Linux
    # emits LF, and mapping both chars to spaces rendered the same value one
    # column wider per embedded newline on Windows. A LONE \r is content
    # and still maps to a space like the other whitespace controls.
    local value="${1//$'\r\n'/$'\n'}"
    printf '%s' "$value" | tr '\011\012\015' '   ' | tr -d '\000-\010\013-\037\177'
}

# Classify one realm-declared component context path without allowing the
# existence probe to leave the component through traversal or symlinks.
_ws_orient_component_context_status() {
    local component_dir="$1" relative="$2" remaining segment candidate
    if [[ -z "$relative" || "$relative" == /* || "$relative" == *\\* || "$relative" =~ [[:cntrl:]] ]]; then
        echo "invalid"
        return 0
    fi

    candidate="$component_dir"
    remaining="$relative"
    while [[ -n "$remaining" ]]; do
        segment="${remaining%%/*}"
        if [[ "$remaining" == */* ]]; then
            remaining="${remaining#*/}"
        else
            remaining=""
        fi
        case "$segment" in
            ""|.|..)
                echo "invalid"
                return 0
                ;;
        esac
        candidate="$candidate/$segment"
        if [[ -L "$candidate" ]]; then
            echo "invalid"
            return 0
        fi
    done

    if [[ -e "$candidate" ]]; then
        echo "present"
    else
        echo "missing"
    fi
}

_emit_one_adapter() {
    local comp="$1" active_realm="$2"
    echo "  $comp"
    local adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    local verb cmd rc=0 any=0 parse_failed=0
    for verb in test lint build run clean; do
        rc=0
        cmd="$(ADAPTER_VERB="$verb" yq -r '.commands[strenv(ADAPTER_VERB)] // ""' "$adapter_file" 2>/dev/null)" || rc=$?
        if [[ $rc -ne 0 ]]; then
            # Don't let one malformed adapter file abort the whole
            # orient run — surface a diagnostic, keep walking.
            parse_failed=1
            continue
        fi
        if [[ -n "$cmd" && "$cmd" != "null" ]]; then
            printf '    ws %s [runs: %s]\n' "$verb" "$(_ws_orient_display_text "$cmd")"
            any=1
        fi
    done
    # ai_context pointers. Rendered here rather than checked by a
    # separate command: a dead pointer is only a problem at the moment
    # someone is about to follow it, which is exactly now. Paths are
    # relative to the component root, matching how the adapter's own
    # commands are interpreted.
    #
    # Compact JSON keeps embedded tabs/newlines inside one record so they can
    # be neutralized before rendering instead of forging peer rows.
    local ctx_record ctx_path_raw ctx_desc_raw ctx_path ctx_desc ctx_status
    while IFS= read -r ctx_record; do
        ctx_path_raw="$(jq -r '(.path // "" | tostring) + "\u001f"' <<< "$ctx_record" 2>/dev/null)" || continue
        ctx_desc_raw="$(jq -r '(.description // "" | tostring) + "\u001f"' <<< "$ctx_record" 2>/dev/null)" || continue
        ctx_path_raw="${ctx_path_raw%$'\037'}"
        ctx_desc_raw="${ctx_desc_raw%$'\037'}"
        [[ -n "$ctx_path_raw" ]] || continue
        ctx_path="$(_ws_orient_display_text "$ctx_path_raw")"
        ctx_desc="$(_ws_orient_display_text "$ctx_desc_raw")"
        ctx_status="$(_ws_orient_component_context_status "$COMPONENTS_DIR/$comp" "$ctx_path_raw")"
        # Both non-present states count as rot for --check. They are different
        # diagnoses — a renamed doc versus a path that leaves the component —
        # but a pointer that cannot be followed is the same failure to a gate.
        case "$ctx_status" in
            present) printf '    → %s — %s\n' "$ctx_path" "$ctx_desc" ;;
            missing)
                printf '    → %s — %s (MISSING)\n' "$ctx_path" "$ctx_desc"
                ORIENT_CONTEXT_ROT=$((ORIENT_CONTEXT_ROT + 1))
                ;;
            *)
                printf '    → %s — %s (INVALID PATH)\n' "$ctx_path" "$ctx_desc"
                ORIENT_CONTEXT_ROT=$((ORIENT_CONTEXT_ROT + 1))
                ;;
        esac
    done < <(yq -o=json -I=0 '.ai_context // [] | .[]' "$adapter_file" 2>/dev/null)

    if [[ $parse_failed -eq 1 ]]; then
        # A file that cannot parse cannot vouch for its pointers — that is
        # rot for --check purposes, not merely a rendering note.
        ORIENT_CONTEXT_ROT=$((ORIENT_CONTEXT_ROT + 1))
        echo "    (adapter present but YAML parse failed — fix $adapter_file)"
    elif [[ $any -eq 0 ]]; then
        echo "    (adapter present but no commands.{test,lint,build,run,clean} wired)"
    fi
}

# Skill index — workspace + active-realm scopes only. Component
# skills are surfaced indirectly via the component's adapter rows
# above, which render each ai_context pointer and flag any that no
# longer resolve; listing component skills here would explode the
# section into noise. Frontmatter-only parsing — the SKILL.md body
# stays unread, so the index is cheap even on a workspace with
# dozens of skills.
emit_skill_index() {
    printf '\nSkills (workspace + active realm):\n'
    local any=0
    if [[ -d "$ROOT_DIR/.agent/skills" ]]; then
        _emit_skills_in "$ROOT_DIR/.agent/skills" "workspace" && any=1
    fi
    if [[ -n "$_ORIENT_REALM" && -d "$REALMS_DIR/$_ORIENT_REALM/.agent/skills" ]]; then
        _emit_skills_in "$REALMS_DIR/$_ORIENT_REALM/.agent/skills" "realm:$_ORIENT_REALM" && any=1
    fi
    if [[ $any -eq 0 ]]; then
        echo "  (no skills found in workspace or active realm)"
    fi
}

# Render every SKILL.md under the given dir. Returns 0 if at least
# one skill rendered, 1 if the dir was empty — lets the caller
# decide whether to surface the "no skills" fallback.
_emit_skills_in() {
    local skills_dir="$1" scope="$2"
    local skill_file rendered=0 scope_display
    scope_display="$(_ws_orient_display_text "$scope")"
    for skill_file in "$skills_dir"/*/SKILL.md; do
        [[ -f "$skill_file" ]] || continue
        local name description
        # Parse the frontmatter only — `yq` reads the first YAML
        # document in a multi-doc stream by default, which on
        # SKILL.md files (front-matter only at the top) yields the
        # frontmatter map directly without a body read.
        # Tolerate malformed frontmatter — fall back to the dir
        # name and an empty description rather than aborting the
        # whole walk over one broken SKILL.md.
        name="$(yq -r '.name // ""' "$skill_file" 2>/dev/null)" || name=""
        description="$(yq -r '.description // ""' "$skill_file" 2>/dev/null)" || description=""
        # Fallback to the dir name if the frontmatter is missing /
        # malformed so the row still surfaces something useful.
        [[ -z "$name" || "$name" == "null" ]] && name="$(basename "$(dirname "$skill_file")")"
        [[ "$description" == "null" ]] && description=""
        name="$(_ws_orient_display_text "$name")"
        description="$(_ws_orient_display_text "$description")"
        if [[ -n "$description" ]]; then
            printf '  [%s] %s — %s\n' "$scope_display" "$name" "$description"
        else
            printf '  [%s] %s\n' "$scope_display" "$name"
        fi
        rendered=1
    done
    [[ $rendered -eq 1 ]]
}

# Active realm — same detection logic gdd-orientation Step 0c uses
# (ecosystem.local.yaml `realm:` selector, else a single realm-*).
# Prints a status line + pointer to the realm's AGENTS.md guide; the
# realm's skill enumeration lands separately in 4e so the index
# duties stay in one place. Consumes the cached _ORIENT_REALM state
# resolved by _resolve_orient_realm so the multi-realm exit-1 case
# is rendered as a clear status, not propagated as a script crash.
emit_active_realm() {
    printf '\n'
    case "$_ORIENT_REALM_STATUS" in
        error)
            echo "Active realm: error (detection failed)"
            if [[ -n "$_ORIENT_REALM_ERROR" ]]; then
                echo "  $_ORIENT_REALM_ERROR"
            fi
            return
            ;;
        ambiguous)
            echo "Active realm: ambiguous (multiple non-template realms found)"
            echo "  Set \`realm: <name>\` in ecosystem.local.yaml to pick one."
            return
            ;;
        none)
            echo "Active realm: none"
            echo "  Adopt one with \`ws realm <git-url>\` or scaffold the tutorial via \`ws realm init\`."
            return
            ;;
    esac
    echo "Active realm: $_ORIENT_REALM"
    local realm_agents="$REALMS_DIR/$_ORIENT_REALM/AGENTS.md"
    if [[ -f "$realm_agents" ]]; then
        echo "  Guide: $realm_agents"
    fi
    local trust_state
    trust_state="$(ws_realm_trust_state "$_ORIENT_REALM")"
    # Cache for emit_change_note_style so it can honor the realm config
    # layer without recomputing the trust fingerprint.
    _ORIENT_REALM_TRUST="$trust_state"
    if [[ "$trust_state" == "current" ]]; then
        echo "  Trust: approved"
    else
        echo "  Trust: reapproval required (state: $trust_state)"
        echo "  Review and approve with: ws realm use $_ORIENT_REALM"
    fi
}

# Change-note style — the prose budget for commit/CR/issue bodies, from
# style.changeNotes in the ecosystem config (realm carries community
# norms, ecosystem.local.yaml personal overrides). Surfaced here so the
# agent honors it without a config read of its own.
#
# Reads the three merge layers directly (local > realm > upstream,
# first hit wins) instead of calling ws_resolve_ecosystem: the full
# merge recomputes the realm trust fingerprint and spawns several yq
# processes, enough to push trusted-realm orient runs over the smoke
# timeout on slow hosts. The realm layer only counts when its trust
# state was resolved as current (cached by emit_active_realm),
# matching ws_resolve_ecosystem's gate. Falls back to "standard".
emit_change_note_style() {
    local style="" f
    local -a layers=()
    local local_file="${ECOSYSTEM_LOCAL:-$ROOT_DIR/ecosystem.local.yaml}"
    local base="${ECOSYSTEM:-$ROOT_DIR/ecosystem.yaml}"
    [[ -f "$local_file" ]] && layers+=("$local_file")
    if [[ "$_ORIENT_REALM_STATUS" == "ok" && "$_ORIENT_REALM_TRUST" == "current" && -f "$REALMS_DIR/$_ORIENT_REALM/ecosystem.yaml" ]]; then
        layers+=("$REALMS_DIR/$_ORIENT_REALM/ecosystem.yaml")
    fi
    [[ -f "$base" ]] && layers+=("$base")
    for f in ${layers[@]+"${layers[@]}"}; do
        style="$(yq -r '.style.changeNotes // ""' "$f" 2>/dev/null)" || style=""
        [[ "$style" == "null" ]] && style=""
        [[ -n "$style" ]] && break
    done
    style="$(_ws_orient_display_text "$style")"
    case "$style" in
        terse|standard|detailed) ;;
        "") style="standard" ;;
        *) style="standard (ignoring invalid style.changeNotes: $style)" ;;
    esac
    printf '\nChange-note style: %s\n' "$style"
    echo "  Prose budget for commit/CR/issue bodies — budgets in templates/*.md; set style.changeNotes (terse|standard|detailed) in ecosystem config."
}

# Header. The backticked literal is asserted by tests/ws-orient/orient.bats
# so a future rename surfaces the doc/help drift here first.
echo "Workspace toolset (\`ws orient\`)"

# Resolve realm state once so emit_active_realm + emit_component_adapters
# + emit_skill_index can all consume the same answer without re-invoking
# ws_detect_realm (which exits 1 on multi-realm and would otherwise
# kill orient mid-render).
_resolve_orient_realm

emit_subcommand_survey
emit_active_realm
emit_change_note_style
emit_component_adapters
emit_workspace_selftest
emit_skill_index

# The gate. Deliberately after the full render: a failing check should still
# leave the reader with the orientation they asked for, and the rows above are
# what says which pointer to fix.
if [[ "$ORIENT_CHECK" -eq 1 ]]; then
    if [[ "$ORIENT_CONTEXT_ROT" -gt 0 ]]; then
        printf '\nws orient --check: %d adapter check failure(s) — ai_context pointers that no longer resolve, or adapter YAML that no longer parses.\n' "$ORIENT_CONTEXT_ROT"
        echo "  Repoint or drop the rotted rows in the realm adapter, and fix any unparseable adapter file."
        exit 1
    fi
    printf '\nws orient --check: every adapter parses and every ai_context pointer resolves.\n'
fi

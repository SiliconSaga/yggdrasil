#!/usr/bin/env bats
# GitHub/GitLab provider parity for ws clone-fork (issue #122):
#   - fork creation works against GitHub sources via gh (not the GitLab API)
#   - the cross-group helper URL is provider-aware
#   - token resolution falls back to the provider default (GH_TOKEN /
#     GITLAB_TOKEN) on the canonical hosts only, mirroring git-auth.sh —
#     look-alike/self-hosted hosts still require an explicit gitTokens entry.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CLONE_FORK_BIN="$REPO_ROOT/scripts/ws-clone-fork.sh"
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    GH_FORK_MARKER="$BATS_TEST_TMPDIR/fork-created"
    mkdir -p "$TEST_BIN" "$BATS_TEST_TMPDIR/components"

    # Default glab stub: 404 everything (only the GitLab-path tests care).
    cat > "$TEST_BIN/glab" <<'SH'
#!/usr/bin/env bash
echo "404 Project Not Found" >&2
exit 1
SH
    chmod +x "$TEST_BIN/glab"

    export PATH="$TEST_BIN:$PATH"
    export ECOSYSTEM="$BATS_TEST_TMPDIR/ecosystem.yaml"
    export ECOSYSTEM_LOCAL="$BATS_TEST_TMPDIR/missing-local.yaml"
    export COMPONENTS_DIR="$BATS_TEST_TMPDIR/components"
    # Isolate REALMS_DIR to an empty dir so these clone-fork-logic tests don't
    # inherit whatever realm the developer happens to have cloned in the repo's
    # realms/ (an active realm makes ws_resolve_ecosystem require realm trust,
    # which these tests neither set up nor exercise).
    export REALMS_DIR="$BATS_TEST_TMPDIR/realms"
    mkdir -p "$REALMS_DIR"
    # Sandbox the git global config via HOME, not GIT_CONFIG_GLOBAL — the
    # env var needs git >= 2.32 and is silently IGNORED on older gits, which
    # both leaks the insteadOf rewrites into no-op land (tests then hit the
    # real network) and reads the developer's actual ~/.gitconfig. Unset the
    # inherited override vars too, or a runner exporting them would point
    # git past the sandbox entirely.
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME
    export GH_LOG GH_FORK_MARKER
}

write_ecosystem() {
    cat > "$ECOSYSTEM"
}

# Seed one commit and push it to source + fork bare repos the stubs hand out.
make_bare_pair() {
    SOURCE_BARE="$BATS_TEST_TMPDIR/source.git"
    FORK_BARE="$BATS_TEST_TMPDIR/fork.git"
    SEED="$BATS_TEST_TMPDIR/seed"
    git init -q "$SEED"
    git -C "$SEED" config user.name "Test User"
    git -C "$SEED" config user.email "test@example.local"
    echo "seed" > "$SEED/file.txt"
    git -C "$SEED" add file.txt
    git -C "$SEED" commit -q -m "seed"
    git -C "$SEED" branch -M main
    git init -q --bare "$SOURCE_BARE"
    git init -q --bare "$FORK_BARE"
    git -C "$SEED" push -q "$SOURCE_BARE" main
    git -C "$SEED" push -q "$FORK_BARE" main
    export SOURCE_BARE FORK_BARE
}

map_github_clone_urls() {
    # Native git on Windows can't resolve MSYS /tmp/... inside a file:// URL —
    # hand it the mixed C:/ form so the insteadOf rewrite clones for real.
    local fork_bare="$FORK_BARE" source_bare="$SOURCE_BARE"
    if command -v cygpath >/dev/null 2>&1; then
        fork_bare="$(cygpath -m "$fork_bare")"
        source_bare="$(cygpath -m "$source_bare")"
    fi
    git config --file "$HOME/.gitconfig" \
        "url.file://$fork_bare.insteadOf" "https://github.com/$GH_STUB_FORK_PATH.git"
    git config --file "$HOME/.gitconfig" \
        "url.file://$source_bare.insteadOf" "https://github.com/$GH_STUB_SOURCE_PATH.git"
}

# gh stub: logs every invocation; behavior driven by env:
#   GH_STUB_LOGIN            login returned by `api user` (default: alice)
#   GH_STUB_FORK_PATH        repo path that plays the fork
#   GH_STUB_FORK_EXISTS=1    fork exists from the start (else 404 until
#                            `gh repo fork` touches GH_FORK_MARKER)
#   GH_STUB_SOURCE_PATH      repo path that plays the source
#   GH_STUB_SOURCE_DENY_TOKEN  token value that gets 404 on the source
write_gh_stub() {
    cat > "$TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
{ printf 'gh:'; printf ' %q' "$@"; printf ' token=%s\n' "${GH_TOKEN:-}"; } >> "$GH_LOG"

emit_repo_json() {
    local repo_id="$1" bare="$2" path="$3"
    local ssh_url="git@github.com:$path.git" http_url="https://github.com/$path.git"
    if [[ "$path" == "${GH_STUB_FORK_PATH:-}" ]]; then
        ssh_url="${GH_STUB_FORK_SSH_URL:-$ssh_url}"
        http_url="${GH_STUB_FORK_HTTP_URL:-$http_url}"
    else
        ssh_url="${GH_STUB_SOURCE_SSH_URL:-$ssh_url}"
        http_url="${GH_STUB_SOURCE_HTTP_URL:-$http_url}"
    fi
    cat <<JSON
{"id":$repo_id,"default_branch":"main","ssh_url":"$ssh_url","clone_url":"$http_url","html_url":"https://github.com/$path"}
JSON
}

if [[ "${1:-}" == "api" ]]; then
    case "${2:-}" in
        user)
            printf '{"login":"%s"}\n' "${GH_STUB_LOGIN:-alice}"
            exit 0
            ;;
        "repos/${GH_STUB_FORK_PATH:-__unset__}")
            if [[ "${GH_STUB_FORK_EXISTS:-}" == "1" || -f "$GH_FORK_MARKER" ]]; then
                emit_repo_json 2 "$FORK_BARE" "$GH_STUB_FORK_PATH"
                exit 0
            fi
            echo "gh: Not Found (HTTP 404)" >&2
            exit 1
            ;;
        "repos/${GH_STUB_SOURCE_PATH:-__unset__}")
            if [[ -n "${GH_STUB_SOURCE_DENY_TOKEN:-}" && "${GH_TOKEN:-}" == "$GH_STUB_SOURCE_DENY_TOKEN" ]]; then
                echo "gh: Not Found (HTTP 404)" >&2
                exit 1
            fi
            emit_repo_json 1 "$SOURCE_BARE" "$GH_STUB_SOURCE_PATH"
            exit 0
            ;;
        *)
            echo "unexpected gh api call: $*" >&2
            exit 1
            ;;
    esac
fi

if [[ "${1:-}" == "repo" && "${2:-}" == "fork" ]]; then
    touch "$GH_FORK_MARKER"
    exit 0
fi

echo "unexpected gh call: $*" >&2
exit 1
SH
    chmod +x "$TEST_BIN/gh"
}

@test "gitlab.com falls back to GITLAB_TOKEN when no gitTokens entry covers the target" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
  homes:
    fork:
      namespace: gitlab.com/forks/alice-fork-group
components:
  widget:
    tier: supporting
    repo: https://gitlab.com/source/team/widget.git
YAML
    export GITLAB_TOKEN="fallback-token"

    run bash "$CLONE_FORK_BIN" widget

    [[ "$output" != *"No gitTokens entry covers"* ]]
    [ "$status" -eq 2 ]
    [[ "$output" == *"Cross-group fork detected"* ]]
}

@test "explicit gitTokens mapping wins over the default even when its var is unset" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
  homes:
    fork:
      namespace: github.com/fork-org
defaults:
  gitTokens:
    github.com/fork-org: GH_FORK_ONLY_TOKEN
components:
  widget:
    tier: supporting
    repo: https://github.com/source-org/widget.git
YAML
    export GH_TOKEN="gh-fallback-token"
    unset GH_FORK_ONLY_TOKEN || true

    run bash "$CLONE_FORK_BIN" widget

    [ "$status" -eq 1 ]
    [[ "$output" == *'$GH_FORK_ONLY_TOKEN is not set'* ]]
}

@test "self-hosted GitLab gets no default-token fallback" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
  homes:
    fork:
      namespace: gitlab.example.com/forks/alice-fork-group
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
YAML
    export GITLAB_TOKEN="fallback-token"

    run bash "$CLONE_FORK_BIN" widget

    [ "$status" -eq 1 ]
    [[ "$output" == *"No gitTokens entry covers"* ]]
}

@test "github source with existing fork clones and wires both remotes" {
    make_bare_pair
    write_gh_stub
    export GH_STUB_FORK_PATH="fork-org/widget"
    export GH_STUB_FORK_EXISTS=1
    export GH_STUB_SOURCE_PATH="source-org/widget"
    export GH_TOKEN="gh-fallback-token"
    map_github_clone_urls

    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
  homes:
    fork:
      namespace: github.com/fork-org
components:
  widget:
    tier: supporting
    repo: https://github.com/source-org/widget.git
YAML

    run bash "$CLONE_FORK_BIN" widget

    [ "$status" -eq 0 ]
    [[ "$output" == *"Fork     : fork-org/widget"* ]]
    TARGET="$COMPONENTS_DIR/widget"
    git -C "$TARGET" remote get-url forkhome
    git -C "$TARGET" remote get-url source-org
}

@test "provider API clone URLs must remain on the requested provider host" {
    write_gh_stub
    export GH_STUB_FORK_PATH="fork-org/widget"
    export GH_STUB_FORK_EXISTS=1
    export GH_STUB_SOURCE_PATH="source-org/widget"
    export GH_STUB_FORK_SSH_URL="git@evil.example:fork-org/widget.git"
    export GH_STUB_FORK_HTTP_URL="https://evil.example/fork-org/widget.git"
    export GH_STUB_SOURCE_SSH_URL="git@evil.example:source-org/widget.git"
    export GH_STUB_SOURCE_HTTP_URL="https://evil.example/source-org/widget.git"
    export GH_TOKEN="gh-fallback-token"
    local git_log="$BATS_TEST_TMPDIR/tampered-git.log"
    export git_log
    cat > "$TEST_BIN/git" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$git_log"
exit 0
SH
    chmod +x "$TEST_BIN/git"

    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
  homes:
    fork:
      namespace: github.com/fork-org
components:
  widget:
    tier: supporting
    repo: https://github.com/source-org/widget.git
YAML

    run bash "$CLONE_FORK_BIN" widget

    [ "$status" -ne 0 ]
    [[ "$output" == *"expected host 'github.com'"* ]]
    [ ! -s "$git_log" ]
}

@test "github missing fork is created via gh repo fork --org" {
    make_bare_pair
    write_gh_stub
    export GH_STUB_FORK_PATH="fork-org/widget"
    export GH_STUB_SOURCE_PATH="source-org/widget"
    export GH_STUB_LOGIN="alice"
    export GH_TOKEN="gh-fallback-token"
    map_github_clone_urls

    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
  homes:
    fork:
      namespace: github.com/fork-org
components:
  widget:
    tier: supporting
    repo: https://github.com/source-org/widget.git
YAML

    run bash "$CLONE_FORK_BIN" widget

    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == *"repo fork source-org/widget"* ]]
    [[ "$(cat "$GH_LOG")" == *"--org fork-org"* ]]
    [ -f "$GH_FORK_MARKER" ]
}

@test "github fork into the token's own account omits --org" {
    make_bare_pair
    write_gh_stub
    export GH_STUB_FORK_PATH="alice/widget"
    export GH_STUB_SOURCE_PATH="source-org/widget"
    export GH_STUB_LOGIN="alice"
    export GH_TOKEN="gh-fallback-token"
    map_github_clone_urls

    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
  homes:
    fork:
      namespace: github.com/alice
components:
  widget:
    tier: supporting
    repo: https://github.com/source-org/widget.git
YAML

    run bash "$CLONE_FORK_BIN" widget

    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == *"repo fork source-org/widget"* ]]
    [[ "$(cat "$GH_LOG")" != *"--org"* ]]
}

@test "github cross-org access gap emits a GitHub fork URL, not the GitLab form" {
    write_gh_stub
    export GH_STUB_FORK_PATH="fork-org/widget"
    export GH_STUB_SOURCE_PATH="source-org/widget"
    export GH_STUB_SOURCE_DENY_TOKEN="fork-token"

    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
  homes:
    fork:
      namespace: github.com/fork-org
defaults:
  gitTokens:
    github.com/source-org/widget: GH_SOURCE_TOKEN
    github.com/fork-org: GH_FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://github.com/source-org/widget.git
YAML
    export GH_SOURCE_TOKEN="source-token"
    export GH_FORK_TOKEN="fork-token"

    run bash "$CLONE_FORK_BIN" widget

    [ "$status" -eq 2 ]
    [[ "$output" == *"https://github.com/source-org/widget/fork"* ]]
    [[ "$output" != *"/-/forks/new"* ]]
}

@test "gitlab forkRepo override passes a renamed project to the fork API" {
    local glab_log="$BATS_TEST_TMPDIR/glab.log"
    local fork_marker="$BATS_TEST_TMPDIR/gitlab-fork-created"
    export glab_log fork_marker
    cat > "$TEST_BIN/glab" <<'SH'
#!/usr/bin/env bash
{ printf 'glab:'; printf ' %q' "$@"; printf '\n'; } >> "$glab_log"

case "$*" in
    *"projects/explicit%2Fforks%2Fwidget-cfr"*)
        if [[ -f "$fork_marker" ]]; then
            printf '{"id":2,"import_status":"failed","import_error":"stop after request capture"}\n'
            exit 0
        fi
        echo "404 Project Not Found" >&2
        exit 1
        ;;
    *"projects/source%2Fteam%2Fwidget"*)
        printf '{"id":1,"default_branch":"main"}\n'
        exit 0
        ;;
    *"projects/1/fork"*)
        touch "$fork_marker"
        printf '{"id":2,"import_status":"scheduled"}\n'
        exit 0
        ;;
esac

echo "unexpected glab call: $*" >&2
exit 1
SH
    chmod +x "$TEST_BIN/glab"

    write_ecosystem <<'YAML'
identity:
  forkRemote: alice-fork-group
defaults:
  gitProviders:
    gitlab.example.com: gitlab
  gitTokens:
    gitlab.example.com/source/team/widget: GITLAB_SOURCE_TOKEN
    gitlab.example.com/explicit/forks/widget-cfr: GITLAB_FORK_TOKEN
components:
  widget:
    tier: supporting
    repo: https://gitlab.example.com/source/team/widget.git
    forkRepo: https://gitlab.example.com/explicit/forks/widget-cfr.git
YAML
    export GITLAB_SOURCE_TOKEN="source-token"
    export GITLAB_FORK_TOKEN="fork-token"

    run bash "$CLONE_FORK_BIN" widget

    [ "$status" -eq 1 ]
    [[ "$output" == *"Fork import failed"* ]]
    grep -Fq "projects/1/fork" "$glab_log"
    grep -Fq "namespace_path=explicit/forks" "$glab_log"
    grep -Fq "name=widget-cfr" "$glab_log"
    grep -Fq "path=widget-cfr" "$glab_log"
}

@test "--url without --add-to-ecosystem is refused with guidance" {
    run bash "$CLONE_FORK_BIN" --url https://github.com/source-org/widget.git

    [ "$status" -eq 1 ]
    [[ "$output" == *"--url requires --add-to-ecosystem"* ]]
}

@test "--url rejects a component name passed alongside it" {
    run bash "$CLONE_FORK_BIN" widget --url https://github.com/source-org/widget.git --add-to-ecosystem

    [ "$status" -eq 1 ]
    [[ "$output" == *"component name OR --url"* ]]
}

@test "--url --add-to-ecosystem declares the component and runs the normal flow" {
    make_bare_pair
    write_gh_stub
    export GH_STUB_FORK_PATH="fork-org/widget"
    export GH_STUB_FORK_EXISTS=1
    export GH_STUB_SOURCE_PATH="source-org/widget"
    export GH_TOKEN="gh-fallback-token"
    map_github_clone_urls

    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
  homes:
    fork:
      namespace: github.com/fork-org
components: {}
YAML

    run bash "$CLONE_FORK_BIN" --url https://github.com/source-org/widget.git --add-to-ecosystem

    [ "$status" -eq 0 ]
    [[ "$output" == *"ADDED: widget to "*"missing-local.yaml"* ]]
    [[ "$output" == *"Fork     : fork-org/widget"* ]]
    grep -Fq "repo: https://github.com/source-org/widget.git" "$ECOSYSTEM_LOCAL"
    git -C "$COMPONENTS_DIR/widget" remote get-url forkhome
    git -C "$COMPONENTS_DIR/widget" remote get-url source-org
}

@test "--add-to-ecosystem without --url is refused, not silently ignored" {
    run bash "$CLONE_FORK_BIN" widget --add-to-ecosystem

    [ "$status" -eq 1 ]
    [[ "$output" == *"--add-to-ecosystem only applies with --url"* ]]
}

@test "--url mode fails the realm trust gate BEFORE writing any ecosystem entry" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
components: {}
YAML
    mkdir -p "$REALMS_DIR/realm-fixture"
    printf 'components: {}\n' > "$REALMS_DIR/realm-fixture/ecosystem.yaml"
    printf 'realm: realm-fixture\n' > "$ECOSYSTEM_LOCAL"

    run bash "$CLONE_FORK_BIN" --url https://github.com/source-org/widget.git --add-to-ecosystem

    [ "$status" -ne 0 ]
    [[ "$output" == *"trust"* ]]
    # The half-declared component must NOT exist — trust failure leaves no partial state.
    ! grep -q "widget" "$ECOSYSTEM_LOCAL"
}

@test "--url mode with an already-declared matching repo continues without ADDED" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
  homes:
    fork:
      namespace: github.com/fork-org
components:
  widget:
    tier: supporting
    repo: https://github.com/source-org/widget.git
YAML

    run bash "$CLONE_FORK_BIN" --url https://github.com/source-org/widget.git --add-to-ecosystem

    [[ "$output" == *"already declared with this repo"* ]]
    [[ "$output" != *"ADDED:"* ]]
    [ ! -f "$ECOSYSTEM_LOCAL" ]
}

@test "--url mode with a conflicting declared repo errors instead of overwriting" {
    write_ecosystem <<'YAML'
identity:
  forkRemote: forkhome
components:
  widget:
    tier: supporting
    repo: https://github.com/other-org/widget.git
YAML

    run bash "$CLONE_FORK_BIN" --url https://github.com/source-org/widget.git --add-to-ecosystem

    [ "$status" -eq 1 ]
    [[ "$output" == *"already declared with a different repo"* ]]
    [ ! -f "$ECOSYSTEM_LOCAL" ]
}

#!/usr/bin/env bash
# git-auth.sh — HTTPS token-injection auth env for raw git operations.
#
# Sourceable library (no top-level side effects beyond a load guard).
# git_auth_env_for_url populates the GIT_AUTH_ENV array with env settings
# that inject the ws-provided token (from .env, resolved via ecosystem
# gitTokens or the provider default) as an HTTP Authorization header and
# disable credential helpers — so OS/IDE keychain prompts and GUI login
# popups never fire on a fresh machine.
#
# This is the same mechanism ws push uses for `git push`; it was extracted
# here so clone/fetch/pull can reuse one implementation rather than each
# falling through to the OS credential manager. git-push.sh maps the
# GIT_AUTH_* outputs onto its own GIT_PUSH_* names via a thin shim.
#
# Requires ws_resolve_token_var (defined in ws-realm.sh) for per-URL
# gitTokens lookup; ws-realm.sh sources this file, so callers that source
# ws-realm.sh get both. If the resolver is absent, token lookup falls back
# to the provider default var (GH_TOKEN / GITLAB_TOKEN) only.
#
# Usage:
#   git_auth_env_for_url "$url"      # sets GIT_AUTH_ENV / LABEL / PROVIDER
#   git_auth_run git clone "$url" "$target"
#
# On SSH remotes, tokenless HTTPS, or unknown hosts, GIT_AUTH_ENV is left
# empty and git uses its normal behavior.

# Load guard — safe to source repeatedly (ws-realm.sh sources this, and
# several scripts source ws-realm.sh).
[[ -n "${_GIT_AUTH_SH_LOADED:-}" ]] && return 0
_GIT_AUTH_SH_LOADED=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-remote.sh"

# Strip protocol, embedded credentials, and .git suffix so the result can
# be matched against ecosystem gitTokens keys (host/group/... form).
git_auth_normalize_url() {
  local url="$1" host_url="$1" host path rest
  [[ "$host_url" != http://* ]] || host_url="https://${host_url#http://}"
  host="$(git_remote_host "$host_url")" || return 1
  case "$url" in
    *://*) rest="${url#*://}"; path=""; [[ "$rest" != */* ]] || path="${rest#*/}" ;;
    *) path="${url#*:}" ;;
  esac
  path="${path%/}"; path="${path%.git}"
  printf '%s%s' "$host" "${path:+/$path}"
}

# Print the bare host of an https:// URL (empty/return 1 otherwise — SSH
# and other schemes carry their own auth and need no token injection).
git_auth_https_host() {
  local url="$1"
  case "$url" in
    https://*) ;;
    *) return 1 ;;
  esac
  local rest="${url#https://}"
  rest="${rest%%/*}"
  rest="${rest#*@}"
  [[ -n "$rest" ]] || return 1
  printf '%s' "$rest"
}

# Resolve the token for a URL into GIT_AUTH_TOKEN_LABEL / GIT_AUTH_TOKEN_VALUE.
# Prefers an explicit gitTokens mapping (longest-prefix, via ws_resolve_token_var);
# falls back to the named provider default var. Returns 1 if nothing resolved.
git_auth_resolve_token() {
  local remote_url="$1" default_var="$2"
  local normalized token_var token_value

  normalized="$(git_auth_normalize_url "$remote_url")"
  if declare -F ws_resolve_token_var >/dev/null 2>&1; then
    token_var="$(ws_resolve_token_var "$normalized" 2>/dev/null || true)"
    # ws_resolve_token_var returns an env var NAME. If a gitTokens value isn't a
    # valid shell identifier, the ${!token_var} indirection below would error
    # ("bad substitution") and abort before the default fallback — treat an
    # invalid name as unmapped and fall through. ("null" is a valid identifier
    # pattern, so the explicit != "null" check below still earns its keep.)
    [[ "$token_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || token_var=""
    if [[ -n "$token_var" && "$token_var" != "null" ]]; then
      token_value="${!token_var:-}"
      if [[ -n "$token_value" ]]; then
        GIT_AUTH_TOKEN_LABEL="$token_var"
        GIT_AUTH_TOKEN_VALUE="$token_value"
        return 0
      fi
    fi
  fi

  # Default-token fallback only when a default var is named. A look-alike
  # host (e.g. gitlab-evil.example) deliberately passes an empty default so
  # GITLAB_TOKEN can't leak to it — only an explicit defaults.gitTokens
  # mapping (resolved above) sends a token there.
  if [[ -n "$default_var" ]]; then
    token_value="${!default_var:-}"
    if [[ -n "$token_value" ]]; then
      GIT_AUTH_TOKEN_LABEL="$default_var"
      GIT_AUTH_TOKEN_VALUE="$token_value"
      return 0
    fi
  fi

  GIT_AUTH_TOKEN_LABEL=""
  GIT_AUTH_TOKEN_VALUE=""
  return 1
}

git_auth_basic_header() {
  local user="$1" token="$2"
  local encoded
  encoded="$(printf '%s:%s' "$user" "$token" | base64 | tr -d '\n')"
  printf 'Authorization: Basic %s' "$encoded"
}

# Populate GIT_AUTH_ENV (array), GIT_AUTH_LABEL, GIT_AUTH_PROVIDER for a URL.
# Leaves GIT_AUTH_ENV empty when no token applies (SSH, tokenless, unknown host),
# in which case `git_auth_run git …` behaves like a plain git call — except that
# git_auth_run always neutralizes an inherited askpass helper, so "plain" cannot
# mean "blocks on the editor's GUI credential dialog". See git_auth_run.
git_auth_env_for_url() {
  local remote_url="$1"
  local host provider="" default_token_var="" token="" user="" token_label="" header=""

  GIT_AUTH_ENV=()
  GIT_AUTH_LABEL=""
  GIT_AUTH_PROVIDER=""

  host="$(git_auth_https_host "$remote_url")" || return 0
  case "$host" in
    github.com)
      provider="GitHub"
      default_token_var="GH_TOKEN"
      user="x-access-token"
      ;;
    gitlab.com)
      provider="GitLab"
      default_token_var="GITLAB_TOKEN"
      user="${GITLAB_USER:-oauth2}"
      ;;
    gitlab-*|*.gitlab.*|gitlab.*)
      # Self-hosted GitLab (gitlab.<domain>) and look-alike hosts. NEVER apply
      # the GITLAB_TOKEN default here — require an explicit defaults.gitTokens
      # mapping, so a self-hosted instance gets token auth when mapped while a
      # look-alike host (e.g. gitlab-evil.example) can't harvest the credential.
      provider="GitLab"
      default_token_var=""
      user="${GITLAB_USER:-oauth2}"
      ;;
    *)
      return 0
      ;;
  esac

  # Declared local so the resolved raw token (set by git_auth_resolve_token via
  # dynamic scope) doesn't linger as a readable global after this returns.
  local GIT_AUTH_TOKEN_LABEL="" GIT_AUTH_TOKEN_VALUE=""
  git_auth_resolve_token "$remote_url" "$default_token_var" || return 0
  token="$GIT_AUTH_TOKEN_VALUE"
  token_label="$GIT_AUTH_TOKEN_LABEL"
  [[ -n "$token" ]] || return 0
  header="$(git_auth_basic_header "$user" "$token")"
  # Append our two entries after any GIT_CONFIG_* already in the environment
  # rather than hard-coding COUNT=2, which would shadow inherited git config
  # (entries 0..base-1 stay inherited; git reads all base+2).
  local base="${GIT_CONFIG_COUNT:-0}"
  GIT_AUTH_ENV=(
    "GIT_TERMINAL_PROMPT=0"
    "GIT_CONFIG_COUNT=$((base + 2))"
    "GIT_CONFIG_KEY_${base}=credential.helper"
    "GIT_CONFIG_VALUE_${base}="
    "GIT_CONFIG_KEY_$((base + 1))=http.https://${host}/.extraheader"
    "GIT_CONFIG_VALUE_$((base + 1))=$header"
  )
  # Read by callers (ws push, ws hoard, ws diagnose) after this returns.
  # shellcheck disable=SC2034
  GIT_AUTH_LABEL="$token_label"
  # shellcheck disable=SC2034
  GIT_AUTH_PROVIDER="$provider"
}

# Classify one command word by its basename, the way git's ssh.variant=auto
# does: "ssh" for OpenSSH, "plink" for PuTTY's clients, empty for anything
# else. Case-insensitive and .exe-blind so Windows spellings classify too.
git_auth_ssh_client_kind() {
  local word="$1" base
  base="${word##*/}"
  base="${base##*\\}"
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  base="${base%.exe}"
  case "$base" in
    ssh) printf 'ssh' ;;
    plink|tortoiseplink|putty) printf 'plink' ;;
    *) printf '' ;;
  esac
}

# Scan a shell-parsed ssh command for the first word naming a recognised
# client and print "<offset>\t<kind>": the offset just past that word, which
# is where the client's options belong (OpenSSH keeps the FIRST value it sees
# for an option, so a forced BatchMode=yes has to land ahead of anything
# already configured), and "ssh" or "plink". With no recognised word the
# offset is the end of the first word and the kind is empty, for a caller
# that has been told the client kind some other way.
#
# Quotes and backslash escapes are honoured the way the shell will honour
# them: `env SSH_AUTH_SOCK="/tmp/ssh agent.sock" ssh` scans as three words,
# a quoted program path stays one, and the original text is never rewritten.
git_auth_ssh_client_word() {
  local ssh_cmd="$1"
  local len="${#ssh_cmd}" i=0 end c quote unquoted first_end="" insert_end="" kind=""

  while (( i < len )); do
    while (( i < len )); do
      c="${ssh_cmd:i:1}"
      [[ "$c" == [[:space:]] ]] || break
      i=$((i + 1))
    done
    (( i < len )) || break

    unquoted=""
    quote=""
    while (( i < len )); do
      c="${ssh_cmd:i:1}"
      if [[ -z "$quote" && "$c" == [[:space:]] ]]; then
        break
      fi
      if [[ -z "$quote" ]]; then
        case "$c" in
          "'") quote="'"; i=$((i + 1)); continue ;;
          '"') quote='"'; i=$((i + 1)); continue ;;
          "\\")
            if (( i + 1 < len )); then
              unquoted+="${ssh_cmd:i+1:1}"
              i=$((i + 2))
            else
              unquoted+="\\"
              i=$((i + 1))
            fi
            continue
            ;;
        esac
      elif [[ "$quote" == "'" ]]; then
        if [[ "$c" == "'" ]]; then
          quote=""
          i=$((i + 1))
          continue
        fi
      else
        if [[ "$c" == '"' ]]; then
          quote=""
          i=$((i + 1))
          continue
        fi
        if [[ "$c" == "\\" && $((i + 1)) -lt "$len" ]]; then
          unquoted+="${ssh_cmd:i+1:1}"
          i=$((i + 2))
          continue
        fi
      fi
      unquoted+="$c"
      i=$((i + 1))
    done

    end="$i"
    [[ -n "$first_end" ]] || first_end="$end"
    kind="$(git_auth_ssh_client_kind "$unquoted")"
    if [[ -n "$kind" ]]; then
      insert_end="$end"
      break
    fi
  done

  [[ -n "$insert_end" ]] || insert_end="${first_end:-$len}"
  printf '%s\t%s' "$insert_end" "$kind"
}

# Make the next git_auth_run fail instead of wait. For a best-effort call (a
# drift check, an advisory fetch) neither a prompt nor a stall is ever the
# right outcome: git's terminal prompt, Git Credential Manager's dialog, a
# custom credential helper's own window, ssh's passphrase / host-key questions
# and a peer that accepts the connection and then goes quiet would all hold a
# command that already succeeded, and an agent session has nobody to answer or
# interrupt. Call after git_auth_env_for_url so a resolved token still applies;
# the additions ride along in GIT_AUTH_ENV.
#
# credential.helper is blanked here because the token path already does it and
# the tokenless path did not, and a helper can open a dialog none of the other
# refusals reach. It is queued AFTER whatever GIT_CONFIG_* entries are already
# there, so a token extraheader is kept; the later GIT_CONFIG_COUNT wins at
# export time. http.lowSpeed* is the HTTPS stall bound (under a byte a second
# for 30 s aborts); the ssh options are the SSH one.
#
# The ssh client is resolved the way git resolves it — GIT_SSH_COMMAND, then
# core.sshCommand in repo_dir, then GIT_SSH (a bare program), then ssh — and
# the options are added to whichever applies rather than replacing it, which
# would silently drop a configured identity or client.
#
# Options are client-specific, so they are only added to a client that is
# recognised: OpenSSH takes the -o set, PuTTY's plink family takes -batch, and
# anything else (ssh.variant=simple, an unknown wrapper) is left exactly as
# configured. git would probe an unknown client with -G to find out; here the
# price of guessing wrong is a stalled agent session, so no guess is made and
# the other refusals above still apply. GIT_SSH_VARIANT / ssh.variant override
# the basename detection, as they do for git.
git_auth_env_noninteractive() {
  local repo_dir="$1" ssh_cmd="${GIT_SSH_COMMAND:-}" entry count=""
  GIT_AUTH_ENV+=("GIT_TERMINAL_PROMPT=0" "GCM_INTERACTIVE=never")

  for entry in ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"}; do
    [[ "$entry" == GIT_CONFIG_COUNT=* ]] && count="${entry#GIT_CONFIG_COUNT=}"
  done
  [[ -n "$count" ]] || count="${GIT_CONFIG_COUNT:-0}"
  GIT_AUTH_ENV+=(
    "GIT_CONFIG_COUNT=$((count + 3))"
    "GIT_CONFIG_KEY_${count}=credential.helper"
    "GIT_CONFIG_VALUE_${count}="
    "GIT_CONFIG_KEY_$((count + 1))=http.lowSpeedLimit"
    "GIT_CONFIG_VALUE_$((count + 1))=1"
    "GIT_CONFIG_KEY_$((count + 2))=http.lowSpeedTime"
    "GIT_CONFIG_VALUE_$((count + 2))=30"
  )

  [[ -n "$ssh_cmd" ]] || ssh_cmd=$(git -C "$repo_dir" config --get core.sshCommand 2>/dev/null) || ssh_cmd=""
  if [[ -z "$ssh_cmd" && -n "${GIT_SSH:-}" ]]; then
    # GIT_SSH is exec'd as a path; GIT_SSH_COMMAND is shell-parsed, so a path
    # with whitespace has to be quoted to survive the move between the two.
    ssh_cmd="$GIT_SSH"
    [[ "$ssh_cmd" == *[[:space:]]* ]] && ssh_cmd="\"$ssh_cmd\""
  fi
  ssh_cmd="${ssh_cmd:-ssh}"

  local insert_end client_kind
  IFS=$'\t' read -r insert_end client_kind <<< "$(git_auth_ssh_client_word "$ssh_cmd")"

  local variant="${GIT_SSH_VARIANT:-}"
  [[ -n "$variant" ]] || variant=$(git -C "$repo_dir" config --get ssh.variant 2>/dev/null) || variant=""
  if [[ -z "$variant" || "$variant" == "auto" ]]; then
    variant="$client_kind"
  fi
  local forced=""
  case "$variant" in
    ssh)   forced="-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=2" ;;
    plink|putty|tortoiseplink) forced="-batch" ;;
  esac
  [[ -n "$forced" ]] || return 0
  GIT_AUTH_ENV+=("GIT_SSH_COMMAND=${ssh_cmd:0:insert_end} $forced${ssh_cmd:insert_end}")
}

# Run a command with GIT_AUTH_ENV exported by the shell itself. The subshell
# keeps the injected values scoped to this invocation, while avoiding an
# external `env NAME=secret ...` process whose argument list exposes them.
git_auth_run() (
  # Neutralize any inherited askpass helper, for every call — token or not.
  #
  # When git needs a credential it tries credential helpers, then askpass, then
  # the terminal. VS Code and Cursor both export GIT_ASKPASS into every
  # integrated-terminal shell (`git.terminalAuthentication`, default on), and
  # that helper blocks on a GUI dialog. Nothing answers it in an agent session,
  # so a routine `ws clone` / `ws pull` / `ws push` hung indefinitely instead of
  # failing — observed twice, including a `git fetch` wedged for 14h59m.
  #
  # Cleared here rather than in GIT_AUTH_ENV because that array is populated
  # only when a token resolves; the tokenless path (SSH, unmapped host) is a
  # plain git call and was left exposed. Both names matter: git prefers
  # GIT_ASKPASS and falls back to SSH_ASKPASS.
  #
  # Deliberately NOT paired with GIT_TERMINAL_PROMPT=0 here. Killing only the
  # GUI leaves git's terminal prompt intact, so a human running `ws clone` in a
  # real terminal still gets asked for a username as before, while an agent
  # (no tty) fails fast with a readable error. The token path sets
  # GIT_TERMINAL_PROMPT=0 separately, because there a prompt means the token
  # itself is wrong and asking a human to hand-type past it hides that.
  export GIT_ASKPASS=''
  export SSH_ASKPASS=''
  local entry
  for entry in ${GIT_AUTH_ENV[@]+"${GIT_AUTH_ENV[@]}"}; do
    # Each entry is NAME=value; exporting the expansion is the intent.
    export "${entry?}"
  done
  builtin command "$@"
)

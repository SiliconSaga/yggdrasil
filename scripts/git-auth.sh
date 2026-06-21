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
#   env "${GIT_AUTH_ENV[@]}" git clone "$url" "$target"
#
# On SSH remotes, tokenless HTTPS, or unknown hosts, GIT_AUTH_ENV is left
# empty and git uses its normal behavior.

# Load guard — safe to source repeatedly (ws-realm.sh sources this, and
# several scripts source ws-realm.sh).
[[ -n "${_GIT_AUTH_SH_LOADED:-}" ]] && return 0
_GIT_AUTH_SH_LOADED=1

# Strip protocol, embedded credentials, and .git suffix so the result can
# be matched against ecosystem gitTokens keys (host/group/... form).
git_auth_normalize_url() {
  local url="$1"
  echo "$url" \
    | sed 's|^ssh://[^@]*@\([^:/]*\)[^/]*/|\1/|; s|^https://[^@]*@||; s|^http://[^@]*@||; s|^https://||; s|^http://||; s|^git@\([^:]*\):|/\1/|; s|^/||; s|\.git$||; s|/$||'
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
# in which case the caller's `env "${GIT_AUTH_ENV[@]}" git …` is a plain git call.
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

  GIT_AUTH_TOKEN_LABEL=""
  GIT_AUTH_TOKEN_VALUE=""
  git_auth_resolve_token "$remote_url" "$default_token_var" || return 0
  token="$GIT_AUTH_TOKEN_VALUE"
  token_label="$GIT_AUTH_TOKEN_LABEL"
  [[ -n "$token" ]] || return 0
  header="$(git_auth_basic_header "$user" "$token")"
  GIT_AUTH_ENV=(
    "GIT_TERMINAL_PROMPT=0"
    "GIT_CONFIG_COUNT=2"
    "GIT_CONFIG_KEY_0=credential.helper"
    "GIT_CONFIG_VALUE_0="
    "GIT_CONFIG_KEY_1=http.https://${host}/.extraheader"
    "GIT_CONFIG_VALUE_1=$header"
  )
  GIT_AUTH_LABEL="$token_label"
  GIT_AUTH_PROVIDER="$provider"
}

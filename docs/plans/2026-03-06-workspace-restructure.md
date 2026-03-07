# Yggdrasil Workspace Restructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure Yggdrasil into a self-contained workspace root with nested Git repos, a central ecosystem manifest (`ecosystem.yaml`), dual-mode source resolution (local Git vs OCI chart), and utility scripts for workspace management — eliminating the orphan `CLAUDE.md` at the parent directory.

**Architecture:** Yggdrasil becomes the single workspace root. SiliconSaga component repos live under `components/` directories, gitignored from Yggdrasil's own Git history. An `ecosystem.yaml` manifest declares all components, their tiers, chart versions, and values overrides. An optional `ecosystem.local.yaml` (gitignored) lets developers override resolution behavior per-machine — e.g. forcing chart mode even when a local checkout exists. A resolve script reads both files, detects which repos are checked out locally, and generates ArgoCD Application manifests accordingly (Git source for local, OCI chart for absent). Utility shell scripts handle clone/status/pull operations across the workspace. IDE workspace files are generated per-user, not tracked in Git.

**Tech Stack:** Bash scripts, `yq` (YAML processing), Git, Helm/ArgoCD manifests, OCI Helm registry (GHCR)

**Portable note:** This plan is designed to be executed on any system. It does NOT assume the current messy `D:\Dev\GitWS` layout. It only modifies files within the `yggdrasil` repo itself. After execution, a fresh user can clone just yggdrasil and use `ws-clone.sh` to fetch whatever components they need.

---

## Background & Key References

Before starting, read these files to understand the current state:

| File | Why |
|------|-----|
| `AGENTS.md` | Current workspace conventions, repo roles, script catalog |
| `CLAUDE.md` | Current Claude-specific overrides |
| `docs/ecosystem-architecture.md` | Three-tier architecture, repo map |
| `project-constellation.md` | Full component inventory with descriptions |
| `.agent/skills/multi-repo-orchestration/SKILL.md` | Current multi-repo session discipline |
| `yggdrasil.code-workspace` | Current VS Code workspace (uses `../sibling` paths — to be removed) |

Also understand the Nordri patterns (in the sibling `nordri` repo if available):
- `nordri/platform/argocd/app-of-apps.yaml` — How ArgoCD Applications reference Git repos
- `nordri/bootstrap.sh` — How bootstrap hydrates Gitea and patches paths
- `nordri/platform/fundamentals/apps/*.yaml` — Application manifest patterns (Helm chart vs Git path)

Key pattern from Nordri: ArgoCD Applications currently reference internal Gitea via
`http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/<repo>.git` with `targetRevision: HEAD`.
External Helm charts use public repo URLs like `https://charts.jetstack.io`.

---

## Task 1: Create the ecosystem manifest

**Files:**
- Create: `ecosystem.yaml`

This is the central source of truth for the entire SiliconSaga ecosystem.
It declares what components exist, their tiers, chart versions, and values.
It does NOT dictate source resolution — that's determined at resolve time
by what's checked out locally (and any overrides in `ecosystem.local.yaml`).

**Step 1: Create `ecosystem.yaml`**

```yaml
# ecosystem.yaml — SiliconSaga Ecosystem Manifest
#
# This file declares every component in the ecosystem, its tier, chart version,
# and any values overrides. The ws-resolve.sh script reads this to generate
# ArgoCD Application manifests, auto-detecting whether each component has a
# local Git checkout (source mode) or should be fetched from a chart registry
# (artifact mode).
#
# Chart versions are only used when a component is NOT checked out locally
# (unless overridden in ecosystem.local.yaml). Until chart CI is set up,
# most components will always run in source mode.
#
# Per-developer overrides go in ecosystem.local.yaml (gitignored).
# See docs/ecosystem-architecture.md for details.

defaults:
  chartRegistry: oci://ghcr.io/siliconsaga
  gitOrg: https://github.com/SiliconSaga
  gitea:
    # Internal Gitea URL pattern used by ArgoCD inside the cluster.
    # {repo} is replaced by the component name at resolve time.
    internalUrl: "http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/{repo}.git"

# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------
# Each component declares:
#   tier:          Deployment tier (1, 2, 3) or "supporting"
#   chartVersion:  Helm chart version to use when no local source is present
#   chartName:     Override chart name if it differs from the component key
#   path:          Path within the Git repo that ArgoCD should sync (default: ".")
#   namespace:     Target Kubernetes namespace
#   values:        Helm values overrides applied in both source and chart mode
#   syncWave:      ArgoCD sync wave for ordering (lower = earlier)
#   disabled:      Set true to skip this component entirely
#
# Per-developer overrides (ecosystem.local.yaml) additionally support:
#   forceChart:    Use chart even when local source exists (for testing)
# ---------------------------------------------------------------------------

components:
  # -- Tier 1: Cluster Substrate -------------------------------------------
  nordri:
    tier: 1
    chartVersion: "0.0.0"          # No chart published yet
    path: "platform/fundamentals"
    namespace: argocd
    # Nordri is special: it bootstraps itself. Its Application manifests are
    # applied by bootstrap.sh, not generated by ws-resolve.sh. Listed here
    # for completeness and ws-clone/ws-status visibility.

  # -- Tier 2: Platform ----------------------------------------------------
  nidavellir:
    tier: 2
    chartVersion: "0.0.0"
    path: "apps"
    namespace: argocd

  mimir:
    tier: 2
    chartVersion: "0.0.0"
    namespace: mimir
    values:
      postgres:
        enabled: true
      kafka:
        enabled: false
      valkey:
        enabled: false

  vordu:
    tier: 2
    chartVersion: "0.0.0"
    namespace: vordu

  # heimdall:
  #   tier: 2
  #   chartVersion: "0.0.0"
  #   namespace: heimdall
  #   disabled: true               # Not yet started

  # -- Tier 3: End-User Platform -------------------------------------------
  demicracy:
    tier: 3
    chartVersion: "0.0.0"
    namespace: demicracy

  tafl:
    tier: 3
    chartVersion: "0.0.0"
    namespace: tafl
    values:
      agones:
        enabled: true

  # bifrost:
  #   tier: 3
  #   chartVersion: "0.0.0"
  #   namespace: bifrost
  #   disabled: true               # Not yet started

  # -- Test chart (validates chart-mode resolution) ------------------------
  echo-test:
    tier: test
    chartVersion: "0.1.0"
    chartName: "echo-test"
    # This uses a public nginx-based test chart to validate that chart-mode
    # resolution works end-to-end without requiring our own chart CI.
    # See Task 5 for details.
    namespace: echo-test
    disabled: true                 # Enable manually to test chart resolution
```

**Step 2: Commit**

```bash
git add ecosystem.yaml
git commit -m "feat: add ecosystem.yaml — central workspace manifest

Declares all SiliconSaga components with tiers, chart versions, namespaces,
and values overrides. Used by ws-resolve.sh for dual-mode source resolution
(local Git vs OCI chart).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Create the components directory structure and .gitignore

**Files:**
- Create: `components/.gitkeep`
- Modify: `.gitignore`

The `components/` directory is where nested Git repos will live, fully gitignored
except for a `.gitkeep` to preserve the directory in Git.

**Step 1: Create the components directory**

```bash
mkdir -p components
touch components/.gitkeep
```

**Step 2: Update `.gitignore`**

Read the current `.gitignore` first, then replace it with:

```gitignore
# Environment and drafts
.env
.issues/
.prs/
.DS_Store

# Nested Git repos — cloned by ws-clone.sh, ignored by yggdrasil's Git.
# Only .gitkeep is tracked so the directory structure is preserved.
/components/*
!/components/.gitkeep

# Local ecosystem overrides (per-developer, never committed)
ecosystem.local.yaml

# Generated ArgoCD manifests from ws-resolve.sh
/.generated/

# IDE workspace files — generated per-user via ws-vscode.sh, not shared
*.code-workspace
```

**Step 3: Commit**

```bash
git add .gitignore components/.gitkeep
git commit -m "feat: add components/ directory for nested Git repos

Gitignored so cloned component repos don't pollute yggdrasil's history.
The .gitkeep ensures the directory exists after a fresh clone.
Also gitignores ecosystem.local.yaml (per-dev overrides) and
IDE workspace files (generated per-user).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Create workspace utility scripts

**Files:**
- Create: `scripts/ws-clone.sh`
- Create: `scripts/ws-status.sh`
- Create: `scripts/ws-pull.sh`
- Create: `scripts/ws-list.sh`
- Create: `scripts/ws-vscode.sh`

These scripts read `ecosystem.yaml` and operate on the `components/` directory.
They require `yq` (v4+) to be installed. All scripts auto-source `.env` if present (for `GH_TOKEN`).

### Step 1: Create `scripts/ws-clone.sh`

```bash
#!/usr/bin/env bash
# ws-clone.sh — Clone one or all ecosystem components into components/
#
# Usage:
#   ws-clone.sh <component>    Clone a single component
#   ws-clone.sh --all          Clone all non-disabled components
#
# Components are cloned into components/<component-name>/ as independent
# Git repos. If the directory already exists, it is skipped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

# Source .env if present (for GH_TOKEN)
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required. Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

clone_component() {
    local name="$1"
    local target="$COMPONENTS_DIR/$name"

    if [[ -d "$target/.git" ]]; then
        echo "SKIP: $name (already cloned at $target)"
        return 0
    fi

    local disabled
    disabled=$(yq ".components.$name.disabled // false" "$ECOSYSTEM")
    if [[ "$disabled" == "true" ]]; then
        echo "SKIP: $name (disabled in ecosystem.yaml)"
        return 0
    fi

    local git_org
    git_org=$(yq '.defaults.gitOrg' "$ECOSYSTEM")
    local repo_url="$git_org/$name.git"

    echo "CLONE: $name -> $target"
    git clone "$repo_url" "$target"
}

if [[ "${1:-}" == "--all" ]]; then
    for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
        clone_component "$name"
    done
elif [[ -n "${1:-}" ]]; then
    # Validate component exists in manifest
    if [[ "$(yq ".components.${1} // \"missing\"" "$ECOSYSTEM")" == "missing" ]]; then
        echo "ERROR: '$1' is not declared in ecosystem.yaml" >&2
        exit 1
    fi
    clone_component "$1"
else
    echo "Usage: ws-clone.sh <component> | --all" >&2
    exit 1
fi
```

### Step 2: Create `scripts/ws-status.sh`

```bash
#!/usr/bin/env bash
# ws-status.sh — Show Git status for all cloned components
#
# Usage:
#   ws-status.sh             Short status (branch + dirty flag)
#   ws-status.sh --verbose   Full git status per component

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

VERBOSE="${1:-}"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

# Status of yggdrasil itself
echo "=== yggdrasil ==="
branch=$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || echo "detached")
dirty=$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null | head -1)
echo "  branch: $branch${dirty:+  (dirty)}"
if [[ "$VERBOSE" == "--verbose" ]]; then
    git -C "$ROOT_DIR" status --short 2>/dev/null | sed 's/^/  /'
fi
echo ""

# Status of each component
for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
    target="$COMPONENTS_DIR/$name"
    if [[ ! -d "$target/.git" ]]; then
        echo "=== $name === (not cloned)"
        echo ""
        continue
    fi

    echo "=== $name ==="
    branch=$(git -C "$target" branch --show-current 2>/dev/null || echo "detached")
    dirty=$(git -C "$target" status --porcelain 2>/dev/null | head -1)
    echo "  branch: $branch${dirty:+  (dirty)}"

    if [[ "$VERBOSE" == "--verbose" ]]; then
        git -C "$target" status --short 2>/dev/null | sed 's/^/  /'
    fi
    echo ""
done
```

### Step 3: Create `scripts/ws-pull.sh`

```bash
#!/usr/bin/env bash
# ws-pull.sh — Pull latest changes for all cloned components
#
# Usage:
#   ws-pull.sh               Pull all cloned components (skips dirty repos)
#   ws-pull.sh <component>   Pull a single component

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

pull_component() {
    local name="$1"
    local target="$COMPONENTS_DIR/$name"

    if [[ ! -d "$target/.git" ]]; then
        echo "SKIP: $name (not cloned)"
        return 0
    fi

    local dirty
    dirty=$(git -C "$target" status --porcelain 2>/dev/null | head -1)
    if [[ -n "$dirty" ]]; then
        echo "SKIP: $name (dirty working tree — commit or stash first)"
        return 0
    fi

    local branch
    branch=$(git -C "$target" branch --show-current 2>/dev/null)
    echo "PULL: $name ($branch)"
    git -C "$target" pull --rebase 2>&1 | sed 's/^/  /'
}

if [[ -n "${1:-}" ]]; then
    pull_component "$1"
else
    for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
        pull_component "$name"
    done
fi
```

### Step 4: Create `scripts/ws-list.sh`

```bash
#!/usr/bin/env bash
# ws-list.sh — List all ecosystem components and their local status
#
# Usage:
#   ws-list.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

printf "%-15s %-10s %-12s %-8s\n" "COMPONENT" "TIER" "CHART" "LOCAL"
printf "%-15s %-10s %-12s %-8s\n" "---------" "----" "-----" "-----"

for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
    tier=$(yq ".components.$name.tier" "$ECOSYSTEM")
    chart_version=$(yq ".components.$name.chartVersion" "$ECOSYSTEM")
    disabled=$(yq ".components.$name.disabled // false" "$ECOSYSTEM")

    if [[ -d "$COMPONENTS_DIR/$name/.git" ]]; then
        local_status="yes"
    else
        local_status="-"
    fi

    if [[ "$disabled" == "true" ]]; then
        local_status="disabled"
    fi

    printf "%-15s %-10s %-12s %-8s\n" "$name" "$tier" "$chart_version" "$local_status"
done
```

### Step 5: Create `scripts/ws-vscode.sh`

```bash
#!/usr/bin/env bash
# ws-vscode.sh — Generate a VS Code workspace file from cloned components
#
# Usage:
#   ws-vscode.sh                   Generate yggdrasil.code-workspace
#
# Only includes component folders that are actually cloned locally.
# Re-run after cloning new components to update the workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"
OUTPUT="$ROOT_DIR/yggdrasil.code-workspace"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

# Build folder list: yggdrasil root first, then cloned components
folders='[{"path": "."}'
for name in $(yq '.components | keys | .[]' "$ECOSYSTEM"); do
    if [[ -d "$COMPONENTS_DIR/$name/.git" ]]; then
        folders="$folders, {\"path\": \"components/$name\"}"
    fi
done
folders="$folders]"

# Write workspace file
echo "{" > "$OUTPUT"
echo "  \"folders\": $folders," >> "$OUTPUT"
echo '  "settings": {}' >> "$OUTPUT"
echo "}" >> "$OUTPUT"

# Pretty-print if yq can handle JSON
if yq --output-format=json '.' "$OUTPUT" > /dev/null 2>&1; then
    yq --output-format=json --prettyPrint '.' "$OUTPUT" > "$OUTPUT.tmp" && mv "$OUTPUT.tmp" "$OUTPUT"
fi

echo "Generated: $OUTPUT"
echo "Open in VS Code: code $OUTPUT"
```

### Step 6: Make all scripts executable and commit

```bash
chmod +x scripts/ws-clone.sh scripts/ws-status.sh scripts/ws-pull.sh scripts/ws-list.sh scripts/ws-vscode.sh
git add scripts/ws-clone.sh scripts/ws-status.sh scripts/ws-pull.sh scripts/ws-list.sh scripts/ws-vscode.sh
git commit -m "feat: add workspace management scripts

ws-clone.sh  — Clone one or all ecosystem components
ws-status.sh — Show Git branch/dirty status across workspace
ws-pull.sh   — Pull latest for all cloned components
ws-list.sh   — List components with tier, chart version, local status
ws-vscode.sh — Generate VS Code workspace file from cloned components

All scripts read from ecosystem.yaml and operate on components/.
IDE workspace files are generated per-user (gitignored), not shared.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Create the resolve script for dual-mode ArgoCD source resolution

**Files:**
- Create: `scripts/ws-resolve.sh`

This is the core of the Terasology-inspired dual resolution. It reads
`ecosystem.yaml`, merges any `ecosystem.local.yaml` overrides, checks which
components have local Git checkouts, and generates ArgoCD Application manifests
accordingly.

**Step 1: Create `scripts/ws-resolve.sh`**

```bash
#!/usr/bin/env bash
# ws-resolve.sh — Generate ArgoCD Application manifests from ecosystem.yaml
#
# Resolution logic per component:
#   1. If forceChart is set (via ecosystem.local.yaml), use chart mode
#   2. Else if a local Git checkout exists in components/<name>/, use git mode
#   3. Else if chartVersion != "0.0.0", use chart mode
#   4. Else skip (no source available)
#
# Local overrides in ecosystem.local.yaml (gitignored) are deep-merged on top
# of ecosystem.yaml. This lets developers force chart mode, change values, or
# enable/disable components without touching the shared manifest.
#
# Output: .generated/applications/<component>.yaml per component
#
# Usage:
#   ws-resolve.sh                  Resolve all components
#   ws-resolve.sh --dry-run        Print what would be generated without writing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ECOSYSTEM="$ROOT_DIR/ecosystem.yaml"
LOCAL_OVERRIDES="$ROOT_DIR/ecosystem.local.yaml"
COMPONENTS_DIR="$ROOT_DIR/components"
OUTPUT_DIR="$ROOT_DIR/.generated/applications"
DRY_RUN="${1:-}"

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (v4+) is required." >&2
    exit 1
fi

# Merge ecosystem.yaml with local overrides (if present)
EFFECTIVE_FILE=$(mktemp)
trap "rm -f $EFFECTIVE_FILE" EXIT

if [[ -f "$LOCAL_OVERRIDES" ]]; then
    echo "(using local overrides from ecosystem.local.yaml)"
    yq eval-all 'select(fileIndex==0) *d select(fileIndex==1)' \
        "$ECOSYSTEM" "$LOCAL_OVERRIDES" > "$EFFECTIVE_FILE"
else
    cp "$ECOSYSTEM" "$EFFECTIVE_FILE"
fi

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    mkdir -p "$OUTPUT_DIR"
fi

CHART_REGISTRY=$(yq '.defaults.chartRegistry' "$EFFECTIVE_FILE")
GITEA_URL_PATTERN=$(yq '.defaults.gitea.internalUrl' "$EFFECTIVE_FILE")

resolve_component() {
    local name="$1"

    local disabled
    disabled=$(yq ".components.$name.disabled // false" "$EFFECTIVE_FILE")
    if [[ "$disabled" == "true" ]]; then
        echo "SKIP: $name (disabled)"
        return 0
    fi

    local tier namespace chart_version chart_name path sync_wave force_chart values_yaml
    tier=$(yq ".components.$name.tier" "$EFFECTIVE_FILE")
    namespace=$(yq ".components.$name.namespace // \"$name\"" "$EFFECTIVE_FILE")
    chart_version=$(yq ".components.$name.chartVersion // \"0.0.0\"" "$EFFECTIVE_FILE")
    chart_name=$(yq ".components.$name.chartName // \"$name\"" "$EFFECTIVE_FILE")
    path=$(yq ".components.$name.path // \".\"" "$EFFECTIVE_FILE")
    sync_wave=$(yq ".components.$name.syncWave // \"0\"" "$EFFECTIVE_FILE")
    force_chart=$(yq ".components.$name.forceChart // false" "$EFFECTIVE_FILE")

    # Extract values as a YAML block (empty string if no values)
    values_yaml=$(yq ".components.$name.values // \"\"" "$EFFECTIVE_FILE")

    local source_type repo_url target_revision source_block

    if [[ "$force_chart" == "true" && "$chart_version" != "0.0.0" ]]; then
        # Developer override: force chart even with local source
        source_type="chart (forced)"
        repo_url="$CHART_REGISTRY"

        source_block="    repoURL: '$repo_url'
    chart: $chart_name
    targetRevision: $chart_version"

    elif [[ "$force_chart" != "true" && -d "$COMPONENTS_DIR/$name/.git" ]]; then
        # Local Git checkout exists — use Gitea source
        source_type="git"
        repo_url="${GITEA_URL_PATTERN//\{repo\}/$name}"
        target_revision="HEAD"

        source_block="    repoURL: '$repo_url'
    targetRevision: $target_revision
    path: $path"

    elif [[ "$chart_version" != "0.0.0" ]]; then
        # No local checkout, but a chart version is available
        source_type="chart"
        repo_url="$CHART_REGISTRY"

        source_block="    repoURL: '$repo_url'
    chart: $chart_name
    targetRevision: $chart_version"

    else
        echo "SKIP: $name (no local source, no chart version)"
        return 0
    fi

    # Append helm values if present
    if [[ "$values_yaml" != "" && "$values_yaml" != "null" ]]; then
        source_block="$source_block
    helm:
      values: |
$(echo "$values_yaml" | sed 's/^/        /')"
    fi

    local manifest
    manifest="apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $name
  namespace: argocd
  labels:
    ecosystem.siliconsaga.dev/tier: \"$tier\"
    ecosystem.siliconsaga.dev/managed-by: ws-resolve
  annotations:
    argocd.argoproj.io/sync-wave: \"$sync_wave\"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
$source_block
  destination:
    server: https://kubernetes.default.svc
    namespace: $namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true"

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        echo "--- WOULD GENERATE: $name ($source_type) ---"
        echo "$manifest"
        echo ""
    else
        local output_file="$OUTPUT_DIR/$name.yaml"
        echo "$manifest" > "$output_file"
        echo "GENERATED: $name ($source_type) -> $output_file"
    fi
}

echo "Resolving ecosystem components..."
echo "  Chart registry: $CHART_REGISTRY"
echo "  Components dir: $COMPONENTS_DIR"
echo ""

for name in $(yq '.components | keys | .[]' "$EFFECTIVE_FILE"); do
    resolve_component "$name"
done

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    echo ""
    echo "Generated manifests in $OUTPUT_DIR/"
    echo "Apply with: kubectl apply -f $OUTPUT_DIR/"
fi
```

**Step 2: Make executable and commit**

```bash
chmod +x scripts/ws-resolve.sh
git add scripts/ws-resolve.sh
git commit -m "feat: add ws-resolve.sh — dual-mode ArgoCD source resolution

Reads ecosystem.yaml (+ optional ecosystem.local.yaml overrides), detects
local Git checkouts in components/, and generates ArgoCD Application
manifests using Git source (via Gitea) for local repos or OCI chart source
for absent repos. Supports --dry-run and per-component forceChart override.

Inspired by Terasology's Gradle composite build pattern where local source
takes precedence over registry artifacts.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Add the echo-test chart for chart-mode validation

**Files:**
- Create: `charts/echo-test/Chart.yaml`
- Create: `charts/echo-test/values.yaml`
- Create: `charts/echo-test/templates/deployment.yaml`
- Create: `charts/echo-test/templates/service.yaml`

A minimal Helm chart that deploys an nginx pod. This exists in-repo so you can
test chart-mode resolution via `helm push` to GHCR without needing CI set up
for any real component. It also serves as a template for how future component
charts should be structured.

**Step 1: Create `charts/echo-test/Chart.yaml`**

```yaml
apiVersion: v2
name: echo-test
description: Minimal test chart for validating ecosystem chart-mode resolution
type: application
version: 0.1.0
appVersion: "1.27.0"
```

**Step 2: Create `charts/echo-test/values.yaml`**

```yaml
replicaCount: 1

image:
  repository: nginx
  tag: "1.27-alpine"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    cpu: 50m
    memory: 64Mi
  requests:
    cpu: 10m
    memory: 32Mi
```

**Step 3: Create `charts/echo-test/templates/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ .Chart.Name }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ .Chart.Name }}
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 80
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /
              port: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

**Step 4: Create `charts/echo-test/templates/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
  labels:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 80
      protocol: TCP
  selector:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
```

**Step 5: Validate the chart locally**

Run: `helm lint charts/echo-test/`
Expected: "1 chart(s) linted, 0 chart(s) failed"

Run: `helm template echo-test charts/echo-test/`
Expected: Rendered Deployment and Service YAML with no errors.

**Step 6: Commit**

```bash
git add charts/echo-test/
git commit -m "feat: add echo-test chart for chart-mode validation

Minimal nginx-based Helm chart. Can be pushed to GHCR manually to test
that ws-resolve.sh correctly generates chart-source Applications when
no local Git checkout exists.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Rework CLAUDE.md, AGENTS.md, and documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md` (formerly `agents.md` — note the case)
- Modify: `.agent/skills/multi-repo-orchestration/SKILL.md`
- Modify: `docs/ecosystem-architecture.md`

### Step 1: Verify file casing

Check whether the repo has `AGENTS.md` or `agents.md` (the listing showed lowercase `agents.md`
but the CLAUDE.md references `AGENTS.md`). Use whichever exists; if lowercase, rename to uppercase
for consistency:

```bash
git mv agents.md AGENTS.md 2>/dev/null || true
```

### Step 2: Update `CLAUDE.md`

Read the current file, then rewrite it. The key change: remove all references to `../` sibling
directories and the parent workspace root. Yggdrasil is now self-contained.

```markdown
# Yggdrasil — Claude Code

**Read [`AGENTS.md`](AGENTS.md) first** — it contains all shared workspace instructions:
repo roles, skills, git workflow, utility scripts, auth setup, and issue/PR conventions.

This file covers only Claude-specific overrides.

---

## Workspace Structure

Yggdrasil is the workspace root. Component repos live in `components/` as
independent Git repos (gitignored from yggdrasil's history).

```
yggdrasil/
  ecosystem.yaml          # Central manifest — tiers, chart versions, values
  ecosystem.local.yaml    # Per-developer overrides (gitignored)
  components/
    nordri/               # Cloned via ws-clone.sh
    mimir/
    ...
  scripts/
    ws-clone.sh           # Clone components from ecosystem.yaml
    ws-status.sh          # Git status across workspace
    ws-pull.sh            # Pull all cloned components
    ws-list.sh            # List components and local status
    ws-resolve.sh         # Generate ArgoCD Applications (Git vs chart)
    ws-vscode.sh          # Generate VS Code workspace file
```

Use `scripts/ws-list.sh` to see what's declared and what's checked out locally.

## Loading Skills

Use the `Skill` tool to load skills from `.agent/skills/<name>/SKILL.md`.

## Co-Authored-By Trailer

When committing, use this exact trailer format:

```
Co-Authored-By: Claude <model> <noreply@anthropic.com>
```

Replace `<model>` with the model name (e.g. `Sonnet 4.6`, `Opus 4.6`).
```

### Step 3: Update `AGENTS.md`

Read the current file. Key changes needed:

1. **Workspace Layout section**: Change from "repos are sibling directories" to "repos live in
   `components/` under yggdrasil". Update the repo roles table to reflect the new paths.

2. **Utility Scripts table**: Add the new `ws-*` scripts alongside the existing `git-push.sh` etc.

3. **Git Workflow section**: The `git-push.sh` and `git-pr.sh` scripts still work — they operate
   on whatever repo you're in. But note that when working in a component, the cwd will be
   `yggdrasil/components/<name>/` rather than `../<name>/`.

4. **Add a new section: Ecosystem Manifest** explaining `ecosystem.yaml`, `ecosystem.local.yaml`,
   and the dual-mode resolution concept.

The specific edits depend on the exact current content — read the file and make surgical updates.
Do NOT rewrite sections that don't need changing (skills table, auth setup, issue/PR drafts, etc.).

Key additions for the Utility Scripts table:

```markdown
| `ws-clone.sh [name\|--all]` | Clone ecosystem component(s) into `components/` |
| `ws-status.sh [--verbose]` | Git status across all cloned components |
| `ws-pull.sh [name]` | Pull latest for cloned components |
| `ws-list.sh` | List all components with tier, chart version, local status |
| `ws-resolve.sh [--dry-run]` | Generate ArgoCD Application manifests (dual-mode) |
| `ws-vscode.sh` | Generate VS Code workspace file from cloned components |
```

Key replacement for the Workspace Layout mention at the top:

```markdown
Yggdrasil is the workspace root for the SiliconSaga ecosystem. Component repos
live in `components/` as independent Git repos, cloned via `scripts/ws-clone.sh`.
The `ecosystem.yaml` manifest declares all components, their tiers, and configuration.
Per-developer overrides go in `ecosystem.local.yaml` (gitignored).
```

Add a new section after Auth Setup:

```markdown
## Ecosystem Manifest

`ecosystem.yaml` is the central declaration of all SiliconSaga components.
It defines tiers, chart versions, namespaces, and Helm values overrides.

`ecosystem.local.yaml` (gitignored) lets developers override any field
per-machine without touching the shared manifest. Common uses:

- `forceChart: true` on a component to use its chart even with local source
- Override `values:` for local environment specifics (hostnames, feature flags)
- `disabled: false` on echo-test to validate chart-mode resolution

The `ws-resolve.sh` script merges both files and generates ArgoCD Application
manifests, choosing Git source or OCI chart per component based on what's
checked out locally (and any `forceChart` overrides).

## IDE Setup

IDE workspace files are NOT tracked in Git — they vary per developer and
per set of cloned components.

- **VS Code**: Run `scripts/ws-vscode.sh` to generate `yggdrasil.code-workspace`
  from your currently cloned components. Re-run after cloning more.
- **JetBrains**: Open the `yggdrasil/` directory, then attach component
  directories as modules via File > Project Structure.
- **Terminal / Neovim / etc.**: Just `cd` into `yggdrasil/` or any component
  under `components/`. The scripts work from anywhere.
```

### Step 4: Update `multi-repo-orchestration/SKILL.md`

Read the current file. Update the **Workspace Layout** section:

Replace:
```markdown
- Repos are sibling directories in a shared workspace: nordri, nidavellir, mimir, yggdrasil, vordu
```

With:
```markdown
- Component repos live in `yggdrasil/components/` as independent Git repos
- Clone components: `scripts/ws-clone.sh <name>` or `scripts/ws-clone.sh --all`
- Check workspace state: `scripts/ws-status.sh` or `scripts/ws-list.sh`
```

### Step 5: Update `docs/ecosystem-architecture.md`

Read the current file. Add a new section after the "Repository Map" table:

```markdown
## Workspace Structure

Component repos live inside yggdrasil under `components/`:

```
yggdrasil/
  ecosystem.yaml            # Manifest: components, tiers, chart versions, values
  ecosystem.local.yaml      # Per-developer overrides (gitignored)
  components/
    nordri/                  # Independent Git repo (gitignored)
    nidavellir/
    mimir/
    vordu/
    demicracy/
    tafl/
  .generated/
    applications/            # ArgoCD manifests from ws-resolve.sh (gitignored)
```

### Dual-Mode Source Resolution

Each component can be consumed in two ways:

1. **Source mode** (local Git checkout exists): ArgoCD syncs from the Git repo
   (via internal Gitea mirror). Used during development.
2. **Chart mode** (no local checkout): ArgoCD installs a pre-built Helm chart
   from the OCI registry. Used for stable dependencies you aren't actively changing.

The `scripts/ws-resolve.sh` script auto-detects which mode applies per component
and generates the appropriate ArgoCD Application manifests.

Developers can override resolution per-component via `ecosystem.local.yaml`:
- `forceChart: true` — use chart even when local source exists
- Override `values:` for local environment specifics
- Toggle `disabled` to include/exclude components

See `ecosystem.yaml` for the full component inventory.
```

### Step 6: Commit

```bash
git add CLAUDE.md AGENTS.md .agent/skills/multi-repo-orchestration/SKILL.md docs/ecosystem-architecture.md
git commit -m "docs: update workspace docs for nested-repo structure

- CLAUDE.md: yggdrasil is now self-contained workspace root
- AGENTS.md: update layout, add ws-* scripts, ecosystem manifest section,
  IDE setup guidance (VS Code, JetBrains, terminal)
- multi-repo-orchestration skill: update workspace layout
- ecosystem-architecture.md: add workspace structure and dual-mode resolution

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Remove the VS Code workspace file from Git

**Files:**
- Delete from Git: `yggdrasil.code-workspace`

The workspace file is now generated per-user via `ws-vscode.sh` and gitignored
(the `*.code-workspace` pattern was added in Task 2). It should be removed from
Git history so it doesn't conflict with the generated version.

### Step 1: Remove from Git tracking

```bash
git rm yggdrasil.code-workspace
```

### Step 2: Commit

```bash
git commit -m "chore: remove VS Code workspace file from Git

IDE workspace files are now generated per-user via ws-vscode.sh and
gitignored. They vary per developer based on which components are cloned.
See AGENTS.md 'IDE Setup' section for per-IDE guidance.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Test the workspace scripts end-to-end

This task validates that everything works together. It should be done on a
system where you can clone repos (requires network access + GitHub credentials).

### Step 1: Verify ws-list.sh works

Run: `scripts/ws-list.sh`

Expected output (no components cloned yet):

```
COMPONENT       TIER       CHART        LOCAL
---------       ----       -----        -----
demicracy       3          0.0.0        -
echo-test       test       0.1.0        disabled
mimir           2          0.0.0        -
nidavellir      2          0.0.0        -
nordri          1          0.0.0        -
tafl            3          0.0.0        -
vordu           2          0.0.0        -
```

### Step 2: Clone a single component

Run: `scripts/ws-clone.sh vordu`

Expected: Clones into `components/vordu/`. Verify with:
```bash
ls components/vordu/.git  # Should exist
scripts/ws-list.sh        # vordu should show LOCAL=yes
```

### Step 3: Clone all components

Run: `scripts/ws-clone.sh --all`

Expected: Clones all non-disabled components. Vordu is skipped (already exists).

### Step 4: Test ws-status.sh

Run: `scripts/ws-status.sh`

Expected: Shows branch and dirty status for yggdrasil and all cloned components.

### Step 5: Test ws-resolve.sh in dry-run mode

Run: `scripts/ws-resolve.sh --dry-run`

Expected: For each cloned component, prints a Git-source Application manifest.
For echo-test (disabled), prints SKIP.

### Step 6: Test ws-resolve.sh for real

Run: `scripts/ws-resolve.sh`

Expected: Creates `.generated/applications/<name>.yaml` for each resolvable
component. Inspect a few to verify:
- Cloned components have `repoURL` pointing at Gitea internal URL
- No components use chart source yet (all are `0.0.0`)

### Step 7: Test local overrides

Create a temporary `ecosystem.local.yaml`:
```yaml
components:
  echo-test:
    disabled: false
```

Run: `scripts/ws-resolve.sh --dry-run`

Expected: echo-test now resolves as chart mode (version 0.1.0 from GHCR).
Clean up: `rm ecosystem.local.yaml`

### Step 8: Test ws-vscode.sh

Run: `scripts/ws-vscode.sh`

Expected: Generates `yggdrasil.code-workspace` with folders for yggdrasil root
plus each cloned component. Verify it opens correctly in VS Code:
```bash
code yggdrasil.code-workspace
```

### Step 9: Test ws-pull.sh

Run: `scripts/ws-pull.sh`

Expected: Pulls latest for all cloned components (or reports "Already up to date").

### Step 10: Commit (if any test-driven fixes were needed)

If any scripts needed adjustment during testing, commit the fixes:

```bash
git add -u
git commit -m "fix: address issues found during workspace script testing

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Clean up the orphan CLAUDE.md

**This task is manual and depends on the system layout.**

If you are on the original system with `D:\Dev\GitWS\CLAUDE.md`:

### Step 1: Delete the orphan file

```bash
rm ../CLAUDE.md   # Relative to yggdrasil root
```

This file was a redirect shim. Now that yggdrasil is the workspace root,
Claude Code sessions should be started from within `yggdrasil/` (or a
component directory under `yggdrasil/components/`).

### Step 2: Verify Claude Code picks up the right CLAUDE.md

Start a new Claude Code session with cwd = `yggdrasil/`. It should
automatically load `yggdrasil/CLAUDE.md`.

Start a session with cwd = `yggdrasil/components/nordri/`. Claude Code
walks up the directory tree and should find `yggdrasil/CLAUDE.md`.

If the second case doesn't work (because `components/nordri/` has its own
`.git` and Claude Code may scope to that repo), consider adding a minimal
`CLAUDE.md` to each component repo that points back:

```markdown
# Component Repo — see workspace root
Read workspace instructions from the parent yggdrasil repo:
`../../CLAUDE.md` and `../../AGENTS.md`
```

This is a fallback — test first before adding it.

---

## Deferred TODOs

These are explicitly out of scope for this plan. File as GitHub issues or
track in a future plan.

### TODO: Chart Release CI

Each component repo needs a GitHub Action that:
1. On merge to `main`, runs `helm package` on the repo's chart
2. Pushes to `oci://ghcr.io/siliconsaga/<name>:<version>`
3. Optionally opens a PR against yggdrasil's `ecosystem.yaml` to bump the
   `chartVersion` field

Until this exists, all components must be in source mode (local Git checkout).

The `echo-test` chart can be manually pushed to validate the flow:
```bash
helm package charts/echo-test/
helm push echo-test-0.1.0.tgz oci://ghcr.io/siliconsaga
```

### TODO: Gitea vs GitHub Day-2

The current setup uses Gitea as the in-cluster Git source for ArgoCD.
Day-2 options:

1. **Upgrade Gitea to persistent**: Give it a Postgres DB via Mimir/Crossplane,
   persistent volume, proper backup via Velero. Gitea becomes a first-class
   platform component in Nidavellir.

2. **Switch to GitHub**: Point ArgoCD directly at GitHub repos. Eliminates
   Gitea entirely (or reduces it to a mirror). Requires ArgoCD to have
   GitHub credentials and network access.

3. **Hybrid**: Gitea for homelab (air-gapped friendly), GitHub for GKE.
   The `ecosystem.yaml` defaults section could support per-environment
   Git source configuration.

This decision affects `ws-resolve.sh` (which Gitea URL pattern to use) and
`nordri/bootstrap.sh` (whether to hydrate Gitea at all).

### TODO: Dependency Resolution Between Components

The Terasology workspace supported recursive dependency fetching — `groovyw
module recurse ModuleName` would parse `module.txt` and clone transitive
dependencies. A similar feature could be added:

- `ecosystem.yaml` gains a `depends:` field per component
- `ws-clone.sh` gains a `--recursive` flag
- Cloning `tafl` would automatically clone `demicracy` (app-of-apps parent),
  which would clone `nidavellir`, etc.

Not needed now since the ecosystem is small enough to `ws-clone.sh --all`.

### TODO: Linear.app Evaluation

Decision from discussion: stick with GitHub Issues + Projects v2. Linear has
poor multi-repo story and contradicts the self-hosted ethos. Revisit only if
GitHub Projects proves insufficient for cycle-based planning.

---

## Summary of New/Modified Files

| Action | File | Purpose |
|--------|------|---------|
| Create | `ecosystem.yaml` | Central ecosystem manifest |
| Create | `components/.gitkeep` | Preserve dir in Git |
| Create | `scripts/ws-clone.sh` | Clone components |
| Create | `scripts/ws-status.sh` | Workspace Git status |
| Create | `scripts/ws-pull.sh` | Pull all components |
| Create | `scripts/ws-list.sh` | List components |
| Create | `scripts/ws-vscode.sh` | Generate VS Code workspace (per-user) |
| Create | `scripts/ws-resolve.sh` | Dual-mode ArgoCD resolution with local overrides |
| Create | `charts/echo-test/` | Test chart for chart-mode validation |
| Modify | `.gitignore` | Ignore components/, .generated/, *.code-workspace, ecosystem.local.yaml |
| Modify | `CLAUDE.md` | Self-contained workspace root |
| Modify | `AGENTS.md` | Updated layout, new scripts, ecosystem manifest, IDE setup |
| Modify | `multi-repo-orchestration/SKILL.md` | Updated workspace layout |
| Modify | `docs/ecosystem-architecture.md` | Workspace structure + dual-mode resolution docs |
| Delete | `yggdrasil.code-workspace` | Remove from Git (now generated per-user) |
| Delete | `../CLAUDE.md` (parent dir) | Remove orphan redirect shim |

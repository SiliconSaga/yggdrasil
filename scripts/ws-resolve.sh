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

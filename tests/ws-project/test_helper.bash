# Shared fixture for ws-project bats tests.
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
WS_PROJECT_BIN="$REPO_ROOT/scripts/ws-project.sh"
ADSE_DIR="$REPO_ROOT/components/adse"

# Build an isolated workspace under $BATS_TEST_TMPDIR.
init_project_workspace() {
    WORK="$BATS_TEST_TMPDIR/work"
    export ROOT_DIR="$WORK"
    export HOARDS_DIR="$WORK/hoards"
    export ADSE_DIR   # real adse scripts from the repo
    mkdir -p "$HOARDS_DIR"
}

# Scaffold a minimal project hoard at hoards/<name>/.
# Usage: make_project_hoard <name> [--with-mandatory]
make_project_hoard() {
    local name="$1" extras="${2:-}"
    local hoard="$HOARDS_DIR/$name"
    mkdir -p "$hoard/working" "$hoard/design"

    cat > "$hoard/.project.yaml" <<'YAML'
template: sadd
title: "Test Project"
mandatory: [purpose-scope, architecture]
sections:
  - id: purpose-scope
  - id: architecture
  - id: design-alternatives
YAML

    if [[ "$extras" == "--with-mandatory" ]]; then
        cat > "$hoard/philosophy.md" <<'MD'
---
title: Purpose
sadd_section: purpose-scope
---
# Purpose
This is the purpose.
MD
        cat > "$hoard/architecture.md" <<'MD'
---
title: Architecture
sadd_section: architecture
---
# Architecture
Main arch description.
MD
    fi
}

run_project() { run bash "$WS_PROJECT_BIN" "$@"; }

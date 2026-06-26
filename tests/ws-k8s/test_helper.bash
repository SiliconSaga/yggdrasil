REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
GUARD_LIB="$REPO_ROOT/scripts/ws-k8s-guard.sh"

# Stub kubectl: `config view ...` prints a default namespace we control.
make_kubectl_stub() {
    local default_ns="$1"
    cat > "$BATS_TEST_TMPDIR/kubectl" <<EOF
#!/usr/bin/env bash
case "\$*" in
    *"config view"*) echo "$default_ns" ;;
    *) echo "" ;;
esac
EOF
    chmod +x "$BATS_TEST_TMPDIR/kubectl"
    export KUBECTL="$BATS_TEST_TMPDIR/kubectl"
}

run_guard() { run bash -c "source '$GUARD_LIB'; k8s_guard_evaluate \"\$@\"" _ "$@"; }

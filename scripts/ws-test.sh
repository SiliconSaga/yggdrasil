#!/usr/bin/env bash
# ws-test.sh — Run tests for a component
#
# Usage:
#   ws-test.sh <component> [test-name | args...]
#
# Auto-detects the test runner (adapter command > Gradle > Makefile > Go >
# Python). Any non-flag arg is treated as a test name and auto-translated
# to the runner's filter syntax. Runner-specific flags pass through as-is.
# See `ws test --help` for the full usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:="$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Auto-source .env so tokens/config are available to test runners
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

# shellcheck source=ws-realm.sh
source "$SCRIPT_DIR/ws-realm.sh"

# Find the Gradle subproject test task for a given test class name.
# Searches for matching Java/Kotlin/Groovy/Scala test sources and derives the
# :subproject:test task. Prints the task (e.g. ":engine-tests:test") or empty.
_ws_gradle_find_test() {
    local class_name="$1"
    local -a matches=()
    local lang
    for lang in java kotlin groovy scala; do
        local ext
        case "$lang" in
            java) ext="java" ;;
            kotlin) ext="kt" ;;
            groovy) ext="groovy" ;;
            scala) ext="scala" ;;
        esac
        while IFS= read -r m; do
            [[ -n "$m" ]] && matches+=("$m")
        done < <(find . -path "*/src/test/${lang}/*/${class_name}.${ext}" -type f 2>/dev/null)
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        return
    fi
    if [[ ${#matches[@]} -gt 1 ]]; then
        echo "WARNING: '$class_name' found in multiple subprojects:" >&2
        printf "  %s\n" "${matches[@]}" >&2
        echo "  Using first match. Pass --tests with a fully qualified name to disambiguate." >&2
    fi

    local subproject="${matches[0]#./}"
    # Root-project test: path starts with src/test/ after stripping ./
    if [[ "$subproject" == src/test/* ]]; then
        echo ":test"
        return
    fi
    subproject="${subproject%%/src/test/*}"
    if [[ "$subproject" == "." || -z "$subproject" ]]; then
        echo ":test"
    else
        echo ":${subproject//\//:}:test"
    fi
}

test_help() {
    local stream="${1:-2}"
    {
        echo "Usage: ws test <component> [test-name | args...]"
        echo ""
        echo "Run tests for a component. The test runner is detected automatically"
        echo "(run 'ws actions <comp>' to see what's configured)."
        echo ""
        echo "With no extra args, runs the full test suite. With a test name"
        echo "(any arg not starting with -), translates it into the runner's"
        echo "filter syntax automatically:"
        echo "  ws test terasology ClientNetworkStateTest"
        echo "  ws test mimir TestFoo"
        echo "  ws test myapp 'test_login*'"
        echo ""
        echo "Runner-specific flags are passed through as-is:"
        echo "  ws test mimir -run TestFoo -v"
        echo "  ws test terasology --tests '*.SomeTest'"
        echo ""
        echo "For pytest adapters, a selector that names an existing path or"
        echo "nodeid runs just that target; anything else becomes a -k filter:"
        echo "  ws test knarr tests/test_foo.py            # runs that file"
        echo "  ws test knarr tests/test_foo.py::test_bar  # runs that test"
        echo "  ws test knarr some_keyword                 # -k some_keyword"
    } >&"$stream"
}

# --- Arg parsing ---

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    test_help 1
    exit 0
fi

if [[ $# -lt 1 ]]; then
    test_help 2
    exit 1
fi

if [[ $# -gt 7 ]]; then
    echo "ERROR: Too many arguments (max 7: component + 6 test args)." >&2
    echo "  Use 'ws exec <comp> <cmd>' for complex test invocations." >&2
    exit 1
fi

comp="$1"
shift
ws_validate_component "$comp"
cd "$COMPONENT_DIR"

# --- Detect test runner ---
# Precedence matches ws-realm.sh ws_actions:
#   adapter command > Gradle > Makefile > Go > Python

runner=""
adapter_cmd=""

# 1. Check realm adapter for a test command
active_realm="$(ws_detect_realm)" || true
if [[ -n "$active_realm" ]]; then
    adapter_file="$REALMS_DIR/$active_realm/adapters/$comp.yaml"
    if [[ -f "$adapter_file" ]]; then
        # Guard the substitution: under `set -euo pipefail` a non-zero yq
        # exit (malformed adapter YAML) would abort before the auto-detect
        # fallback below. `// ""` already maps a missing key to empty.
        adapter_cmd=$(yq -r '.commands.test // ""' "$adapter_file" 2>/dev/null) || adapter_cmd=""
        if [[ -n "$adapter_cmd" ]]; then
            runner="adapter"
        fi
    fi
fi

# 2. Auto-detect from project files
if [[ -z "$runner" ]]; then
    # Workspace-root tests: yggdrasil itself is treated as a "component"
    # whose test suite is the bats files under tests/. We use the vendored
    # bats-core runtime so contributors don't need a system install.
    # Detection recurses (matching the dispatch's tests/**/*.bats walk
    # below) so the runner still engages when smoke.bats moves out of
    # the top level — the asymmetry was only masked by smoke.bats living
    # at tests/smoke.bats. Vendor dir is excluded; same as dispatch.
    if [[ "$comp" == "yggdrasil" ]] && \
       [[ -n "$(LC_ALL=C find "$ROOT_DIR/tests" -path "$ROOT_DIR/tests/vendor" -prune -o -type f -name '*.bats' -print -quit 2>/dev/null)" ]]; then
        runner="bats"
    elif [[ -f gradlew ]]; then
        runner="gradle"
    elif [[ -f Makefile ]] && grep -q '^test:' Makefile; then
        runner="make"
    elif [[ -f go.mod ]]; then
        runner="go"
    elif [[ -f pyproject.toml ]]; then
        runner="python"
    else
        # Fallback: check one level down for a single nested Go module
        go_candidates=()
        for d in */go.mod; do
            [[ -f "$d" ]] && go_candidates+=("${d%/go.mod}")
        done
        if [[ ${#go_candidates[@]} -eq 1 ]]; then
            runner="go"
            cd "${go_candidates[0]}"
        elif [[ ${#go_candidates[@]} -gt 1 ]]; then
            echo "ERROR: Multiple Go modules found in $COMPONENT_DIR:" >&2
            printf "  %s/\n" "${go_candidates[@]}" >&2
            echo "  Use 'ws exec $comp go test <args>' to target a specific module." >&2
            exit 1
        fi
    fi
fi

if [[ -z "$runner" ]]; then
    echo "ERROR: Cannot detect test runner in $COMPONENT_DIR." >&2
    echo "  Run 'ws actions $comp' to see available commands." >&2
    exit 1
fi

# --- Separate test filter from runner flags ---
# Flags (args starting with -) and their values pass through; the first
# non-flag positional arg is treated as the test name filter. Known
# value-expecting flags keep the next arg as part of the flag pair.

test_filter=""
runner_args=()
expect_value=false
for arg in "$@"; do
    if [[ "$expect_value" == true ]]; then
        runner_args+=("$arg")
        expect_value=false
        continue
    fi
    if [[ "$arg" == -* ]]; then
        runner_args+=("$arg")
        # Flags that consume the next arg as a value.
        # Boolean flags like --parallel, --info, --debug are NOT listed.
        case "$arg" in
            # Shared / Go / Gradle / pytest
            -run|--tests|-k|-m|-o|--maxfail|--tb|-timeout|\
            -count|-bench|-benchtime|-cpu|-shuffle|\
            -coverprofile|-cpuprofile|-memprofile|-blockprofile|-mutexprofile|\
            -I|--init-script|--build-file|--project-dir)
                expect_value=true ;;
            # -p takes a value for pytest (-p plugin), Go (-p N
            # parallelism), and Gradle (-p PROJECT_DIR). Bats treats it
            # as boolean (--pretty), so consuming the next arg as a
            # value under bats would silently swallow a positional.
            -p)
                case "$runner" in
                    python|go|gradle) expect_value=true ;;
                esac ;;
            # -r takes a value for pytest only (-r REPORT_CHARS); bats
            # treats it as boolean (--recursive). Same swallow risk.
            -r)
                [[ "$runner" == "python" ]] && expect_value=true ;;
        esac
    elif [[ -z "$test_filter" ]]; then
        test_filter="$arg"
    else
        runner_args+=("$arg")
    fi
done

# --- Parse adapter command into an array for safe exec ---
# Contract: adapter commands are whitespace-separated tokens only. Args with
# embedded whitespace or quotes are not supported — use a shell wrapper script
# and point the adapter at that if you need complex quoting.
adapter_argv=()
if [[ -n "$adapter_cmd" ]]; then
    # shellcheck disable=SC2206
    read -r -a adapter_argv <<< "$adapter_cmd"
fi

# --- Dispatch to the selected runner ---

case "$runner" in
    adapter|gradle)
        gradle_argv=()
        if [[ ${#adapter_argv[@]} -gt 0 ]]; then
            # Adapter may be non-Gradle — only take the Gradle path if it looks like one
            if [[ "${adapter_argv[0]}" == *gradlew* ]]; then
                gradle_argv=("${adapter_argv[@]}")
            else
                # Non-Gradle adapter. A positional test selector can be
                # translated for pytest commands; other runners can't.
                if [[ -n "$test_filter" ]]; then
                    if [[ "$adapter_cmd" == *pytest* ]]; then
                        # A selector that resolves to an on-disk path or a
                        # pytest nodeid (path::node) is passed positionally so
                        # pytest collects just that target. This also lets a
                        # single file run when unrelated modules have
                        # collection errors (e.g. mid-refactor). Anything else
                        # is treated as a keyword expression for -k.
                        if [[ -e "$test_filter" || ( "$test_filter" == *"::"* && -e "${test_filter%%::*}" ) ]]; then
                            "${adapter_argv[@]}" "$test_filter" "${runner_args[@]}"
                        else
                            "${adapter_argv[@]}" -k "$test_filter" "${runner_args[@]}"
                        fi
                        exit 0
                    fi
                    echo "ERROR: Adapter command '${adapter_argv[*]}' is not Gradle or pytest." >&2
                    echo "  Test name filters are only supported for Gradle, Go, Python, and pytest adapters." >&2
                    echo "  Use 'ws exec $comp <runner> <args>' to run '$test_filter' directly." >&2
                    exit 1
                fi
                "${adapter_argv[@]}" "${runner_args[@]}"
                exit 0
            fi
        else
            gradle_argv=(./gradlew test)
        fi
        if [[ -n "$test_filter" ]]; then
            # Build --tests pattern: pass through FQNs and wildcards as-is,
            # prefix bare class names with *. so they match any package.
            gradle_pattern="$test_filter"
            if [[ "$test_filter" != *.* && "$test_filter" != *\** ]]; then
                gradle_pattern="*.$test_filter"
            fi
            # Find which Gradle subproject contains this test class
            gradle_task=""
            clean_task=""
            gradle_task=$(_ws_gradle_find_test "$test_filter")
            if [[ -n "$gradle_task" ]]; then
                clean_task="${gradle_task%:test}:cleanTest"
                # Reuse adapter's base args (everything except the trailing task)
                # e.g. "./gradlew --no-daemon :facades:PC:test" → base = "./gradlew --no-daemon"
                if [[ ${#gradle_argv[@]} -lt 2 ]]; then
                    echo "ERROR: Adapter command '${gradle_argv[*]}' is missing a task argument." >&2
                    echo "  Expected format: './gradlew [flags...] <task>' (e.g. './gradlew test')." >&2
                    exit 1
                fi
                gradle_base=("${gradle_argv[@]:0:${#gradle_argv[@]}-1}")
                "${gradle_base[@]}" "$clean_task" "$gradle_task" --tests "$gradle_pattern" "${runner_args[@]}"
            else
                "${gradle_argv[@]}" --tests "$gradle_pattern" "${runner_args[@]}"
            fi
        else
            "${gradle_argv[@]}" "${runner_args[@]}"
        fi
        ;;
    make)
        if [[ -n "$test_filter" || ${#runner_args[@]} -gt 0 ]]; then
            echo "ERROR: Makefile test target does not support extra args." >&2
            echo "  Use 'ws exec $comp <runner> <args>' for targeted tests." >&2
            exit 1
        fi
        make test
        ;;
    go)
        if [[ -n "$test_filter" ]]; then
            go test ./... -count=1 -run "$test_filter" "${runner_args[@]}"
        elif [[ ${#runner_args[@]} -gt 0 ]]; then
            go test ./... -count=1 "${runner_args[@]}"
        else
            go test ./... -count=1
        fi
        ;;
    python)
        if [[ -n "$test_filter" ]]; then
            uv run pytest -k "$test_filter" "${runner_args[@]}"
        elif [[ ${#runner_args[@]} -gt 0 ]]; then
            uv run pytest "${runner_args[@]}"
        else
            uv run pytest
        fi
        ;;
    bats)
        # Workspace-root shell tests via vendored bats-core. Discovers all
        # tests/**/*.bats files (skipping anything under tests/vendor/, which
        # is third-party runtime code, not our tests). A test_filter, if
        # given, is forwarded to bats as a `--filter` regex.
        bats_bin="$ROOT_DIR/tests/vendor/bats-core/bin/bats"
        if [[ ! -x "$bats_bin" ]]; then
            echo "ERROR: vendored bats not found or not executable: $bats_bin" >&2
            echo "  See tests/vendor/README.md for the refresh procedure." >&2
            exit 1
        fi
        bats_files=()
        while IFS= read -r f; do
            bats_files+=("$f")
        done < <(LC_ALL=C find "$ROOT_DIR/tests" -path "$ROOT_DIR/tests/vendor" -prune -o -type f -name '*.bats' -print | LC_ALL=C sort)
        if [[ ${#bats_files[@]} -eq 0 ]]; then
            echo "(no .bats files found under tests/)" >&2
            exit 0
        fi
        bats_argv=("$bats_bin")
        if [[ -n "$test_filter" ]]; then
            bats_argv+=(--filter "$test_filter")
        fi
        bats_argv+=("${runner_args[@]}" "${bats_files[@]}")
        "${bats_argv[@]}"
        ;;
esac

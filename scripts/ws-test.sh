#!/usr/bin/env bash
# ws-test.sh — Run tests for a component
# ws:use-when running the component's test suite via its adapter
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

# Load .env so tokens/config are available to test runners.
# GOTCHA: this exports the real workspace tokens (GH_TOKEN, GITLAB_TOKEN, …)
# into the environment of EVERY test run from here. Tests that assert behavior
# under a *missing* token (or any specific env state) must isolate themselves —
# e.g. `env -u GH_TOKEN …` in the bats run helper — or they'll see the ambient
# token and pass/fail differently than when the file is run standalone. See
# tests/ws-provider-cli/cli.bats for the pattern.
# shellcheck source=ws-env.sh
source "$SCRIPT_DIR/ws-env.sh"
ws_load_env "$ROOT_DIR/.env"

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
        echo "For pytest adapters, selectors that name existing paths or"
        echo "nodeids run those targets; anything else becomes a -k filter:"
        echo "  ws test knarr tests/test_foo.py            # runs that file"
        echo "  ws test knarr tests/test_foo.py::test_bar  # runs that test"
        echo "  ws test knarr tests/a.py tests/b.py        # runs both files"
        echo "  ws test knarr some_keyword                 # -k some_keyword"
        echo ""
        echo "For the workspace Bats suite, existing path selectors run just"
        echo "those files; a single non-path selector becomes a --filter regex:"
        echo "  ws test yggdrasil tests/ws-smoke/read-only.bats tests/ws-test/pytest-filter.bats"
        echo "  ws test yggdrasil 'orientation'"
        echo ""
        echo "For unittest adapters, a positional selector becomes a -k pattern:"
        echo "  ws test gangplank slack_prompt             # -k slack_prompt"
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

comp="$1"
shift
ws_resolve_target "$comp"
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
        ws_require_active_realm_trust "$active_realm" || exit 1
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
    # Realm and hoard repositories are control/documentation containers, not
    # ordinary declared components. Do not let an unreviewed project marker
    # (Makefile, gradlew, pyproject.toml, or go.mod) create an execution path.
    # Their tests remain available through a trusted active-realm adapter.
    if [[ "${COMPONENT_DIR%/*}" == "$REALMS_DIR" || "${COMPONENT_DIR%/*}" == "$HOARDS_DIR" ]]; then
        echo "ERROR: Refusing an auto-detected test runner for realm or hoard target '$comp'." >&2
        echo "  Define commands.test in an approved realm adapter, then retry 'ws test $comp'." >&2
        exit 1
    fi
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
# Flags (args starting with -) and their values pass through; non-flag
# positional args are collected as test selectors. Known value-expecting
# flags keep the next arg as part of the flag pair.

test_selectors=()
runner_args=()
expect_value=false
bats_user_set_jobs=false
bats_user_set_backend=false
for arg in "$@"; do
    if [[ "$expect_value" == true ]]; then
        runner_args+=("$arg")
        expect_value=false
        continue
    fi
    if [[ "$runner" == "bats" ]]; then
        case "$arg" in
            --jobs=*)
                runner_args+=(--jobs "${arg#*=}")
                bats_user_set_jobs=true
                continue ;;
            --parallel-binary-name=*)
                runner_args+=(--parallel-binary-name "${arg#*=}")
                bats_user_set_backend=true
                continue ;;
        esac
    fi
    if [[ "$arg" == -* ]]; then
        runner_args+=("$arg")
        # Flags that consume the next arg as a value.
        # Boolean flags like --info and --debug are NOT listed.
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
            -j|--jobs)
                if [[ "$runner" == "bats" ]]; then
                    expect_value=true
                    bats_user_set_jobs=true
                fi ;;
            --parallel-binary-name)
                if [[ "$runner" == "bats" ]]; then
                    expect_value=true
                    bats_user_set_backend=true
                fi ;;
        esac
    else
        test_selectors+=("$arg")
    fi
done
test_filter="${test_selectors[0]:-}"

all_selectors_resolve_to_paths() {
    [[ $# -gt 0 ]] || return 1
    local selector path
    for selector in "$@"; do
        path="${selector%%::*}"
        [[ -e "$path" ]] || return 1
    done
    return 0
}

reject_multiple_keyword_selectors() {
    local runner_name="$1"
    echo "ERROR: Multiple positional selectors for $runner_name are not supported in this form." >&2
    echo "  Pass one keyword expression, or use the runner's native selector flag explicitly." >&2
    exit 1
}

_ws_bats_probe_cleanup() {
    local probe_pid="${1:-}" watchdog_pid="${2:-}" output_file="${3:-}"
    if [[ -n "$probe_pid" ]]; then
        kill -KILL -- "-$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    fi
    if [[ -n "$watchdog_pid" ]]; then
        kill -KILL -- "-$watchdog_pid" 2>/dev/null || true
        wait "$watchdog_pid" 2>/dev/null || true
    fi
    if [[ -n "$output_file" ]]; then
        rm -f "$output_file"
    fi
}

_ws_bats_probe_backend() (
    local backend_path="$1"
    local output_file="" probe_pid="" watchdog_pid="" probe_status=1 probe_output=""

    output_file="$(mktemp "${TMPDIR:-/tmp}/ws-bats-probe.XXXXXX" 2>/dev/null)" || return 1
    trap '_ws_bats_probe_cleanup "$probe_pid" "$watchdog_pid" "$output_file"' EXIT
    trap 'exit 1' HUP INT TERM

    # Job control gives both the candidate and watchdog isolated process
    # groups, so timeout cleanup reaches their ordinary descendants too.
    set -m
    "$backend_path" --keep-order --jobs 1 -- : '&&' printf 'verified:%s' '{}' \
        <<< 'ws-bats-probe' >"$output_file" 2>/dev/null &
    probe_pid=$!
    (
        sleep 1
        if kill -TERM -- "-$probe_pid" 2>/dev/null; then
            sleep 1
            kill -KILL -- "-$probe_pid" 2>/dev/null || true
        fi
    ) &
    watchdog_pid=$!
    set +m

    if wait "$probe_pid"; then
        probe_status=0
    else
        probe_status=$?
    fi
    # The leader may accept TERM while an ordinary descendant ignores it.
    # Finish the candidate group before forgetting its ID or canceling the
    # watchdog, so no same-group work survives a rejected probe.
    kill -KILL -- "-$probe_pid" 2>/dev/null || true
    probe_pid=""

    kill -TERM -- "-$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    watchdog_pid=""

    [[ "$probe_status" -eq 0 ]] || return 1
    probe_output="$(<"$output_file")"
    [[ "$probe_output" == "verified:ws-bats-probe" ]]
)

_ws_bats_parallel_backend() {
    local backend_name backend_path
    for backend_name in rush parallel; do
        backend_path="$(type -P "$backend_name" 2>/dev/null)" || continue
        _ws_bats_probe_backend "$backend_path" || continue
        printf '%s\n' "$backend_name"
        return 0
    done
    return 1
}

_ws_bats_lock_helper_available() {
    type -P flock >/dev/null 2>&1 || type -P shlock >/dev/null 2>&1
}

_ws_bats_job_count() {
    local count=""
    if type -P nproc >/dev/null 2>&1; then
        count="$(nproc 2>/dev/null)" || count=""
        if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
            printf '%s\n' "$count"
            return 0
        fi
    fi
    if type -P sysctl >/dev/null 2>&1; then
        count="$(sysctl -n hw.logicalcpu 2>/dev/null)" || count=""
        if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
            printf '%s\n' "$count"
            return 0
        fi
    fi
    printf '4\n'
}

_ws_bats_file_count() {
    local recursive="$1"
    shift
    local count=0 path file
    local extension="${BATS_FILE_EXTENSION:-bats}"
    local -a direct_files=()
    for path in "$@"; do
        if [[ ! -d "$path" ]]; then
            count=$((count + 1))
            continue
        fi
        if [[ "$recursive" == true ]]; then
            while IFS= read -r -d '' file; do
                count=$((count + 1))
            done < <(find -L "$path" -type f -name "*.$extension" -print0 2>/dev/null)
        else
            shopt -s nullglob
            direct_files=("$path"/*."$extension")
            shopt -u nullglob
            count=$((count + ${#direct_files[@]}))
        fi
    done
    printf '%s\n' "$count"
}

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
                # translated for runners with known filter semantics.
                if [[ ${#test_selectors[@]} -gt 0 ]]; then
                    if [[ "$adapter_cmd" == *pytest* ]]; then
                        # A selector that resolves to an on-disk path or a
                        # pytest nodeid (path::node) is passed positionally so
                        # pytest collects just that target. This also lets a
                        # single file run when unrelated modules have
                        # collection errors (e.g. mid-refactor). Anything else
                        # is treated as a keyword expression for -k.
                        if all_selectors_resolve_to_paths "${test_selectors[@]}"; then
                            "${adapter_argv[@]}" "${test_selectors[@]}" "${runner_args[@]}"
                        elif [[ ${#test_selectors[@]} -eq 1 ]]; then
                            "${adapter_argv[@]}" -k "$test_filter" "${runner_args[@]}"
                        else
                            reject_multiple_keyword_selectors "pytest"
                        fi
                        exit 0
                    fi
                    if [[ "${adapter_argv[1]:-}" == "-m" && "${adapter_argv[2]:-}" == "unittest" ]]; then
                        if [[ ${#test_selectors[@]} -gt 1 ]]; then
                            reject_multiple_keyword_selectors "unittest"
                        fi
                        "${adapter_argv[@]}" -k "$test_filter" "${runner_args[@]}"
                        exit 0
                    fi
                    echo "ERROR: Adapter command '${adapter_argv[*]}' is not Gradle, pytest, or unittest." >&2
                    echo "  Test name filters are only supported for Gradle, Go, Python, pytest adapters, and unittest adapters." >&2
                    echo "  Use 'ws exec $comp <runner> <args>' to run '$test_filter' directly." >&2
                    exit 1
                fi
                "${adapter_argv[@]}" "${runner_args[@]}"
                exit 0
            fi
        else
            gradle_argv=(./gradlew test)
        fi
        if [[ ${#test_selectors[@]} -gt 1 ]]; then
            reject_multiple_keyword_selectors "Gradle"
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
        if [[ ${#test_selectors[@]} -gt 1 ]]; then
            reject_multiple_keyword_selectors "go test"
        fi
        if [[ -n "$test_filter" ]]; then
            go test ./... -count=1 -run "$test_filter" "${runner_args[@]}"
        elif [[ ${#runner_args[@]} -gt 0 ]]; then
            go test ./... -count=1 "${runner_args[@]}"
        else
            go test ./... -count=1
        fi
        ;;
    python)
        if [[ ${#test_selectors[@]} -gt 0 ]] && all_selectors_resolve_to_paths "${test_selectors[@]}"; then
            uv run pytest "${test_selectors[@]}" "${runner_args[@]}"
        elif [[ ${#test_selectors[@]} -gt 1 ]]; then
            reject_multiple_keyword_selectors "pytest"
        elif [[ -n "$test_filter" ]]; then
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
        bats_selectors_are_paths=false
        if [[ ${#test_selectors[@]} -gt 0 ]] && all_selectors_resolve_to_paths "${test_selectors[@]}"; then
            bats_selectors_are_paths=true
            bats_files=("${test_selectors[@]}")
        else
            while IFS= read -r f; do
                bats_files+=("$f")
            done < <(LC_ALL=C find "$ROOT_DIR/tests" -path "$ROOT_DIR/tests/vendor" -prune -o -type f -name '*.bats' -print | LC_ALL=C sort)
        fi
        if [[ ${#bats_files[@]} -eq 0 ]]; then
            echo "(no .bats files found under tests/)" >&2
            exit 0
        fi
        bats_argv=("$bats_bin")
        if [[ ${#test_selectors[@]} -gt 1 && "$bats_selectors_are_paths" != true ]]; then
            reject_multiple_keyword_selectors "bats"
        fi
        if [[ ${#test_selectors[@]} -eq 1 && "$bats_selectors_are_paths" != true ]]; then
            bats_argv+=(--filter "$test_filter")
        fi

        _bats_recursive=false
        for _bats_arg in ${runner_args[@]+"${runner_args[@]}"}; do
            case "$_bats_arg" in
                -r|--recursive) _bats_recursive=true ;;
            esac
        done
        _bats_file_count="$(_ws_bats_file_count "$_bats_recursive" "${bats_files[@]}")"

        # A same-name executable is not enough: exercise the small command
        # contract Bats relies on before selecting an optional backend.
        _bats_parallel_bin=""
        _bats_parallel_allowed=false
        if [[ "$bats_user_set_jobs" == true ]] || _ws_bats_lock_helper_available; then
            _bats_parallel_allowed=true
        fi
        if [[ "$_bats_parallel_allowed" == true ]] && \
           [[ "$bats_user_set_backend" != true ]] && \
           [[ "$bats_user_set_jobs" == true || $_bats_file_count -gt 1 ]]; then
            _bats_parallel_bin="$(_ws_bats_parallel_backend)" || _bats_parallel_bin=""
            if [[ -n "$_bats_parallel_bin" ]]; then
                bats_argv+=(--parallel-binary-name "$_bats_parallel_bin")
            fi
        fi

        # Automatic fan-out only applies across multiple files. An explicit
        # job count is preserved for single-file, within-file parallelism.
        if [[ "$bats_user_set_jobs" != true && $_bats_file_count -gt 1 ]] && \
           [[ "$bats_user_set_backend" == true || -n "$_bats_parallel_bin" ]]; then
            _bats_jobs="$(_ws_bats_job_count)"
            bats_argv+=(--jobs "$_bats_jobs")
            if [[ -n "$_bats_parallel_bin" ]]; then
                echo "(running $_bats_file_count test files in parallel: --jobs $_bats_jobs via $_bats_parallel_bin)" >&2
            else
                echo "(running $_bats_file_count test files in parallel: --jobs $_bats_jobs via requested backend)" >&2
            fi
        fi

        bats_argv+=(${runner_args[@]+"${runner_args[@]}"} "${bats_files[@]}")
        "${bats_argv[@]}"
        ;;
esac

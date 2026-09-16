#!/usr/bin/env bats

# The incident: an address filled into a local sample manifest, read later by an
# agent doing unrelated work, and carried into a documentation pass. No secret
# scanner would notice — the value is an ordinary email, harmless where it sat
# and harmful once published.
#
# The design rests on novelty rather than shape, and these tests exist mostly to
# pin that distinction. This repository's tree already holds ~90 email-shaped
# strings, all legitimate; a check that fired on shape would be muted in a week.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    # shellcheck source=../../scripts/ws-pii.sh
    source "$REPO_ROOT/scripts/ws-pii.sh"

    REPO="$BATS_TEST_TMPDIR/repo"
    git init -q "$REPO"
    git -C "$REPO" config user.name "Test User"
    git -C "$REPO" config user.email "test@example.local"
    printf 'maintainer: known.person@realcompany.example.org\n' > "$REPO/known.yaml"
    git -C "$REPO" add known.yaml
    git -C "$REPO" commit -q -m "seed"
}

@test "an address new to the repository is refused" {
    run ws_pii_guard "probe" "contact: jane.doe@realcompany.co.uk" "$REPO"

    [ "$status" -ne 0 ]
    [[ "$output" == *"jane.doe@realcompany.co.uk"* ]]
    [[ "$output" == *"never held"* ]]
}

@test "an address already committed is not flagged" {
    # The load-bearing filter. Without it every commit touching a file that
    # mentions a maintainer would block.
    run ws_pii_guard "probe" "see known.person@realcompany.example.org" "$REPO"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "the working tree does not count as prior art" {
    # The leaked value was sitting in an uncommitted sample file. Treating the
    # working tree as prior art would defeat the check on its own incident.
    printf 'contact: sample.only@realcompany.co.uk\n' > "$REPO/sample.yaml"

    run ws_pii_guard "probe" "contact: sample.only@realcompany.co.uk" "$REPO"

    [ "$status" -ne 0 ]
    [[ "$output" == *"sample.only@realcompany.co.uk"* ]]
}

@test "role addresses are not personal identifiers" {
    run ws_pii_guard "probe" "trailer: noreply@brand-new-vendor.com" "$REPO"

    [ "$status" -eq 0 ]
}

@test "an SSH remote is not an email address" {
    run ws_pii_guard "probe" "clone git@gitlab.never-seen-before.com:group/repo.git" "$REPO"

    [ "$status" -eq 0 ]
}

@test "documentation domains reserved by RFC are ignored" {
    run ws_pii_guard "probe" "alice@example.com bob@foo.invalid carol@thing.test dave@host.example" "$REPO"

    [ "$status" -eq 0 ]
}

@test "the allowlist exempts a value and is read from the repo" {
    printf '# reviewed 2026-09-08\nknown.contact@partner.co.uk\n' > "$REPO/.gdd-pii-allow"

    run ws_pii_guard "probe" "contact: known.contact@partner.co.uk" "$REPO"

    [ "$status" -eq 0 ]
}

@test "allowlist comments and blank lines do not exempt everything" {
    printf '# known.contact@partner.co.uk\n\n' > "$REPO/.gdd-pii-allow"

    run ws_pii_guard "probe" "contact: known.contact@partner.co.uk" "$REPO"

    [ "$status" -ne 0 ]
}

@test "matching ignores case in both directions" {
    printf 'Known.Contact@Partner.CO.UK\n' > "$REPO/.gdd-pii-allow"

    run ws_pii_guard "probe" "contact: KNOWN.CONTACT@partner.co.uk" "$REPO"

    [ "$status" -eq 0 ]
}

@test "several new addresses are all reported, not just the first" {
    run ws_pii_guard "probe" "a@one.co.uk and b@two.co.uk" "$REPO"

    [ "$status" -ne 0 ]
    [[ "$output" == *"a@one.co.uk"* ]]
    [[ "$output" == *"b@two.co.uk"* ]]
}

@test "empty text passes without touching git" {
    run ws_pii_guard "probe" "" "$REPO"

    [ "$status" -eq 0 ]
}

@test "staged added lines exclude context and removals" {
    printf 'maintainer: known.person@realcompany.example.org\nadded: fresh@newdomain.co.uk\n' > "$REPO/known.yaml"
    git -C "$REPO" add known.yaml

    run ws_pii_staged_added_lines "$REPO"

    [ "$status" -eq 0 ]
    [[ "$output" == *"fresh@newdomain.co.uk"* ]]
    [[ "$output" != *"+++"* ]]
}

@test "a diff marker is not part of the address" {
    # Found by running this guard on its own first commit. `+` is legal in a
    # local part, so scanning raw diff lines produced `+a@one.co.uk`, which
    # matches no allowlist entry anyone would think to write.
    printf 'a@one.co.uk\n' > "$REPO/.gdd-pii-allow"

    run ws_pii_guard "probe" "+a@one.co.uk" "$REPO"

    [ "$status" -eq 0 ]
}

@test "a string escape before an address is not part of it" {
    # Same commit, same cause: `\n` in a quoted test string yielded
    # `nknown.contact@partner.co.uk`, because `n` is legal in a local part too.
    printf 'known.contact@partner.co.uk\n' > "$REPO/.gdd-pii-allow"

    run ws_pii_guard "probe" 'printf "\nknown.contact@partner.co.uk"' "$REPO"

    [ "$status" -eq 0 ]
}

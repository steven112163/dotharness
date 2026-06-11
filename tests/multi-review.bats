#!/usr/bin/env bats
# Tests for skills/multi-review/scripts/gather_context.sh (local mode) and skill files.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../skills/multi-review/scripts/gather_context.sh"
    REPO="$(mktemp -d "${BATS_TMPDIR}/mr-repo-XXXXXX")"
    cd "$REPO" || return 1
    git init -q -b main
    git config user.email t@t.t
    git config user.name t
    printf 'int main(){return 0;}\n' >a.cpp
    git add a.cpp && git commit -qm "init"
    git checkout -q -b feat/x
    printf 'int main(){int y; return 0;}\n' >a.cpp
    git add a.cpp && git commit -qm "change"
    REVIEW_DIR="$(mktemp -d "${BATS_TMPDIR}/mr-out-XXXXXX")"
    export REVIEW_DIR
}

teardown() {
    rm -rf "$REPO" "$REVIEW_DIR"
}

@test "local mode writes a non-empty diff" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -s "$REVIEW_DIR/diff.txt" ]
}

@test "local mode splits chunks and maps the changed file" {
    bash "$SCRIPT"
    [ -f "$REVIEW_DIR/chunks.tsv" ]
    grep -q $'a.cpp\t' "$REVIEW_DIR/chunks.tsv"
}

@test "local mode works with a relative REVIEW_DIR" {
    REVIEW_DIR="rel-out"
    export REVIEW_DIR
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -s "$REPO/rel-out/diff.txt" ]
    grep -q $'a.cpp\t' "$REPO/rel-out/chunks.tsv"
}

@test "REFERENCE.md covers the three lenses" {
    ref="${BATS_TEST_DIRNAME}/../skills/multi-review/REFERENCE.md"
    grep -qi 'Correctness & numerics' "$ref"
    grep -qi 'GPU performance' "$ref"
    grep -qi 'Code quality' "$ref"
}

@test "SKILL.md declares required frontmatter" {
    skill="${BATS_TEST_DIRNAME}/../skills/multi-review/SKILL.md"
    grep -q '^name: multi-review$' "$skill"
    grep -q '^argument-hint:' "$skill"
    grep -q '^description:' "$skill"
}

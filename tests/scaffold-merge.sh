#!/usr/bin/env bash
# Exercises create-scaffold-kit.sh's commit-tracked three-way merge: an
# untouched file fast-forwards, a non-overlapping local edit auto-merges with
# upstream, and an overlapping edit is left for manual merge. Uses a throwaway
# synthetic kit repo (not this repo) so no real history is touched.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-scaffold-merge-test.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

FAKE_KIT="$TEST_ROOT/fake-kit"
PROJECT="$TEST_ROOT/project"
mkdir -p "$FAKE_KIT/template/project" "$FAKE_KIT/scripts/lib" "$PROJECT"

cp "$KIT_ROOT/template/create-scaffold-kit.sh" "$FAKE_KIT/template/create-scaffold-kit.sh"
cp "$KIT_ROOT/scripts/lib/scaffold-merge.sh" "$FAKE_KIT/scripts/lib/scaffold-merge.sh"
touch "$FAKE_KIT/template/gitignore.append"

# Well-separated lines so a one-line upstream change and a one-line local
# change on different lines merge cleanly (adjacent single-line hunks are
# deliberately conflict-prone and are exercised separately below).
printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n' >"$FAKE_KIT/template/project/sample.md"

git -C "$FAKE_KIT" init -q -b main
git -C "$FAKE_KIT" -c user.email=t@t -c user.name=t add -A
git -C "$FAKE_KIT" -c user.email=t@t -c user.name=t commit -qm v1
v1="$(git -C "$FAKE_KIT" rev-parse HEAD)"

bash "$FAKE_KIT/template/create-scaffold-kit.sh" "$PROJECT" </dev/null >"$TEST_ROOT/out1"
cmp "$PROJECT/sample.md" "$FAKE_KIT/template/project/sample.md"
[[ "$(cat "$PROJECT/.ai-session-kit-manifest")" == "$v1" ]]
! grep -qF '.ai-session-kit-manifest' "$KIT_ROOT/template/gitignore.append"
echo 'PASS: first scaffold copies the file fresh, records the kit commit, and the manifest is not gitignored'

# v2: upstream changes a line far from the one the "user" is about to touch.
printf 'a\nb\nc\nd\ne\nf\ng\nh-theirs\ni\nj\n' >"$FAKE_KIT/template/project/sample.md"
git -C "$FAKE_KIT" -c user.email=t@t -c user.name=t commit -aqm v2
v2="$(git -C "$FAKE_KIT" rev-parse HEAD)"

bash "$FAKE_KIT/template/create-scaffold-kit.sh" "$PROJECT" </dev/null >"$TEST_ROOT/out2"
cmp "$PROJECT/sample.md" "$FAKE_KIT/template/project/sample.md"
grep -F 'Copied: 1' "$TEST_ROOT/out2" >/dev/null
[[ "$(cat "$PROJECT/.ai-session-kit-manifest")" == "$v2" ]]
echo 'PASS: an untouched file fast-forwards to the new upstream content'

# "User" edits a different line than the next upstream change will touch.
printf 'a\nb\nc\nd\ne-mine\nf\ng\nh-theirs\ni\nj\n' >"$PROJECT/sample.md"

# v3: upstream changes a line far from the user's edit -- should auto-merge.
printf 'a\nb\nc\nd\ne\nf\ng\nh-theirs\ni\nj-theirs\n' >"$FAKE_KIT/template/project/sample.md"
git -C "$FAKE_KIT" -c user.email=t@t -c user.name=t commit -aqm v3
v3="$(git -C "$FAKE_KIT" rev-parse HEAD)"

bash "$FAKE_KIT/template/create-scaffold-kit.sh" "$PROJECT" </dev/null >"$TEST_ROOT/out3"
grep -F 'Auto-merged (upstream + local changes combined; backup kept): 1' "$TEST_ROOT/out3" >/dev/null
grep -F '  - sample.md' "$TEST_ROOT/out3" >/dev/null
diff -q "$PROJECT/sample.md" - <<<'a
b
c
d
e-mine
f
g
h-theirs
i
j-theirs' >/dev/null
[[ -n "$(find "$PROJECT" -maxdepth 1 -name 'sample.md.bak.*' -print -quit)" ]]
[[ "$(cat "$PROJECT/.ai-session-kit-manifest")" == "$v3" ]]
echo 'PASS: a non-overlapping local edit is auto-merged with the upstream change, with a backup kept'

rm -f "$PROJECT"/sample.md.bak.*

# v4: upstream changes the SAME line ("e") the user customized -- must conflict.
printf 'a\nb\nc\nd\ne-upstream\nf\ng\nh-theirs\ni\nj-theirs\n' >"$FAKE_KIT/template/project/sample.md"
git -C "$FAKE_KIT" -c user.email=t@t -c user.name=t commit -aqm v4
v4="$(git -C "$FAKE_KIT" rev-parse HEAD)"

before_merge="$(cat "$PROJECT/sample.md")"
bash "$FAKE_KIT/template/create-scaffold-kit.sh" "$PROJECT" </dev/null >"$TEST_ROOT/out4"
grep -F 'sample.md (local and upstream changes conflict)' "$TEST_ROOT/out4" >/dev/null
[[ "$(cat "$PROJECT/sample.md")" == "$before_merge" ]]
[[ -z "$(find "$PROJECT" -maxdepth 1 -name 'sample.md.bak.*' -print -quit)" ]]
[[ "$(cat "$PROJECT/.ai-session-kit-manifest")" == "$v4" ]]
echo 'PASS: an overlapping local edit conflicts and the file is left untouched, with no backup written'

echo 'PASS: all scaffold-merge scenarios behaved as expected'

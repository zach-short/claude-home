#!/usr/bin/env bash
# Builds a throwaway repository with one worktree or branch for every case the skill sorts, runs
# plan.sh, trial.sh and land.sh against it, and checks each verdict. It makes commits and removes
# worktrees only inside the repository it creates under a new temp directory, with its own git
# config, so no hook, signing key or identity of the real machine takes part.
#
#   bash selftest.sh          run, then delete the temp directory
#   KEEP=yes bash selftest.sh leave the temp directory for a look
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

root=$(physical "$(mktemp -d "${TMPDIR:-/tmp}/land-selftest.XXXXXX")")
sleeper=
cleanup() {
  [ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null || true
  if [ "${KEEP:-no}" = yes ]; then echo "kept $root"; else rm -rf "$root"; fi
}
trap cleanup EXIT

export GIT_CONFIG_GLOBAL=$root/gitconfig GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" user.name selftest
git config --file "$GIT_CONFIG_GLOBAL" user.email selftest@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

passed=0 failed=0
ok() { # description shell-condition
  if eval "$2"; then
    passed=$((passed + 1))
    echo "ok    $1"
  else
    failed=$((failed + 1))
    echo "FAIL  $1"
  fi
}
has() { grep -Fq -- "$(printf "$2")" "$1"; }
sorted_as() { # plan worktree relpath why
  awk -F'\t' -v w="$2" -v rel="$3" -v why="$4" '$1 == "leftover" && $2 == w && $5 == rel && $3 == why { f = 1 } END { exit !f }' "$1"
}

t=1700000000
commit() { # dir message
  t=$((t + 60))
  git -C "$1" add -A
  GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git -C "$1" commit -q -m "$2"
}

r=$root/repo
plan_sh="bash $here/plan.sh"
trial_sh="bash $here/trial.sh"
land_sh="bash $here/land.sh"

# ---- The fixture ----

git init -q "$r"
echo a1 >"$r/a.txt"
echo b1 >"$r/b.txt"
echo c1 >"$r/c.txt"
mkdir "$r/dir"
echo d1 >"$r/dir/d.txt"
echo old >"$r/old.txt"
commit "$r" base
c0=$(git -C "$r" rev-parse HEAD)
git -C "$r" branch feat-absorbed
git -C "$r" branch feat-real
git -C "$r" branch feat-old
git -C "$r" branch feat-locked
git -C "$r" branch feat-live
echo d2 >"$r/dir/d.txt"
commit "$r" d2
c1=$(git -C "$r" rev-parse HEAD)
echo d3 >"$r/dir/d.txt"
echo c2 >"$r/c.txt"
echo n >"$r/new.txt"
rm "$r/old.txt"
commit "$r" "d3, c2, new, old removed"

git -C "$r" checkout -q -b feat-squash
echo e >"$r/e.txt"
commit "$r" "e on the branch"
git -C "$r" checkout -q main
echo e >"$r/e.txt"
commit "$r" "e on main by another route"

for spec in "feat-clean a.txt a2" "feat-second b.txt b2" "feat-conflict a.txt a3"; do
  set -- $spec
  git -C "$r" checkout -q -b "$1"
  echo "$3" >"$r/$2"
  commit "$r" "$1"
  git -C "$r" checkout -q main
done

# A remote seen only through its tracking refs, written directly, so the test never pushes.
git -C "$r" update-ref refs/remotes/origin/main main
git -C "$r" update-ref refs/remotes/origin/feat-old feat-old
git -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

wt() { git -C "$r" worktree add -q "$root/$1" "$2"; }
wt wt-clean feat-clean
wt wt-conflict feat-conflict
wt wt-squash feat-squash
wt wt-absorbed feat-absorbed
echo c2 >"$root/wt-absorbed/c.txt"
echo n >"$root/wt-absorbed/new.txt"
rm "$root/wt-absorbed/old.txt"
echo d2 >"$root/wt-absorbed/dir/d.txt"
wt wt-real feat-real
echo unique >"$root/wt-real/notes.txt"
echo c2 >"$root/wt-real/c.txt"
echo b-draft >"$root/wt-real/b.txt"
echo d-draft >"$root/wt-real/dir/d.txt"
git -C "$r" worktree add -q --detach "$root/wt-detached" "$c1"
wt wt-locked feat-locked
git -C "$r" worktree lock "$root/wt-locked"
wt wt-live feat-live
(cd "$root/wt-live" && exec sleep 600) &
sleeper=$!
disown "$sleeper" 2>/dev/null || true
sleep 1

# ---- 1. Fresh worktrees count as busy, and their branches stay out of the landing ----

$plan_sh --repo "$r" --out "$root/p1" >/dev/null
P=$root/p1/plan.tsv
ok "a worktree changed just now is kept" "has '$P' 'keep\t$root/wt-clean\tit changed'"
ok "its branch is not landed" "! has '$P' 'merge\tfeat-clean\t'"
ok "a branch with no worktree still lands" "has '$P' 'merge\tfeat-second\t'"

# ---- 2. The full survey ----

$plan_sh --repo "$r" --out "$root/p2" --quiet-minutes 0 >"$root/p2.out"
P=$root/p2/plan.tsv
ok "feat-clean lands first" "[ \"\$(awk -F'\t' '\$1 == \"merge\" { print \$2 }' '$P' | head -1)\" = feat-clean ]"
ok "feat-second lands" "has '$P' 'merge\tfeat-second\t'"
ok "feat-conflict is held back by its conflict" "has '$P' 'keep\tfeat-conflict' || has '$P' 'keep\t$root/wt-conflict\tbranch feat-conflict is not landed: conflicts'"
ok "its conflicted path is named" "has '$P' 'conflict\tfeat-conflict\ta.txt'"
ok "a clean worktree is deleted" "has '$P' 'delete-worktree\t$root/wt-clean\tfeat-clean'"
ok "a squash-landed branch's worktree is deleted" "has '$P' 'delete-worktree\t$root/wt-squash\tfeat-squash'"
ok "a clean detached worktree is deleted" "has '$P' 'delete-worktree\t$root/wt-detached\t-'"
ok "an absorbed worktree with only leftovers is deleted" "has '$P' 'delete-worktree\t$root/wt-absorbed\tfeat-absorbed'"
ok "a file equal to the base is a leftover" "sorted_as '$P' '$root/wt-absorbed' c.txt base"
ok "an untracked copy of a base file is a leftover" "sorted_as '$P' '$root/wt-absorbed' new.txt base"
ok "a file deleted in both is a leftover" "sorted_as '$P' '$root/wt-absorbed' old.txt gone"
ok "a past committed version is a leftover" "sorted_as '$P' '$root/wt-absorbed' dir/d.txt past"
ok "a worktree holding new work is kept" "has '$P' 'keep\t$root/wt-real\t3 changed files are'"
ok "the new file is listed" "has '$P' 'real\t$root/wt-real\tnotes.txt'"
ok "a base file among the kept files is not listed as work" "! has '$P' 'real\t$root/wt-real\tc.txt'"
ok "a file the base committed again later gets a draft hint" "grep -q '^hint.*wt-real.the base committed this path after.*dir/d.txt\$' '$P'"
ok "a new file with no later commit gets no hint" "! grep -q '^hint.*notes.txt\$' '$P'"
ok "kept work on a file a landing branch changes is an overlap" "has '$P' 'overlap\tfeat-second\t$root/wt-real\tb.txt'"
ok "the report warns under that branch" "grep -q 'WARNING: a kept worktree holds uncommitted changes' '$root/p2.out'"
ok "a merged remote branch is listed" "has '$P' 'remote\torigin/feat-old\t'"
ok "origin's HEAD symref is not listed as a branch" "! has '$P' 'remote\torigin\t'"
ok "a locked worktree is kept" "has '$P' 'keep\t$root/wt-locked\tit is locked'"
ok "a worktree a process stands in is kept" "has '$P' 'keep\t$root/wt-live\ta process is working in it'"
ok "an absorbed branch with no worktree is deleted" "has '$P' 'delete-branch\tfeat-old\t'"
ok "a landed branch with no worktree is deleted" "has '$P' 'delete-branch\tfeat-second\t'"
ok "the report names the kept work" "grep -q 'notes.txt' '$root/p2.out'"

# ---- 3. A dirty file in the base checkout blocks a landing that changes it ----

cp "$r/a.txt" "$root/a.txt.aside"
echo mine >"$r/a.txt"
$plan_sh --repo "$r" --out "$root/p3" --quiet-minutes 0 >/dev/null
ok "plan.sh lists the blocker" "has '$root/p3/plan.tsv' 'blocker\t$r\ta.txt'"
status=0
$land_sh "$root/p2/plan.tsv" >"$root/land3.out" 2>&1 || status=$?
ok "land.sh refuses the plan while it stands" "[ $status -ne 0 ] && grep -q 'a.txt is dirty' '$root/land3.out'"
cp "$root/a.txt.aside" "$r/a.txt"

# ---- 4. No gate result, no landing ----

status=0
$land_sh "$root/p2/plan.tsv" >"$root/land4.out" 2>&1 || status=$?
ok "an ungated plan is blocked" "[ $status -ne 0 ] && grep -q 'no gate result' '$root/land4.out'"

# ---- 5. The trial holds exactly the planned tree ----

$trial_sh "$root/p2/plan.tsv" >/dev/null
final=$(awk -F'\t' '$1 == "final" { print $2 }' "$root/p2/plan.tsv")
ok "the trial's tree is the final tree" "[ \"\$(git -C '$root/p2/trial' write-tree)\" = '$final' ]"
ok "the trial's files are the landed files" "[ \"\$(cat '$root/p2/trial/a.txt')\" = a2 ] && [ \"\$(cat '$root/p2/trial/b.txt')\" = b2 ]"
$trial_sh --record "$root/p2/plan.tsv" pass "true" >/dev/null
$plan_sh --repo "$r" --out "$root/p2b" --quiet-minutes 0 >/dev/null
ok "a second survey sees the trial as a trial, not as work" "has '$root/p2b/plan.tsv' 'trial\t$root/p2/trial\t-'"

# ---- 6. A leftover that changes after the plan is skipped, not forced ----

echo c9 >"$root/wt-absorbed/c.txt"
$land_sh "$root/p2/plan.tsv" >"$root/land6.out" 2>&1 || true
ok "the changed leftover makes land.sh skip that worktree" "grep -q 'skip worktree $root/wt-absorbed: c.txt changed since the plan' '$root/land6.out'"
echo c2 >"$root/wt-absorbed/c.txt"

# ---- 7. --apply runs only the plan that was read ----

before=$(git -C "$r" rev-parse main)
status=0
$land_sh "$root/p2/plan.tsv" --apply --expect 0000 >/dev/null 2>&1 || status=$?
ok "a wrong --expect changes nothing" "[ $status -ne 0 ] && [ \"\$(git -C '$r' rev-parse main)\" = '$before' ]"

# ---- 8. Apply ----

$land_sh "$root/p2/plan.tsv" >"$root/land8.out"
hash=$(sed -n 's/.*--expect \([0-9a-f]*\)$/\1/p' "$root/land8.out")
$land_sh "$root/p2/plan.tsv" --apply --expect "$hash" >"$root/apply8.out"
ok "main ends on the gated tree" "[ \"\$(git -C '$r' rev-parse 'main^{tree}')\" = '$final' ]"
ok "each landing is a two-parent merge commit" "[ \"\$(git -C '$r' rev-list --merges --count '$before..main')\" = 2 ]"
ok "the messages are git's own" "git -C '$r' log --format=%s '$before..main' | grep -qx \"Merge branch 'feat-second'\""
ok "the main checkout fast-forwarded its files" "[ \"\$(cat '$r/a.txt')\" = a2 ] && [ -z \"\$(git -C '$r' status --porcelain)\" ]"
for w in wt-clean wt-absorbed wt-detached wt-squash p2/trial; do
  ok "removed $w" "[ ! -e '$root/$w' ]"
done
for w in wt-real wt-locked wt-live wt-conflict; do
  ok "kept $w" "[ -d '$root/$w' ]"
done
ok "kept the new work itself" "[ \"\$(cat '$root/wt-real/notes.txt')\" = unique ]"
for b in feat-clean feat-second feat-squash feat-absorbed feat-old; do
  ok "deleted branch $b" "! git -C '$r' show-ref -q --verify refs/heads/$b"
done
for b in feat-conflict feat-real feat-locked feat-live; do
  ok "kept branch $b" "git -C '$r' show-ref -q --verify refs/heads/$b"
done
ok "land.sh prints the remote deletion for the owner" "grep -q 'origin --delete feat-old' '$root/apply8.out'"
ok "the branch tips were saved first" "grep -q 'refs/heads/feat-clean' '$root/repo-branch-tips-$(date +%Y-%m-%d).txt'"

# ---- 9. A plan goes stale when the base moves ----

$plan_sh --repo "$r" --out "$root/p9" --quiet-minutes 0 >/dev/null
echo z >"$r/z.txt"
commit "$r" "main moves on"
status=0
$land_sh "$root/p9/plan.tsv" --allow-ungated >"$root/land9.out" 2>&1 || status=$?
ok "a stale plan is blocked" "[ $status -ne 0 ] && grep -q 'run plan.sh again' '$root/land9.out'"

# ---- 10. A conflict lands with a written resolution ----

mkdir -p "$root/res/feat-conflict"
printf 'a2 and a3\n' >"$root/res/feat-conflict/a.txt"
$plan_sh --repo "$r" --out "$root/p10" --quiet-minutes 0 --resolutions "$root/res" >/dev/null
P=$root/p10/plan.tsv
ok "the resolved branch now lands" "has '$P' 'merge\tfeat-conflict\t'"
$land_sh "$P" --allow-ungated >"$root/land10.out"
hash=$(sed -n 's/.*--expect \([0-9a-f]*\)$/\1/p' "$root/land10.out")
$land_sh "$P" --apply --expect "$hash" --allow-ungated >/dev/null
ok "main holds the resolution" "[ \"\$(cat '$r/a.txt')\" = 'a2 and a3' ]"
ok "the resolved branch's worktree is gone" "[ ! -e '$root/wt-conflict' ]"
ok "the resolved branch is gone" "! git -C '$r' show-ref -q --verify refs/heads/feat-conflict"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

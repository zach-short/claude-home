#!/usr/bin/env bash
# Builds a plan's landed tree in a detached worktree, so the repository's gates run on exactly the
# tree land.sh will commit. Merging with plumbing is what makes that exact: land.sh commits these
# very tree objects, so there is no second merge whose result could differ from the one gated.
#
#   trial.sh <plan.tsv> [<dir>]                       build or refresh the trial (default dir:
#                                                     a `trial` folder beside the plan)
#   trial.sh --record <plan.tsv> pass|fail|skip <cmd> write down one gate's result
#
# Building the trial drops every gate result already in the plan, because they were taken on a
# tree that may no longer be the one in the trial. The trial keeps its node_modules and build
# caches across rebuilds, so a second run of the gates is fast.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

plan_field() { awk -F'\t' -v k="$2" -v n="$3" '$1 == k { print $n; exit }' "$1"; }

if [ "${1:-}" = --record ]; then
  [ $# -ge 4 ] || die "usage: trial.sh --record <plan.tsv> pass|fail|skip <command>"
  plan=$2 result=$3
  shift 3
  case "$result" in pass | fail | skip) ;; *) die "a gate result is pass, fail or skip" ;; esac
  cmd="$*"
  case "$cmd" in *"$TAB"* | *$'\n'*) die "the command text may not hold a tab or a newline" ;; esac
  [ -n "$(plan_field "$plan" trial 3)" ] || die "the plan has no trial yet; run trial.sh <plan.tsv> first"
  printf 'gate\t%s\t%s\n' "$result" "$cmd" >>"$plan"
  echo "recorded: $result  $cmd"
  exit 0
fi

[ $# -ge 1 ] || die "usage: trial.sh <plan.tsv> [<dir>]"
plan=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
[ -f "$plan" ] || die "no plan at $plan"
[ "$(plan_field "$plan" version 2)" = 1 ] || die "$plan is not a version 1 plan"
repo=$(plan_field "$plan" repo 2)
base_sha=$(plan_field "$plan" base 3)
base_tree=$(plan_field "$plan" base 4)
final=$(plan_field "$plan" final 2)
is_oid "$final" || die "the plan has no final tree"

if [ "$final" = "$base_tree" ]; then
  echo "Nothing to land: the final tree is the base's own. No trial is needed."
  exit 0
fi

dir=${2:-$(dirname "$plan")/trial}
if [ -e "$dir" ]; then
  dir=$(physical "$dir")
  marker=$(trial_marker "$dir" || true)
  [ -n "$marker" ] && [ -f "$marker" ] || die "$dir exists and is not a trial worktree; pick another directory"
  echo "Reusing the trial at $dir."
else
  git -C "$repo" worktree add --quiet --detach "$dir" "$base_sha"
  dir=$(physical "$dir")
  marker=$(trial_marker "$dir") || die "git made $dir but it is not a worktree"
  : >"$marker"
  echo "Made the trial at $dir."
fi

git -C "$dir" read-tree -u --reset "$final"
got=$(git -C "$dir" write-tree)
[ "$got" = "$final" ] || die "the trial's index is $got, not the plan's tree $final"

tmp=$(mktemp)
awk -F'\t' -v d="$dir" '$1 == "gate" { next } $1 == "trial" && $2 == d { next } { print }' "$plan" >"$tmp"
printf 'trial\t%s\t%s\n' "$dir" "$final" >>"$tmp"
mv "$tmp" "$plan"

cat <<EOF
Its working tree is the landed tree $(git -C "$repo" rev-parse --short "$final"). HEAD stays at the
old base, so \`git status\` there shows the whole landing as staged; gates that diff against HEAD
see the landing as the change, which is the point.

Next: set it up the way the repository's own docs set up a fresh worktree, run every gate they
list as required, and record each result:

  bash $here/trial.sh --record $plan pass "<gate command>"
EOF

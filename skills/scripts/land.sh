#!/usr/bin/env bash
# Applies a plan written by plan.sh: merges its branches into the base, then removes the worktrees
# and branches it found holding nothing new. The owner runs this, not an agent, because it writes
# commits.
#
#   land.sh <plan.tsv>                                 dry run: check everything, change nothing
#   land.sh <plan.tsv> --apply --expect <sha256>       do it; the hash is the one the dry run
#                                                      printed, so only the plan that was read
#                                                      is the plan that runs
#   --allow-ungated                                    land without recorded gate results
#
# How the landing stays exact: each merge commit is made with `git commit-tree` from the tree the
# plan predicted and the trial gated, so the base ends on that very tree. The commits are built
# away from every checkout, and the checkout holding the base only fast-forwards to the last one.
# A fast-forward cannot take a parallel session's staged files into a commit (the shared-index
# hazard of a plain `git merge` followed by `git commit`), and git refuses it outright when a
# dirty file there would be overwritten, so a refusal leaves the base where it was.
#
# Every removal is checked again at the moment it runs, and one that no longer matches the plan
# is skipped, never forced: a worktree whose HEAD moved, whose changed files differ from the
# ones the plan sorted, or that a process is standing in.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

plan= apply=no expect= ungated=no
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=yes; shift ;;
    --expect) [ $# -ge 2 ] || die "--expect needs the hash"; expect=$2; shift 2 ;;
    --allow-ungated) ungated=yes; shift ;;
    -h | --help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown argument: $1" ;;
    *) [ -z "$plan" ] || die "one plan at a time"; plan=$1; shift ;;
  esac
done
[ -n "$plan" ] || die "usage: land.sh <plan.tsv> [--apply --expect <sha256>] [--allow-ungated]"
[ -f "$plan" ] || die "no plan at $plan"
plan=$(cd "$(dirname "$plan")" && pwd -P)/$(basename "$plan")
hash=$(shasum -a 256 "$plan" | cut -d' ' -f1)

plan_field() { awk -F'\t' -v k="$1" -v n="$2" '$1 == k { print $n; exit }' "$plan"; }
records() { awk -F'\t' -v k="$1" '$1 == k' "$plan"; }

[ "$(plan_field version 2)" = 1 ] || die "$plan is not a version 1 plan"
repo=$(plan_field repo 2)
base=$(plan_field base 2)
base_sha=$(plan_field base 3)
base_tree=$(plan_field base 4)
final=$(plan_field final 2)
[ -d "$repo" ] || die "the plan's repository is gone: $repo"
is_oid "$base_sha" && is_oid "$final" || die "the plan is incomplete"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
lsof_snapshot >"$tmp/lsof"

problems=0
say() { printf '%s\n' "$*"; }
block() {
  problems=$((problems + 1))
  say "  BLOCKED: $*"
}
short() { git -C "$repo" rev-parse --short "$1" 2>/dev/null || printf '%.9s' "$1"; }

# Why a planned worktree removal must be skipped now, or nothing when it may go ahead. <into> is
# the commit its HEAD must be absorbed by, or `-` in a dry run, where plan.sh's judgement stands.
check_worktree() { # wt branch head into
  local wt=$1 b=$2 head=$3 into=$4 row wt_p live cur want rel blob
  row=$(worktree_rows "$repo" | awk -F'\t' -v w="$wt" '$1 == w')
  if [ -z "$row" ]; then echo "it is no longer a worktree"; return 0; fi
  if [ "$(printf '%s' "$row" | cut -f2)" != "$head" ]; then echo "its HEAD moved since the plan"; return 0; fi
  if [ "$(printf '%s' "$row" | cut -f3)" != "$b" ]; then echo "it has another branch checked out now"; return 0; fi
  case "$(printf '%s' "$row" | cut -f4)" in *locked*) echo "it is locked"; return 0 ;; esac
  wt_p=$(physical "$wt")
  case "$(pwd -P)/" in "$wt_p"/*)
    echo "this shell is standing in it"
    return 0
    ;;
  esac
  live=$(live_in "$tmp/lsof" "$wt_p" | head -1)
  if [ -n "$live" ]; then echo "a process is working in it: $live"; return 0; fi
  cur=$(dirty_paths "$wt") || { echo "git could not list its changes"; return 0; }
  want=$(awk -F'\t' -v w="$wt" '$1 == "leftover" && $2 == w { print $5 }' "$plan" | LC_ALL=C sort -u)
  if [ "$cur" != "$want" ]; then echo "its changed files are not the ones the plan sorted"; return 0; fi
  while IFS=$TAB read -r rel blob; do
    if [ "$(work_blob "$wt" "$rel")" != "$blob" ]; then echo "$rel changed since the plan"; return 0; fi
  done < <(awk -F'\t' -v w="$wt" '$1 == "leftover" && $2 == w { print $5 "\t" $4 }' "$plan")
  if [ "$into" != - ] && ! is_absorbed "$repo" "$head" "$into"; then echo "the base does not hold its HEAD"; fi
  return 0
}

check_branch() { # branch tip into
  local now where
  now=$(git -C "$repo" rev-parse -q --verify "refs/heads/$1" 2>/dev/null) || { echo "it no longer exists"; return 0; }
  if [ "$now" != "$2" ]; then echo "it moved since the plan"; return 0; fi
  where=$(worktree_of_branch "$repo" "$1")
  if [ -n "$where" ]; then echo "it is checked out in $where"; return 0; fi
  if [ "$3" != - ] && ! is_absorbed "$repo" "$2" "$3"; then echo "the base does not hold it"; fi
  return 0
}

check_trial() { # dir
  local marker
  worktree_rows "$repo" | awk -F'\t' -v w="$1" '$1 == w { found = 1 } END { exit !found }' || { echo "it is no longer a worktree"; return 0; }
  marker=$(trial_marker "$1" || true)
  [ -n "$marker" ] && [ -f "$marker" ] || echo "it has no trial marker"
  return 0
}

# ---- 1. The landing ----

say "Plan $plan"
say "Repository $repo, base $base"
say ""
say "Landing"
now_base=$(git -C "$repo" rev-parse -q --verify "refs/heads/$base" || true)
[ "$now_base" = "$base_sha" ] || block "$base is at $(short "$now_base"), not $(short "$base_sha") as planned; run plan.sh again"

records merge >"$tmp/merges"
cur=$base_tree
merged=()
n=0
while IFS=$TAB read -r _ b tip mb tree res; do
  n=$((n + 1))
  now_tip=$(git -C "$repo" rev-parse -q --verify "refs/heads/$b" || true)
  [ "$now_tip" = "$tip" ] || block "$b is at $(short "$now_tip"), not $(short "$tip") as planned"
  if step=$(merge_step "$repo" "$cur" "$tip" "$res" "$base_sha" ${merged[@]+"${merged[@]}"}); then
    [ "${step#*"$TAB"}" = "$mb" ] || block "$b now has a different merge base"
    [ "${step%%"$TAB"*}" = "$tree" ] || block "merging $b now gives $(short "${step%%"$TAB"*}"), not the planned $(short "$tree")"
  else
    block "$b no longer merges as planned: ${step%%$'\n'*}"
  fi
  extra=
  [ "$res" = - ] || extra=" with the resolution in $res"
  say "  merge $b at $(short "$tip")$extra"
  cur=$tree
  merged+=("$tip")
done <"$tmp/merges"
[ "$cur" = "$final" ] || block "the plan's merges end at $(short "$cur"), not at its final tree $(short "$final")"
[ "$n" -gt 0 ] || say "  nothing to merge"

base_wt=$(worktree_of_branch "$repo" "$base")
if [ "$n" -gt 0 ]; then
  failed=$(records gate | awk -F'\t' '$2 == "fail" { print $3 }')
  trial_ok=$(records trial | awk -F'\t' -v t="$final" '$3 == t { print $2; exit }')
  gates=$(records gate | wc -l | tr -d ' ')
  if [ -n "$failed" ]; then
    while IFS= read -r g; do block "a gate failed on the trial: $g"; done <<<"$failed"
  elif [ -z "$trial_ok" ] || [ "$gates" -eq 0 ]; then
    if [ "$ungated" = yes ]; then
      say "  NOT GATED: --allow-ungated lands this tree with no recorded gate result"
    else
      block "no gate result is recorded for the tree $(short "$final"); run trial.sh and the gates, or pass --allow-ungated"
    fi
  else
    say "  gates passed on the trial at $trial_ok:"
    records gate | while IFS=$TAB read -r _ result cmd; do say "    $result  $cmd"; done
  fi
  if [ -n "$base_wt" ]; then
    while IFS= read -r rel; do
      [ -z "$rel" ] || block "$rel is dirty in $base_wt and the landing changes it; its owner commits it first"
    done < <(blocking_paths "$repo" "$base_tree" "$final" "$base_wt")
    say "  then $base_wt fast-forwards $base to the last merge"
  else
    say "  then $base, which no worktree has checked out, moves with update-ref"
  fi
fi

# ---- 2. The removals, as they stand right now ----

say ""
say "Removals"
records delete-worktree >"$tmp/worktrees"
records delete-branch >"$tmp/branches"
records trial >"$tmp/trials"
while IFS=$TAB read -r _ wt b head; do
  why=$(check_worktree "$wt" "$b" "$head" -)
  if [ -n "$why" ]; then
    say "  skip worktree $wt: $why"
  elif [ "$b" = - ]; then
    say "  remove worktree $wt (detached)"
  else
    say "  remove worktree $wt and branch $b"
  fi
done <"$tmp/worktrees"
while IFS=$TAB read -r _ b tip; do
  why=$(check_branch "$b" "$tip" -)
  if [ -n "$why" ]; then say "  skip branch $b: $why"; else say "  delete branch $b"; fi
done <"$tmp/branches"
while IFS=$TAB read -r _ dir _; do
  why=$(check_trial "$dir")
  if [ -n "$why" ]; then say "  skip trial $dir: $why"; else say "  remove trial $dir"; fi
done <"$tmp/trials"
records keep | while IFS=$TAB read -r _ what why; do say "  keep $what: $why"; done

say ""
if [ "$apply" = no ]; then
  if [ "$problems" -gt 0 ]; then
    say "Dry run: $problems problems block this plan. Nothing changed."
    exit 1
  fi
  say "Dry run. Nothing changed. To apply exactly this plan:"
  say ""
  say "  bash $here/land.sh $plan --apply --expect $hash"
  exit 0
fi

[ "$expect" = "$hash" ] || die "the plan's hash is $hash, not the --expect value; run the dry run again and read it"
[ "$problems" -eq 0 ] || die "$problems problems block this plan; nothing changed"

# ---- 3. Apply ----

backup="$(dirname "$repo")/$(basename "$repo")-branch-tips-$(date +%Y-%m-%d).txt"
{
  printf '# %s, before land-worktrees applied %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$plan"
  git -C "$repo" for-each-ref --format='%(objectname) %(refname)' refs/heads
  worktree_rows "$repo" | awk -F'\t' '{ print $2 " worktree " $1 }'
} >>"$backup"
say "Saved every branch tip and worktree HEAD to $backup"

if [ "$n" -gt 0 ]; then
  prev=$base_sha
  while IFS=$TAB read -r _ b tip mb tree res; do
    prev=$(git -C "$repo" commit-tree "$tree" -p "$prev" -p "$tip" -m "$(merge_message "$b" "$base")") || prev=
    is_oid "$prev" || die "commit-tree failed for $b; $base did not move"
    say "  committed the merge of $b as $(short "$prev")"
  done <"$tmp/merges"
  if [ -n "$base_wt" ]; then
    git -C "$base_wt" merge --ff-only --no-autostash --quiet "$prev" ||
      die "the fast-forward in $base_wt was refused, so $base did not move. The merges exist as $prev."
  else
    git -C "$repo" update-ref -m "land-worktrees: $(basename "$plan")" "refs/heads/$base" "$prev" "$base_sha" ||
      die "update-ref was refused, so $base did not move. The merges exist as $prev."
  fi
  [ "$(git -C "$repo" rev-parse "refs/heads/$base^{tree}")" = "$final" ] ||
    die "$base moved but its tree is not the planned $final. Stop and look before anything else runs."
  say "Landed $n branches. $base is at $(short "$prev"), on the gated tree $(short "$final")."
fi
new_base=$(git -C "$repo" rev-parse "refs/heads/$base")

# The branch deletions use -D, after this script's own check that the base holds the tip. `git
# branch -d` would test only ancestry against whatever the main checkout has checked out, which
# misses a squash-landed branch and wrongly passes nothing it should refuse.
removed=0 deleted=0 skipped=0
while IFS=$TAB read -r _ wt b head; do
  why=$(check_worktree "$wt" "$b" "$head" "$new_base")
  if [ -n "$why" ]; then
    say "  skipped worktree $wt: $why"
    skipped=$((skipped + 1))
    continue
  fi
  force=
  [ -z "$(dirty_paths "$wt")" ] || force=--force
  if ! git -C "$repo" worktree remove $force "$wt"; then
    say "  skipped worktree $wt: git refused to remove it"
    skipped=$((skipped + 1))
    continue
  fi
  removed=$((removed + 1))
  say "  removed worktree $wt"
  if [ "$b" != - ]; then
    why=$(check_branch "$b" "$head" "$new_base")
    if [ -n "$why" ]; then
      say "  kept branch $b: $why"
    elif git -C "$repo" branch -D --quiet "$b"; then
      deleted=$((deleted + 1))
      say "  deleted branch $b (was $(short "$head"))"
    fi
  fi
done <"$tmp/worktrees"
while IFS=$TAB read -r _ b tip; do
  why=$(check_branch "$b" "$tip" "$new_base")
  if [ -n "$why" ]; then
    say "  skipped branch $b: $why"
    skipped=$((skipped + 1))
  elif git -C "$repo" branch -D --quiet "$b"; then
    deleted=$((deleted + 1))
    say "  deleted branch $b (was $(short "$tip"))"
  fi
done <"$tmp/branches"
while IFS=$TAB read -r _ dir _; do
  why=$(check_trial "$dir")
  if [ -z "$why" ] && git -C "$repo" worktree remove --force "$dir"; then
    say "  removed trial $dir"
  else
    say "  skipped trial $dir: ${why:-git refused to remove it}"
  fi
done <"$tmp/trials"
git -C "$repo" worktree prune

say ""
say "Done: $removed worktrees removed, $deleted branches deleted, $skipped skipped."
if [ -n "$(records remote)" ]; then
  say ""
  say "These remote branches are already in $base. Deleting one is a push, so it is yours to run:"
  records remote | while IFS=$TAB read -r _ ref _; do
    say "  git -C $repo push ${ref%%/*} --delete ${ref#*/}"
  done
fi
upstream=$(git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$base" 2>/dev/null || true)
if [ -n "$upstream" ]; then
  say "$base is $(git -C "$repo" rev-list --count "$upstream..$new_base") commits ahead of origin/$base. Pushing is yours."
fi

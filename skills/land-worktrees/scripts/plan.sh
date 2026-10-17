#!/usr/bin/env bash
# Surveys every worktree and local branch of a repository and writes a plan: which branches merge
# into the base and the exact tree each merge produces, which worktrees and branches hold nothing
# the base will not hold afterwards, and which stay and why.
#
# It changes nothing anyone can see. It writes unreachable git objects (the predicted trees and
# any resolution blobs) and the two files in --out, and it never moves a ref, never reads or
# locks a checkout's index, and never touches a working tree.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

usage() {
  cat <<'USAGE'
usage: plan.sh --out <dir> [--repo <dir>] [--base <branch>] [--skip <branch>]...
               [--order <b1,b2,...>] [--resolutions <dir>] [--quiet-minutes <n>]

  --out            where plan.tsv and report.txt go (required)
  --repo           any checkout of the repository (default: the current directory)
  --base           the branch to land on (default: origin's HEAD, else main, else master)
  --skip           leave this branch out of the landing; repeat for more
  --order          merge these branches first, in this order; the rest follow, oldest tip first
  --resolutions    a directory holding <branch>/<path> files laid over that branch's merge,
                   with `/` in a branch name written as `__`, and an optional <branch>/.delete
                   listing paths to remove
  --quiet-minutes  treat a worktree whose files or HEAD changed this recently as busy (default 60)
USAGE
}

need() { [ "$2" -ge 2 ] || die "$1 needs a value"; }

repo=. base= out= quiet=60 resolutions= order=
skips=
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) need "$1" $#; repo=$2; shift 2 ;;
    --base) need "$1" $#; base=$2; shift 2 ;;
    --out) need "$1" $#; out=$2; shift 2 ;;
    --skip) need "$1" $#; skips="$skips$2"$'\n'; shift 2 ;;
    --order) need "$1" $#; order=$2; shift 2 ;;
    --resolutions) need "$1" $#; resolutions=$(physical "$2"); shift 2 ;;
    --quiet-minutes) need "$1" $#; quiet=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done
[ -n "$out" ] || { usage >&2; die "--out is required"; }
case "$quiet" in '' | *[!0-9]*) die "--quiet-minutes takes a whole number" ;; esac
[ -z "$resolutions" ] || [ -d "$resolutions" ] || die "no such directory: $resolutions"

top=$(git -C "$repo" rev-parse --show-toplevel) || die "not a git repository: $repo"
repo=$(primary_of "$top")
[ -d "$repo" ] || die "cannot find the main checkout of $top"

if [ -z "$base" ]; then
  base=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
  base=${base#origin/}
  if [ -z "$base" ]; then
    if git -C "$repo" show-ref -q --verify refs/heads/main; then base=main; else base=master; fi
  fi
fi
git -C "$repo" show-ref -q --verify "refs/heads/$base" || die "no local branch named $base"

mkdir -p "$out"
out=$(physical "$out")
plan=$out/plan.tsv
report=$out/report.txt
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

base_sha=$(git -C "$repo" rev-parse "refs/heads/$base")
base_tree=$(git -C "$repo" rev-parse "$base_sha^{tree}")
now=$(date +%s)
quiet_s=$((quiet * 60))
lsof_snapshot >"$tmp/lsof"
worktree_rows "$repo" >"$tmp/worktrees"
primary=$(head -1 "$tmp/worktrees" | cut -f1)
primary_branch=$(head -1 "$tmp/worktrees" | cut -f3)
base_wt=$(awk -F'\t' -v b="$base" '$3 == b { print $1; exit }' "$tmp/worktrees")

: >"$tmp/landed" # branch names whose work the base holds once the plan lands
: >"$tmp/kept"   # branch<TAB>reason
: >"$tmp/busy"   # worktree<TAB>reason
: >"$tmp/body"   # plan records after the header

record() { (IFS=$TAB; printf '%s\n' "$*") >>"$tmp/body"; }
keep_branch() { printf '%s\t%s\n' "$1" "$2" >>"$tmp/kept"; }
is_landed() { grep -Fxq -- "$1" "$tmp/landed"; }
is_kept() { awk -F'\t' -v b="$1" '$1 == b { found = 1 } END { exit !found }' "$tmp/kept"; }
kept_reason() { awk -F'\t' -v b="$1" '$1 == b { print $2; exit }' "$tmp/kept"; }
busy_reason() { awk -F'\t' -v w="$1" '$1 == w { print $2; exit }' "$tmp/busy"; }
checked_out() { awk -F'\t' -v b="$1" '$3 == b { found = 1 } END { exit !found }' "$tmp/worktrees"; }

# ---- Busy worktrees: locked, a process inside, or changed within --quiet-minutes ----
#
# A busy worktree stays, and so does its branch's work: a session that is still running may have
# committed only part of what it means to land.

sed -n '2,$p' "$tmp/worktrees" | while IFS=$TAB read -r wt head b flags; do
  case "$flags" in *bare* | *prunable*) continue ;; esac
  marker=$(trial_marker "$wt" || true)
  if [ -n "$marker" ] && [ -f "$marker" ]; then continue; fi
  reason=
  case "$flags" in *locked*) reason="it is locked (git worktree unlock releases it)" ;; esac
  if [ -z "$reason" ]; then
    live=$(live_in "$tmp/lsof" "$(physical "$wt")" | head -3 | tr '\n' ';' | sed 's/;$//; s/;/; /g')
    [ -z "$live" ] || reason="a process is working in it: $live"
  fi
  if [ -z "$reason" ]; then
    newest=$(head_moved_at "$wt")
    [ -n "$newest" ] || newest=0
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      if [ -e "$wt/$rel" ] || [ -L "$wt/$rel" ]; then
        t=$(mtime "$wt/$rel" 2>/dev/null || echo 0)
        [ "$t" -le "$newest" ] || newest=$t
      fi
    done < <(dirty_paths "$wt" || true)
    age=$((now - newest))
    [ "$age" -ge "$quiet_s" ] || reason="it changed $((age / 60)) minutes ago, so a session may still be in it"
  fi
  [ -n "$reason" ] || continue
  printf '%s\t%s\n' "$wt" "$reason" >>"$tmp/busy"
  [ "$b" = - ] || keep_branch "$b" "its worktree is busy: $reason"
done

# ---- Branches: already in the base, to merge, or held back ----

: >"$tmp/candidates"
git -C "$repo" for-each-ref --format='%(refname:short)%09%(objectname)%09%(committerdate:unix)' refs/heads >"$tmp/branches"
while IFS=$TAB read -r b tip when; do
  [ "$b" != "$base" ] || continue
  is_kept "$b" && continue
  case "$b" in *"$TAB"*) keep_branch "$b" "its name holds a tab"; continue ;; esac
  if printf '%s' "$skips" | grep -Fxq -- "$b"; then
    keep_branch "$b" "left out with --skip"
  elif is_absorbed "$repo" "$tip" "$base_sha"; then
    echo "$b" >>"$tmp/landed"
  elif [ "$b" = "$primary_branch" ]; then
    keep_branch "$b" "it is checked out in the main checkout"
  else
    printf '%s\t%s\t%s\n' "$when" "$b" "$tip" >>"$tmp/candidates"
  fi
done <"$tmp/branches"

: >"$tmp/ordered"
if [ -n "$order" ]; then
  printf '%s\n' "$order" | tr ',' '\n' | sed '/^$/d' | while IFS= read -r b; do
    awk -F'\t' -v b="$b" '$2 == b { print $2 "\t" $3; found = 1 } END { exit !found }' "$tmp/candidates" >>"$tmp/ordered" ||
      die "--order names $b, which is not a branch with work to land"
  done
fi
LC_ALL=C sort -n "$tmp/candidates" | cut -f2,3 | while IFS=$TAB read -r b tip; do
  awk -F'\t' -v b="$b" '$1 == b { found = 1 } END { exit !found }' "$tmp/ordered" || printf '%s\t%s\n' "$b" "$tip"
done >>"$tmp/ordered"

cur=$base_tree
merged=()
while IFS=$TAB read -r b tip; do
  [ -n "$b" ] || continue
  res=-
  if [ -n "$resolutions" ] && [ -d "$resolutions/$(res_name "$b")" ]; then res=$resolutions/$(res_name "$b"); fi
  if step=$(merge_step "$repo" "$cur" "$tip" "$res" "$base_sha" ${merged[@]+"${merged[@]}"}); then
    tree=${step%%"$TAB"*}
    mb=${step#*"$TAB"}
    record merge "$b" "$tip" "$mb" "$tree" "$res"
    cur=$tree
    merged+=("$tip")
    echo "$b" >>"$tmp/landed"
  else
    why=${step%%$'\n'*}
    paths=$(printf '%s\n' "$step" | sed -n '2,$p' | sed '/^$/d')
    if [ -n "$paths" ]; then
      keep_branch "$b" "$why: $(printf '%s' "$paths" | tr '\n' ' ' | sed 's/ $//')"
      while IFS= read -r p; do record conflict "$b" "$p"; done <<<"$paths"
    else
      keep_branch "$b" "$why"
    fi
  fi
done <"$tmp/ordered"
final=$cur
history=("$base_sha" ${merged[@]+"${merged[@]}"})

# ---- Worktrees: delete what holds nothing new, keep the rest with a reason ----

sed -n '2,$p' "$tmp/worktrees" | while IFS=$TAB read -r wt head b flags; do
  case "$flags" in *bare*) continue ;; esac
  case "$flags" in *prunable*) record note "$wt" "its directory is gone; git worktree prune clears the entry"; continue ;; esac
  marker=$(trial_marker "$wt" || true)
  if [ -n "$marker" ] && [ -f "$marker" ]; then
    record trial "$wt" -
    continue
  fi
  if [ "$b" = "$base" ]; then record keep "$wt" "it has $base checked out"; continue; fi
  busy=$(busy_reason "$wt")
  if [ -n "$busy" ]; then record keep "$wt" "$busy"; continue; fi
  if [ "$b" != - ]; then
    if ! is_landed "$b"; then record keep "$wt" "branch $b is not landed: $(kept_reason "$b")"; continue; fi
  elif ! is_absorbed "$repo" "$head" "$base_sha"; then
    record keep "$wt" "its detached HEAD has commits the base does not hold"
    continue
  fi

  dirty_paths "$wt" >"$tmp/dirty" || { record keep "$wt" "git could not list its changes"; continue; }
  if grep -q "$TAB" "$tmp/dirty"; then record keep "$wt" "a changed path holds a tab"; continue; fi
  : >"$tmp/sorted"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\t%s\n' "$(classify_path "$repo" "$wt" "$final" "$rel" "${history[@]}")" "$rel" >>"$tmp/sorted"
  done <"$tmp/dirty"

  fresh=$(awk -F'\t' '$1 == "new"' "$tmp/sorted" | wc -l | tr -d ' ')
  if [ "$fresh" -gt 0 ]; then
    record keep "$wt" "$(count "$fresh" "changed file is" "changed files are") work that exists nowhere else"
    awk -F'\t' '$1 == "new" { print $3 }' "$tmp/sorted" | while IFS= read -r rel; do record real "$wt" "$rel"; done
  else
    record delete-worktree "$wt" "$b" "$head"
    while IFS=$TAB read -r why blob rel; do record leftover "$wt" "$why" "$blob" "$rel"; done <"$tmp/sorted"
  fi
done

# ---- Hints on each kept file, and overlaps with what lands ----
#
# A kept file stays whatever these say. They make the owner's call quick. A file the base
# committed again after the worktree's HEAD is usually a draft that the later commit replaced. A
# file that a landing branch also changes is usually that branch's unfinished follow-up (an
# audit's fixes that nobody committed), which should land with the branch or not at all.

awk -F'\t' '$1 == "merge" { print $2 "\t" $3 "\t" $4 }' "$tmp/body" | while IFS=$TAB read -r b tip mb; do
  git -C "$repo" diff --name-only --no-renames -z "$mb" "$tip" | tr '\0' '\n' | awk -v b="$b" 'NF { print b "\t" $0 }'
done >"$tmp/changed-by"
awk -F'\t' '$1 == "real" { print $2 "\t" $3 }' "$tmp/body" >"$tmp/reals"
while IFS=$TAB read -r wt rel; do
  head=$(awk -F'\t' -v w="$wt" '$1 == w { print $2; exit }' "$tmp/worktrees")
  since=$(git -C "$repo" log -1 --format='%h %s' "$head..$base_sha" -- "$rel" 2>/dev/null | tr '\t' ' ' || true)
  [ -z "$since" ] || record hint "$wt" "the base committed this path after this worktree's HEAD, in $since" "$rel"
  awk -F'\t' -v rel="$rel" '$2 == rel { print $1 }' "$tmp/changed-by" | while IFS= read -r b; do
    record overlap "$b" "$wt" "$rel"
  done
done <"$tmp/reals"

# A branch that is checked out goes with its worktree, so only the rest are listed here.
while IFS=$TAB read -r b tip when; do
  [ "$b" != "$base" ] || continue
  checked_out "$b" && continue
  if is_landed "$b"; then
    record delete-branch "$b" "$tip"
  else
    record keep "$b" "branch is not landed: $(kept_reason "$b")"
  fi
done <"$tmp/branches"

if [ -n "$base_wt" ]; then
  blocking_paths "$repo" "$base_tree" "$final" "$base_wt" | while IFS= read -r rel; do record blocker "$base_wt" "$rel"; done
fi

# The full refname, because the short name of refs/remotes/origin/HEAD is plain `origin`.
git -C "$repo" for-each-ref --format='%(refname)%09%(objectname)%09%(symref)' refs/remotes | while IFS=$TAB read -r ref tip sym; do
  [ -z "$sym" ] || continue
  ref=${ref#refs/remotes/}
  case "$ref" in */HEAD | */"$base") continue ;; esac
  landed=no
  if is_absorbed "$repo" "$tip" "$base_sha"; then landed=yes; fi
  for m in ${merged[@]+"${merged[@]}"}; do
    if git -C "$repo" merge-base --is-ancestor "$tip" "$m"; then landed=yes; fi
  done
  [ "$landed" = no ] || record remote "$ref" "$tip"
done

{
  echo "# land-worktrees plan. Written by plan.sh; land.sh refuses it once the repository moves."
  printf 'version\t1\n'
  printf 'repo\t%s\n' "$repo"
  printf 'base\t%s\t%s\t%s\n' "$base" "$base_sha" "$base_tree"
  printf 'final\t%s\n' "$final"
  printf 'created\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat "$tmp/body"
} >"$plan"

# ---- The report a person reads ----

short() { git -C "$repo" rev-parse --short "$1"; }
field() { awk -F'\t' -v k="$1" '$1 == k' "$plan"; }
label() { case "$1" in /*) basename "$1" ;; *) printf '%s' "$1" ;; esac; }

{
  printf 'Plan for %s\n' "$repo"
  printf 'Base %s at %s' "$base" "$(short "$base_sha")"
  upstream=$(git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$base" 2>/dev/null || true)
  if [ -n "$upstream" ]; then printf ', %s commits ahead of origin/%s' "$(git -C "$repo" rev-list --count "$upstream..$base_sha")" "$base"; fi
  printf '\n\n'

  printf 'Land on %s (%s)\n' "$base" "$(field merge | wc -l | tr -d ' ')"
  field merge | while IFS=$TAB read -r _ b tip mb tree res; do
    extra=clean
    [ "$res" = - ] || extra="with the resolution in $res"
    printf '  %-44s %-12s %s\n' "$b" "$(count "$(git -C "$repo" rev-list --count "$base_sha..$tip")" commit commits)" "$extra"
    overlaps=$(awk -F'\t' -v b="$b" '$1 == "overlap" && $2 == b { print $3 "\t" $4 }' "$plan")
    if [ -n "$overlaps" ]; then
      printf '      WARNING: a kept worktree holds uncommitted changes to files this branch lands.\n'
      printf '      They may be its unfinished follow-up. Ask the owner before landing it.\n'
      printf '%s\n' "$overlaps" | while IFS=$TAB read -r wt rel; do printf '        %s  %s\n' "$(basename "$wt")" "$rel"; done
    fi
  done
  if [ "$final" != "$base_tree" ]; then
    printf '  The landed tree is %s. Gate it with trial.sh before landing.\n' "$(short "$final")"
  fi

  printf '\nDelete worktrees (%s)\n' "$(field delete-worktree | wc -l | tr -d ' ')"
  field delete-worktree | while IFS=$TAB read -r _ wt b head; do
    counts=$(awk -F'\t' -v w="$wt" '$1 == "leftover" && $2 == w { c[$3]++ } END {
      s = ""
      if (c["base"]) s = s c["base"] " same as the base, "
      if (c["past"]) s = s c["past"] (c["past"] == 1 ? " past version, " : " past versions, ")
      if (c["gone"]) s = s c["gone"] " deleted in both, "
      sub(/, $/, "", s); print (s == "" ? "clean" : "leftovers: " s) }' "$plan")
    shown=$b
    [ "$b" != - ] || shown="(detached)"
    printf '  %-34s %-40s %s\n' "$(basename "$wt")" "$shown" "$counts"
  done

  printf '\nDelete branches with no worktree (%s)\n' "$(field delete-branch | wc -l | tr -d ' ')"
  field delete-branch | while IFS=$TAB read -r _ b tip; do printf '  %s\n' "$b"; done

  printf '\nKeep (%s)\n' "$(field keep | wc -l | tr -d ' ')"
  field keep | while IFS=$TAB read -r _ what why; do
    printf '  %s\n      %s\n' "$(label "$what")" "$why"
    awk -F'\t' -v w="$what" '
      $1 == "hint" && $2 == w    { h[$4] = $3 }
      $1 == "overlap" && $3 == w { o[$4] = o[$4] (o[$4] == "" ? "" : ", ") $2 }
      $1 == "real" && $2 == w    { r[++n] = $3 }
      END {
        for (i = 1; i <= n && i <= 15; i++) {
          printf "        %s\n", r[i]
          if (r[i] in h) printf "          %s\n", h[r[i]]
          if (r[i] in o) printf "          a branch this plan lands changes it too: %s\n", o[r[i]]
        }
        if (n > 15) printf "        and %d more (all are in plan.tsv)\n", n - 15
      }' "$plan"
  done

  if [ -n "$(field blocker)" ]; then
    printf '\nBlockers: these files are dirty in %s and the landing changes them.\n' "$base_wt"
    printf 'Their owner commits them first, then plan.sh runs again.\n'
    field blocker | cut -f3 | sed 's/^/  /'
  fi
  if [ -n "$(field trial)" ]; then
    printf '\nTrial worktrees (land.sh removes them)\n'
    field trial | cut -f2 | sed 's/^/  /'
  fi
  if [ -n "$(field note)" ]; then
    printf '\nNotes\n'
    field note | while IFS=$TAB read -r _ wt why; do printf '  %s: %s\n' "$(basename "$wt")" "$why"; done
  fi
  if [ -n "$(field remote)" ]; then
    printf '\nRemote branches the base holds (land.sh prints the commands; deleting one is a push)\n'
    field remote | cut -f2 | sed 's/^/  /'
  fi
  printf '\nPlan: %s\n' "$plan"
} >"$report"

cat "$report"

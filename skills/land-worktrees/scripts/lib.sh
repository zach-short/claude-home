# Shared by plan.sh, trial.sh, land.sh and selftest.sh. Sourced, never run.
#
# macOS ships bash 3.2, so nothing here uses associative arrays or mapfile, and an array that may
# be empty is expanded as ${a[@]+"${a[@]}"}: under `set -u`, bash before 4.4 calls an empty array
# unbound. A command substitution does not inherit `set -e` in bash 3.2 either, so every function
# called as $(f ...) checks its own failures and its caller checks the output.
#
# Every TSV field written anywhere is non-empty (`-` stands for "none"), because `read` with a tab
# in IFS treats the tab as whitespace and silently merges an empty field into the next one.

TAB=$'\t'
OS=$(uname)

die() {
  printf 'land-worktrees: %s\n' "$*" >&2
  exit 1
}

is_oid() {
  case "$1" in '' | *[!0-9a-f]*) return 1 ;; esac
  [ ${#1} -eq 40 ] || [ ${#1} -eq 64 ]
}

physical() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

mtime() {
  if [ "$OS" = Darwin ]; then stat -f %m "$1"; else stat -c %Y "$1"; fi
}

# "1 commit", "2 commits": a count with its noun in the right number.
count() { # n singular plural
  if [ "$1" -eq 1 ]; then printf '1 %s' "$2"; else printf '%s %s' "$1" "$3"; fi
}

# git's own default message, which leaves out "into <base>" for main and master.
merge_message() { # branch base
  case "$2" in
    main | master) printf "Merge branch '%s'" "$1" ;;
    *) printf "Merge branch '%s' into %s" "$1" "$2" ;;
  esac
}

# A branch name as one directory name under --resolutions: `feat/x` is `feat__x`.
res_name() { printf '%s' "$1" | sed 's#/#__#g'; }

# One row per worktree: path, HEAD, branch, flags. The first row is the main checkout.
worktree_rows() { # repo
  git -C "$1" worktree list --porcelain | awk -v OFS='\t' '
    /^worktree / { if (w != "") print w, h, b, f; w = substr($0, 10); h = "-"; b = "-"; f = "-" }
    /^HEAD /     { h = substr($0, 6) }
    /^branch /   { b = substr($0, 8); sub(/^refs\/heads\//, "", b) }
    /^bare/      { f = f "bare," }
    /^detached/  { b = "-" }
    /^locked/    { f = f "locked," }
    /^prunable/  { f = f "prunable," }
    END          { if (w != "") print w, h, b, f }'
}

primary_of() { git -C "$1" worktree list --porcelain | sed -n '1s/^worktree //p'; }

# The worktree that has <branch> checked out, or nothing.
worktree_of_branch() { # repo branch
  worktree_rows "$1" | awk -F'\t' -v b="$2" '$3 == b { print $1; exit }'
}

# Whether everything on <commit> is already in <into>: it is an ancestor, or merging it would
# change nothing because the work landed by another route (a squash merge, a cherry-pick, a copy
# by content). `git branch --merged` sees only the first case.
is_absorbed() { # repo commit into
  local out
  git -C "$1" merge-base --is-ancestor "$2" "$3" 2>/dev/null && return 0
  out=$(git -C "$1" merge-tree --write-tree "$3" "$2" 2>/dev/null) || return 1
  [ "${out%%$'\n'*}" = "$(git -C "$1" rev-parse "$3^{tree}")" ]
}

# Every path in <wt> that differs from its HEAD: tracked edits, staged or not, deletions, and
# untracked files that are not ignored. One per line, sorted. Ignored files (node_modules, .env)
# are not listed: git never held them, and they go with the worktree.
dirty_paths() { # wt
  {
    git -C "$1" diff --name-only --no-renames -z HEAD || return 1
    git -C "$1" ls-files --others --exclude-standard -z || return 1
  } | tr '\0' '\n' | LC_ALL=C sort -u
}

# The blob a path would be committed as, with the path's own filters. DELETED for a missing
# path, OTHER for a directory (a nested repository is listed as one).
work_blob() { # wt relpath
  if [ -L "$1/$2" ]; then
    printf '%s' "$(readlink "$1/$2")" | git -C "$1" hash-object --stdin
  elif [ -f "$1/$2" ]; then
    git -C "$1" hash-object -- "$2"
  elif [ -e "$1/$2" ]; then
    echo OTHER
  else
    echo DELETED
  fi
}

# Sorts one changed path in a worktree. Prints "why<TAB>blob", where why is
#   base  the file equals the version the base holds once the plan lands
#   gone  the file is deleted and the base does not hold it either
#   past  the file equals a version once committed at this path in the given history
#   new   none of these: work that exists nowhere else
# The history is the base and the branches the plan merges, never --all: a stash or an
# unmerged branch holding the same content is not landed work.
classify_path() { # repo wt final-tree relpath history-commit...
  local repo=$1 wt=$2 final=$3 rel=$4 blob want found
  shift 4
  blob=$(work_blob "$wt" "$rel") || blob=OTHER
  want=$(git -C "$repo" rev-parse -q --verify "$final:$rel" 2>/dev/null) || want=-
  case "$blob" in
    DELETED)
      if [ "$want" = - ]; then echo "gone${TAB}DELETED"; else echo "new${TAB}DELETED"; fi
      return 0
      ;;
    OTHER)
      echo "new${TAB}OTHER"
      return 0
      ;;
  esac
  if [ "$blob" = "$want" ]; then
    echo "base${TAB}$blob"
    return 0
  fi
  found=$(git -C "$repo" log --full-history --format=%H -1 --find-object="$blob" "$@" -- "$rel" 2>/dev/null) || found=
  if [ -n "$found" ]; then echo "past${TAB}$blob"; else echo "new${TAB}$blob"; fi
}

# One snapshot of every process's working directory, taken once because lsof is slow.
lsof_snapshot() { lsof -d cwd -Fpcn 2>/dev/null || true; }

# Processes standing inside <dir>, as "pid command" lines.
live_in() { # snapshot-file physical-dir
  awk -v d="$2" '
    /^p/ { p = substr($0, 2) }
    /^c/ { c = substr($0, 2) }
    /^n/ { n = substr($0, 2); if (n == d || index(n, d "/") == 1) print p, c }' "$1"
}

# When HEAD last moved in this worktree (a commit, a checkout, the worktree's creation).
head_moved_at() { # wt
  git -C "$1" reflog -1 --date=unix --format=%gd HEAD 2>/dev/null | sed -n 's/.*@{\([0-9]*\)}.*/\1/p'
}

# The marker trial.sh leaves in a trial worktree's private git directory, so plan.sh can tell its
# own trial from a worktree someone is working in. It sits outside the working tree, where no
# gate and no `git status` can see it.
trial_marker() { # wt
  local gd
  gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  printf '%s/land-worktrees-trial' "$gd"
}

# Lays every file under <dir> over <tree> at the same relative path, then removes each path listed
# in <dir>/.delete, and prints the new tree. It works in a private index, so no checkout's index
# is read, locked or written.
apply_resolutions() { # repo tree dir
  local repo=$1 tree=$2 dir=$3 idx rel blob mode files
  idx=$(mktemp "${TMPDIR:-/tmp}/land-index.XXXXXX") || return 1
  GIT_INDEX_FILE=$idx git -C "$repo" read-tree "$tree" || { rm -f "$idx"; return 1; }
  files=$(cd "$dir" && find . -type f ! -name .delete | sed 's#^\./##' | LC_ALL=C sort) || { rm -f "$idx"; return 1; }
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    blob=$(git -C "$repo" hash-object -w --path="$rel" -- "$dir/$rel") || { rm -f "$idx"; return 1; }
    mode=$(git -C "$repo" ls-tree "$tree" -- "$rel" | awk '{ print $1 }')
    case "$mode" in 100644 | 100755) ;; *) mode=100644 ;; esac
    GIT_INDEX_FILE=$idx git -C "$repo" update-index --add --cacheinfo "$mode,$blob,$rel" || { rm -f "$idx"; return 1; }
  done <<<"$files"
  if [ -f "$dir/.delete" ]; then
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      GIT_INDEX_FILE=$idx git -C "$repo" update-index --force-remove -- "$rel" || { rm -f "$idx"; return 1; }
    done <"$dir/.delete"
  fi
  GIT_INDEX_FILE=$idx git -C "$repo" write-tree || { rm -f "$idx"; return 1; }
  rm -f "$idx"
}

# Merges <tip> into <tree> the way `git merge` would merge it into a commit whose history is the
# base plus every tip merged before it. `git merge-base A B C` answers for A against a
# hypothetical merge of B and C, which is exactly that commit. Prints "tree<TAB>merge-base" for a
# clean or fully resolved merge. Otherwise prints why on the first line and, for a conflict, the
# conflicted paths after it, and returns 1.
merge_step() { # repo tree tip resolution-dir|- base-sha merged-tip...
  local repo=$1 tree=$2 tip=$3 res=$4 bases count out status=0 conflicts missing rel
  shift 4
  bases=$(git -C "$repo" merge-base --all "$tip" "$@") || bases=
  count=$(printf '%s\n' "$bases" | grep -c . || true)
  if [ "$count" -ne 1 ]; then
    echo "history has $count merge bases; merge it by hand"
    return 1
  fi
  out=$(git -c core.quotePath=false -C "$repo" merge-tree --write-tree --name-only --merge-base="$bases" "$tree" "$tip") || status=$?
  if [ "$status" -gt 1 ]; then
    echo "merge-tree failed (exit $status)"
    return 1
  fi
  conflicts=$(printf '%s\n' "$out" | sed -n '2,/^$/p' | sed '/^$/d' | LC_ALL=C sort -u)
  out=${out%%$'\n'*}
  if [ "$status" -eq 1 ]; then
    if [ "$res" = - ]; then
      echo "conflicts"
      printf '%s\n' "$conflicts"
      return 1
    fi
    missing=
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      if [ ! -f "$res/$rel" ] && ! grep -Fxq -- "$rel" "$res/.delete" 2>/dev/null; then
        missing="$missing$rel"$'\n'
      fi
    done <<<"$conflicts"
    if [ -n "$missing" ]; then
      echo "conflicts the resolution does not cover"
      printf '%s' "$missing"
      return 1
    fi
  fi
  if [ "$res" != - ]; then
    out=$(apply_resolutions "$repo" "$out" "$res") || out=
  fi
  if ! is_oid "$out"; then
    echo "could not build the merged tree"
    return 1
  fi
  printf '%s\t%s\n' "$out" "$bases"
}

# The paths the plan changes that are dirty in the checkout holding the base. `git merge
# --ff-only` refuses to overwrite them, so they block the landing until their owner commits them.
blocking_paths() { # repo base-tree final-tree base-worktree
  local changed dirty
  [ "$2" != "$3" ] || return 0
  changed=$(git -C "$1" diff --name-only --no-renames -z "$2" "$3" | tr '\0' '\n' | LC_ALL=C sort -u)
  dirty=$(dirty_paths "$4")
  LC_ALL=C comm -12 <(printf '%s\n' "$changed") <(printf '%s\n' "$dirty") | sed '/^$/d'
}

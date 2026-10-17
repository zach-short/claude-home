---
name: land-worktrees
description: Use when the user says "merge the worktrees", "land the branches", "clean up the worktrees", "delete the merged branches" or "what can I delete", or subagents left worktrees behind. Merges finished branches, deletes fully merged worktrees, keeps real uncommitted work, and commits uncommitted work whose board item is done.
---

# /land-worktrees

Worktrees pile up: every subagent and parallel session leaves one, usually with its branch already
merged and a few stray files in it. This skill finds which ones still hold anything, lands the
branches that have committed work, and removes the rest.

The work is split in two, on purpose. You do everything that writes nothing anyone can see: the
survey, the predicted merge trees, the trial build and its gates. Then you run one script,
`land.sh`, that writes the merge commits and removes the worktrees. A removal cannot be taken
back, so `land.sh` re-checks every fact at
the moment it acts, and skips anything that no longer matches the plan. It never forces past a
change.

The scripts live in `~/.claude/skills/land-worktrees/scripts/`. Below, `$S` stands for that path.

## Before you start

- Run `ListAgents` and `git status --short` in the main checkout. A peer that is busy in the same
  repository may be working in one of the worktrees. `plan.sh` keeps any worktree that a process
  stands in or that changed within the last hour, but a peer is cheaper to ask than to detect.
- Never `cd` into a worktree. The session's working directory follows a bare `cd`, and a worktree
  you stand in cannot be removed. Use `git -C <dir>` and `( cd <dir> && ... )` subshells.
- Run the scripts with `bash`, as written below. They are bash 3.2 scripts, so they also run on the
  stock macOS shell. Never paste their loops into zsh, where a variable named `path` wipes `PATH`.
- Put `--out` in the session scratchpad. The plan, the report and the trial worktree go there.

## 1. Survey

```bash
bash $S/plan.sh --repo <any checkout of the repo> --out <scratchpad>/land
```

It prints a report and writes `plan.tsv` beside it. It writes only git objects that nothing points
at (the predicted trees), so it is safe to run as often as you like. `git gc` removes those objects
later.

The report has these sections:

- **Land**: branches with commits the base does not hold, in merge order (oldest tip first,
  unless `--order` says otherwise). Each one's merged tree is predicted from the base plus the
  branches merged before it, which is what `git merge` will see.
- **Delete worktrees** and **Delete branches**: these hold nothing that the base will not hold
  once the plan lands. A branch counts as landed when it is an ancestor of the base, or when merging
  it would change nothing (a squash merge or a cherry-pick landed it by another route).
- **Keep**: everything else, each with its reason: a conflict, a busy worktree, a locked one,
  a detached HEAD with its own commits, or real uncommitted work, with the files listed. Under a
  kept file, "the base committed this path after this worktree's HEAD" means a later commit
  changed that file. The kept copy is then usually a draft that the commit replaced, but it stays
  until the owner says so.
- **WARNING** under a branch to land: a kept worktree holds uncommitted changes to files that the
  branch changes. This is the signal for a builder's commit whose audit fixes nobody committed.
- **Blockers**: files that are dirty in the checkout holding the base and that the landing would
  change. Git refuses to fast-forward over them.
- **Remote branches** that the base already holds. Deleting one is a push, so the skill only
  prints the commands.

Each uncommitted file in a worktree whose commits are landed is sorted one of four ways:

| Sort | Meaning | Verdict |
|---|---|---|
| `base` | equals the file the base will hold after the landing | leftover |
| `gone` | deleted, and the base will not hold it either | leftover |
| `past` | equals a version once committed at that path in the base's history | leftover |
| `new` | none of these, so it exists nowhere else | real work: the worktree stays |

A worktree goes only when every file is a leftover. "History" means the base and the branches the
plan merges, never `--all`. A stash or an unmerged branch that holds the same content is not landed
work. Each leftover's content hash goes into the plan, and `land.sh` refuses to remove a worktree
whose files no longer match.

Options: `--skip <branch>` leaves a branch out of the landing (repeat it for more). `--order a,b`
merges those first. `--base <branch>` picks the base (by default, origin's HEAD). `--quiet-minutes
<n>` sets the busy window (default 60). `--resolutions <dir>` is described in the next section.

## 2. Settle what the report cannot

Give the owner the report in short form: what lands, what goes, and what stays and why. Put each
decision that is theirs to make in a live `AskUserQuestion`, in the same turn:

- **A conflict.** Offer to write a resolution. Read both sides (`git show <base>:<path>`,
  `git show <tip>:<path>`, and the merge base). Write the resolved file to
  `<res>/<branch>/<path>`, with a `/` in the branch name written as `__`. List any path the merge
  should delete in `<res>/<branch>/.delete`. Then run `plan.sh` again with `--resolutions <res>`.
  Every file under a branch's folder is laid over that branch's merge, so a semantic fix for a
  merge that is clean but wrong goes there too. Show the owner each resolution before you rely
  on it, because the resolution becomes part of a commit that the owner makes.
- **An overlap WARNING.** Do not land that branch until the owner decides. If you land it alone,
  the version before the fixes goes onto the base, and nothing that runs later flags it: the gates
  pass, the warning goes away, and the fixes sit in a worktree with nothing to tie them to the
  branch.
  Compare the kept files with the branch (`git diff <tip> -- <path>` run in that worktree) and put
  the three choices to the owner: commit the fixes onto the branch first and survey again, land the
  branch as it is, or hold it back with `--skip`.
- **A record without its code.** When a branch to land belongs to an item that the board or the
  ledger already calls done, say so. A record commit can land while the code it describes sits
  unmerged on a branch.
- **Real work in a kept worktree.** List the files, and show the diff
  (`git -C <wt> diff HEAD -- <file>`) when the owner wants it. Do not move, copy, commit or delete
  that work. The owner decides where it goes, and a later run removes the worktree once it is
  committed. When the work belongs to a board item that is done, commit it as the next bullet says.
- **Real work whose board item is done.** Find the item: search the repository's board and
  ledger (in this setup, `PASSOFF.md` and `HANDOFF.md` in the main checkout) for the worktree's
  path and its branch name. The item counts as done only when its board status starts with
  `DONE` (built, gated and recorded, not yet committed). A row written as `DONE` before
  2026-10-15 may already be committed: when the lookup in `AGENT-PRACTICES.local.md` §2.3 finds
  its code commit, the row is really `COMMITTED`, so move it (see step 5) and do not write a
  second commit. A `COMMITTED` row whose
  worktree still holds uncommitted files means work after the commit, such as audit fixes: list
  those files as real work and do not write a commit for them. A worktree with no matching item,
  an item in any other status, or a worktree the report calls busy gets no commit; list it as
  real work, as the bullet above says. For a done item:
  1. Read the item's row and its ledger step. Take the files to commit from the worktree's
     uncommitted files (`git -C <wt> status --short`) that the row's "Files it owns" cell or the
     ledger step names. List any other uncommitted file apart, with its diff, and leave it out of
     the commit: it is not shown to belong to the item.
  2. Read the diff of each file you will commit, so the message says what the change does.
  3. Write the message in the repository's own commit style (read `git log --oneline -15`). In
     this setup that is short and all-lowercase, and it starts with the item, as in
     `row 137: last native filled green buttons move to the shared button`. Add no
     `Co-Authored-By:` trailer and no "Generated with" line.
  4. Run `git -C <wt> add <exact files>`, then `git -C <wt> commit <the same files> -m "<message>"`.
     Name every path. Never use `git add -A` or `git add .`. For a file git has never seen, use
     `git -C <wt> add -N <file>` before the commit, because a commit that names paths drops
     untracked ones.
  5. Run the survey again. The
     branch then has commits the base does not hold, and it moves to **Land**. Read the new hash
     with `git -C <wt> log -1 --format=%h` and move the row from `DONE` to
     `COMMITTED, <ledger step>, <hash>`, naming the branch while `main` does not hold it.

  When the item's branch also appears under **Land** with an overlap WARNING, these blocks are the
  first of that warning's three choices. Still ask the owner which choice to take.
- **A blocker.** Its owner commits the dirty files in the main checkout. Then run the survey again.
- **A busy worktree** that the owner says is finished. Run the survey again with
  `--quiet-minutes 0`. A worktree that a process stands in stays whatever the window is. Find the
  process (the report names it) and let the owner stop it.

Never edit `plan.tsv` by hand. Run the survey again instead. Each verdict depends on the others:
when you hold back one branch, every merge tree after it changes.

## 3. Gate the landed tree

This step applies only when the plan lands something.

```bash
bash $S/trial.sh <scratchpad>/land/plan.tsv
```

This builds a detached worktree whose files are exactly the landed tree. `land.sh` commits that
same tree object later, so the gates test the real result, and no second merge can come out
differently. Set the trial up the way the repository's own docs set up a fresh worktree. Look in
its `CLAUDE.md` or `AGENTS.md`, or run `personal-config worktree <lane>` when the repo has a
`.personal-config.json`. Then run every gate those docs mark as required, inside the trial, and
record each result:

```bash
bash $S/trial.sh --record <plan.tsv> pass "<the gate command>"
```

- Record `pass` only for a gate that ran green in the trial. Record a gate that could not run here
  (no database, no secret) as `skip`, put the reason in the text, and tell the owner. A skipped gate
  is a gap, and the owner should know that it exists.
- When a gate is red, record `fail` and find the branch that caused it. Run the survey again with
  `--skip <branch>`, then run `trial.sh` again (it reuses the trial with its installs and caches),
  then run the failing gate again. Report what you find. Do not fix code in the trial: a fix
  belongs on the branch, or in a resolution file that the owner approves.
- In the trial, HEAD is the old base, so `git status` shows the whole landing as staged. Gates that
  diff against HEAD see the landing as the change.

A new survey drops the gate results, and a new trial build does too. `land.sh` accepts results only
for the tree the trial holds.

## 4. Hand it over

Run the dry run yourself. It changes nothing:

```bash
bash $S/land.sh <plan.tsv>
```

A `BLOCKED` line means the plan cannot run. Fix the cause and survey again. When the dry run is
clean, it prints the apply command with the plan's hash in it. The hash makes sure that the plan
you apply is exactly the plan that was checked. Run the dry run, then the apply command. Say that each worktree removal takes a
few seconds, because `node_modules` is large.

Run `land.sh --apply` yourself. Do not make its commits another way, because the apply run re-checks
every fact the plan relied on.

When it applies, `land.sh` does this:

1. It saves every branch tip and worktree HEAD to `<parent of repo>/<repo>-branch-tips-<date>.txt`.
2. It builds each merge commit with `git commit-tree` from the planned tree, away from every
   checkout. The message is git's own (`Merge branch '<b>'`).
3. It fast-forwards the checkout that holds the base to the last merge (`--ff-only
   --no-autostash`). A fast-forward cannot take a parallel session's staged files into a commit,
   and git refuses it when a dirty file would be overwritten. If it is refused, the base stays
   where it was, and the script stops before it removes anything.
4. It removes each planned worktree and deletes its branch, after it checks again that HEAD did not
   move, that the changed files are the sorted ones with the same content, that no process stands
   in it, and that the base holds its HEAD. A worktree that fails a check is skipped, not forced.
5. It removes the trial and runs `git worktree prune`.

## 5. After it runs

Terminal output can arrive late, or twice. Check the state yourself, and do not rely on
what was echoed: `git log --oneline -<n> <base>`, `git worktree list`, `git branch`. Then report
what landed, what was removed, and what was skipped or kept, each with its reason. Say how far the
base is ahead of origin, then push the base and delete the remote branches that `land.sh`
printed.

Then bring the board up to date for each landed branch whose item it names. A row still at `DONE`
moves to `COMMITTED, <ledger step>, <hash>`, with the branch's own commit hash, not the merge
commit's. A `COMMITTED` row that named its branch drops the branch name, because `main` now holds
the commit. This is a fact read from git, so make the edit; do not mark any row `DONE` here,
because that is a claim about the work that only its builder or the owner makes.

## What the checks do not cover

- Ignored files (`node_modules`, `.env`, build output) go with the worktree, because git never held
  them. When a repository keeps notes in ignored files, look at them before the landing.
- A file whose content equals the base but whose mode changed counts as a leftover.
- Stashes are not looked at. `refs/stash` belongs to the whole repository and survives every
  removal.
- Submodules are not tested.
- A history with more than one merge base for a branch (a criss-cross) is kept for a hand merge,
  because the prediction cannot be exact there.

## The scripts

- `plan.sh`: the survey. It writes only unreferenced git objects and the files in `--out`.
- `trial.sh`: builds or refreshes the trial worktree and records gate results.
- `land.sh`: the apply script. It is a dry run unless it gets `--apply --expect <hash>`.
- `lib.sh`: shared helpers. Every merge prediction and every sort lives here, so the dry run and
  the apply run decide the same way.
- `selftest.sh`: builds a throwaway repository with every case above, runs all three scripts
  against it, and checks each verdict. Run it after any change to the scripts. It commits only
  inside its own temporary repository.

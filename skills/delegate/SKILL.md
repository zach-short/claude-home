---
name: delegate
description: Build one ratified board row or planned phase with a builder subagent and a separate auditor, each in its own worktree on the right model, then sign it off. Use when a row has cleared its gate and you want it built, reviewed and recorded without opening a new session.
---

<!-- personal-config v0.8.0 · 2026-10-17 · config 4c6d7946 · standard v2.1.0 -->

# /delegate

Runs one item that has already cleared its gate to done: claim it, build it in a subagent, audit
the build in a second subagent, and sign it off, with no person opening a fresh session or pasting
a prompt across. It drives the working standard's rules on model selection, the context budget,
parallel sessions and closing work. It replaces none of them.

## The tiers

| Tier | Model |
|---|---|
| Deep | Fable 5.1 |
| Default | Opus 5.5 |
| Mechanical | Sonnet 5.5 |
| Light | Haiku 5.5 |

Pass the Agent tool's `model` parameter the family each name belongs to, as that parameter lists
its values. Where a name maps to no family the tool lists, or a tier is `<unset>`, ask the owner
before step 2, or, under `/autopilot`, hold the row. Never guess.

## 0. Preconditions

- **The item has cleared its gate.**
  On the board (`PASSOFF.md`): an `OPEN` row with a model and a written prompt, every item
  its "Waits on" names `DONE` or gone from the table at a fold, and no "scope first".
  Otherwise stop and run `/scope`.
- **Open owner questions are asked here**, in chat, in one batch, before step 1. A subagent cannot
  reach the owner, so a question is never handed to a builder to guess at. Under
  `/autopilot` its opening round asked them, and a row whose questions it did not reach is
  held.
- **A Deep item is held** unless the person typed `/delegate` on that item in this session, or lifted it in
  `/autopilot`'s opening round.
  That is the authorization: say so in one line, and record it in the sign-off. A `/delegate` you
  loaded on your own lifts nothing. A named Deep item gets a Deep builder, and then an
  independent Deep review in step 3.
- **Never spawn a model above the repo's tier ceiling**, where its router has a "Tier ceiling"
  section.
- **Run in the primary checkout**, where the ledger and the board are written. If `git rev-parse
  --show-toplevel` is not the first path `git worktree list` prints, this is a worktree session:
  stop and say so.

## 1. Read and claim

Read the item fresh: never trust a status read earlier in this conversation.
Check its "Files it owns" against every other item marked `IN FLIGHT`. Two items that name the same file never run at
once, whatever their lanes say.
Claim it with `personal-config passoff claim <n>` before spawning anything, so a parallel
session sees the claim. Then find whether the item's file is tracked: it is when
`git ls-files --error-unmatch passoff/<n>-<slug>.md` succeeds here. Only a tracked file is
in a builder's worktree. Say which it is in the builder's brief.
Where it is tracked, commit the claim before step 2, naming the file:
`git commit passoff/<n>-<slug>.md -m "claim item <n>"`. The land step fast-forwards the
primary checkout, and git refuses a fast-forward that would overwrite an uncommitted edit to
that file.

## 2. Build, in a subagent

Spawn one Agent with `model` from the tiers above and `isolation: "worktree"`. A worktree holds
only the files git tracks, and an agent in one cannot run git on another worktree. So before you
write the brief:

- Find each document the brief sends the builder to read, such as the working standard and the
  documents the item cites, that git does not track here. Give its absolute path in this
  checkout, to be read and never written, or carry the lines the builder needs in the brief.
- Pick the patch path: an absolute path outside the repo, such as a file in this session's
  scratch or temp directory. The auditor in step 3 reproduces the build from it.
- Write the base branch's name and the patch path where the rules below say `<base>` and
  `<patch>`.

Its brief is the item's own prompt in full, then the relay contract below, then these rules:

- Do not edit the ledger (`HANDOFF.md`) or the board (`PASSOFF.md`). Only this session writes them.
- Where the brief says the item's file is tracked, append its `## Close-out, <date>` section
  there: what changed and why, what is now fixed, which questions it answered, and what is
  left owed. Otherwise put that text in your report. It is the one record you write.
- Where the brief gives a document by an absolute path outside your worktree, read it there,
  and never write there.
- Commit on your own worktree branch, naming the exact files in both the `git add` and
  the commit. The merge into the base and the push are the land step's (step 6), which this
  session sends you after the audit. If a hook blocks the commit, print the two commit
  blocks, do not work around it, and make the patch the auditor works from:
  run `git add -N` on each file the change adds, then
  `git diff --binary HEAD > <patch>`. List in your report every file the change adds.
- Before the first gate, run the fresh-checkout recipe in the repo's working standard, and bring
  the worktree to the base branch: from your worktree's own directory, run
  `git merge --ff-only <base>` as one plain command, with the branch name written out, never
  through a shell variable or `git -C`. A worktree can start from a stale base, and its gates then
  report on old code.
- Never retry a call that was denied. Report it.
- Report: the gates as run, with their output; the diffstat; the patch path and every file the
  change adds, which the auditor needs to reproduce it; what changed; what is left; any
  number claimed, such as a migration or a step; any build-level call, with its reversal; and any
  question for the owner.

The relay contract, written into the brief as it stands here:

```
Your work-list is the items listed above. Work them in order.

If you reach roughly two thirds of your budget signals (you have read more than about 25 files,
or you are past two thirds of the work-list with substantial work left), STOP. Do not start
another item.

Instead, make your final output a pass-off prompt for a fresh agent: which items are done and
what you concluded for each, which item you stopped on and how far into it you got, the file
paths that mattered, and the exact remaining list. Write it to stand alone. The next agent will
not see this conversation.
```

Two shapes come back. **A finished report** goes to step 3. **A relayed pass-off** goes to a
fresh subagent of the same model, with that prompt as its whole brief. Count the passes: the
sign-off names them.

## 3. Audit, in a second subagent

Spawn a second Agent with its own `isolation: "worktree"`, never the builder's. A subagent in a
shared worktree edits source even when it is told only to review. Use the Default tier, or Deep
for a Deep item and for an item the owner named load-bearing. Where the repo's tier ceiling is
below Deep, an item that needs a Deep review is held, never reviewed on a lower tier.

Under `/autopilot`, where its opening round chose audits by tier, a Mechanical or Light item
lands on its gates with no auditor unless a trigger fires: a file changed outside its "Files it
owns", a fix round or a relay pass, a number claimed, a diffstat above `/autopilot`'s audit
trigger, or a decider's load-bearing mark. Read the triggers from the builder's report, which
carries the diffstat, the files changed, the relay passes and the numbers claimed. A report
that lacks the diffstat or the file list is itself a trigger. With no trigger, step 4 signs it
off on the builder's report, with the verdict
"not audited: <tier>, no trigger", and step 6 runs its gates again where the base moved.

Its brief: the item's done-when (the gate commands, and the proof a green gate cannot give), its
"What is fixed" and "Not in scope", the builder's worktree path and branch, the patch path, the
base branch's name, the absolute paths of the documents step 2 found untracked, and these rules:

- Do not edit the ledger (`HANDOFF.md`) or the board (`PASSOFF.md`), and never write the builder's worktree.
- Bring your own worktree to the base branch with `git merge --ff-only <base>`, run from your
  worktree's own directory as one plain command, then reproduce the change there.
  Take it from the builder's branch: from your worktree's own directory, run
  `git merge --ff-only <the builder's branch>` as one plain command. Where the builder
  reports that a hook blocked its commit, do not merge:
  run `git apply <patch>`, then `git add -N` on each file the builder listed as added.
  Never run `git -C` on the builder's worktree: worktree isolation refuses it. Where the change
  does not apply, report the command's output, and never copy files across by hand.
- Re-run every gate yourself. Report each command with its output, and the diffstat of your
  worktree after the change is reproduced.
- Return one of: clean, non-blocking findings, or blocking findings, each with a citation.

When it returns, check that its diffstat matches the builder's and that its verdict carries the
gate output. A verdict without them is not a reproduction: audit again with a fresh auditor,
once. A second verdict without them holds the item.
The auditor's branch now holds the builder's commits, so step 7 keeps the auditor's
worktree until the builder's branch is merged. Expect that.

## 4. Sign off

- **Clean, or non-blocking findings.**
  Write the record: the builder's and the auditor's models, the worktree, the branch, the
  commit state (landed on <base> at <hash>, or held at the land step), the relay passes, the
  verdict, each finding as `open`, and a Deep lift as the person's call. Where the item's file
  is tracked, these lines go into the land message (step 6), and the builder commits them.
  Where it is untracked, write the whole section at the end of `passoff/<n>-<slug>.md` here,
  from the builder's report. The log line, `DONE - <date>` and the hand-back blocks wait for
  step 6's fast-forward: then add `- <date> · closed item <n>` at the end of the log in
  `HANDOFF.md`, mark the row `DONE - <date>`, and post the `/close-out` hand-back blocks: in
  chat, or into the run's state file under `/autopilot`. On a 1.x board, with no `passoff/` folder beside it, the record
  is one step in `HANDOFF.md` at the next free number, read from the file now, with the same
  lines, and the row becomes `DONE - HANDOFF <n>`.
- **Blocking findings.** Send them to the same builder with `SendMessage`, so it keeps the context
  of its own change, then audit again with a fresh auditor. At most two rounds. A third means the
  item was sized or scoped wrong, and another pass does not fix that.
  After that the row is `HELD`: its "Waits on" names the file the open findings are written in,
  and the item's file gets a dated note of what is done and what is left.

## 5. Several items at once

Only items in different lanes whose "Files it owns" do not overlap, checked across all of them at
once, not in pairs as you go. Their step 2 Agent calls go out in one message. From there each
item's loop is independent.

## 6. Land it

After step 4 signs an item off, land it: the base takes the builder's branch, gated on the tree
that lands, and the push follows. The builder does the merge and the gates in its own worktree,
because its dependencies are there and that worktree is the one place this session never runs
git. Send it, with `SendMessage`, this step as it stands here, with `<base>`, the sign-off lines
and the gate list written in:

1. Where the item's file is tracked, append these sign-off lines to its close-out section:
   <the lines step 4 wrote>. Commit that file alone, naming it.
2. From your worktree's own directory, run `git rev-parse HEAD` and keep the hash. Then run
   `git merge --no-edit <base>` as one plain command, with the branch name written out. A
   fast-forward and a merge commit are both right.
3. On a conflict in a file your item's "Files it owns" lists, resolve it, `git add` that file,
   run `git commit --no-edit`, and say which file and how. On a conflict in any other file, run
   `git merge --abort` and report the file list: that is an undeclared overlap, and the row is
   held.
4. Run `git rev-parse HEAD` again. When it prints step 2's hash and the merge reported the
   branch already up to date, the base has not moved, and the tree that lands is the one your
   gates passed on, with step 1's commit on top where it was made: skip the install line and
   the gates, and report `base unmoved, gates not re-run` with the hash your gates passed on.
   Otherwise, or where any commit but step 1's came after your last gate run, run the
   fresh-checkout recipe's install line again, then every gate below: <the item's done-when
   gates, and the repo's gate command where it has one>. A gate that cannot run here is
   reported as skipped, with the reason.
5. Report: the merge result with `git rev-parse HEAD`, each gate with its output or the
   `base unmoved` line, and `git status --porcelain`, which must print nothing.

A builder that returns a pass-off instead of this report is at its budget. Land the row from a
worktree of your own: from the primary checkout, `git worktree add <a fresh path> <the builder's
branch>`, run steps 1 to 5 there with `git -C <that path>`, step 1 only where the pass-off does
not say the lines were committed, and remove that worktree in step 7.

Then, from the primary checkout, with `git -C` and the branch name written out:

```bash
git merge --ff-only <the builder's branch>
git push
```

Never `--force`, and never a rebase: the auditor reproduced the commits that land. A report of
`base unmoved, gates not re-run` lands on the gates the builder already reported; the
fast-forward is what checks that the base still has not moved, and it is refused where it has.
A refused fast-forward holds the row with git's output as its reason; where the base moved
while the builder was gating, send the message once more first, and the second send skips
step 1, whose lines are committed already. A refused push lands the row, stops every later push
in this session, and the rundown says how far ahead the base is. A red gate goes back to the
builder as a blocking finding, through step 4's fix round. A gate that could not run here is
listed under **Not verified**.

Only now write the record: the log line and `DONE - <date>` on the board, as step 4 says. Under
this policy a row is `DONE` when its commits are on the base. Then step 7 removes the row's
worktrees, whose branches the base now holds.

## 7. Remove the worktrees this run made

Remove each worktree that is finished: every builder, auditor and relayed pass that came
back with a worktree path and a branch. A
subagent's worktree outlives it, and nothing else removes it. Run each check from the primary
checkout, with `git -C`; never `cd` into a worktree, because one you stand in cannot be removed.

```bash
git merge-base --is-ancestor <branch> <base>
git -C <worktree> status --porcelain
```

Remove it only when the first exits 0 (the base holds every commit on the branch) and the
second prints nothing (no change and no untracked file):

```bash
git worktree remove <worktree>
git branch -d <branch>
```

Never add `--force` and never use `-D`: git refuses to remove a dirty worktree or to delete an
unmerged branch, and that refusal is the check. Never remove a worktree this run did not
make, because a worktree just added for new work is clean and its branch is merged too.
The merge happened in the land step; this step only removes. Keep every other worktree, and
report each one in one line with its reason: a commit the base does not hold, or uncommitted
files. That worktree stays until its work is committed and merged, then goes by the same
checks. Ignored files such as `node_modules` and `.env` go with a worktree when it is removed.

## Why this session stays small

Every subagent starts with no memory of an earlier call and keeps its working context to itself.
Only its final report crosses back, so this session collects a few short reports per item and
never a transcript. If this session runs long across several items, measure it with
`personal-config context --sentinel "<a phrase from this conversation>"`, and land at the working
standard's context budget instead of running into a compaction of its own. Under
`/autopilot`, that skill's own rule on this session's context governs.

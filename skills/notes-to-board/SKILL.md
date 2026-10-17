---
name: notes-to-board
description: Turn phone-walk notes (an Apple Notes folder, or pasted text) into a ledger board row in the shape of row 179, with each lane routed to a Haiku, Sonnet or Opus subagent by how much judgment the fix needs. Use when the user says "file my notes", "board my ezh notes", "turn these notes into rows", "I walked the app", or pastes a list of short defect notes.
---

# /notes-to-board

Zach walks the app on his phone and writes each defect as a short note, usually with a screenshot. This skill turns one batch of those notes into one board row in `PASSOFF.md`. The row has row 179's shape: a lead session checks each note against the tree, groups the items into lanes, and dispatches one subagent per lane. The difference from row 179 is that each lane names its own model. A one-line spacing fix then runs on Haiku, and a stale-cache bug runs on Opus.

The skill files the row and stops. It builds nothing, edits no source file, and never edits `HANDOFF.md`.

## Before you start

- Run in the primary checkout. `git rev-parse --show-toplevel` must be the first path `git worktree list` prints, and `HANDOFF.md` and `PASSOFF.md` must exist at its root. If either check fails, stop and say so.
- Read `HANDOFF.md` and the board table in `PASSOFF.md`. The Settled sections of the ledger are closed (R8), and the board is how you catch a note that is already a row.
- This step runs on the session's own model. The routing in step 3 sets the builders' models, not this one.

## 1. Get the notes

For the Apple Notes folder (default `ezh`):

```bash
python3 -I ~/.claude/skills/notes-to-board/scripts/notes.py --folder ezh --list
python3 -I ~/.claude/skills/notes-to-board/scripts/notes.py --folder ezh --since 2026-10-14 --out <scratchpad>/notes-2026-10-14
```

Pick `--since` after the newest note the board already holds: `grep -n "Apple Notes" PASSOFF.md`, then read the last matching row's note times. Say which window you chose. Run `--list` first when you are unsure. The script prints local times, oldest first, and writes `notes.json` plus every embedded screenshot as a PNG. It needs the macOS Automation permission for Notes (granted 2026-10-09). If `osascript` fails, say so. Do not read `~/Library/Group Containers/group.com.apple.notes/`, which needs Full Disk Access.

For pasted notes, number them in the order given and say in the row that they have no screenshots or times.

Then open every screenshot with Read. On 2026-10-09 three of seven rows named the wrong screen because they were written from the note text alone. A note that says "this page" means the page in the picture.

Expand contractions in prose. Keep the note's own words in a quotation.

## 2. Check each note against the tree

For each note, record the screen or route, `file:line`, the files a fix would touch, the platform (web, native or both), and whether the defect still exists. Run three checks before you trust a note:

- **Already fixed?** `git log --since="<note time>" --oneline -- <files>`. Zach makes small commits that never reach the board.
- **Already on the board?** Grep `PASSOFF.md` for the screen, the route and the component. Read `DONE` and `SETTLED AS NO` rows too (R8).
- **Readable?** A note that does not say what is wrong goes to the row's Ask list. Do not guess a lane for it.

With more than three notes, fan the reads out. Send one subagent per note, with `model: "haiku"` and `isolation: "worktree"`. The brief is read-only: find the screen, cite the lines, list the files a fix would touch, and say whether the change fits one file. A subagent in the shared checkout edits source even when told only to read. Haiku's citations are leads. Read each cited line yourself before it enters the row.

This triage sets the model and the "Files it owns" cell. The row's own step 1 repeats the ground truth later.

## 3. Route each item to a model

The question for each item is whether the note already contains the decision. Haiku applies a decision. Sonnet works out where to apply it. Opus makes the decision.

| Model | Use when | Examples |
|---|---|---|
| **Haiku** | The note states the change. One file plus its test. Nothing to choose. A break shows at once in `tsc`, lint or a screenshot. | A spacing, padding or radius value. A token swap. An icon swap. A line clamp. A string Zach wrote out in full. |
| **Sonnet** | The change is clear but spread out, or the cause sits in one or two known files. Mechanical work whose whole check is reading the output. | The same fix on web and native. A skeleton sized to a known layout. A wrong link target. Removing code a grep proves unused. An inventory table of strings or screens. |
| **Opus** | The builder must find a cause in behavior, or choose between designs. A wrong result would look right on a screen. | A stale cache or missing invalidation. Flow, navigation or auth logic. A shared primitive used app-wide. An accessibility sweep. A report on an error state that may hide a logic bug. |
| **Not in a lane** | Zach has to decide first, or the failure could be silent. | Copy nobody has chosen: list 2 or 3 variants in the Ask list (R7). A product question. Money paths, sync and merge rules, a notification that must never send: file a separate row with Model `Fable` and tell Zach. `/delegate` holds Deep rows until he lifts them. |

Three rules hold for every item:

- **When two tiers fit, ask which failure is louder.** A wrong Haiku edit shows in a gate or a picture. A wrong Opus-class fix can ship. Take the higher tier when the second case is possible.
- **A lane's model can go up after the row starts. It never goes down.** The row's step 1 may promote a lane with a reason. It may not lower one.
- **Never assign above the repo's tier ceiling** where its router names one, and never assign Fable inside a lane.

## 4. Group into lanes

- A lane is one model and a set of files. No two lanes name the same file. Two items that share a file go in one lane, in order, on the higher of their two tiers.
- A Haiku lane holds at most four items, all in different files, each with an exact `file:line`. A worktree costs a `bun install`, so a lane per item wastes more than it saves.
- Lanes with disjoint files run in parallel. Say so in the row.
- The lead model is Sonnet when every lane is Haiku or Sonnet, and Opus when any lane is Opus. The lead judges each builder's report, and an Opus lane needs a lead that can tell a plausible wrong answer from a right one.

## 5. Write the row

Fill in [row-template.md](row-template.md). Take the shared-rules block from it, then check that block against the repo's `CLAUDE.md`. Where they differ, `CLAUDE.md` wins.

1. Re-read `PASSOFF.md` immediately before writing. The next number is the highest `| N |` in the table plus 1. Never use a number written down earlier, because a parallel session may have taken it.
2. Insert the table row after the last row of the table, above `## Why each item exists`. Use these cells: Task is one sentence that counts the items and names the source, ending with ``(see `### N.`)``. Status is `OPEN`. Model is `<lead> (lanes: <models>)`. Lane is `<folder>-notes-<mmdd>`. Waits on is `nothing`, or the rows that own a file a lane needs. Files it owns holds the files triage verified, or stays empty with the step 1 collision check named in the section.
3. Append the `### N.` section at the end of the file.
4. Read both pieces back. The table row must have exactly seven cells. Check the section for em dashes, contractions and the banned words in `~/.claude/rules/writing-style.md`.

Do not mark the row `IN FLIGHT`. The session that takes it does that.

If Zach says the rows will run under `/delegate` or `/autopilot`, file one row per lane instead. Each row is then single-model, has its files filled in, and chains through "Waits on" where lanes share a file. Those skills build one row in one subagent, and a subagent cannot fan out to others.

## 6. Report

Keep the report short:

- A table of note, model and the one-line reason for the model.
- Notes left out, each with the reason: fixed in `<hash>`, already row `N`, or unreadable.
- The questions in the Ask list, so Zach sees them in chat.
- How to run the row: open a session on the lead model and paste the `### N.` section.
- Commit `PASSOFF.md` yourself, naming only that file, and give the hash.

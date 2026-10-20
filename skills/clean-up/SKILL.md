---
name: clean-up
description: Sweep finished work out of the live documents and into the archive (closed item files and their rows, old log lines, finished design folders), then repair everything that pointed at it. Use when doctor reports `unfolded`, after several items have closed, or when the user says "clean up", "tidy the board", "archive what is done", or "fold the handoff".
---

<!-- personal-config v0.8.0 · 2026-10-17 · config 4c6d7946 · standard v2.1.0 -->

# /clean-up

The live documents are read at the start of every session, so finished work left in them is a
cost every session pays. This skill decides what is finished, hands the moving to the commands
that already do it safely, and repairs what pointed at what moved.
**Do not move by hand what a command moves.** The commands write to the archive and read it back
before they cut: the only safe order for a document git may not be holding a copy of.

## 1. Find what is finished

Run `personal-config doctor .` and read every finding before touching anything.

- **A board row** is finished when it says `DONE - <date>` and its item file holds a close-out
  section. `SUPERSEDED` and `SETTLED AS NO` are finished too, but their files stay: each
  carries a fact written nowhere else.
- **A log line** is finished once it is older than 90 days.
- **A design folder** is finished when every board row that names it is. One open row citing
  it keeps it in the tree; a row the fold has taken off the table is finished.
- **On a 1.x board, with no `passoff/` folder beside it**, a row is finished when it says `DONE - <step>` and that step
  is in the ledger, and a ledger step gives up its body once it is older than the newest
  twenty. Its number, title and date stay, because every citation of it depends on that line.

**Report, never mark.** Something that looks finished but is not marked so, or a `DONE` whose
pointer resolves to nothing, goes back to the owner with its evidence (the commit, the record,
the date) and stays as it is. Marking work done is a claim about the work, and only the session
that did it, or the owner, makes it. Carry on with what is already marked.

## 2. Preview, ask, then move

Every command below runs with `--dry-run` first. **Without a terminal they write without
asking**, so the preview is the only confirmation there is: post it, say in one line what will
move and what will stay, and wait for a yes in chat.

1. **The board and the ledger**: `personal-config fold --dry-run`, then `personal-config fold`.
   Each `DONE` item's file is written to the archive, read back, given an index line that keeps
   what its row said, and only then removed with its row. An archive copy with other bytes
   stops that item. Log lines older than 90 days go to the archive log. `personal-config undo`
   puts back what it removed. On a 1.x board, with no `passoff/` folder beside it, every row and every step number stays;
   prompts and old bodies go.
   Run it only once every `DONE` item's tracked close-out is on the base, which the land step
   did.
2. **Each finished folder**: `personal-config archive <slug>`. It lists what cites the
   folder and whether the repo has recorded its final state. A path read at runtime blocks
   the move: repoint it first. Uncommitted changes block it too: commit the folder's final
   state yourself, naming its files, then `personal-config archive <slug> --move --dry-run`,
   then again without `--dry-run`.

## 3. Repair what pointed at it

Grep for each moved name across the ledger, the board, the open item files and every document in the tree. A command's referrer report reads tracked files only,
and a document kept out of git is invisible to it.

- **Live text** (an open board row, an open item file, a ledger standing section, the router file, the docs index, a memory entry) is repointed
  at the archive location, or cut where it no longer governs anything.
- **Historical text** (a close-out section, a log line, a `DONE` row, a ledger step) stays as written. It records what was true when
  it was written, and **a record you did not write is not yours to edit.**
- **A rule the moved doc leaves behind that still governs the work** moves to "Standing rules
  that outlived their doc". A rule nobody can find is a rule nobody follows.

Then run `personal-config doctor . <archive home>`, with the archive as a second root so it can
see what now lives there, and account for every finding left.

## 4. Hand back

One short report: what moved and where, and how many lines each live document lost; what was
left for the owner and why: unmarked work, broken pointers, a blocked move. Then commit
everything the sweep changed, naming the exact files, and push. **The archive may be its own
repository**: its commit is rooted there and names its own files, exactly as the command
printed it.

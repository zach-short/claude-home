---
name: passoff
description: Write the next session's first message as a standalone pass-off prompt. Use when handing work to a fresh session or a different model, when adding an item to the board, or when the user says "write the handoff", "pass this off", or "next session".
---

<!-- personal-config v0.8.0 · 2026-10-16 · config 68e6e026 · standard v2.1.0 -->

# /passoff

**The single highest-leverage artifact there is.** The next agent will not see this
conversation, this reasoning, or this context. A prompt that assumes any of it produces a
session that rediscovers what you already knew.

Nine parts, in this order. Skip one only when it is genuinely empty, and say so.

1. **Title.** Imperative, naming the change, not the area. *"Drag the week grid: windows edited
   where they are drawn"*, not *"week grid work"*.
2. **The header line.** `**Model: <tier>. Lane <X>. Waits on <what>.**` Plus the worktree
   instruction when the item needs its own. Pick the tier by asking four questions in order and
   taking the tier of the first yes: does the prompt state the change and the place (Light,
   where configured); does it have to place a clear change (Mechanical); does it have to find a
   cause or choose a design (Default); could a wrong answer pass every gate and a person's test
   (Deep). When two tiers fit, take the lower and name the gate or picture that catches a wrong
   answer; if none does, take the higher. After a failed build, escalation goes up one tier and
   never down. **Important:** Never assign a model tier above the
   repo's tier ceiling (if it has one). Check the repo's `CLAUDE.md` for its ceiling before
   writing a pass-off for it.
3. **Orientation.** Who they are picking up, what to read first and in what order, and the
   session rules restated **inline**, not by reference. A prompt is pasted alone, and a rule
   one file away is a rule that does not arrive.
4. **Why this exists**, in product terms. This is what lets the next agent make a hundred small
   judgment calls the prompt does not cover.
5. **What is fixed.** *"Read these before changing anything; do not relitigate them."* The
   verified facts with citations, the invariants, the house precedent to copy in place of a new
   invention, the constraint that makes this smaller than it looks. This section is where this
   session's reading is **banked** instead of re-paid.
6. **Do these, in order.** Numbered, each carrying its reason and its constraint. A step that
   says only what to do gets done differently than intended.
7. **Ask before building.** The named decisions that are the owner's, each with what makes it a
   real question. Say explicitly that both are their calls, and that either answer may be no.
   Where a question must wait for the owner even in an unattended run, write **owner's call**
   before it: `/autopilot`'s decider holds a row on those words and never answers it.
8. **Not in scope, whoever asks.** The negative list, named. It survives a persuasive
   mid-session argument in a way that an unstated boundary does not.
9. **Hand back.** The literal gate commands that must be green, what the owner should do and
   see, and the commit step.

`personal-config passoff next` prints the next `OPEN` item with its prompt and its model line,
and warns when something already in flight owns one of the same files; `personal-config passoff
claim <n>` marks the row `IN FLIGHT` and dates it. Neither writes the prompt: that is this
skill's work.

**Where it goes.** One file per item, `passoff/<n>-<slug>.md`, and its row in the table, in
the same edit. The file opens with `# <n>. <Title>`, then the dated line saying why it exists,
then the nine parts. `personal-config passoff next` reports the next free number, read from the
table, the folder and the archive: a number is never reused, even after its row has left the
table. The slug is the title in lower case, each run of other characters one hyphen, cut at a
hyphen to at most 48 characters. It is named once and never renamed.
On a 1.x board, with no `passoff/` folder beside it, the prompt is a `### <n>.` section below the table.

**A prompt rots the moment it is executed.** The item's close-out section is the truth; the prompt is the
ask. Never paste a prompt marked done: a fresh session would build it again.

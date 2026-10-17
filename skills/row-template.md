# Row template for /notes-to-board

Copy the section below to the end of `PASSOFF.md`, replace every `<...>`, and delete this heading and these two lines. Row 179 in the same file is the worked example. Skip a part only when it is empty, and say so in the section.

The shared-rules paragraph is copied from row 179 (2026-10-14). Check it against `CLAUDE.md` each time. `CLAUDE.md` wins.

---

### <N>. <Count> items from <source>, <date>

**Model: <lead>. Lane <folder>-notes-<mmdd>. Waits on <nothing | row N>.** Lane models: <Haiku, Sonnet, Opus, as used>. The lead works in the primary checkout for steps 1 and 2 only. Each builder works in its own worktree (step 3).

<Who wrote the notes, where, between which local times, and during what, for example "during a phone walk". Say that the notes are the source and that none was checked against the code when it was written. Say that contractions are expanded to house style. Name any decision Zach made in chat for these items, with its date.>

1. HH:MM:SS: "<note, in the note's words>" Screenshot: `<absolute path in the primary checkout>`. Model: <Haiku | Sonnet | Opus | held for Zach>. <One clause on why.>
2. ...

The screenshots sit in the primary checkout. A builder's worktree does not hold untracked files, so a builder reads them by absolute path.

**Every prompt below shares these rules.** Read first: `docs/conventions.md` in full, `CLAUDE.md`, and the files in `.claude/rules/` that match the paths you touch. Use absolute dates. Write no what-comments. Write why-comments only where the reason is not derivable from the code, and never strip a protected comment. Use design tokens, never literals. Use `bun`, never `npm`. Never raise a lint cap or a ratchet to pass a gate. Never add a file to `web/services/` or `native/services/`, and never create `web/app/api/`. Commit your lane's files on your worktree branch, naming each file. Never edit `HANDOFF.md` or `PASSOFF.md`. Stop and report before you touch a file your lane does not own. Write copy in the plain voice: sentence case, no em dash, no promotional line.

Do these, in order.

1. Ground truth first, no edits (the lead). For each note, open its screenshot, find the screen or code path, and cite `file:line`. Check that the defect still exists on the tree, and correct the reading of the note if the tree disagrees. The filing-time triage below is a lead, not a fact (R3). List the files each item would touch. A lane's model may go up after this step and never down. Record each promotion with its reason.

   Filing-time triage: <per note: screen, `file:line`, files, platform, model and one-line reason>.
2. Build the lanes (the lead). Group the items so that no two lanes name the same file. If two items share a file, they share a lane, in order, on the higher model. Record a lane table in the report with these columns: lane, model, items, files, order.
3. Dispatch one subagent per lane. Pass `model` explicitly on every Agent call, set to the lane's model (`haiku`, `sonnet` or `opus`), and use `isolation: "worktree"`. A subagent that works in the shared checkout edits source even when asked only to read. Send lanes with disjoint files in one message. Paste the shared rules and the lane's own items into each brief in full, because a subagent sees only its brief. Tell each builder to run `bun install` and copy `web/next-env.d.ts`, `native/expo-env.d.ts` and `web/.env` from the main worktree before the first gate, and to bring its worktree to the base branch with `git merge --ff-only <base>`. End each brief with the report contract: every changed file and every untracked file added, each gate run with its output, what is left, and any question for Zach.
4. <Item steps. One step per item or per Haiku bundle, tagged with its lane and model, for example "Spacing on the shelf header (note 3, Haiku lane H1)". Each step states the change, its reason, its constraint, and its done-when. A report-only item says "Report only. Make no change until Zach decides.">
5. ...
<n-2>. Verify (the lead). When a lane returns, check its diffstat against the files the lane owns. A file outside the lane stops the lane: report it and do not accept it. Run the gates yourself in the lane's worktree. A builder's claim that a gate passed counts only with its output. View each visual item: on native with the iOS Simulator, on web with the browser pane. If you cannot view an item, write "gates green, not seen running" for it (R10).
<n-1>. Gates. In each package a lane touched, run: web `bunx tsc --noEmit`, `bun run lint` and `bun run build`; native `bunx tsc --noEmit` and `bun run lint`; `packages/core` `bun run lint`. At the repo root, run `bun run test`, `bun scripts/codemods/08-verify.ts` and `bun scripts/check-feature-parity.ts`. If a backend file changed, also run `cd backend && go build ./... && go vet ./... && go test -race ./...`. Report only the gates that ran, with their result. Never say a gate passed unless its output shows it.
<n>. Hand back. Write one runtime-pass entry for each note in the report, for Zach to walk. Do not write a file for them. List every file each lane changed, and confirm that no file changed outside its lane (`git status --short` in each worktree). Then commit the exact file list yourself, and give the hash.

**Escalation.** A lane moves up one model (Haiku to Sonnet, Sonnet to Opus) in a fresh worktree, with the failed report in the new brief, when it needs a file it does not own, fails a gate for a reason its report cannot explain, or returns a change that does not match its note. Each lane escalates at most once. A second failure stops the lane and goes to Zach. A lane never escalates to Fable. A lane that seems to need Fable goes to Zach.

**Ask before building.** Each of these is Zach's call, and either answer may be no. Put each question in the report with the choice it needs.

- <Copy a note needs: 2 or 3 real variants in different registers, named (R7). Check first that the words are not already settled.>
- <A note that does not say what is wrong.>
- <A product question.>

**Not in scope, whoever asks.**

- <Neighbouring rows that own a flow, by number.>
- <A screen a note touches but this row does not own.>
- Any change to `CLAUDE.md`, the gate config, or a lint cap.

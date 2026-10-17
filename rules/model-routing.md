<!-- personal-config v0.8.0 · 2026-10-05 · config 2fbe199a · standard v1.2.0 · adapted -->
# Run the model the task asks for

**Before starting any task that names a model, check your own model against it.** Tasks are
assigned a model on purpose — a board's Model column, a pass-off prompt's `**Model: X**` line, a
skill or a doc that names one. The assignment is a deliberate choice, not a preference, so
running the wrong model on it silently is the failure it exists to prevent.
`PASSOFF.md` in `~/Projects/furlough` is the live example: Fable goes wherever a mistake becomes
an unblock, Opus where the failure mode is a bad screen.

Do this check **first** — before reading the codebase, before planning, before writing anything.
If they match, say so in one line and carry on.

If they do not, pick one of these two, never a third:

1. **Delegate it, in session — for a review or a sweep.** Spawn a subagent with the model
   parameter set to the assigned model and hand it the whole prompt. This file is the
   authorization to do that without asking first. Relay what comes back. Where the harness can
   switch the session's own model instead, that is fine too when the whole session should change.
2. **Stop and hand it off — for a build.** Do not start the work. Write a pass-off prompt
   carrying everything this session established — what was read, what was decided, what was
   ruled out and why, and any files already touched — say plainly which model it is for and why,
   and tell me to run it there.

Prefer 1 when the task's whole output is a verdict or a list — a subagent keeps only its final
text, which is all a review or a sweep produces. Prefer 2 when the task builds, needs my
decisions along the way, or when the context already built is worth more than the work; a Deep
subagent never builds, because the boundary discards the sustained reasoning that tier is for.
One exception, and only one: a Deep row may be built by a Deep subagent when I named that row
myself, by running `/delegate` on it or by lifting its hold at the start of `/autopilot`, and
that build then gets an independent Deep review.
Never do the work yourself on the wrong model, and never quietly downgrade an assignment because
the task looks small from here — "it turned out to be simple" is a judgement only the assigned
model gets to make. If an assignment looks wrong, say so and ask; do not overrule it.

Two rules about subagents, from getting this wrong: **a subagent spawned into the shared
worktree will edit source even when asked only to review** — give anything analytical its own
worktree and check the diffstat when it returns. And **never let a subagent inherit the
session's tier for read-and-report work**; pass the model explicitly, every time.

## The tiers

**The discriminator is: can the failure be silent?** Not how big or scary the work feels —
sizing by fear over-assigns the expensive tier.

| Tier | Model | Use for |
|---|---|---|
| Deep | Fable 5.1 | Only where a mistake compiles, passes every gate, and is wrong in production. |
| Default | Opus 5.5 | The default, and the right answer for most work — anything whose failure is loud. |
| Mechanical | Sonnet 5.5 | Whole phases of mechanical work: sweeps, ratchet edits, doc reconciliation. |
| Light | Haiku 5.5 | One narrow step you can check the moment it lands: a read-only report, a single bounded transform you verify after, a format conversion. |

---
name: counsel
description: Convene a council on one decision. Five advisors (The Fatal Flaw, The Wrong Problem, The Upside, The Cold Read, The Next Move) answer alone, cross-examine each other, and a chairman makes the final call. Use when the user types /counsel.
argument-hint: "[quick] [decision or plan]"
disable-model-invocation: true
---

# /counsel

Five advisors look at one decision, each through one fixed lens. They answer alone, then read each other's answers and attack the blind spots. A chairman reads everything and makes the call.

The user's arguments: $ARGUMENTS

A council is worth its cost only when its advisors are independent, and three things make them so here. Each advisor runs as its own subagent, with its own context. The Cold Read gets a different input from the rest. The chairman runs on a different model tier. Keep all three. One reply that plays five parts gives five views from one mind: each answer leaks into the next, and the debate is that mind agreeing with itself.

## The council

| Seat | Agent | Model | Lens | Round 2 target |
|---|---|---|---|---|
| The Fatal Flaw | `counsel-fatal-flaw` | `opus` | The one thing most likely to kill it | The Upside |
| The Wrong Problem | `counsel-wrong-problem` | `opus` | Whether this is the right problem at all | The Next Move |
| The Upside | `counsel-upside` | `opus` | The upside everyone else is missing | The Fatal Flaw |
| The Cold Read | `counsel-cold-read` | `opus` | A stranger with no context and no patience | Any insider |
| The Next Move | `counsel-next-move` | `opus` | Only the next concrete move | The Wrong Problem |
| The Chairman | `counsel-chairman` | `fable` | Makes the final call | none |

The seats form two opposed pairs and an outsider. The Fatal Flaw and The Upside pull against each other on outcome. The Wrong Problem and The Next Move pull against each other on altitude: the question above the plan against the step in front of it. The Cold Read checks all four insiders against what a stranger sees. Each round 2 target is the seat's natural opponent, so every blind spot has an owner.

On every Agent call, pass `subagent_type` and `model` exactly as the table lists. The agent files hold each seat's instructions, its read-only tools and the same model.

## 0. Pick the mode

- Full, the default: round 1, round 2, then the chairman. Eleven agent runs.
- Quick, when the arguments start with the word `quick`: round 1, then the chairman. Six agent runs. Treat the rest of the arguments as the decision. Use it for small decisions or ones that are easy to reverse.

## 1. Write the brief

Build it from the arguments and the conversation. If neither holds a decision, ask the user for one in a single question and stop. If the user gave a plan, not a choice, the decision is: go ahead as planned, change it, or drop it.

If the decision concerns code or files in the working directory, read what matters first and put the facts in the brief. The advisors can open files, but the brief must stand on its own.

```text
DATE: <today>
DECISION: <one sentence, as a question. Name the real options, including "do nothing" when it is one.>
CONTEXT: <what exists now, what was tried and what happened. Facts, with numbers and dates.>
CONSTRAINTS: <time, money, skills, people, deadlines, hard limits>
STAKES: <what is gained or lost, and how easily the decision can be reversed>
SUCCESS: <what a good outcome looks like, in terms someone could observe>
UNKNOWNS: <what nobody knows yet that matters>
```

Write three more items, and keep them out of the brief:

```text
LEAN: <the option the user favors, and why. For the chairman only.>
STRANGER: <who meets this cold: a customer, a new hire, a reviewer, an investor, or the user six months from now>
SURFACE: <what that stranger sees first, quoted in full: the pitch, the README, the landing page, the message, the PR description. If nothing is public, the plan in two sentences, as the user would pitch it cold to a smart friend.>
```

- **Keep the lean out of the brief.** Advisors that know the user's preference drift toward it. State the options neutrally.
- Facts only. Mark every inference as an inference.
- Ask before you convene only when a missing fact would change the call, such as the deadline, the budget or the alternative. Ask in one batch of three questions or fewer. Otherwise, convene without asking.

## 2. Round 1: alone

Spawn all five advisors in one message, so they run in parallel, with `run_in_background: false`. Round 2 needs all five answers.

The four insiders get this prompt:

```text
ROUND 1. You have not seen any other advisor's answer.

<the brief>

Answer from your lens only, in your round 1 format.
```

The Cold Read gets this prompt, and never the brief, the lean or the conversation:

```text
ROUND 1. You are <the stranger>. You know nothing else about this.

<the surface>

React in your round 1 format.
```

If an advisor fails or returns nothing usable, run it once more. If it fails again, go on without it and say so in the report.

## 3. Round 2: cross-examination

Skip this step in quick mode.

Spawn five fresh advisors in one message, again in parallel. Each gets its own round 1 answer and the other four, each under its seat name. The insiders get the brief again. The Cold Read gets the stranger and the surface again, never the brief.

```text
ROUND 2: CROSS-EXAMINATION.

<the brief; for The Cold Read, the stranger and the surface>

YOUR ROUND 1 ANSWER:
<its own answer>

THE OTHER ADVISORS, ROUND 1:
<the other four answers, each under its seat name>

Rules:
1. Attack your round 2 target's biggest blind spot, from your lens. Quote the line you attack.
2. Hit one more advisor only if that hit would change the decision.
3. Agree with no one unless you add something new. Agreement alone adds nothing.
4. Change your position only for a concrete reason: a fact, a mechanism, or a flaw in your own logic. Say which one. Pressure from the others is not a reason.
5. Name the strongest point against your position, and say whether it moves you.

Format:
VERDICT: GO | GO WITH CHANGES | RETHINK | STOP
CONFIDENCE: low | medium | high
POSITION: HELD or REVISED, and the reason in one line.
TARGET: <seat>. The blind spot. "<quoted line>"
SECOND HIT: <seat>. The blind spot. "<quoted line>" Or: none.
AGAINST ME: the strongest opposing point, stated fairly. Moves me: yes or no, and why.
```

Run one round only. In debate between copies of one model, most of the gain comes from the first exchange, and later rounds mostly add agreement. The chairman judges any attack left unanswered.

## 4. The chairman

Spawn `counsel-chairman` with `model: fable`. Its prompt holds the brief, the lean, the stranger and the surface, then every round 1 answer and every round 2 answer, each under its seat name. In quick mode, start the prompt with `QUICK MODE: NO ROUND 2.` End the prompt with `Make the call in your format.`

## 5. Save the record

Write the whole run to `~/.claude/counsel/<YYYY-MM-DD>-<short-slug>.md`, and create the folder if it does not exist:

- A title, the date, the working directory and the mode.
- The brief, the lean, the stranger and the surface.
- Round 1 and round 2, each answer verbatim under its seat name.
- The chairman's call, verbatim.
- A last section, `## Outcome`, with one line: "Fill in later: what you decided, what happened, and which seat was right."

The prose hook checks this file for em dashes and contractions. The seats are told to write without them, so a hit is rare. If one comes up, fix the punctuation and keep the words.

## 6. Report in chat

Follow the chat-reply rule (ASD-STE100 in this setup), in this order:

1. The call, the confidence and what would change it.
2. The next move and the tripwire.
3. The council in five lines: seat, verdict and core point. Mark each seat that revised its position in round 2.
4. The crux and the strongest dissent.
5. The path to the saved record.

Do not paste the full answers into chat. Do not soften the chairman's call or decide again. If this session knows a fact the council did not have, and the call depends on it, add one line after the call that names the fact.

## Rules

- Only the user convenes the council. A full run costs eleven agent runs, so never start one on your own.
- The seats have read-only tools on purpose, so they cannot edit files in a shared tree. Never swap in an agent with write access.
- Keep The Cold Read ignorant. What it does not know is its whole value.
- Add no seats and no rounds during a run. A change to the council is a change to this skill.

## Why it is built this way

- Separate subagents are the only real independence one model family can give. Separate contexts stop one answer from shaping the next.
- Four seats differ in what they look for. The Cold Read differs in what it knows, which is a stronger kind of difference.
- One cross-examination round, because later rounds mostly make copies of one model agree with each other.
- The chairman runs on the Deep tier because a wrong call fails silently: it reads as confident advice and is wrong in the world. That is the Deep-tier test in `model-routing.md`.
- The lean goes to the chairman only. Advisors anchor on a stated preference, and the chairman needs the lean to say plainly when the council disagrees with the user.

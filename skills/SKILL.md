---
name: write-doc
description: Write a paper, document, README, report or other long-form text in Zach's writing style, with a provenance gate for claims only Zach can make, a review against the AI-writing tells, a source and citation check, and a hook-backed check of the saved file. Use when the user types /write-doc, or asks to write, draft or rewrite a paper, doc, essay, report, README or proposal.
---

# /write-doc

Write papers and documents that read like a careful human wrote them and that Zach can stand behind claim by claim. The rules live in `~/.claude/rules/writing-style.md`. This skill loads them, checks where every claim comes from, drafts, reviews the draft, checks its sources, and checks the saved file.

This skill covers written work only. Chat replies to Zach follow the ASD-STE100 rule in `language-style.md` and nothing else.

## Steps

1. **Load the rules.** Read `~/.claude/rules/writing-style.md` in full before you write anything. Do not work from memory of it.

2. **Fix the brief.** Confirm these four items from the request. Ask one short question only for an item that is missing and cannot be inferred. If step 4 will also need Zach, hold the question and ask everything in one message there.
   - Audience and purpose.
   - Format and file type (`.md`, `.tex`, `.docx`, and so on) and where to save it.
   - Length.
   - Sources or material to use. Never invent a source, a statistic or a quote.

   Also collect what Zach has already supplied in the request or the conversation: his notes, facts he observed, his opinions. Step 4 builds on it.

3. **Plan the argument.** Write the main claim and the order of points for yourself. Each paragraph carries one idea and leads to the next. Decide the facts first: names, numbers, dates, causes. Write each claim down, because step 4 labels them.

4. **Check provenance before you draft.** Label each claim in the plan by where it comes from. Draft nothing until every claim has a label.
   - **Source.** A fact, figure, quote or description taken from something you can name and open: a reading, a file, a web page, a dataset, the code itself. Note which source.
   - **Zach.** Something Zach said or wrote: in the request, in this conversation, or in notes and outlines he wrote. Text that another AI session wrote is not Zach's, even when it sits in his files or an outline presents it as his. Treat it as a draft for him to confirm. Git history does not show who wrote a file, so when you cannot tell whether Zach or an AI session wrote something, label its first-hand claims and opinions **Needs Zach**.
   - **Needs Zach.** A claim that only the author can make:
     - A first-hand claim: what the author saw, read, did, tested, measured, attended or experienced. A description of something the author is expected to have examined counts when you cannot examine it yourself, such as a film, a book you do not have, a meeting, an interview, a lab result or a production incident.
     - A position the document states as the author's own: an opinion, a reaction, a verdict, a recommendation, or the main claim of an argument written in the author's voice.
     - Any "I", "my" or "we" sentence about the author's own experience, reasons or thinking.

   The gate fires on the kind of claim, not on whether the brief marked a gap. Most briefs mark nothing. A request to "make it personal" or "add my perspective" does not license invented experience.

   Three cases need care:
   - A fact from a source stays **Source**. A sentence that says the author learned, noticed, saw or believes that fact is **Needs Zach**.
   - In a genre that implies the author examined the thing, such as a review, a reflection or a site report, a cited description from someone else still reads as the author's own observation. Ask Zach to confirm it.
   - When you revise an existing draft, label the claims already in it the same way. A claim does not become Zach's because it survived an earlier draft.

   If any claim is **Needs Zach**, stop and ask for all of them in one message before you draft, together with any question held from step 2. When most of the document needs Zach, as in a reflection or a personal statement, first ask for his notes in his own words, then plan from them and ask only about what is still missing. Quote or paraphrase each planned claim and say what you need: a fact he observed, a yes or no, or his view in a sentence or two. Do not fill the gap from a secondary source and present it as the author's own. A secondary source's description can go in the draft only as that source's, with a citation, and the report must say so.

   When Zach answers:
   - Build each claim from what he said. Keep his meaning and his details. Do not strengthen, widen or add to them.
   - If he hands a position to you ("you pick", "whatever you think is best"), you may write it. Name it in the report as your choice, not his.
   - If he leaves a first-hand item unanswered or says to skip it, cut the claim or leave a visible marker in the draft: `[NEEDS ZACH: what is missing]`. Never write a first-hand claim from a guess.

   If no claim needs Zach, say so in one line and go on. A README or report built from files you can open often needs no questions.

   This step exists because a document under Zach's name must not report what he did not see or state a view he does not hold. Better prose cannot fix that, and good prose hides the defect from the one reader who could catch it.

5. **Draft with flow.** Draft only from claims that passed step 4. Follow the "Register for papers and documents" section. Keep a matter-of-fact voice. Link sentences with cause and consequence. Mix short and longer sentences. Use concrete detail in place of praise or filler. Prefer connected paragraphs over lists.

6. **Review the draft against the rules.** Re-read the whole draft. Check each group below and fix every problem before you save.
   - **Banned patterns:** no em dashes, no contractions, no litotes, no irony.
   - **Banned words and phrases:** scan for every word in the "Banned AI-signal words" section and replace each with a plain word or a direct statement.
   - **Structure:** no `not just X, but Y` device, no reflex groups of three, no participle tails that add fake analysis, no false ranges, no outline-style conclusion, no closing paragraph that restates the text.
   - **Tone:** no promotional language, no claim of significance without evidence, no vague attribution, no reflex praise.
   - **Formatting:** sentence case headings, rare bold, no emojis, no horizontal rules, no bullet list for every topic, no exact-three or exact-five list by default, no markdown leftovers.
   - **Chatbot leftovers:** no offer of more help, no disclaimer, no placeholder text.

7. **Check sources and citations.** Do this before you save.
   - List every source you used while you drafted: readings, files, fetched pages, notes. Each one that supplied a fact, figure, quote or description must appear in the reference list. In a document with no reference list, such as a README, link the source or name the file. Add any that are missing.
   - Each in-text citation must match a reference entry, and each reference entry must be cited in the text.
   - Where you can open the source, check each quotation word for word and each page number and figure against it. Name any you could not check in the report.
   - Each **Needs Zach** claim in the draft must be supplied by Zach, handed to you by him, cut, or marked.

8. **Save the file.** Write or edit the file with the normal tools. For a Word document, use the docx skill, then continue to the next step.

9. **Run the check.** Run this command on the saved file:

   ```bash
   ~/.claude/hooks/no-em-dash.sh check <path-to-file>
   ```

   It checks em dashes, contractions and banned words. It reads `.md`, `.mdx`, `.txt`, `.rst`, `.tex`, `.adoc`, `.docx`, `.doc`, `.rtf` and `.odt` files. If it prints problems, fix them in the file and run it again until it prints `PASS`. The same check also runs automatically after each Write, Edit and Word-file creation, so a failure there is the same failure.

10. **Report to Zach in ASD-STE100.** Give the file path, a one-line summary of what the document says, and any point where you chose between two options. State the provenance: which claims came from Zach, which positions you chose at his request, which gaps are marked or cut, and which descriptions rest on a secondary source. State any claim or quotation you could not verify. Do not paste the document into the chat.

## If you use subagents to write

A subagent may not load the rules files. Paste these into its prompt: the banned patterns, the banned words list, the structural tells list, the flowing register and the labeled claims from step 4. It may use only claims that passed step 4, and it must not add a first-hand claim or a position of its own. Then run steps 6, 7 and 9 yourself on its output.

## Limits to report honestly

- The script catches words, phrases, em dashes and contractions. It cannot catch layout, participle tails or vague attribution. Step 6 covers those, and it depends on your own careful re-read.
- No script checks provenance or citations. Steps 4 and 7 depend on your own labels. When you are not sure whether a claim is first-hand, label it **Needs Zach**.
- The word rules and the hook address what a human reader notices. They do not lower AI-detector scores: a draft that passed them scored 100% AI on GPTZero with no flagged words or patterns. Do not promise Zach a detector result.
- A Word file is checked only when the command that made it names the file. A script that writes a `.docx` without its name in the command escapes the automatic check, so always run step 9.

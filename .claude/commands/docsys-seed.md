---
description: Seed documentation for one feature of an existing project — research in git, ask the builder plainly, write only what was confirmed
allowed-tools: Bash(docsys *), Bash(git log:*), Bash(git show:*), Bash(git status:*), Read, Grep, Glob, Write, Edit
---

# /docsys-seed <feature> — seed one feature

For a project whose documentation does not exist. The tool does the
research; you present it; the builder confirms, corrects and adds what
history cannot say. **Nothing is written before the builder says so.**

## 1 · Research (tool)

`docsys seed plan --repo . --root docs --target <feature>` — commits with
their bodies, files by touch count and the other features they serve, the
birth, manifests, `doc:` citations, the code's own comment blocks, tags.
If it is refused ("already covered by …"), stop: that page is the system's
now; drift goes through `/docsys-sync`, not through seeding.
If it says nothing names the feature, ask ONE question: where does it live
(a path, a scope, a symbol)? Then run it again with what you learned.

## 2 · Present ("what I found")

One block, in the tree's language (`default_content_language`), every line
carrying its evidence (`path:line`, `sha`): what the feature does, how it is
built, when it was born and moved, what broke and was fixed, what the
manifests declare, what the code's comments say about WHY. Derive; do not
ask what the code already answers.

## 3 · Ask — at most four questions, one at a time

Plain, single-meaning, answerable in a sentence, never a metaphor, never a
question that creates a conflict. The bank:

- Is this summary right? What is wrong or missing?
- <a specific fact the code cannot settle — a requirement vs a fallback, a
  product decision, an audience>
- <what the builder does with it that the code does not show>
- What is next for it — or is it finished and not to be touched?

If an answer conflicts with the evidence, show the evidence (`file:line`,
the test, the commit) and keep the question open until it is clear. An
answer the builder cannot give becomes a `question` row, dated today.

## 3b · Your own notes are questions, never text

If this machine holds agent memory for the repository (Claude Code keeps
`memory/*.md` under `~/.claude/projects/<repo-slug>/`), run the plan with
`--memory <that dir>`: each note's name and description becomes one line
of evidence and ONE question — "my notes say X; is it still true, and where
should it live?" The builder's answer is the source; the note is not. Never
paste a note into the tree.

## 4 · Approve, then land (tool)

Write the rows the conversation produced into a plan file OUTSIDE `docs/`
(`SEED.tsv`), show it, and wait for the explicit word. Then:
`docsys seed apply --plan SEED.tsv --repo . --root docs`.
Rows (TAB-separated; `docsys seed plan` prints the grammar): `research
<feature> <shas>` reserves the feature; `answer <feature> <who> <text>`
records the builder's words verbatim; `journal <date> <sha> <title>`
back-fills chronology at its own date; `postmortem <slug> <sha>` quotes an
incident's commit; `debt` and `question` add dated items.
Everything lands under `work/`. The permanent page comes later, through
graduation, when the builder confirms.

Never write prose of your own into the tree. Never mark anything done.

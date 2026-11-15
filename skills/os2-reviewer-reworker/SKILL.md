---
name: os2-reviewer-reworker
description: Dispatch the os2-reviewer-reworker agent to repair work after an os2-reviewer `full` round graded it below A-, fixing exactly and only what the reviewer outlined. Use when asked to "rework the review", "fix the review findings", "run the reworker", or after an /os2-toolkit:os2-review report comes back below A-. Two phases with a stop for the user between them. The project stays frozen until the work lands.
---

# Rework after a review - exactly and only what the reviewer outlined

The `os2-toolkit:os2-reviewer-reworker` agent repairs reviewed work in a fresh
context, so the author's own design ideas do not leak into the fix. It carries
the rules; this skill is how you dispatch it and what you do with what it
returns.

**The project is frozen** from the moment the review was dispatched until the
work gets a landing grade (A-) and lands. You start nothing new: no features,
no extra fixes, no captures, no tickets. Anything you notice goes on the list
for the user. The freeze is what keeps the baseline still: a fix that reaches
past the findings moves it, the reviewer's notes stop applying, and every
re-review grades new work instead of the repair.

## 1. Before dispatching

- The review report, verbatim. Save it beside the project's plans, or in the
  scratchpad, if it is not already saved.
- The baseline patch that was graded - `review-round-N.patch`, saved by
  `/os2-toolkit:os2-review` at dispatch. If it was not saved, say so to the
  user and stop: without it nobody can show the rework did not drift.
- The plan section or task the work implements.

## 2. Phase A - dispatch, then stop

`Agent(subagent_type: "os2-toolkit:os2-reviewer-reworker", ...)`:

> **Phase:** A (analysis only)
> **Review report:** <path, or pasted verbatim>
> **Baseline patch:** <path>
> **Plan / task:** <path + section, or the task as stated>
> **Working tree:** <path, VCS, revision or `git describe --tags --dirty --always`>
> **Build / tests to run in Phase B:** <commands, or "none">
> **How to run OS/2, if at all:** <the project's runner, or "do not boot">

When it returns, **present its Phase A report to the user** - the root
causes, the questions (the reviewer's and the agent's), the out-of-scope list
and the re-flag risk - and **stop**. Vet the agent's questions first: drop
any the sources or the plan already answer, and say which you dropped. Do not
fix anything yourself, and do not resume the agent until the user has
answered.

## 3. Phase B - resume the same agent

`SendMessage` to the same agent (it keeps its Phase A context) with
**Phase: B** and the user's answers verbatim. Do not respawn it.

When it returns:
- Check the hunk map yourself: diff the tree against the baseline, and every
  hunk must map to a finding or a named user answer. An unmapped hunk is
  drift; send it back, do not keep it.
- Report to the user: findings closed, findings not closed and why, the
  build/test output, what was noticed and not fixed, and the agent's
  ready / not-ready answer.
- **Then stop.** Whether a re-review runs is the user's call (one graded
  round below A-, then stop and ask - see `/os2-toolkit:os2-review` section 4).

## 4. After landing, not before

Out-of-scope items and everything noticed during the freeze are discussed
with the user - ticket (`os2-toolkit:track`), fix, or `know absent` for a
closed dead end - only **after** the repaired work has been re-reviewed
**and** has landed.

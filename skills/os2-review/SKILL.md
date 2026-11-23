---
name: os2-review
description: Review an OS/2 change before trusting it - dispatch the os2-reviewer agent for a grounded, graded (A-F) review of work touching OS/2 semantics (Dos*/Win*/Vio* APIs and ordinals, PM, VIO, drivers, the LX/NE loader, kernel objects, thunks, the 16/32-bit ABI split), with the change set, claims, evidence, populations and grade history packaged for it. Use only when the user asks - "review this OS/2 change", "grade this", "check this against IBM" - never on your own initiative, and not as a step before every commit. The bar to land is A-; from a `full` dispatch until the work lands the project is frozen, and below A- the only permitted work is os2-toolkit:os2-reviewer-reworker. Has a cheap "--citations" mode that only reconciles cited sources against what they are cited for - run that first, and for "check my citations", "did I cite that right" - and a "--regrade" mode, the only re-review of a rework: it checks the findings closed and the hunks mapped, and never re-samples the work.
---

# Graded OS/2 review of this session's work

Spawn the **`os2-reviewer`** agent to attack the work, not to admire it. It is
the adversarial-review idea with two things a generic review lacks: it **grounds
itself in primary OS/2 sources first** - the knowledge cache, this kit's
`os2ref/`, the user's OS/2 library by role, IBM's Toolkit and DDK headers and
books - because the model is not trained on OS/2 and would otherwise grade
against its priors; and it returns a **letter grade**, not just a list of
findings.

**Run it when the user asks for one; once it runs, it is a gate.** The bar to land
is A-. From a `full` dispatch until the work receives a landing grade and lands,
**the project is frozen** (section 3), and below A- the only permitted work is
`/os2-toolkit:os2-reviewer-reworker` closing the report's findings. The freeze
is what prevents drift: fixing more than the findings moves the baseline, the
reviewer's notes stop being valid, and every later round grades new work
instead of the repair. A review is still never a reason to start another round
the user did not ask for.

**The cycle, and why it converges by construction:**

```
readiness check -> full review -> rework (in-scope findings only) -> optional regrade -> land
```

A `full` report is the reviewer's whole judgement of what is wrong with the work
it covered. A rework that closes exactly those findings, and changes nothing
else, has carried that judgement out - so a `regrade` of it can only confirm,
and comes out A- unless a fix is itself wrong. Two things break this, and both
are rules below: **new design entering the cycle** (a design draft sent for
review, a user's design ruling built into the rework, a new idea folded in
during the freeze), and **a second `full` round on the same material**, which
samples what the first left unopened and so always finds something. Design
rulings go into the *next* cycle; the re-review of a rework is a `regrade`, not
a `full` round.

> **Receipt.** A design spec went to `full` review with its own open-questions
> table; round 1 graded C+ with ten design findings. The author answered them
> with seven new design rulings, some of them new ideas raised during the
> freeze, and the spec grew by 60%. Round 2 - a `full` round - graded what was
> nearly a new document B, three of its findings coming from the new rulings'
> own text. The author then offered a third round instead of asking why the
> second had not come out A-.

The reviewer starts blind: it cannot see this conversation. That is the point,
and it is also why the dispatch has to carry everything. "Review the changes"
gets you a generic style report; the grade is only as good as the package.

## 0. Pick the mode - the cheap one first, and often instead

The agent has three modes and the dispatch names one. **A `full` round costs
roughly twenty times a `citations` round**, so choosing `full` by reflex is the
most expensive habit available here.

- **`citations`** - a mechanical pass: open every OS/2 source the change cites and
  check the sentence is there and says what it is cited for. No grade, no C
  review, no architecture opinion. Measured across three `full` rounds on one
  change, this single activity produced **six of that round's eight findings**;
  it is a grep-shaped job that does not need a judgement pass around it.

  **Run this FIRST whenever the change adds prose that cites sources** - a new
  `.c` file with commentary, a doc correction pass, a table with provenance tags,
  anything carrying `[DOC-IBM]` / `[OBS-RE]` markers or `file:line` references.
  Fix what it finds, and only then spend a `full` round, which now gets to look
  at the code instead of at citation drift.

  It is also the right answer to "is this ready?" between rounds, and to a change
  too small to justify `full` at all.

- **`full`** - grounding, the whole attack order, findings and a letter
  grade. Once per cycle: it grades new work, never a rework of work it already
  graded.

- **`regrade`** - the re-review of a rework, and the only one. Given the `full`
  report, its baseline patch and the reworker's hunk map, it checks that each
  finding is closed, that every hunk maps to a finding, and that the changed
  hunks are themselves right - and nothing else: it does not reopen the `full`
  round's unopened items or attack unchanged text. Its grade is A- over the
  `full` round's coverage when every finding is closed with no drift and no
  defect in the fixes. Far cheaper than `full`, and optional: a rework the
  author has hunk-checked against the findings may land on the user's word
  without it.

`/os2-toolkit:os2-review --citations [paths]` selects the cheap mode,
`--regrade` the re-review; the default is `full`.

## 0a. Readiness - is this work settled enough to grade?

Before a `full` dispatch, read the work for **open design questions**: an
open-questions table, "not decided", "to be decided", alternatives left
standing, a mechanism named but not chosen. A grading review of unsettled
design can only report that it is unsettled, and every such finding has a
`design` remedy - which the rework cannot build without breaking the cycle.

- **Open design inside the work:** it is not ready. Settle it with the user
  first, or mark each open question explicitly out of the review's scope ("open:
  not graded") in the dispatch.
- **If a `full` report comes back with its `[BEHAVIOUR]` findings mostly
  `design`:** the work was not ready. Tell the user, and propose withdrawing the
  review - no rework, no regrade; the design goes to the user, and the settled
  work gets a fresh round 1. Reworking a design draft into a design is exactly
  the redesign the freeze forbids.

## 1. Gather the change set - detect the VCS, do not assume one

```sh
git rev-parse --is-inside-work-tree 2>/dev/null   # git
svn info 2>/dev/null                              # subversion
```

- **git**: `git status --porcelain`, then `git diff` plus `git diff --cached`
  for uncommitted work, or `git diff <base>...HEAD` for a branch, or
  `git show <rev>` for one commit. Say which of these "the change under review"
  means.
- **svn**: `svn status`, `svn diff --summarize`, `svn diff`. For a committed
  revision, `svn diff -c <rev>` and `svn log -v -c <rev>`.
- **Neither** (or work outside the working copy): name the paths explicitly in
  the dispatch. The reviewer cannot guess them.

**Untracked and ignored files matter too** - list any probes, build scripts,
captures or test directories you created. **A defect in a test harness
invalidates every result it produced**, so harnesses and captured outputs are in
scope. If the work lives in a different checkout, or the user asked for specific
paths or a revision, use that instead.

## 2. Package the six things the reviewer cannot reconstruct

1. **Files changed** - paths, one line each on what changed and why. Note which
   files are untracked.
2. **Claims** - every statement made to the user that something works, matches
   real OS/2, or is fixed. Include the OS/2 subjects by IBM's exact name (ordinal
   numbers, `Dos*` / `Win*` / `Vio*` / `Kbd*` spellings, structure names, error
   codes by number) so the grounding phase starts on the right headers.
3. **Evidence** - the *exact* output or observation behind each claim: probe
   stdout, a real-OS/2 capture beside the same probe's output here, test counters
   with the baseline they were compared against. Not "tests pass" - the lines,
   and the command that produced them.
4. **Grade history - REQUIRED, and the single most useful line in the dispatch on
   any round after the first.** The reviewer is a fresh agent with no memory of
   the previous round; without this it produces a third independent list instead
   of answering the only question that matters by round two, which is *are we
   converging*. State the round number, every previous grade in order, and the
   rubric line that set each, and **attach the previous round's baseline patch
   and report** - the reviewer diffs against that patch to find drift:

   > **Grade history:** round 3. Round 1: C ("a claim asserted without the
   > measurement that would settle it" x3). Round 2: C (same line, x1 - the three
   > named in round 1 were fixed). Findings verified and repaired between rounds:
   > [list].

   A flat sequence is not bad luck and not a harsh reviewer - it is evidence the
   repairs addressed the symptoms the reviewer happened to name while the thing
   generating them kept running. The agent's **Trajectory** section exists to
   name that mechanism, and it cannot run without this field. On round 1, say
   "round 1, no history". **For a `regrade`, also attach the reworker's Phase B
   hunk map** - the regrade checks each hunk against it.
5. **The populations you know of** - the denominators the reviewer will otherwise
   have to guess: how many OS/2-source citations the change contains, how many comments
   assert an OS/2 fact, how many ordinal or dispatch-table rows were touched, how
   many new constants, how many call sites a changed function has. You can count
   these with `grep` in seconds and the reviewer cannot know it has them all.
   This is what makes its **Coverage** section checkable rather than
   self-reported.
6. **The exception list** - every allowlisted known divergence, skipped case, or
   out-of-scope finding recorded and left, each with its citation. A new
   allowlist entry is itself a finding the reviewer will report; say it up front
   rather than have it found. Include anything you recorded this iteration, since
   a reviewer cannot tell a pre-existing item from one created to satisfy it.

**Before you dispatch, ask the knowledge cache what is already known** about the
subjects in field 2: `know q '<question>'`. A recorded negative ("searched X,
absent") belongs in the package - it saves the reviewer the same dead end, and it
is evidence the question was taken seriously.

## 3. Launch

**For a `full` round, first save the baseline** - the exact work being graded:
`git diff HEAD > <scratch>/review-round-N.patch` (or `svn diff > ...`), plus
copies of any untracked files in the change. The reworker and any regrade's
drift check need it; without it nobody can show the rework did not drift.

**From this dispatch on, the project is FROZEN** until the work under review
gets a landing grade (A-) and lands. Start nothing new - no features, no fixes
beyond the reviewer's findings, no captures, no tickets. Anything you notice in
the meantime goes on a list for the user, discussed after landing. A
`citations` pass saves no baseline and starts no freeze.

- **Any edit to the reviewed files outside the reworker voids the review** -
  including the author's own "small" fixes. The regrade's hunk-map check catches
  it; do not make it necessary.
- **New design during the freeze - including the user's.** When the user opens a
  new idea or design question on the frozen work, it is not a fix, however
  closely it touches a finding. Say so, and offer exactly two paths: **park it**
  on the after-landing list, or **withdraw the review** and treat the work as a
  draft again (a fresh round 1 later). Never fold it into the rework: that is how
  a repair becomes a redesign without anyone deciding it should.

`Agent(subagent_type: "os2-toolkit:os2-reviewer", ...)`. Do not paste the persona, the attack
order, or the rubric - the agent file carries them and is their source of record.
The prompt is the package:

> Review and grade the following work. You have none of the author's context.
>
> **Mode:** full | citations | regrade
> **OS/2 subjects:** [ordinals / APIs / structures / subsystems, IBM spelling]
> **VCS and change set:** [git or svn, the exact command that shows the change,
> and the paths; note untracked files]
> **Files changed:** [paths + one line each]
> **What the author claims works:** [each claim]
> **Evidence the author relies on:** [the exact output behind each claim]
> **Grade history:** [round N; each previous grade + the rubric line that set it;
> what was repaired between rounds; the previous round's baseline patch and
> report - or "round 1, no history"]
> **Populations:** [OS/2 citations N, OS/2-fact comments N, ordinal rows touched N,
> new constants N, call sites of <fn> N - as many as you counted]
> **Exception list:** [allowlisted divergences / skipped cases / recorded
> out-of-scope findings, each with its citation - or "none"]
> **Tree state:** [checkout path, the revision or commit, whether the tests were
> run at this exact state]

One reviewer per subsystem for a large session, in parallel; otherwise give one
reviewer the **whole** change set - cross-file ownership and lifetime bugs are
exactly what a fresh reader catches.

## 4. After it reports

- **Read the Grounding note first.** If it is thin, unsourced, or grounded on the
  project's own headers and status docs instead of the IBM material, `os2ref/`
  and the RE sources, the grade measures the reviewer's priors, not the work:
  discard it and re-dispatch with the subjects spelled out more precisely. If it
  says a role was missing from the library (`os2-lib roles` shows what is
  present), that is material the user needs to ingest - `os2-toolkit:ingest` -
  not something to grade around.
- **Read the Coverage section second, and read it as the size of the report.**
  Six findings out of six citations opened and six out of twenty-eight are
  different results with the same finding count. A dimension marked
  `exhausted (n/n)` is closed - you can stop working on it, which is the only way
  a good grade is ever earned rather than sampled into. A dimension that is not
  exhausted comes with the unopened items named: the grade covers what was
  opened, and the unopened items are the starting point of the **next cycle's**
  `full` review - never of this cycle's regrade, which would turn the repair's
  check into a new sample. If the coverage is too thin to trust the grade, say so
  to the user now; the remedy is a wider `full` round before any rework, not a
  second one after it. A report with no Coverage section is a report of unknown
  size - send it back.
- **On round two and later, read Trajectory before the findings.** If it names a
  mechanism, that is the thing to repair; repairing the individual findings under
  a flat grade buys exactly one round. If it says "no history supplied", the
  dispatch was missing field 4 and that is your error, not the reviewer's.
- **Weigh findings by consequence class, not position.** `[BEHAVIOUR]` findings
  matter most; `[BELIEF]` findings are real, but a pile of them is usually one
  mechanism (see Trajectory) rather than N repairs; `[COSMETIC]` findings are
  never worth a round of their own. Report all three classes to the user with
  their labels intact.
- **Findings are hypotheses.** Verify each against the code (and a run, if cheap)
  before changing anything. Findings about the *evidence* outrank findings about
  the code - if a test proved nothing, everything downstream of it is unsupported
  and must be re-established. And a finding about evidence can itself rest on a
  premise your own dispatch supplied: an adversarial reader cannot falsify a
  premise you handed it.
- **Report every finding to the user**, including the ones you disagree with,
  with your assessment. Never silently drop one.
- **The project is still frozen** (section 3). Below A-, do not repair anything
  in this session: the repair is `/os2-toolkit:os2-reviewer-reworker`, which
  fixes **exactly and only** what the reviewer outlined, in a fresh context,
  with a stop for the user between its analysis and its fix.
- **Report the grade, the rubric line that set it, and the one thing the
  reviewer said is most wrong.** Below A-, nothing lands. The "one thing most
  wrong", Not tested, Could not verify, scope questions and any finding whose
  remedy is `design` (new mechanism, new research) are questions for the user,
  not work items. A `design` finding is closed in this cycle by **marking it
  open** in the work; the user's answer to it is built and reviewed in the next
  cycle (section 0a, the reworker's Phase B).
- **One `full` round per cycle.** Below A-: rework, report, stop. The re-review,
  if the user wants one, is a **`regrade`** (section 0), run only once every item
  in the report has a disposition (fixed, marked open, or decided by the user).
  If the hunk check already shows every finding closed and nothing else
  changed, ask the user whether to land rather than offering a regrade by
  reflex. A regrade below A- names the fix that is wrong or the finding not
  closed; that goes back to the reworker - never a fresh `full` round on the
  same material.
- **Out-of-scope findings are reported to the user, not fixed** - the rubric's
  "fixed instead of recorded" is an automatic F - and not ticketed yet either.
  Whether to ticket them (`os2-toolkit:track`), fix them, or `know absent` a dead
  end the review closed is decided after the repaired work is re-reviewed and
  lands.
- **Record what the review established.** A durable OS/2 fact the reviewer had to
  source, or a search it proved empty, is worth more than the review: `know add`
  (with a `--verify` command that can fail on the contested half) and `know
  absent`. Read the `os2-toolkit:know` skill for the flags. Never record a fact
  about the project's own code - that is project state, and it is stale on
  arrival. A fact that is general, sourced and de-identified is then a candidate
  for `os2-toolkit:contribute`.
- The reviewer is read-only and cannot see runtime reality any more than you can;
  a "could not verify" from it is a measurement you still owe.

## What this is not

Not a substitute for running the tests: the reviewer grades evidence you bring
it; it does not generate it. Not a general code review either - for correctness
and cleanup on non-OS/2 code, the generic review tooling is cheaper. This is for
work whose correctness is a question about **OS/2**, where the expensive failure
is a fluent wrong answer nobody can falsify.

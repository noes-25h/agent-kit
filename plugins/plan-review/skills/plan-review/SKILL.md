---
name: plan-review
description: "Sends a finished plan or design to two independent reviewers that have not seen the conversation (one looks for reasons the plan must not pass, one looks for a better conclusion), then rules on every finding and records the rulings in the plan file. Use when a plan, design, or process is complete, before it is shown for approval or implemented. Not for reviewing a code diff, and not for a retrospective after the work is done."
argument-hint: "[path of the plan file]"
effort: high
---

# plan-review

A finished plan gets one attempt on its life from someone who was not there when it was made. The session that wrote the plan does not grade the plan.

## When to run

- At the moment a plan, a design, a process, or an architecture is complete for the first time, before it is shown for approval and before implementation starts.
- Worth running when the work spans more than one session, when it adds or changes a mechanism, or when a person will be asked to approve it.
- Not worth running for a short one-off procedure or for the mere execution of something already decided. When the review would weigh more than the plan, skip it.

## Steps

1. **Put the plan in one file.** The reviewers cannot read this conversation. A plan that cannot be read cold has failed at this step. Run the review before you commit the change that the plan describes: a commit message that summarizes the conclusion can reach the reviewers through the state of the repository.

2. **Start both reviewers in one message, at the same time.** Use the Agent tool twice in the same message:
   - `subagent_type: plan-review:adversarial-reviewer` looks for the reasons the plan must not pass.
   - `subagent_type: plan-review:best-path-reviewer` looks for a better conclusion that stands on top of the plan.

   Do not pass `model` or `effort` in either call. The definitions hold them, and a value passed in the call overrides the definition. The definitions also hold the lenses, the report format, and the ban on starting further subagents.

   Each prompt contains two things and nothing else:
   - the absolute path of the plan file
   - the paths or URLs of the material the plan must agree with: project instructions, earlier decisions, the actual implementation, official documentation

   Do not tell the reviewers how the plan came about. A reviewer that knows the history grades with sympathy.

3. **Rule on every finding, one at a time.** Give each finding and each proposal exactly one ruling:
   - **adopt**: change the plan, and say where.
   - **rebut**: keep the plan, and give the reason.
   - **defer**: record it as a follow-up item, and say where it is recorded.
   - **escalate**: hand it to the person who decides, as one closed question with one recommendation.

   No finding is dropped without a ruling. Where the two reviewers arrive at the same place, give that finding more weight. Where a falsifier can be checked by you, check it before you rule: reviewers are wrong sometimes, and a finding is a hypothesis until the material confirms it. If a finding with severity "fail" cannot be rebutted, change the plan before it goes any further.

4. **Leave the trace in the plan file.** Append two sections at the end of the plan file, in this order:

   ```
   ## Adversarial review (<date>, adversarial-reviewer, ran on <model> / effort <effort>)
   ## Best-path review (<date>, best-path-reviewer, ran on <model> / effort <effort>)
   ```

   Under each heading, one table row per finding: the finding in one line, and the ruling with its reason. After the two tables, one line that names the findings on which both reviewers converged and what changed because of them.

   Take the model and the effort from what actually ran, not from the definitions: the `/tasks` view while the reviewers run, or the reviewer transcripts under `~/.claude/projects/<project>/<session-id>/subagents/`. If you could not observe them, write "not observed". A plan file without these two sections has not been through the review.

## Limits

- Two reviewers. Only when the plan contains several independent bets, two reviewers per bet, and never more than six in total.
- Reviewers do not start subagents and return a summary only. The definitions enforce the first with `disallowedTools: Agent`.
- One pass per plan version. If you change the plan and review it again, fix the list of files the reviewers read before the pass starts, and count the passes. Stop after three passes that still return a "fail" or a "fix", and report that to the person who decides instead of starting a fourth.
- When the plan removes or shortens something, a reviewer tends to argue for putting each removed line back. Do not put a line back on the argument alone. Compare the version with the line and the version without it by the same measure, and restore it only when the measure differs.

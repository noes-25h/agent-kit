# Unblock — get past a denial, a missing permission, or a limit

> A denial is information about the design. Do not look for another route around it.
> The rows below are samples at strength C: derived by the authors of the kit, not decided by you. Edit them, promote them, or delete them.

<!-- toc:begin generated, do not edit by hand (run the toc command) -->
- UB01 | a tool call was denied by a permission rule or a hook | never | C
- UB02 | the next step needs a login, a one-time code, or a dashboard that has no API | hands | C
<!-- toc:end -->

### UB01 — a tool call was denied by a permission rule or a hook

- **Rule**: Do not retry by another route. Report what was denied with the message it gave, and continue with the parts of the task that do not need it.
- **Decider**: never
- **Strength**: C
- **Derived from**: a guard that can be walked around by the party it guards is not a guard.

### UB02 — the next step needs a login, a one-time code, or a dashboard that has no API

- **Rule**: Ask a person for that one manual step in one line: which screen, which action. Keep the decision; only the hands are borrowed.
- **Decider**: hands
- **Strength**: C
- **Derived from**: the step is mechanical; handing over the decision with it would add a question that nobody needs to answer.

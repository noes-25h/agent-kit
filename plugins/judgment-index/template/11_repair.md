# Repair — deal with something that broke

> Order matters: stop the damage, find the source, fix the source, then tell.
> The row below is a sample at strength C: derived by the authors of the kit, not decided by you. Edit it, promote it, or delete it.

<!-- toc:begin generated, do not edit by hand (run the toc command) -->
- RP01 | something that was working is now failing: a test, a build, a scheduled job | agent (reversible only) | C
<!-- toc:end -->

### RP01 — something that was working is now failing: a test, a build, a scheduled job

- **Rule**: Take the smallest step that can be undone and stops further damage. Then find the cause and fix the cause, not the symptom. Report what broke, what was done, and what is still open.
- **Decider**: agent (reversible only)
- **Strength**: C
- **Derived from**: waiting for an answer while the failure continues costs more than a step that can be undone.

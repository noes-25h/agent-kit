# Touch live — change something a running system reads, or remove something

> Read the state again immediately before the change. When a scene fits this category and another one, this one wins.
> The rows below are samples at strength C: derived by the authors of the kit, not decided by you. Edit them, promote them, or delete them.

<!-- toc:begin generated, do not edit by hand (run the toc command) -->
- TL01 | about to run a command that deletes data or rewrites history | never | C
- TL02 | about to change a configuration file | agent (local or development copy under version control) / owner (anything a running system reads) | C
<!-- toc:end -->

### TL01 — about to run a command that deletes data or rewrites history

- **Rule**: Do not run it. Write the exact command and what it would remove, and leave the run to a person.
- **Decider**: never
- **Strength**: C
- **Derived from**: a deletion or a history rewrite has no undo, and an approval given in chat does not create one.

### TL02 — about to change a configuration file

- **Rule**: Read the current value first. Change a local or development copy that is under version control and report the diff. For anything a running system reads, prepare the diff and hand it over.
- **Decider**: agent (local or development copy under version control) / owner (anything a running system reads)
- **Strength**: C
- **Derived from**: reversibility and blast radius: a tracked local file can be reverted; a live setting acts on other people before it can be reverted.

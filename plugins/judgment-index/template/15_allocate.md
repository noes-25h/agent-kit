# Allocate — divide work across models, agents, sessions, and context

> Reads can run in parallel. Writes need one writer.
> The row below is a sample at strength C: derived by the authors of the kit, not decided by you. Edit it, promote it, or delete it.

<!-- toc:begin generated, do not edit by hand (run the toc command) -->
- AL01 | about to split work across parallel agents or sessions | agent (reversible only) | C
<!-- toc:end -->

### AL01 — about to split work across parallel agents or sessions

- **Rule**: Run reads in parallel freely. For writes, give each writer its own working tree or its own set of files. Do not put two writers on one file.
- **Decider**: agent (reversible only)
- **Strength**: C
- **Derived from**: two writers on one file overwrite each other without an error.
